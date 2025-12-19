package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"go.opentelemetry.io/otel/trace"
)

var (
	// Prometheus metrics
	requestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)

	itemsCreated = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "inventory_items_created_total",
			Help: "Total number of inventory items created",
		},
	)

	itemsQueried = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "inventory_items_queried_total",
			Help: "Total number of inventory item queries",
		},
	)

	requestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "endpoint"},
	)
)

// InventoryItem represents an item in the inventory
type InventoryItem struct {
	ID          int       `json:"id" db:"id"`
	ProductName string    `json:"product_name" db:"product_name"`
	SKU         string    `json:"sku" db:"sku"`
	Quantity    int       `json:"quantity" db:"quantity"`
	Location    string    `json:"location" db:"location"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
}

// CreateItemRequest represents the request to create an inventory item
type CreateItemRequest struct {
	ProductName string `json:"product_name" binding:"required"`
	SKU         string `json:"sku" binding:"required"`
	Quantity    int    `json:"quantity" binding:"required"`
	Location    string `json:"location" binding:"required"`
}

// StockLevel represents stock information from MongoDB
type StockLevel struct {
	ID         primitive.ObjectID `json:"id" bson:"_id,omitempty"`
	ProductSKU string             `json:"product_sku" bson:"product_sku"`
	Warehouse  string             `json:"warehouse" bson:"warehouse"`
	Available  int                `json:"available" bson:"available"`
	Reserved   int                `json:"reserved" bson:"reserved"`
	UpdatedAt  time.Time          `json:"updated_at" bson:"updated_at"`
}

// App holds the application dependencies
type App struct {
	db          *sql.DB
	mongoDB     *mongo.Database
	tracer      trace.Tracer
	serviceName string
}

// Initialize OpenTelemetry
func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "localhost:4317"
	}

	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "inventory-service"
	}

	log.Printf("Initializing OpenTelemetry with endpoint: %s", endpoint)

	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create trace exporter: %w", err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.TraceContext{})

	return tp, nil
}

// Health check handler
func (app *App) healthCheck(c *gin.Context) {
	ctx := c.Request.Context()
	_, span := app.tracer.Start(ctx, "healthCheck")
	defer span.End()

	health := gin.H{
		"status":  "healthy",
		"service": app.serviceName,
	}

	// Check PostgreSQL
	if err := app.db.PingContext(ctx); err != nil {
		log.Printf("PostgreSQL health check failed: %v", err)
		health["postgres"] = "error"
		health["status"] = "unhealthy"
	} else {
		health["postgres"] = "connected"
	}

	// Check MongoDB
	if err := app.mongoDB.Client().Ping(ctx, nil); err != nil {
		log.Printf("MongoDB health check failed: %v", err)
		health["mongodb"] = "error"
		health["status"] = "unhealthy"
	} else {
		health["mongodb"] = "connected"
	}

	if health["status"] == "unhealthy" {
		c.JSON(http.StatusServiceUnavailable, health)
		return
	}

	c.JSON(http.StatusOK, health)
}

// Create inventory item (PostgreSQL)
func (app *App) createItem(c *gin.Context) {
	ctx := c.Request.Context()
	_, span := app.tracer.Start(ctx, "createItem")
	defer span.End()

	var req CreateItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("Creating inventory item: %s (SKU: %s)", req.ProductName, req.SKU)

	query := `
		INSERT INTO inventory (product_name, sku, quantity, location, created_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, created_at
	`

	var item InventoryItem
	item.ProductName = req.ProductName
	item.SKU = req.SKU
	item.Quantity = req.Quantity
	item.Location = req.Location

	err := app.db.QueryRowContext(ctx, query,
		item.ProductName, item.SKU, item.Quantity, item.Location, time.Now(),
	).Scan(&item.ID, &item.CreatedAt)

	if err != nil {
		log.Printf("Error creating inventory item: %v", err)
		span.RecordError(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create item"})
		return
	}

	// Also create stock level in MongoDB
	stockLevel := StockLevel{
		ProductSKU: item.SKU,
		Warehouse:  item.Location,
		Available:  item.Quantity,
		Reserved:   0,
		UpdatedAt:  time.Now(),
	}

	collection := app.mongoDB.Collection("stock_levels")
	_, err = collection.InsertOne(ctx, stockLevel)
	if err != nil {
		log.Printf("Error creating stock level in MongoDB: %v", err)
		// Continue anyway, PostgreSQL is the primary storage
	}

	itemsCreated.Inc()
	requestsTotal.WithLabelValues("POST", "/api/inventory", "201").Inc()
	log.Printf("Inventory item created: ID=%d", item.ID)

	c.JSON(http.StatusCreated, item)
}

// List inventory items (PostgreSQL)
func (app *App) listItems(c *gin.Context) {
	ctx := c.Request.Context()
	_, span := app.tracer.Start(ctx, "listItems")
	defer span.End()

	skip := c.DefaultQuery("skip", "0")
	limit := c.DefaultQuery("limit", "100")

	skipInt, _ := strconv.Atoi(skip)
	limitInt, _ := strconv.Atoi(limit)

	log.Printf("Listing inventory items (skip=%d, limit=%d)", skipInt, limitInt)

	query := `
		SELECT id, product_name, sku, quantity, location, created_at
		FROM inventory
		ORDER BY created_at DESC
		OFFSET $1 LIMIT $2
	`

	rows, err := app.db.QueryContext(ctx, query, skipInt, limitInt)
	if err != nil {
		log.Printf("Error listing inventory: %v", err)
		span.RecordError(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list items"})
		return
	}
	defer rows.Close()

	items := []InventoryItem{}
	for rows.Next() {
		var item InventoryItem
		if err := rows.Scan(&item.ID, &item.ProductName, &item.SKU,
			&item.Quantity, &item.Location, &item.CreatedAt); err != nil {
			log.Printf("Error scanning row: %v", err)
			continue
		}
		items = append(items, item)
	}

	itemsQueried.Inc()
	requestsTotal.WithLabelValues("GET", "/api/inventory", "200").Inc()
	log.Printf("Retrieved %d inventory items", len(items))

	c.JSON(http.StatusOK, items)
}

// Get inventory item by ID (PostgreSQL)
func (app *App) getItem(c *gin.Context) {
	ctx := c.Request.Context()
	_, span := app.tracer.Start(ctx, "getItem")
	defer span.End()

	id := c.Param("id")
	log.Printf("Fetching inventory item: %s", id)

	span.SetAttributes(attribute.String("item.id", id))

	query := `
		SELECT id, product_name, sku, quantity, location, created_at
		FROM inventory
		WHERE id = $1
	`

	var item InventoryItem
	err := app.db.QueryRowContext(ctx, query, id).Scan(
		&item.ID, &item.ProductName, &item.SKU,
		&item.Quantity, &item.Location, &item.CreatedAt,
	)

	if err == sql.ErrNoRows {
		log.Printf("Inventory item not found: %s", id)
		c.JSON(http.StatusNotFound, gin.H{"error": "Item not found"})
		return
	}

	if err != nil {
		log.Printf("Error fetching inventory item: %v", err)
		span.RecordError(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch item"})
		return
	}

	itemsQueried.Inc()
	requestsTotal.WithLabelValues("GET", "/api/inventory/:id", "200").Inc()
	log.Printf("Inventory item retrieved: %d", item.ID)

	c.JSON(http.StatusOK, item)
}

// Get stock levels from MongoDB
func (app *App) getStockLevels(c *gin.Context) {
	ctx := c.Request.Context()
	_, span := app.tracer.Start(ctx, "getStockLevels")
	defer span.End()

	log.Println("Fetching stock levels from MongoDB")

	collection := app.mongoDB.Collection("stock_levels")
	cursor, err := collection.Find(ctx, bson.M{})
	if err != nil {
		log.Printf("Error fetching stock levels: %v", err)
		span.RecordError(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch stock levels"})
		return
	}
	defer cursor.Close(ctx)

	var stockLevels []StockLevel
	if err := cursor.All(ctx, &stockLevels); err != nil {
		log.Printf("Error decoding stock levels: %v", err)
		span.RecordError(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to decode stock levels"})
		return
	}

	requestsTotal.WithLabelValues("GET", "/api/stock-levels", "200").Inc()
	log.Printf("Retrieved %d stock levels", len(stockLevels))

	c.JSON(http.StatusOK, stockLevels)
}

func main() {
	ctx := context.Background()

	// Initialize OpenTelemetry
	tp, err := initTracer(ctx)
	if err != nil {
		log.Fatalf("Failed to initialize tracer: %v", err)
	}
	defer func() {
		if err := tp.Shutdown(ctx); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "inventory-service"
	}

	app := &App{
		tracer:      otel.Tracer(serviceName),
		serviceName: serviceName,
	}

	// Connect to PostgreSQL
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgresql://demo:demo123@localhost:5432/demo?sslmode=disable"
	}

	log.Printf("Connecting to PostgreSQL...")
	app.db, err = sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("Failed to connect to PostgreSQL: %v", err)
	}
	defer app.db.Close()

	// Test PostgreSQL connection
	if err := app.db.PingContext(ctx); err != nil {
		log.Fatalf("Failed to ping PostgreSQL: %v", err)
	}
	log.Println("Connected to PostgreSQL")

	// Create inventory table if not exists
	createTableQuery := `
		CREATE TABLE IF NOT EXISTS inventory (
			id SERIAL PRIMARY KEY,
			product_name VARCHAR(255) NOT NULL,
			sku VARCHAR(100) UNIQUE NOT NULL,
			quantity INTEGER NOT NULL,
			location VARCHAR(255) NOT NULL,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		)
	`
	if _, err := app.db.ExecContext(ctx, createTableQuery); err != nil {
		log.Fatalf("Failed to create inventory table: %v", err)
	}

	// Connect to MongoDB
	mongoURI := os.Getenv("MONGODB_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://demo:demo123@localhost:27017"
	}
	mongoDBName := os.Getenv("MONGODB_DATABASE")
	if mongoDBName == "" {
		mongoDBName = "demo"
	}

	log.Printf("Connecting to MongoDB...")
	mongoClient, err := mongo.Connect(ctx, options.Client().ApplyURI(mongoURI))
	if err != nil {
		log.Fatalf("Failed to connect to MongoDB: %v", err)
	}
	defer mongoClient.Disconnect(ctx)

	// Test MongoDB connection
	if err := mongoClient.Ping(ctx, nil); err != nil {
		log.Fatalf("Failed to ping MongoDB: %v", err)
	}
	app.mongoDB = mongoClient.Database(mongoDBName)
	log.Printf("Connected to MongoDB database: %s", mongoDBName)

	// Set Gin to release mode if not in debug
	if os.Getenv("GIN_MODE") == "" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Create Gin router
	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(gin.Logger())

	// Add OpenTelemetry middleware
	router.Use(otelgin.Middleware(serviceName))

	// Register routes
	router.GET("/health", app.healthCheck)
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))

	router.POST("/api/inventory", app.createItem)
	router.GET("/api/inventory", app.listItems)
	router.GET("/api/inventory/:id", app.getItem)
	router.GET("/api/stock-levels", app.getStockLevels)

	// Start server
	addr := ":8002"
	log.Printf("Inventory service listening on %s", addr)
	if err := router.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
