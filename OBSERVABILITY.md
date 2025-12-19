# Observability Implementation Guide

This document explains how observability is implemented in each service with **minimal code changes**.

## Design Philosophy

The goal is to add comprehensive observability (metrics, logs, traces) with **minimal intrusion** into business logic. We achieve this through:

1. **Auto-instrumentation** where possible
2. **Middleware/decorators** for cross-cutting concerns
3. **Simple annotations** for manual instrumentation
4. **Standardized libraries** across all services

---

## Python Service (FastAPI + OpenTelemetry)

### Key Approach: Auto-instrumentation Wrapper

The Python service uses OpenTelemetry's automatic instrumentation, requiring **ZERO code changes** to the main application logic.

### Implementation

**1. Install instrumentation packages:**
```python
# requirements.txt
opentelemetry-instrumentation-fastapi
opentelemetry-instrumentation-sqlalchemy
opentelemetry-exporter-otlp
```

**2. Run with auto-instrumentation:**
```bash
opentelemetry-instrument \
  --traces_exporter otlp \
  --service_name user-service \
  uvicorn main:app
```

**That's it!** The wrapper automatically:
- Creates spans for HTTP requests
- Traces database queries
- Captures exceptions
- Propagates trace context

### What Gets Instrumented Automatically:

- ✅ All FastAPI routes
- ✅ SQLAlchemy database queries
- ✅ HTTP client requests
- ✅ Exception tracking

### Manual Metrics (Prometheus)

For custom business metrics, we add minimal code:

```python
from prometheus_client import Counter

# Define once
user_created = Counter('users_created_total', 'Total users created')

# Use in handler
def create_user(...):
    # ... business logic ...
    user_created.inc()  # ← Single line
```

### Code Changes Required: **~5 lines per custom metric**

---

## Rust Service (Axum + Tracing)

### Key Approach: Procedural Macros

Rust uses the `tracing` crate with procedural macros for zero-overhead observability.

### Implementation

**1. Add dependencies:**
```toml
[dependencies]
tracing = "0.1"
tracing-opentelemetry = "0.22"
opentelemetry-otlp = "0.14"
```

**2. Initialize once at startup:**
```rust
// main.rs - one-time setup
fn init_tracing() {
    let tracer = opentelemetry_otlp::new_pipeline()
        .tracing()
        .install_batch(opentelemetry_sdk::runtime::Tokio)
        .expect("Failed to initialize tracer");

    tracing_subscriber::registry()
        .with(tracing_opentelemetry::layer().with_tracer(tracer))
        .init();
}
```

**3. Instrument functions with a single attribute:**
```rust
#[instrument]  // ← Single line annotation
async fn create_order(payload: CreateOrderRequest) -> Result<Order> {
    // ... business logic ...
    // All function calls, errors, and returns are automatically traced
}
```

### What Gets Instrumented:

- ✅ Function entry/exit with `#[instrument]`
- ✅ HTTP requests via `TraceLayer` middleware
- ✅ Automatic error capture
- ✅ Structured logging

### Code Changes Required: **1 line per function**

---

## Go Service (Gin + OpenTelemetry)

### Key Approach: Middleware

Go uses OpenTelemetry middleware for automatic HTTP tracing.

### Implementation

**1. Add OpenTelemetry packages:**
```go
import (
    "go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
    "go.opentelemetry.io/otel"
)
```

**2. Initialize tracer once:**
```go
// main.go - one-time setup
func initTracer(ctx context.Context) {
    exporter, _ := otlptracegrpc.New(ctx, ...)
    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
    )
    otel.SetTracerProvider(tp)
}
```

**3. Add middleware to router:**
```go
router := gin.New()
router.Use(otelgin.Middleware("inventory-service"))  // ← Single line
```

**4. Optional: Manual spans for specific operations:**
```go
func getItem(c *gin.Context) {
    ctx, span := tracer.Start(c.Request.Context(), "getItem")  // ← 1 line
    defer span.End()  // ← 1 line
    
    // ... business logic ...
}
```

### What Gets Instrumented Automatically:

- ✅ All HTTP requests (via middleware)
- ✅ Request/response metadata
- ✅ Error status codes

### Code Changes Required: 
- **1 line** for middleware
- **2 lines** per manual span (optional)

---

## Comparison: Code Changes Needed

