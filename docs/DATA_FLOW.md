# Observability Data Flow: Metrics, Logs, and Traces

This document explains how telemetry data flows from your services to Grafana using **OpenTelemetry Collector** as a unified, vendor-agnostic observability agent.

## Overview Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                    Microservice (Any of the 3)                   │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐          │
│  │   Metrics    │  │     Logs     │  │   Traces       │          │
│  │  (Prometheus │  │  (Structured │  │ (OpenTelemetry │          │
│  │   client)    │  │     JSON)    │  │    SDK)        │          │
│  └──────┬───────┘  └──────┬───────┘  └───────┬────────┘          │
│         │                 │                  │                   │
│    /metrics              stdout            OTLP gRPC             │
│   endpoint              (JSON logs)        :4317                 │
│         │                 │                  │                   │
└─────────┼─────────────────┼──────────────────┼───────────────────┘
          │                 │                  │
          │                 │                  │
          │                 │                  │ PUSH (OTLP)
          │                 │                  ▼
          │                 │          ┌──────────────────────┐
          │                 │          │  OpenTelemetry       │
          │                 └─────────►│    Collector         │◄────┐
          │                            │                      │     │
          │ PULL (scrape)              │  - OTLP Receiver     │     │
          └───────────────────────────►│  - Prometheus Scraper│     │
                                       │  - Filelog Receiver  │     │
                                       │  - Batch Processor   │     │
                                       └──────────┬───────────┘     │
                                                  │                 │
                                    ┌─────────────┼─────────────┐   │
                                    │             │             │   │
                                    ▼             ▼             ▼   │
                              ┌──────────┐  ┌─────────┐  ┌─────────┐
                              │Prometheus│  │  Loki   │  │  Tempo  │
                              │ (Metrics)│  │ (Logs)  │  │(Traces) │
                              └────┬─────┘  └────┬────┘  └────┬────┘
                                   │             │            │
                                   └─────────────┴────────────┘
                                                 │
                                                 │ Query
                                                 ▼
                                          ┌─────────────┐
                                          │   Grafana   │
                    │             │
                    │ - Dashboards│
                    │ - Explore   │
                    │ - Alerts    │
                    └─────────────┘
```

---

## 1. Metrics Flow (PULL Model)

### Architecture

```
Service exposes /metrics endpoint
         ↓
   [Prometheus]
   Scrapes every 30 seconds via HTTP GET
         ↓
   Stores as time-series data
         ↓
   [Grafana]
   Queries Prometheus using PromQL
```

### How It Works in Our Demo

**Service Side** - Expose metrics endpoint:

```python
# Python Service Example
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
from fastapi import Response

# Define metric once
requests_total = Counter('http_requests_total', 'Total requests', 
                         ['method', 'endpoint', 'status'])

# Increment in your code
@app.post("/api/users")
async def create_user():
    # ... business logic ...
    requests_total.labels(method="POST", endpoint="/api/users", status=201).inc()
    return user

# Expose metrics endpoint
@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

**Prometheus Side** - Scrape configuration:

```yaml
# prometheus-config.yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'user-service'
    static_configs:
      - targets: ['python-user-service:8000']
    metrics_path: '/metrics'
  
  - job_name: 'order-service'
    static_configs:
      - targets: ['rust-order-service:8001']
    
  - job_name: 'inventory-service'
    static_configs:
      - targets: ['go-inventory-service:8002']
```

**Kubernetes ServiceMonitor** (auto-discovery):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: python-user-service
spec:
  selector:
    matchLabels:
      app: python-user-service
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

### Key Characteristics

- ✅ **PULL model**: Prometheus actively scrapes services
- ✅ **HTTP endpoint**: Services expose `/metrics` on demand
- ✅ **Scrape interval**: Configurable (default 15-30 seconds)
- ✅ **Text format**: Plain text Prometheus format
- ✅ **Service discovery**: Kubernetes ServiceMonitors auto-discover services
- ✅ **No agent needed**: Services only need to expose endpoint
- ✅ **Stateless**: Services don't need to push or queue data

### What Gets Collected

Example metrics output from `/metrics`:

```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",endpoint="/api/users",status="200"} 1543
http_requests_total{method="POST",endpoint="/api/users",status="201"} 89

# HELP http_request_duration_seconds HTTP request duration
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{le="0.1"} 1200
http_request_duration_seconds_bucket{le="0.5"} 1500
http_request_duration_seconds_sum 450.5
http_request_duration_seconds_count 1632
```

