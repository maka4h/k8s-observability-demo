# Rust Order Service

Axum-based order management service with MongoDB and NATS integration.

## Features

- ✅ RESTful API for order management
- ✅ MongoDB database with async driver
- ✅ NATS messaging for event publishing
- ✅ Prometheus metrics endpoint
- ✅ Health check endpoint
- ✅ OpenTelemetry distributed tracing
- ✅ Structured JSON logging with tracing

## Endpoints

- `POST /api/orders` - Create a new order
- `GET /api/orders` - List all orders (with pagination)
- `GET /api/orders/{id}` - Get order by ID
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics

## Environment Variables

```bash
MONGODB_URI=mongodb://demo:demo123@mongodb:27017
MONGODB_DATABASE=demo
NATS_URL=nats://nats:4222
OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
OTEL_SERVICE_NAME=order-service
RUST_LOG=info
```

## Running Locally

```bash
# Build
cargo build --release

# Run
cargo run

# Or run the binary directly
./target/release/order-service
```

## Testing

```bash
# Create an order
curl -X POST http://localhost:8001/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 1,
    "product_name": "Laptop",
    "quantity": 2,
    "price_per_unit": 999.99
  }'

# List orders
curl http://localhost:8001/api/orders

# Get specific order (use ID from create response)
curl http://localhost:8001/api/orders/507f1f77bcf86cd799439011

# Check metrics
curl http://localhost:8001/api/metrics

# Health check
curl http://localhost:8001/health
```

## Observability Features

### Tracing Instrumentation

Using `#[instrument]` macro from `tracing` crate provides automatic:
- Function entry/exit spans
- Automatic argument capture
- Error tracking
- Nested span creation

### Custom Metrics

- `http_requests_total` - Total HTTP requests
- `orders_created_total` - Total orders created
- `orders_queried_total` - Total order queries
- `http_request_duration_seconds` - Request duration histogram

### Events Published to NATS

- `order.created` - When a new order is created

### Logging

All logs are output in JSON format for easy parsing by log aggregators like Loki.
