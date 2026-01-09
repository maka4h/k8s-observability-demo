# Project Summary

## What Has Been Created

A complete Kubernetes observability demonstration with three microservices in different languages, all integrated with a full observability stack.

## 🏗️ Project Structure

```
k8s-observability-demo/
├── services/
│   ├── python-user-service/      # FastAPI + PostgreSQL + NATS
│   │   ├── main.py               # Application code
│   │   ├── requirements.txt      # Python dependencies
│   │   ├── Dockerfile            # Container image
│   │   └── README.md
│   │
│   ├── rust-order-service/       # Axum + MongoDB + NATS
│   │   ├── src/main.rs           # Application code
│   │   ├── Cargo.toml            # Rust dependencies
│   │   ├── Dockerfile            # Container image
│   │   └── README.md
│   │
│   └── go-inventory-service/     # Gin + PostgreSQL + MongoDB
│       ├── main.go               # Application code
│       ├── go.mod                # Go dependencies
│       ├── Dockerfile            # Container image
│       └── README.md
│
├── k8s/
│   ├── infrastructure/           # Database and messaging deployments
│   │   ├── postgres.yaml         # PostgreSQL StatefulSet
│   │   ├── mongodb.yaml          # MongoDB StatefulSet
│   │   └── nats.yaml             # NATS Deployment
│   │
│   ├── services/                 # Microservice deployments
│   │   ├── python-user-service.yaml
│   │   ├── rust-order-service.yaml
│   │   └── go-inventory-service.yaml
│   │
│   └── observability/            # Observability configuration
│       ├── otel-collector.yaml
│       ├── tempo-config.yaml
│       ├── prometheus-config.yaml
│       └── grafana-datasources.yaml
│
├── scripts/
│   ├── install-observability.sh # Install observability stack
│   ├── deploy-services.sh        # Deploy all services
│   ├── test-services.sh          # Test all endpoints
│   └── load-test.sh              # Generate load
│
├── docker-compose.yml            # Local development environment
├── Makefile                      # Convenient commands
├── README.md                     # Main documentation
├── QUICKSTART.md                 # Getting started guide
├── OBSERVABILITY.md              # Implementation details
└── .gitignore

```

## 🎯 Services Overview

### 1. Python User Service (Port 8000)
- **Framework**: FastAPI
- **Database**: PostgreSQL
- **Messaging**: NATS (publisher)
- **Features**:
  - User CRUD operations
  - SQLAlchemy ORM
  - Event publishing on user creation
  - Auto-instrumentation with OpenTelemetry

**Endpoints**:
- `POST /api/users` - Create user
- `GET /api/users` - List users
- `GET /api/users/{id}` - Get user
- `DELETE /api/users/{id}` - Delete user
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics

### 2. Rust Order Service (Port 8001)
- **Framework**: Axum
- **Database**: MongoDB
- **Messaging**: NATS (publisher)
- **Features**:
  - Order management
  - Async MongoDB driver
  - Event publishing on order creation
  - Tracing instrumentation with `#[instrument]`

**Endpoints**:
- `POST /api/orders` - Create order
- `GET /api/orders` - List orders
- `GET /api/orders/{id}` - Get order
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics

### 3. Go Inventory Service (Port 8002)
- **Framework**: Gin
- **Databases**: PostgreSQL + MongoDB
- **Features**:
  - Inventory management
  - Dual database (relational + document)
  - Stock level tracking
  - OpenTelemetry middleware

**Endpoints**:
- `POST /api/inventory` - Create inventory item
- `GET /api/inventory` - List inventory
- `GET /api/inventory/{id}` - Get item
- `GET /api/stock-levels` - Get stock levels (MongoDB)
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics

## 📊 Observability Stack

### Metrics (Prometheus)
- Automatic scraping via ServiceMonitors
- 15-day retention
- Custom business metrics
- RED metrics (Rate, Errors, Duration)

### Logs (Loki)
- JSON structured logging
- 7-day retention
- Automatic label extraction
- Correlation with traces

### Traces (Tempo)
- OpenTelemetry OTLP ingestion
- Distributed tracing across services
- Context propagation
- 24-hour retention

### Visualization (Grafana)
- Unified dashboard
- Pre-configured datasources
- Explore interface
- Trace to logs correlation

## 🚀 Quick Start Commands

### Local Development (Docker Compose)

```bash
# Start everything
make deploy-local

# Test services
make test-local

# Generate load
make load-test-local

# View logs
make logs-local

# Cleanup
make clean-local
```

### Kubernetes Deployment

```bash
# Install observability stack
make install-observability

# Build and deploy services
make deploy-k8s

# Port forward to access
make port-forward-grafana
make port-forward-services

# Test services
make test

# Generate load
make load-test

# Check status
make status-k8s

# Cleanup
make clean-k8s
```

## 🔑 Key Features

### ✨ Minimal Code Changes for Observability

