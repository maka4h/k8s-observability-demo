use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use mongodb::{
    bson::{doc, oid::ObjectId, DateTime as BsonDateTime},
    Client, Collection, Database,
};
use prometheus::{Encoder, IntCounter, Histogram, TextEncoder, register_int_counter, register_histogram};
use serde::{Deserialize, Serialize};
use std::{net::SocketAddr, sync::Arc};
use tower_http::trace::TraceLayer;
use tracing::{info, warn, error, instrument};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use tracing_opentelemetry::OpenTelemetrySpanExt;
use chrono::{DateTime, Utc};
use futures::stream::StreamExt;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry::trace::TraceContextExt;
use opentelemetry::global;
use opentelemetry::propagation::Injector;
use opentelemetry_sdk::propagation::TraceContextPropagator;

// Application state
#[derive(Clone)]
struct AppState {
    db: Database,
    nats_client: Option<async_nats::Client>,
    metrics: Arc<Metrics>,
    http_client: reqwest::Client,
    user_service_url: String,
    inventory_service_url: String,
}

impl std::fmt::Debug for AppState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AppState")
            .field("db", &"Database")
            .field("nats_client", &self.nats_client.is_some())
            .field("metrics", &"Metrics")
            .field("http_client", &"HttpClient")
            .field("user_service_url", &self.user_service_url)
            .field("inventory_service_url", &self.inventory_service_url)
            .finish()
    }
}

// Prometheus metrics
struct Metrics {
    requests_total: IntCounter,
    orders_created: IntCounter,
    orders_queried: IntCounter,
    request_duration: Histogram,
}

impl Metrics {
    fn new() -> Self {
        Self {
            requests_total: register_int_counter!("http_requests_total", "Total HTTP requests").unwrap(),
            orders_created: register_int_counter!("orders_created_total", "Total orders created").unwrap(),
            orders_queried: register_int_counter!("orders_queried_total", "Total order queries").unwrap(),
            request_duration: register_histogram!("http_request_duration_seconds", "HTTP request duration").unwrap(),
        }
    }
}

// Order model
#[derive(Debug, Serialize, Deserialize, Clone)]
struct Order {
    #[serde(rename = "_id", skip_serializing_if = "Option::is_none")]
    id: Option<ObjectId>,
    user_id: i32,
    product_name: String,
    quantity: i32,
    total_price: f64,
    status: String,
    #[serde(with = "bson::serde_helpers::chrono_datetime_as_bson_datetime")]
    created_at: DateTime<Utc>,
}

// User model from user-service
#[derive(Debug, Serialize, Deserialize, Clone)]
struct User {
    id: i32,
    name: String,
    email: String,
}

// Simple request for basic order creation (no validation)
#[derive(Debug, Deserialize)]
struct CreateOrderRequestSimple {
    user_id: i32,
    product_name: String,
    quantity: i32,
    price_per_unit: f64,
}

// Request for validated order creation
#[derive(Debug, Deserialize)]
struct CreateOrderRequest {
    user_id: i32,
    product_id: String,
    quantity: i32,
}

// Inventory item from inventory-service
#[derive(Debug, Serialize, Deserialize, Clone)]
struct InventoryItem {
    id: i32,
    product_name: String,
    sku: String,
    quantity: i32,
    location: String,
    #[serde(default)]
    price: f64,  // Optional field with default
}

#[derive(Debug, Deserialize)]
struct ListQuery {
    #[serde(default)]
    skip: u64,
    #[serde(default = "default_limit")]
    limit: i64,
}

fn default_limit() -> i64 {
    100
}

// Helper to get trace ID from current span
fn get_trace_id() -> String {
    use opentelemetry::trace::TraceContextExt;
    let context = tracing::Span::current().context();
    let span = context.span();
    let span_context = span.span_context();
    span_context.trace_id().to_string()
}

// Error handling
#[derive(Debug)]
enum AppError {
    DatabaseError(mongodb::error::Error),
    NotFound,
    InternalError(String),
    HttpError(String),
    UserNotFound(i32),
    InsufficientInventory(String, i32, i32), // product_name, requested, available
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            AppError::DatabaseError(e) => {
                error!("Database error: {}", e);
                (StatusCode::INTERNAL_SERVER_ERROR, "Database error".to_string())
            }
            AppError::NotFound => (StatusCode::NOT_FOUND, "Order not found".to_string()),
            AppError::InternalError(msg) => {
                error!("Internal error: {}", msg);
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string())
            }
            AppError::HttpError(msg) => {
                error!("HTTP error: {}", msg);
                (StatusCode::INTERNAL_SERVER_ERROR, "HTTP request failed".to_string())
            }
            AppError::UserNotFound(user_id) => {
                error!("User not found: {}", user_id);
                (StatusCode::BAD_REQUEST, format!("User {} not found", user_id))
            }
            AppError::InsufficientInventory(product, requested, available) => {
                error!("Insufficient inventory for {}: requested {}, available {}", product, requested, available);
                (StatusCode::BAD_REQUEST, format!("Insufficient inventory for {}: requested {}, available {}", product, requested, available))
            }
        };

        (status, Json(serde_json::json!({ "error": error_message }))).into_response()
    }
}