---

## 2. Logs Flow (PUSH Model)

### Architecture

```
Service writes logs to stdout/stderr
         ↓
   Container runtime captures logs
         ↓
   [OpenTelemetry Collector]
   Filelog receiver monitors container logs
   Reads from /var/lib/docker/containers
         ↓
   Adds labels (service_name, deployment_environment)
   Processes with batch processor
         ↓
   Exports via OTLP HTTP to Loki
         ↓
   [Loki]
   Receives and indexes logs
   Stores with labels (not full-text indexing!)
         ↓
   [Grafana]
   Queries Loki using LogQL
```

### How It Works in Our Demo

**Service Side** - Just log to stdout:

```python
# Python Service - No special code needed!
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Structured JSON logging (better for querying)
logger.info("User created", extra={
    "user_id": 123,
    "email": "user@example.com",
    "trace_id": "abc123"
})

# Output:
# {"timestamp":"2025-12-19T10:30:45","level":"info","msg":"User created",
#  "user_id":123,"email":"user@example.com","trace_id":"abc123"}
```

```rust
// Rust Service - Logs automatically JSON formatted
use tracing::{info, error};

#[instrument]
async fn create_order(payload: CreateOrderRequest) {
    info!(user_id = payload.user_id, "Creating order");
    // Logs output in JSON format automatically
}

// Output:
// {"timestamp":"2025-12-19T10:30:45","level":"info","target":"order_service",
//  "span":{"name":"create_order"},"fields":{"user_id":123},"msg":"Creating order"}
```

```go
// Go Service - Standard logging
log.Printf("Creating inventory item: %s (SKU: %s)", req.ProductName, req.SKU)

// Output:
// 2025/12/19 10:30:45 Creating inventory item: Gaming Mouse (SKU: MOUSE-001)
```

**OpenTelemetry Collector** - Unified collection:

```yaml
# otel-collector-config.yaml
receivers:
  filelog:
    include:
      - /var/lib/docker/containers/*/*.log
  
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 10s
  
  resource:
    attributes:
      - key: deployment.environment
        value: demo
        action: insert

exporters:
  otlphttp/loki:
    endpoint: http://loki:3100/otlp
  
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true
  
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
```

**Loki Side** - Storage and indexing:

Loki indexes **only labels** (not log content), making it cost-effective:

- `service_name=user-service`
- `deployment_environment=demo`
- `container_name=python-user-service`

The actual log content is compressed and stored without full-text indexing.

### Key Characteristics

- ✅ **PUSH model**: OTel Collector pushes logs to Loki via OTLP
- ✅ **Stdout/stderr**: Services just log normally (12-factor app pattern)
- ✅ **DaemonSet/Sidecar**: Flexible deployment patterns
- ✅ **Automatic labels**: Metadata extracted from containers
- ✅ **Structured JSON**: Easy to query and filter
- ✅ **Unified agent**: Same collector for logs, metrics, and traces
- ✅ **Vendor-agnostic**: OTLP standard protocol
- ✅ **Cost-effective**: Only labels indexed (not full log content)

### Querying in Grafana

```logql
# All logs from user service
{service_name="user-service"}

# Logs containing "error"
{app="python-user-service"} |= "error"

# Parse JSON and filter
{app="python-user-service"} | json | user_id="123"

# Logs with specific trace ID
{namespace="demo"} | json | trace_id="abc123"
```

---

## 3. Traces Flow (PUSH Model via OTLP)

### Architecture

```
Service creates spans via OpenTelemetry SDK
         ↓
   [OpenTelemetry SDK]
   Batches spans in memory
         ↓
   Exports via OTLP protocol (gRPC or HTTP)
   to OTEL_EXPORTER_OTLP_ENDPOINT
         ↓
   [Tempo]
   Receives spans on port 4317 (gRPC) or 4318 (HTTP)
   Links spans by trace_id
   Stores complete traces
         ↓
   [Grafana]
   Queries Tempo by trace ID or search criteria
```

### How It Works in Our Demo

**Python** (auto-instrumentation):

```bash
# No code changes needed - just wrap your command!
opentelemetry-instrument \
  --traces_exporter otlp \
  --exporter_otlp_endpoint http://tempo:4317 \
  --service_name user-service \
  uvicorn main:app

# Environment variables work too
export OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
export OTEL_SERVICE_NAME=user-service
opentelemetry-instrument uvicorn main:app
```