| Feature | Python | Rust | Go |
|---------|--------|------|-----|
| **HTTP Tracing** | 0 lines (auto) | 1 line (middleware) | 1 line (middleware) |
| **Database Tracing** | 0 lines (auto) | 1 line per function | 2 lines per query |
| **Error Tracking** | 0 lines (auto) | 0 lines (auto with #[instrument]) | 0 lines (auto with middleware) |
| **Custom Metrics** | 2 lines per metric | 2 lines per metric | 2 lines per metric |
| **Log Correlation** | 0 lines (auto) | 0 lines (auto) | Manual (optional) |

---

## Configuration: Environment Variables

All services use the same environment variables for consistency:

```bash
# OpenTelemetry Configuration
OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
OTEL_SERVICE_NAME=my-service
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1  # 10% sampling

# Application Configuration
LOG_LEVEL=info
```

**No code changes needed to modify these!**

---

## What You Get Automatically

### 1. Distributed Tracing

```
User Request → User Service → PostgreSQL
                ↓
            NATS Event → Order Service → MongoDB
```

Each hop is automatically traced with:
- Span ID and Trace ID
- Timing information
- Request/response data
- Error details

### 2. Metrics

Every service automatically exposes:

```
http_requests_total{method="GET",endpoint="/api/users",status="200"}
http_request_duration_seconds_bucket{le="0.1"}
```

Plus custom business metrics:
```
users_created_total
orders_created_total
inventory_items_queried_total
```

### 3. Logs

All logs include:
- Timestamp
- Log level
- Service name
- Trace ID (for correlation)
- Structured fields (JSON)

### 4. Correlation

The killer feature: **automatic correlation** between:
- Metrics → Traces (via exemplars)
- Logs → Traces (via trace ID)
- Traces → Metrics (via service name)

---

## Best Practices

### ✅ DO:

1. **Use auto-instrumentation** whenever possible
2. **Add custom metrics** for business KPIs
3. **Use structured logging** (JSON)
4. **Set sampling rates** appropriate for your traffic
5. **Tag/label** spans and metrics consistently

### ❌ DON'T:

1. **Don't** create spans for every function (use selectively)
2. **Don't** log sensitive data (PII, passwords, tokens)
3. **Don't** sample at 100% in production (expensive)
4. **Don't** block on telemetry exports (use async)
5. **Don't** forget to set resource attributes (service.name, etc.)

---

## Advanced: Adding Custom Instrumentation

### Python: Custom Span

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

def complex_operation():
    with tracer.start_as_current_span("complex_operation"):
        # ... work ...
        span = trace.get_current_span()
        span.set_attribute("user_id", user_id)
```

### Rust: Custom Span

```rust
use tracing::info_span;

fn complex_operation() {
    let span = info_span!("complex_operation", user_id = %user_id);
    let _enter = span.enter();
    // ... work ...
}
```

### Go: Custom Attributes

```go
span.SetAttributes(
    attribute.String("user.id", userId),
    attribute.Int("order.count", count),
)
```

---

## Performance Impact

### Overhead Comparison

| Operation | Overhead | Mitigation |
|-----------|----------|------------|
| Auto-instrumentation | ~1-2% | Built-in optimization |
| Manual spans | <0.1% per span | Use selectively |
| Metrics collection | <1% | Sampling |
| Log export | ~2-5% | Async export, buffering |
| Trace export | ~1-3% | Sampling (10% recommended) |

### Recommendations:

1. **Start with 10% trace sampling** in production
2. **Increase sampling** temporarily when debugging
3. **Use async exporters** (all our examples do)
4. **Monitor exporter queue sizes**

---

## Troubleshooting

### Problem: No traces appearing

**Check:**
1. OTEL_EXPORTER_OTLP_ENDPOINT is correct
2. Tempo is running and accessible
3. Service logs for export errors
4. Sampling rate isn't 0

### Problem: High memory usage

**Solution:**
- Reduce trace sampling rate
- Decrease batch size in exporter config
- Enable tail-based sampling

### Problem: Traces incomplete

**Solution:**
- Verify context propagation headers
- Check for blocking operations
- Ensure spans are properly closed

---

## Summary

### Total Code Changes Per Service:

**Python (FastAPI)**
- Setup: Run with `opentelemetry-instrument` wrapper
- Per-service setup: 0 lines
- Per-endpoint: 0 lines
- Custom metrics: ~2 lines each
- **Total: ~10 lines for complete observability**

**Rust (Axum)**
- Setup: Init tracing (15 lines, once)
- Per-handler: 1 line (`#[instrument]`)
- Custom metrics: ~2 lines each
- **Total: ~25 lines for complete observability**

**Go (Gin)**
- Setup: Init tracer (20 lines, once)
- Middleware: 1 line
- Per-handler: 0-2 lines (optional)
- Custom metrics: ~2 lines each
- **Total: ~30 lines for complete observability**

### Result:

**Full observability with < 50 lines of code per service!**

That's the power of modern observability tools. 🚀
