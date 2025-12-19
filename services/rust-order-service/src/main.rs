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
use chrono::{DateTime, Utc};
use futures::stream::StreamExt;
use opentelemetry_otlp::WithExportConfig;

// Application state
#[derive(Clone)]
struct AppState {
    db: Database,
    nats_client: Option<async_nats::Client>,
    metrics: Arc<Metrics>,
}

impl std::fmt::Debug for AppState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AppState")
            .field("db", &"Database")
            .field("nats_client", &self.nats_client.is_some())
            .field("metrics", &"Metrics")
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

#[derive(Debug, Deserialize)]
struct CreateOrderRequest {
    user_id: i32,
    product_name: String,
    quantity: i32,
    price_per_unit: f64,
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

// Error handling
#[derive(Debug)]
enum AppError {
    DatabaseError(mongodb::error::Error),
    NotFound,
    InternalError(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            AppError::DatabaseError(e) => {
                error!("Database error: {}", e);
                (StatusCode::INTERNAL_SERVER_ERROR, "Database error")
            }
            AppError::NotFound => (StatusCode::NOT_FOUND, "Order not found"),
            AppError::InternalError(msg) => {
                error!("Internal error: {}", msg);
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error")
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
    Json(payload): Json<CreateOrderRequest>,
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
        .with(tracing_subscriber::fmt::layer().json())
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

    // Create application state
    let state = AppState {
        db,
        nats_client,
        metrics,
    };

    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/metrics", get(metrics_handler))
        .route("/api/orders", post(create_order).get(list_orders))
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