**Python**: Uses `opentelemetry-instrument` wrapper - **0 code changes**
```bash
opentelemetry-instrument uvicorn main:app
```

**Rust**: Uses `#[instrument]` macro - **1 line per function**
```rust
#[instrument]
async fn create_order(...) { }
```

**Go**: Uses middleware - **1 line for entire service**
```go
router.Use(otelgin.Middleware("inventory-service"))
```

### 📈 Automatic Instrumentation

All services automatically capture:
- ✅ HTTP request/response traces
- ✅ Database query spans
- ✅ Error tracking
- ✅ Context propagation
- ✅ Metrics (requests, duration, errors)
- ✅ Structured logs with trace correlation

### 🔗 Service Communication

```
User API → PostgreSQL
    ↓
  NATS Event
    ↓
Order API → MongoDB
    ↓
Query Inventory → PostgreSQL + MongoDB
```

All traced end-to-end!

### 📊 Metrics Exposed

Each service exposes:
- `http_requests_total` - Request count by method, endpoint, status
- `http_request_duration_seconds` - Request latency histogram
- Custom business metrics (users created, orders placed, etc.)

### 🔍 Distributed Tracing

See complete request flows:
1. User creates account (User Service → PostgreSQL)
2. Event published to NATS
3. Order created (Order Service → MongoDB)
4. Inventory checked (Inventory Service → PostgreSQL + MongoDB)

Each step is a span in a single trace!

## 💡 What Makes This Special

### 1. **Multi-Language Support**
Demonstrates observability patterns in Python, Rust, and Go - showing that the approach works across languages.

### 2. **Real-World Architecture**
Not just "Hello World" - includes:
- Multiple databases (PostgreSQL, MongoDB)
- Message queues (NATS)
- Service-to-service communication
- Realistic data models

### 3. **Production-Ready**
- Health checks
- Graceful shutdown
- Resource limits
- Structured logging
- Error handling

### 4. **Minimal Intrusion**
Observability is added with **minimal changes** to business logic:
- Python: ~10 lines
- Rust: ~25 lines
- Go: ~30 lines

### 5. **Complete Observability**
Not just metrics or just logs - full **three-pillar observability**:
- Metrics for aggregation
- Logs for debugging
- Traces for distributed understanding

### 6. **Cost-Effective**
Uses open-source tools only:
- No license fees
- Configurable retention periods
- Sampling for cost control

## 🎓 Learning Resources

### Documentation Files

1. **README.md** - Architecture overview and setup
2. **QUICKSTART.md** - Step-by-step getting started
3. **OBSERVABILITY.md** - Deep dive into implementation
4. **Service READMEs** - Language-specific details

### Example Queries

**Prometheus** (Metrics):
```promql
# Request rate
sum(rate(http_requests_total[5m])) by (service)

# Error rate
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)

# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

**Loki** (Logs):
```logql
# All errors
{namespace="demo"} |= "error"

# User service logs with trace correlation
{app="python-user-service"} | json | line_format "{{.trace_id}}"
```

**Tempo** (Traces):
- Search by service name
- Filter by duration
- Find errors automatically

## 🔧 Customization Ideas

### Add More Services
1. Create new service in any language
2. Add OpenTelemetry instrumentation (1-2 lines)
3. Expose `/metrics` endpoint
4. Deploy to K8s with ServiceMonitor

### Add Custom Metrics
```python
# Python
from prometheus_client import Counter
my_metric = Counter('my_metric', 'Description')
my_metric.inc()
```

### Add Alerting
Create Prometheus AlertManager rules:
```yaml
- alert: HighErrorRate
  expr: sum(rate(http_requests_total{status=~"5.."}[5m])) > 10
```

### Create Dashboards
Import pre-built dashboards or create custom ones in Grafana.

## 🐛 Troubleshooting

### Services Won't Start
```bash
# Check logs
docker-compose logs
kubectl logs -n demo -l app=python-user-service

# Check dependencies
docker-compose ps
kubectl get pods -n demo
```

### No Metrics
```bash
# Test metrics endpoint
curl http://localhost:8000/metrics

# Check Prometheus targets
open http://localhost:9090/targets
```

### No Traces
```bash
# Verify Tempo endpoint
kubectl get svc -n observability tempo

# Check sampling rate
echo $OTEL_TRACES_SAMPLER_ARG
```

## 📚 Next Steps

1. **Run the demo locally**: `make deploy-local`
2. **Explore Grafana**: Create dashboards, query data
3. **Modify services**: Add your own endpoints
4. **Deploy to K8s**: Test in cluster environment
5. **Add alerting**: Set up AlertManager
6. **Customize**: Adapt for your use case

## 🤝 Contributing

This is a demonstration project. Feel free to:
- Add more services
- Improve instrumentation
- Add more dashboards
- Share your learnings

## 📄 License

MIT License - use this however you want!

---

**You now have a complete, production-ready observability demo!** 🎉

Start with `make deploy-local` and explore from there. Check QUICKSTART.md for detailed instructions.
