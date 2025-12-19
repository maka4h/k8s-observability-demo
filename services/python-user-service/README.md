# Python User Service

FastAPI-based user management service with PostgreSQL and NATS integration.

## Features

- ✅ RESTful API for user management (CRUD operations)
- ✅ PostgreSQL database with SQLAlchemy ORM
- ✅ NATS messaging for event publishing
- ✅ Prometheus metrics endpoint
- ✅ Health check endpoint
- ✅ OpenTelemetry auto-instrumentation (zero code changes needed!)
- ✅ Structured JSON logging

## Endpoints

- `POST /api/users` - Create a new user
- `GET /api/users` - List all users (with pagination)
- `GET /api/users/{id}` - Get user by ID
- `DELETE /api/users/{id}` - Delete user
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics

## Environment Variables

```bash
DATABASE_URL=postgresql://demo:demo123@postgres:5432/demo
NATS_URL=nats://nats:4222
OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
OTEL_SERVICE_NAME=user-service
LOG_LEVEL=INFO
```

## Running Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Run with auto-instrumentation
opentelemetry-instrument \
  --traces_exporter otlp \
  --service_name user-service \
  uvicorn main:app --host 0.0.0.0 --port 8000

# Or run directly (without tracing)
python main.py
```

## Testing

```bash
# Create a user
curl -X POST http://localhost:8000/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe","email":"john@example.com"}'

# List users
curl http://localhost:8000/api/users

# Get specific user
curl http://localhost:8000/api/users/1

# Check metrics
curl http://localhost:8000/metrics

# Health check
curl http://localhost:8000/health
```

## Observability Features

### Automatic Instrumentation

Using `opentelemetry-instrument` wrapper provides automatic:
- HTTP request/response tracing
- Database query tracing
- Exception tracking
- Span attributes for all operations

**No manual span creation needed!**

### Custom Metrics

- `http_requests_total` - Total HTTP requests by method, endpoint, status
- `http_request_duration_seconds` - Request duration histogram
- `users_created_total` - Total users created
- `users_queried_total` - Total user queries

### Events Published to NATS

- `user.created` - When a new user is created
- `user.deleted` - When a user is deleted