impl From<mongodb::error::Error> for AppError {
    fn from(err: mongodb::error::Error) -> Self {
        AppError::DatabaseError(err)
    }
}

// Health check handler
#[instrument]
async fn health_check(State(state): State<AppState>) -> impl IntoResponse {
    info!("Health check requested");
    
    // Check MongoDB connection
    let db_status = match state.db.list_collection_names(None).await {
        Ok(_) => "connected",
        Err(e) => {
            error!("Database health check failed: {}", e);
            "error"
        }
    };

    let nats_status = match &state.nats_client {
        Some(client) if client.connection_state() == async_nats::connection::State::Connected => "connected",
        _ => "disconnected",
    };

    let health = serde_json::json!({
        "status": if db_status == "connected" { "healthy" } else { "unhealthy" },
        "service": "order-service",
        "database": db_status,
        "nats": nats_status,
    });

    Json(health)
}

// Metrics handler
#[instrument]
async fn metrics_handler() -> impl IntoResponse {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();
    let mut buffer = vec![];
    encoder.encode(&metric_families, &mut buffer).unwrap();
    
    (
        StatusCode::OK,
        [("Content-Type", encoder.format_type().to_string())],
        buffer,
    )
}

// Create order handler
#[instrument(skip(state))]
async fn create_order(
    State(state): State<AppState>,
    Json(payload): Json<CreateOrderRequestSimple>,
) -> Result<(StatusCode, Json<Order>), AppError> {
    info!("Creating order for user {}", payload.user_id);

    let collection: Collection<Order> = state.db.collection("orders");

    let order = Order {
        id: None,
        user_id: payload.user_id,
        product_name: payload.product_name.clone(),
        quantity: payload.quantity,
        total_price: payload.price_per_unit * payload.quantity as f64,
        status: "pending".to_string(),
        created_at: Utc::now(),
    };

    let result = collection.insert_one(order.clone(), None).await?;
    let order_id = result.inserted_id.as_object_id().unwrap();

    let mut created_order = order;
    created_order.id = Some(order_id);

    // Publish event to NATS
    if let Some(client) = &state.nats_client {
        let event = serde_json::json!({
            "event": "order.created",
            "order_id": order_id.to_string(),
            "user_id": payload.user_id,
            "timestamp": Utc::now().to_rfc3339(),
        });
        
        if let Err(e) = client.publish("order.created", event.to_string().into()).await {
            error!("Failed to publish NATS event: {}", e);
        } else {
            info!("Published order.created event for order {}", order_id);
        }
    }

    state.metrics.orders_created.inc();
    state.metrics.requests_total.inc();
    
    info!("Order created successfully: {}", order_id);

    Ok((StatusCode::CREATED, Json(created_order)))
}

// Helper to inject trace context into HTTP headers
struct HeaderInjector<'a>(&'a mut reqwest::header::HeaderMap);

impl<'a> Injector for HeaderInjector<'a> {
    fn set(&mut self, key: &str, value: String) {
        if let Ok(name) = reqwest::header::HeaderName::from_bytes(key.as_bytes()) {
            if let Ok(val) = reqwest::header::HeaderValue::from_str(&value) {
                self.0.insert(name, val);
            }
        }
    }
}

