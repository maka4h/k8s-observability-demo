# Quick Start Guide

This guide will help you get the observability demo up and running quickly.

## Prerequisites

- Docker & Docker Compose
- kubectl
- Helm 3
- A Kubernetes cluster (minikube, kind, or cloud provider)
- (Optional) make

## Option 1: Local Development with Docker Compose (Easiest)

Perfect for quick testing and development without Kubernetes.

### Step 1: Start Everything

```bash
# Using Make
make deploy-local

# Or using Docker Compose directly
docker-compose up -d
```

### Step 2: Wait for Services to Start

```bash
# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### Step 3: Test the Services

```bash
# Run test script
make test-local

# Or manually test
curl http://localhost:8000/health
curl http://localhost:8001/health
curl http://localhost:8002/health
```

### Step 4: Access Observability Tools

- **Grafana**: http://localhost:3000 (admin / admin)
- **Prometheus**: http://localhost:9090
- **User Service**: http://localhost:8000
- **Order Service**: http://localhost:8001
- **Inventory Service**: http://localhost:8002

### Step 5: Generate Traffic

```bash
# Run load test
make load-test-local

# Or specify duration and rate
./scripts/load-test.sh http://localhost:8000 http://localhost:8001 http://localhost:8002 30 5
```

### Step 6: Explore Observability

1. Open Grafana at http://localhost:3000
2. Go to **Explore**
3. Select **Prometheus** datasource and query: `http_requests_total`
4. Select **Tempo** datasource to view traces
5. Select **Loki** datasource to view logs

### Cleanup

```bash
make clean-local
```

---

## Option 2: Kubernetes Deployment (Production-like)

### Step 1: Install Observability Stack

```bash
# Install Prometheus, Grafana, Loki, Tempo
make install-observability

# Wait for completion (may take 2-3 minutes)
kubectl get pods -n observability --watch
```

### Step 2: Deploy Services

```bash
# Build images and deploy
make deploy-k8s

# Check deployment status
make status-k8s
```

### Step 3: Access Services

```bash
# Port forward Grafana (in one terminal)
make port-forward-grafana

# Port forward services (in another terminal)
make port-forward-services
```

### Step 4: Test Services

```bash
# Run tests
make test

# Or manually
curl http://localhost:8000/api/users
```

### Step 5: Generate Load

```bash
make load-test
```

### Cleanup

```bash
make clean-k8s
```

---

## Understanding the Architecture

### Services

1. **Python User Service** (FastAPI)
   - Manages users
   - PostgreSQL for storage
   - Publishes events to NATS

2. **Rust Order Service** (Axum)
   - Manages orders
   - MongoDB for storage
   - Subscribes to NATS events

3. **Go Inventory Service** (Gin)
   - Manages inventory
   - PostgreSQL + MongoDB
   - Dual-database example

### Observability Components

- **OpenTelemetry Collector**: Unified agent collecting logs, metrics, and traces
- **Prometheus**: Stores time-series metrics
- **Loki**: Stores logs with label-based indexing
- **Tempo**: Stores distributed traces
- **Grafana**: Unified dashboard for all observability data

### Key Features

✨ **Minimal Code Changes**
- Python: Uses `opentelemetry-instrument` wrapper
- Rust: Uses `#[instrument]` macros
- Go: Uses middleware (`otelgin.Middleware`)

📊 **Automatic Instrumentation**
- HTTP requests traced automatically
- Database queries tracked
- Errors captured

🔗 **Distributed Tracing**
- See complete request flows across services
- Context propagation via headers

---

## Common Operations

### View Logs

```bash
# Local (Docker Compose)
docker-compose logs -f python-user-service
docker-compose logs -f rust-order-service
docker-compose logs -f go-inventory-service

# Kubernetes
kubectl logs -n demo -l app=python-user-service -f
kubectl logs -n demo -l app=rust-order-service -f
kubectl logs -n demo -l app=go-inventory-service -f
```

### Check Metrics

```bash
# User service metrics
curl http://localhost:8000/metrics

# Order service metrics
curl http://localhost:8001/metrics

# Inventory service metrics
curl http://localhost:8002/metrics
```

### Access Databases Directly

```bash
# PostgreSQL (Docker Compose)
docker-compose exec postgres psql -U demo -d demo

# MongoDB (Docker Compose)
docker-compose exec mongodb mongosh --username demo --password demo123 demo

# NATS monitoring
open http://localhost:8222
```

### Rebuild Individual Service

```bash
# Python
docker-compose build python-user-service
docker-compose up -d python-user-service

# Rust
docker-compose build rust-order-service
docker-compose up -d rust-order-service

# Go
docker-compose build go-inventory-service
docker-compose up -d go-inventory-service
```

---

## Grafana Dashboard Examples

### 1. Service Overview Dashboard

Create a dashboard with these panels:

**Request Rate**
```promql
sum(rate(http_requests_total[5m])) by (service)
```

**Error Rate**
```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
```

**Request Duration (P95)**
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

### 2. Traces Query

In Grafana Explore with Tempo datasource:
- Search by service name
- Filter by duration > 1s
- Find traces with errors

### 3. Logs Query

In Grafana Explore with Loki datasource:
```logql
{namespace="demo"} |= "error"
```

---

## Troubleshooting

### Services won't start

```bash
# Check if ports are already in use
lsof -i :8000
lsof -i :8001
lsof -i :8002

# Check Docker logs
docker-compose logs
```

### No metrics in Prometheus

- Verify service is exposing `/metrics`
- Check Prometheus targets: http://localhost:9090/targets
- Verify ServiceMonitor is created (K8s only)

### No traces in Tempo

- Check OTEL_EXPORTER_OTLP_ENDPOINT environment variable
- Verify Tempo is running: `kubectl get pods -n observability`
- Check service logs for OpenTelemetry errors

### Database connection errors

- Ensure databases are ready before services start
- Check connection strings in environment variables
- Verify network connectivity

---

## Next Steps

1. **Add Custom Metrics**: Instrument business-specific metrics
2. **Create Alerts**: Set up Prometheus AlertManager rules
3. **Build Dashboards**: Create service-specific Grafana dashboards
4. **Add Exemplars**: Link metrics to traces
5. **Implement SLOs**: Define and track Service Level Objectives

## Resources

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Grafana Tutorials](https://grafana.com/tutorials/)
- [Kubernetes Observability](https://kubernetes.io/docs/tasks/debug/)
