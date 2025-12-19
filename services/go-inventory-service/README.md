# Go Inventory Service

Gin-based inventory management service with PostgreSQL and MongoDB integration.

## Features

- ✅ RESTful API for inventory management
- ✅ PostgreSQL for primary inventory storage
- ✅ MongoDB for stock level tracking
- ✅ Prometheus metrics endpoint
- ✅ Health check endpoint
- ✅ OpenTelemetry distributed tracing with minimal code changes
- ✅ Automatic instrumentation via middleware

## Endpoints

- `POST /api/inventory` - Create inventory item (writes to both PostgreSQL and MongoDB)
- `GET /api/inventory` - List inventory items from PostgreSQL (with pagination)
- `GET /api/inventory/{id}` - Get inventory item by ID from PostgreSQL
- `GET /api/stock-levels` - Get stock levels from MongoDB
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics

## Environment Variables

```bash
DATABASE_URL=postgresql://demo:demo123@postgres:5432/demo?sslmode=disable
MONGODB_URI=mongodb://demo:demo123@mongodb:27017
MONGODB_DATABASE=demo
OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
OTEL_SERVICE_NAME=inventory-service
GIN_MODE=release
LOG_LEVEL=info
```

## Running Locally

```bash
# Install dependencies
go mod download

# Build
go build -o inventory-service

# Run
./inventory-service

# Or use go run
go run main.go
```

## Testing

```bash
# Create inventory item
curl -X POST http://localhost:8002/api/inventory \
  -H "Content-Type: application/json" \
  -d '{
    "product_name": "Gaming Mouse",
    "sku": "MOUSE-001",
    "quantity": 100,
    "location": "Warehouse A"
  }'

# List inventory
curl http://localhost:8002/api/inventory

# Get specific item
curl http://localhost:8002/api/inventory/1

# Get stock levels (from MongoDB)
curl http://localhost:8002/api/stock-levels

# Check metrics
curl http://localhost:8002/metrics

# Health check
curl http://localhost:8002/health
```

## Observability Features

### Minimal Code Changes for Tracing

Using the `otelgin.Middleware()` provides automatic instrumentation:
- HTTP request/response tracing
- Automatic span creation
- Context propagation
- No manual span management needed!

Additional tracing with manual spans uses simple `tracer.Start()` calls where needed.

### Custom Metrics

- `http_requests_total` - Total HTTP requests by method, endpoint, status
- `http_request_duration_seconds` - Request duration histogram
- `inventory_items_created_total` - Total inventory items created
- `inventory_items_queried_total` - Total inventory queries

### Database Integration

- **PostgreSQL**: Primary storage for inventory items
- **MongoDB**: Stock level tracking with real-time updates
- Both databases checked in health endpoint