The wrapper automatically:

- Creates spans for all HTTP requests
- Traces database queries (SQLAlchemy)
- Captures exceptions
- Propagates trace context via headers

**Rust** (manual initialization, then automatic):

```rust
// Initialize once at startup in main.rs
fn init_tracing() {
    let otlp_endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://tempo:4317".to_string());
  
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
                    opentelemetry::KeyValue::new("service.name", "order-service"),
                ]))
        )
        .install_batch(opentelemetry_sdk::runtime::Tokio)
        .expect("Failed to initialize tracer");

    tracing_subscriber::registry()
        .with(tracing_opentelemetry::layer().with_tracer(tracer))
        .init();
}

// Then just annotate functions - spans created automatically!
#[instrument]
async fn create_order(payload: CreateOrderRequest) -> Result<Order> {
    // Span created automatically for this function
    // All inner function calls also traced
    let result = db.insert_one(order).await?;
    Ok(result)
}
```

**Go** (middleware + manual spans):

```go
// Initialize once at startup
func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
    endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
  
    exporter, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithEndpoint(endpoint),
        otlptracegrpc.WithInsecure(),
    )
  
    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(resource.NewWithAttributes(
            semconv.ServiceName("inventory-service"),
        )),
    )
  
    otel.SetTracerProvider(tp)
    return tp, nil
}

// Add middleware - automatically traces all HTTP requests
router := gin.New()
router.Use(otelgin.Middleware("inventory-service"))

// Optional: Add manual spans for detailed operations
func (app *App) getItem(c *gin.Context) {
    ctx, span := app.tracer.Start(c.Request.Context(), "getItem")
    defer span.End()
  
    // Add custom attributes
    span.SetAttributes(attribute.String("item.id", id))
  
    // Your business logic
    item, err := db.QueryRow(ctx, query, id)
    if err != nil {
        span.RecordError(err)
        return
    }
}
```

### Context Propagation

This is the **magic** that makes distributed tracing work:

```
Client Request
    ↓
Service A (Python User Service)
    │
    ├─ Creates Trace ID: xyz789
    ├─ Creates Span ID: span001
    │
    ├─ HTTP Request to Service B
    │  Headers:
    │    traceparent: 00-xyz789-span001-01
    │
    ↓
Service B (Rust Order Service)
    │
    ├─ Extracts trace context from headers
    ├─ Continues same Trace ID: xyz789
    ├─ Creates new Span ID: span002
    ├─ Sets parent: span001
    │
    └─ Both services export to Tempo
  
Result: Single trace with linked spans!
```

### Key Characteristics

- ✅ **PUSH model**: Services push spans to Tempo
- ✅ **OTLP protocol**: Standard OpenTelemetry protocol (gRPC or HTTP)
- ✅ **Batching**: SDK batches spans for efficiency (reduces network calls)
- ✅ **Asynchronous**: Export happens in background, doesn't block app
- ✅ **Sampling**: Only trace a % of requests (configurable)
- ✅ **Context propagation**: Trace IDs flow across service boundaries
- ✅ **Automatic instrumentation**: HTTP, DB, and framework spans created automatically

### Trace Structure in Tempo

```json
{
  "traceID": "xyz789",
  "spans": [
    {
      "spanID": "span001",
      "parentSpanID": null,
      "operationName": "POST /api/users",
      "serviceName": "user-service",
      "startTime": 1702987845000000,
      "duration": 120000,
      "tags": {
        "http.method": "POST",
        "http.status_code": 201,
        "user.email": "user@example.com"
      }
    },
    {
      "spanID": "span002",
      "parentSpanID": "span001",
      "operationName": "INSERT users",
      "serviceName": "user-service",
      "startTime": 1702987845050000,
      "duration": 45000,
      "tags": {
        "db.system": "postgresql",
        "db.statement": "INSERT INTO users..."
      }
    }
  ]
}
```

---

## Why Separate Collectors?

Each telemetry type has fundamentally different characteristics:

| Aspect                  | Metrics                  | Logs               | Traces              |
| ----------------------- | ------------------------ | ------------------ | ------------------- |
| **Volume**        | Low (aggregated)         | High (every event) | Medium (sampled)    |
| **Collection**    | PULL (scrape)            | PUSH (stream)      | PUSH (export)       |
| **Storage**       | Time-series DB           | Compressed text    | Span database       |
| **Query Pattern** | Aggregations             | Text search        | Trace ID lookup     |
| **Retention**     | Weeks/Months             | Days/Week          | Hours/Days          |
| **Cardinality**   | Low (10-100 per service) | Unlimited          | Medium              |
| **Index**         | All data                 | Labels only        | Trace IDs           |
| **Cost**          | Low                      | Medium             | Low (with sampling) |

### Benefits of Separate Systems

1. **Optimized Storage**

   - Prometheus: Efficient time-series compression
   - Loki: Logs stored in chunks, only labels indexed
   - Tempo: Trace-oriented storage with trace ID index
2. **Independent Scaling**

   - Scale metrics storage separately from log storage
   - High log volume doesn't affect trace performance
   - Different retention policies per system
3. **Specialized Query Languages**

   - **PromQL** for metrics: `rate(http_requests_total[5m])`
   - **LogQL** for logs: `{app="user-service"} |= "error"`
   - **TraceQL** for traces: `{service.name="user-service" && http.status_code=500}`
4. **Collection Method Matches Data Type**

   - Metrics: PULL works well (services expose state)
   - Logs: PUSH works well (continuous stream)
   - Traces: PUSH works well (spans need to be sent together)

---

## The Magic: Correlation in Grafana

Even though data flows through separate pipelines, Grafana **unifies** them:

### Example Workflow

```
1. View Metrics Dashboard
   └─ See spike in error rate (Prometheus)
   
2. Click "View Related Logs"
   └─ Grafana queries Loki for same time range
   └─ Filters by same service labels
   
3. See Error Logs
   └─ Logs show trace_id: "abc123"
   
4. Click trace_id Link
   └─ Grafana queries Tempo for trace "abc123"
   
5. View Complete Trace
   └─ See all spans across all services
   └─ Identify exactly where error occurred
```

### How Correlation Works

**1. Trace ID in Logs** - OpenTelemetry automatically injects:

```python
# OpenTelemetry automatically adds trace context to logs
logger.info("User created")
# Output includes: {"msg":"User created","trace_id":"abc123","span_id":"span001"}
```

**2. Grafana Datasource Configuration**:

```yaml
# grafana-datasources.yaml
datasources:
  - name: Loki
    type: loki
    url: http://loki:3100
    jsonData:
      derivedFields:
        - datasourceUid: tempo
          matcherRegex: "traceID=(\\w+)"
          name: TraceID
          url: "$${__value.raw}"
        
  - name: Tempo
    type: tempo
    url: http://tempo:3200
    jsonData:
      tracesToLogs:
        datasourceUid: 'loki'
        tags: ['service_name']
        spanStartTimeShift: '-1h'
        spanEndTimeShift: '1h'
      tracesToMetrics:
        datasourceUid: 'prometheus'
```

**3. Exemplars** (links from metrics to traces):

```python
# Prometheus can store exemplars linking metrics to traces
http_requests_total{method="POST",endpoint="/api/users",status="500"} 1 {trace_id="abc123"}
```

**4. Time Correlation**:

- All systems use same timestamps
- Grafana can show metrics, logs, and traces for same time range
- Automatically correlates by time + service labels

### Visual Correlation Flow

```
┌──────────────────────────────────────────────────────┐
│              Grafana Unified View                    │
├──────────────────────────────────────────────────────┤
│                                                      │
│  [Metrics Dashboard]                                 │
│  http_requests_total{status="500"} = 15 ← Spike!     │
│         │                                            │
│         │ Click "View Related Logs"                  │
│         ▼                                            │
│  [Logs View]                                         │
│  {app="user-service"} |= "error"                     │
│  2025-12-19 10:30:45 ERROR Database timeout          │
│    trace_id: "abc123" ← Click this                   │
│         │                                            │
│         │ Jump to Trace                              │
│         ▼                                            │
│  [Trace View]                                        │
│  Trace: abc123                                       │
│  ├─ POST /api/users (120ms)                          │
│  │  ├─ INSERT users (45ms)                           │
│  │  └─ PostgreSQL query (80ms) ← ERROR HERE!         │
│  └─ NATS publish (5ms)                               │
│                                                      │
└──────────────────────────────────────────────────────┘
```

---

## Environment Variables for Configuration