// Create validated order - calls user-service and inventory-service to verify and get details
#[instrument(skip(state))]
async fn create_validated_order(
    State(state): State<AppState>,
    Json(payload): Json<CreateOrderRequest>,
) -> Result<(StatusCode, Json<Order>), AppError> {
    let trace_id = get_trace_id();
    info!(trace_id = %trace_id, "Creating VALIDATED order for user {} with product {}", payload.user_id, payload.product_id);

    // Step 1: Validate that the user exists by calling user-service
    info!(trace_id = %trace_id, "Step 1: Validating user {} exists via user-service", payload.user_id);
    let user_url = format!("{}/api/users/{}", state.user_service_url, payload.user_id);
    
    // Inject trace context into HTTP headers
    let cx = tracing::Span::current().context();
    let mut headers = reqwest::header::HeaderMap::new();
    global::get_text_map_propagator(|propagator| {
        propagator.inject_context(&cx, &mut HeaderInjector(&mut headers));
    });
    
    let user_response = state.http_client
        .get(&user_url)
        .headers(headers)
        .send()
        .await
        .map_err(|e| AppError::HttpError(format!("Failed to call user-service: {}", e)))?;
    
    if !user_response.status().is_success() {
        error!(trace_id = %trace_id, "User {} not found in user-service", payload.user_id);
        return Err(AppError::UserNotFound(payload.user_id));
    }

    let user: User = user_response
        .json()
        .await
        .map_err(|e| AppError::HttpError(format!("Failed to parse user response: {}", e)))?;
    
    info!(trace_id = %trace_id, "User validated: {} ({})", user.name, user.email);

    // Step 2: Get product details from inventory-service
    info!(trace_id = %trace_id, "Step 2: Fetching product {} from inventory-service", payload.product_id);
    let inventory_url = format!("{}/api/inventory/{}", state.inventory_service_url, payload.product_id);
    
    // Inject trace context into HTTP headers
    let cx = tracing::Span::current().context();
    let mut headers = reqwest::header::HeaderMap::new();
    global::get_text_map_propagator(|propagator| {
        propagator.inject_context(&cx, &mut HeaderInjector(&mut headers));
    });
    
    let inventory_response = state.http_client
        .get(&inventory_url)
        .headers(headers)
        .send()
        .await
        .map_err(|e| AppError::HttpError(format!("Failed to call inventory-service: {}", e)))?;
    
    if !inventory_response.status().is_success() {
        error!(trace_id = %trace_id, "Product {} not found in inventory-service", payload.product_id);
        return Err(AppError::HttpError(format!("Product '{}' not found in inventory", payload.product_id)));
    }

    let inventory_item: InventoryItem = inventory_response
        .json()
        .await
        .map_err(|e| AppError::HttpError(format!("Failed to parse inventory response: {}", e)))?;
    
    // Use a default price if not available
    let price = if inventory_item.price > 0.0 { inventory_item.price } else { 999.99 };
    
    info!(trace_id = %trace_id, "Product found: {} - ${} (stock: {})", inventory_item.product_name, price, inventory_item.quantity);

    // Check if sufficient quantity is available
    if inventory_item.quantity < payload.quantity {
        error!(trace_id = %trace_id, "Insufficient inventory for {}: requested {}, available {}", 
               inventory_item.product_name, payload.quantity, inventory_item.quantity);
        return Err(AppError::HttpError(format!(
            "Insufficient inventory: requested {}, available {}", 
            payload.quantity, 
            inventory_item.quantity
        )));
    }
    
    info!(trace_id = %trace_id, "Inventory validated: {} available (requested {})", inventory_item.quantity, payload.quantity);

    // Step 3: Create the order
    info!(trace_id = %trace_id, "Step 3: Creating order in database");
    let collection: Collection<Order> = state.db.collection("orders");

    let total_price = price * payload.quantity as f64;
    let order = Order {
        id: None,
        user_id: payload.user_id,
        product_name: inventory_item.product_name.clone(),
        quantity: payload.quantity,
        total_price,
        status: "pending".to_string(),
        created_at: Utc::now(),
    };

    let result = collection.insert_one(order.clone(), None).await?;
    let order_id = result.inserted_id.as_object_id().unwrap();

    let mut created_order = order;
    created_order.id = Some(order_id);

    // Publish event to NATS
    if let Some(client) = &state.nats_client {
        let event = serde_json::json!({
            "event": "order.created",
            "order_id": order_id.to_string(),
            "user_id": payload.user_id,
            "user_name": user.name,
            "product_id": payload.product_id,
            "product_name": inventory_item.product_name,
            "quantity": payload.quantity,
            "total_price": total_price,
            "timestamp": Utc::now().to_rfc3339(),
        });
        
        if let Err(e) = client.publish("order.created", event.to_string().into()).await {
            error!("Failed to publish NATS event: {}", e);
        } else {
            info!("Published order.created event for order {}", order_id);
        }
    }

    state.metrics.orders_created.inc();
    state.metrics.requests_total.inc();
    
    info!(trace_id = %trace_id, "✅ Validated order created: {} for user {} ({}), product: {} x{}", 
          order_id, user.name, user.email, inventory_item.product_name, payload.quantity);

    Ok((StatusCode::CREATED, Json(created_order)))
}

