# Kubernetes Observability Demo

A comprehensive demonstration of observability in Kubernetes with microservices written in Python, Rust, and Go.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐.  │
│  │   Python     │    │     Rust     │    │      Go      │   │
│  │  User API    │◄──►│   Order API  │◄──►│ Inventory API│   │
│  │  (FastAPI)   │    │    (Axum)    │    │    (Gin)     │   │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘   │
│         │                   │                    │          │
│         ▼                   ▼                    ▼          │
│  ┌──────────┐       ┌──────────┐        ┌──────────┐        │
│  │PostgreSQL│       │ MongoDB  │        │PostgreSQL│        │
│  └──────────┘       └──────────┘        │ MongoDB  │        │
│         │                   │           └──────────┘        │
│         └───────┬───────────┘                               │
│                 ▼                                           │
│           ┌──────────┐                                      │
│           │   NATS   │                                      │
│           └──────────┘                                      │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         Observability Stack                          │   │
│  │  Prometheus │ Loki │ Tempo │ Grafana                 │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Services

### Python User Service (FastAPI)

- **Port:** 8000
- **Endpoints:**
  - `GET /api/users` - List users
  - `POST /api/users` - Create user
  - `GET /api/users/{id}` - Get user by ID
  - `GET /health` - Health check
  - `GET /metrics` - Prometheus metrics
- **Dependencies:** PostgreSQL, NATS

### Rust Order Service (Axum)

- **Port:** 8001
- **Endpoints:**
  - `GET /api/orders` - List orders
  - `POST /api/orders` - Create order
  - `GET /api/orders/{id}` - Get order by ID
  - `GET /health` - Health check
  - `GET /metrics` - Prometheus metrics
- **Dependencies:** MongoDB, NATS

### Go Inventory Service (Gin)

- **Port:** 8002
- **Endpoints:**
  - `GET /api/inventory` - List inventory
  - `POST /api/inventory` - Add inventory item
  - `GET /api/inventory/{id}` - Get item by ID
  - `GET /health` - Health check
  - `GET /metrics` - Prometheus metrics
- **Dependencies:** PostgreSQL, MongoDB

## Observability Features

All services include **zero-code-change** observability through OpenTelemetry:

### Metrics (Prometheus)

- HTTP request counts, duration, status codes
- Database query metrics
- Message queue metrics
- Custom business metrics

### Logs (Loki)

- Structured JSON logging
- Automatic correlation with traces
- Log levels: DEBUG, INFO, WARN, ERROR

### Traces (Tempo)

- Distributed tracing across all services
- Automatic span creation for HTTP requests
- Database query spans
- NATS message spans

## Quick Start

### Prerequisites

- Docker & Docker Compose
- kubectl
- Helm 3
- Kubernetes cluster (minikube, kind, or cloud provider)

### Local Development (Docker Compose)

```bash
# Start all services and dependencies
docker-compose up -d

# View logs
docker-compose logs -f

# Test endpoints
curl http://localhost:8000/api/users
curl http://localhost:8001/api/orders
curl http://localhost:8002/api/inventory

# Access Grafana
open http://localhost:3000  # user: admin, pass: admin
```

### Kubernetes Deployment

```bash
# Create namespace
kubectl create namespace demo

# Deploy infrastructure (PostgreSQL, MongoDB, NATS)
kubectl apply -f k8s/infrastructure/

# Deploy observability stack
kubectl apply -f k8s/observability/

# Deploy microservices
kubectl apply -f k8s/services/

# Port forward to access services
kubectl port-forward -n demo service/python-user-service 8000:8000
kubectl port-forward -n demo service/rust-order-service 8001:8001
kubectl port-forward -n demo service/go-inventory-service 8002:8002

# Access Grafana
kubectl port-forward -n observability service/grafana 3000:3000
```

### Helm Deployment (Recommended)

```bash
# Install observability stack
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Deploy using provided Helm values
./scripts/install-observability.sh

# Deploy services
helm install demo-services ./helm/demo-services
```

## Testing the Setup

### Generate Traffic

```bash
# Run load test script
./scripts/load-test.sh

# Or manually
for i in {1..100}; do
  curl -X POST http://localhost:8000/api/users -H "Content-Type: application/json" \
    -d "{\"name\":\"User$i\",\"email\":\"user$i@example.com\"}"
  sleep 0.1
done
```

### View Observability Data

1. **Grafana Dashboard:** http://localhost:3000

   - Default credentials: `admin/admin`
   - Pre-configured dashboards for each service
2. **Prometheus:** http://localhost:9090

   - Query metrics directly
   - Example: `http_requests_total{service="user-service"}`
3. **Explore Traces:**

   - Go to Grafana → Explore → Select Tempo
   - Search for traces by service or time range

## Project Structure

```
.
├── services/
│   ├── python-user-service/      # FastAPI service
│   ├── rust-order-service/        # Axum service
│   └── go-inventory-service/      # Gin service
├── k8s/
│   ├── infrastructure/            # Databases, NATS
│   ├── observability/             # Prometheus, Grafana, Loki, Tempo
│   └── services/                  # Microservices deployments
├── helm/
│   └── demo-services/             # Helm chart for all services
├── scripts/
│   ├── install-observability.sh   # Setup observability stack
│   └── load-test.sh               # Generate test traffic
└── docker-compose.yml              # Local development
```

## Key Features

### ✨ Minimal Code Changes for Observability

All services use OpenTelemetry auto-instrumentation:

- **Python:** `opentelemetry-instrument` wrapper
- **Rust:** Tracing middleware layer
- **Go:** Middleware handlers

No manual span creation needed for basic operations!

### 📊 Unified Dashboards

Pre-configured Grafana dashboards showing:

- Service RED metrics (Rate, Errors, Duration)
- Database connection pools
- Message queue throughput
- Infrastructure metrics

### 🔍 Distributed Tracing

See complete request flows:

```
User API → PostgreSQL → NATS → Order API → MongoDB
```

### 🎯 Service Discovery

Automatic discovery via Kubernetes ServiceMonitor CRDs.

## Environment Variables

Each service supports these observability environment variables:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
OTEL_SERVICE_NAME=user-service
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1  # 10% sampling
LOG_LEVEL=INFO
```

## Troubleshooting

### No metrics showing up?

- Check ServiceMonitor is created: `kubectl get servicemonitors -n demo`
- Verify Prometheus targets: `kubectl port-forward -n observability svc/prometheus 9090:9090`

### No traces in Tempo?

- Verify OTEL_EXPORTER_OTLP_ENDPOINT is correct
- Check trace sampling rate (might be too low)
- Review service logs for OTLP export errors

### Logs missing in Loki?

- Ensure Promtail DaemonSet is running: `kubectl get ds -n observability`
- Check pod logs are being written to stdout/stderr

## Next Steps

1. **Add custom metrics** for business KPIs
2. **Configure alerts** in Prometheus AlertManager
3. **Set up dashboards** for specific use cases
4. **Implement log-based metrics** in Loki
5. **Add exemplars** to link metrics with traces

## License

MIT