All services use standard OpenTelemetry environment variables:

```bash
# Traces
OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
OTEL_SERVICE_NAME=my-service
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1  # 10% sampling rate

# Logs
LOG_LEVEL=info
LOG_FORMAT=json

# Application-specific
DATABASE_URL=postgresql://user:pass@host:5432/db
NATS_URL=nats://nats:4222
```

**Benefits:**

- ✅ No code changes to modify configuration
- ✅ Same variables across all languages
- ✅ Easy to change per environment (dev, staging, prod)
- ✅ Standard OpenTelemetry convention

---

## Performance and Overhead

### Metrics (Prometheus)

- **Collection overhead**: ~0.5% CPU per scrape
- **Service overhead**: Minimal (counters in memory)
- **Network**: Small (one HTTP GET every 30s)
- **Storage**: ~1-2 GB per day per 100 services

### Logs (Loki via OpenTelemetry Collector)

- **Collection overhead**: ~2-5% CPU (OTel Collector filelog receiver)
- **Service overhead**: None (just stdout)
- **Network**: Medium (continuous stream to OTel Collector)
- **Storage**: ~500 MB per day per 100 services

### Traces (Tempo)

- **Collection overhead**: ~1-3% CPU with 10% sampling
- **Service overhead**: Minimal with batching
- **Network**: Low with batching and sampling
- **Storage**: ~2-5 GB per day per 100 services (10% sampling)

### Total Observability Overhead

- **With proper configuration**: < 5% total overhead
- **Key optimizations**:
  - Trace sampling (10% in production)
  - Async export (doesn't block requests)
  - Batching (reduces network calls)
  - Efficient storage (Loki doesn't index content)

---

## Summary

### Unified Telemetry Pipeline with OpenTelemetry Collector

**OpenTelemetry Collector** acts as a vendor-agnostic, unified agent that:

1. **Collects** logs, metrics, and traces from multiple sources
2. **Processes** data with batching, filtering, and enrichment
3. **Exports** to multiple backends simultaneously

1. **Metrics (Prometheus)**

   - OTel Collector **scrapes** `/metrics` endpoints every 30s
   - Services expose metrics in memory
   - Exported via Prometheus Remote Write
   - Time-series storage optimized for aggregations
   - Query with PromQL

2. **Logs (Loki)**

   - OTel Collector filelog receiver monitors container logs
   - Services write to stdout/stderr (no modification needed)
   - Exported via OTLP HTTP to Loki
   - Label-based indexing (cost-effective)
   - Query with LogQL

3. **Traces (Tempo)**

   - Services send traces via OTLP gRPC to OTel Collector (port 4317)
   - OTel Collector batches and exports to Tempo
   - Distributed tracing with context propagation
   - Query with TraceQL

### Unified in Grafana

Despite using a unified collector, Grafana provides:

- ✅ Single pane of glass for all telemetry
- ✅ Correlation between metrics, logs, traces
- ✅ Jump from metric → log → trace
- ✅ Time-correlated views
- ✅ Trace-to-logs linking via trace_id
- ✅ Service-level correlation
- ✅ Trace ID linking

### Why This Architecture?

- **Specialized storage** for each data type
- **Optimized queries** (PromQL, LogQL, TraceQL)
- **Independent scaling** and retention
- **Cost-effective** (Loki doesn't index content, traces sampled)
- **Standard protocols** (Prometheus, OTLP, etc.)
- **Flexible** (can replace any component)

This is the **modern observability stack** using **OpenTelemetry Collector** as a unified, vendor-agnostic agent! 🚀

---

## Quick Reference

| Data Type   | Collection | Agent              | Protocol     | Port      | Storage    | Query   |
| ----------- | ---------- | ------------------ | ------------ | --------- | ---------- | ------- |
| **Metrics** | PULL/PUSH  | OTel Collector     | Prometheus   | 8000-8002 | Prometheus | PromQL  |
| **Logs**    | PUSH       | OTel Collector     | OTLP HTTP    | 3100      | Loki       | LogQL   |
| **Traces**  | PUSH       | OTel Collector     | OTLP gRPC    | 4317      | Tempo      | TraceQL |

**OpenTelemetry Collector Ports:**
- 4317: OTLP gRPC (traces from services)
- 4318: OTLP HTTP 
- 8888: Internal metrics
- 8889: Prometheus exporter

All queryable from **Grafana** on port **3000**.