// List orders handler
#[instrument(skip(state))]
async fn list_orders(
    State(state): State<AppState>,
    Query(query): Query<ListQuery>,
) -> Result<Json<Vec<Order>>, AppError> {
    info!("Listing orders (skip={}, limit={})", query.skip, query.limit);

    let collection: Collection<Order> = state.db.collection("orders");
    
    let options = mongodb::options::FindOptions::builder()
        .skip(query.skip)
        .limit(query.limit)
        .build();

    let mut cursor = collection.find(None, options).await?;
    let mut orders = Vec::new();

    while let Some(result) = cursor.next().await {
        match result {
            Ok(order) => orders.push(order),
            Err(e) => error!("Error reading order: {}", e),
        }
    }

    state.metrics.orders_queried.inc();
    state.metrics.requests_total.inc();
    
    info!("Retrieved {} orders", orders.len());

    Ok(Json(orders))
}

// Get order by ID handler
#[instrument(skip(state))]
async fn get_order(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<Order>, AppError> {
    info!("Fetching order: {}", id);

    let object_id = ObjectId::parse_str(&id)
        .map_err(|e| AppError::InternalError(format!("Invalid ID: {}", e)))?;

    let collection: Collection<Order> = state.db.collection("orders");
    let order = collection
        .find_one(doc! { "_id": object_id }, None)
        .await?
        .ok_or(AppError::NotFound)?;

    state.metrics.orders_queried.inc();
    state.metrics.requests_total.inc();
    
    info!("Order retrieved: {}", id);

    Ok(Json(order))
}

// Initialize tracing
fn init_tracing() {
    let otlp_endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://localhost:4317".to_string());
    
    let service_name = std::env::var("OTEL_SERVICE_NAME")
        .unwrap_or_else(|_| "order-service".to_string());

    info!("Initializing OpenTelemetry with endpoint: {}", otlp_endpoint);

    // Set global propagator for trace context
    global::set_text_map_propagator(TraceContextPropagator::new());

    // Initialize OpenTelemetry tracer
    let tracer = opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(
            opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint(otlp_endpoint)
        )
        .with_trace_config(
            opentelemetry_sdk::trace::config()
                .with_resource(opentelemetry_sdk::Resource::new(vec![
                    opentelemetry::KeyValue::new("service.name", service_name),
                ]))
        )
        .install_batch(opentelemetry_sdk::runtime::Tokio)
        .expect("Failed to initialize tracer");

    // Create tracing subscriber with OpenTelemetry layer
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::from_default_env()
            .add_directive(tracing::Level::INFO.into()))
        .with(
            tracing_subscriber::fmt::layer()
                .json()
                .with_current_span(true)
                .with_span_list(false)
        )
        .with(tracing_opentelemetry::layer().with_tracer(tracer))
        .init();
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    init_tracing();

    info!("Starting order service...");

    // Initialize metrics
    let metrics = Arc::new(Metrics::new());

    // Connect to MongoDB
    let mongodb_uri = std::env::var("MONGODB_URI")
        .unwrap_or_else(|_| "mongodb://demo:demo123@localhost:27017".to_string());
    let mongodb_database = std::env::var("MONGODB_DATABASE")
        .unwrap_or_else(|_| "demo".to_string());

    info!("Connecting to MongoDB at {}", mongodb_uri);
    let client = Client::with_uri_str(&mongodb_uri).await?;
    let db = client.database(&mongodb_database);
    
    // Test connection
    db.list_collection_names(None).await?;
    info!("Connected to MongoDB database: {}", mongodb_database);

    // Connect to NATS
    let nats_client = match std::env::var("NATS_URL") {
        Ok(nats_url) => {
            info!("Connecting to NATS at {}", nats_url);
            match async_nats::connect(&nats_url).await {
                Ok(client) => {
                    info!("Connected to NATS");
                    Some(client)
                }
                Err(e) => {
                    error!("Failed to connect to NATS: {}", e);
                    None
                }
            }
        }
        Err(_) => {
            warn!("NATS_URL not set, NATS client not initialized");
            None
        }
    };

    // Create HTTP client for service-to-service calls
    let http_client = reqwest::Client::new();
    
    // Get user service URL
    let user_service_url = std::env::var("USER_SERVICE_URL")
        .unwrap_or_else(|_| "http://python-user-service:8000".to_string());
    info!("User service URL configured: {}", user_service_url);

    // Get inventory service URL
    let inventory_service_url = std::env::var("INVENTORY_SERVICE_URL")
        .unwrap_or_else(|_| "http://go-inventory-service:8002".to_string());
    info!("Inventory service URL configured: {}", inventory_service_url);

    // Create application state
    let state = AppState {
        db,
        nats_client,
        metrics,
        http_client,
        user_service_url,
        inventory_service_url,
    };

    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/metrics", get(metrics_handler))
        .route("/api/orders", post(create_order).get(list_orders))
        .route("/api/orders/validated", post(create_validated_order))
        .route("/api/orders/:id", get(get_order))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Start server
    let addr = SocketAddr::from(([0, 0, 0, 0], 8001));
    info!("Order service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
