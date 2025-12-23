# NATS Trace Propagation Verification

## Overview
This document explains how to verify that OpenTelemetry trace context is successfully propagated through NATS messages between microservices.

## What is Being Propagated?

When a NATS message is published, the following W3C Trace Context information is included in the message headers:

- **traceparent**: A header containing the trace ID, span ID, and sampling flags
- **Format**: `version-trace_id-parent_span_id-trace_flags`
- **Example**: `00-765d68aee5456f40082351d17e3d1d50-9ab03edb388b9645-01`

## Components

### 1. **trace_id** (32 hex characters)
The unique identifier for the entire distributed trace. This stays the same across all services in the trace.

### 2. **span_id** (16 hex characters)  
The identifier for the current span (the parent span from the publisher's perspective).

### 3. **trace_flags** (2 hex characters)
Sampling and other flags. `01` means the trace is sampled.

## Verification Methods

### Method 1: Using the Verification Script

Run the automated verification script:

```bash
./verify-nats-trace.sh
```

This script will:
1. Create a test user (triggering a NATS message)
2. Extract trace context from Python publisher logs
3. Extract trace context from Rust consumer logs
4. Compare the trace IDs to verify they match
5. Display the W3C Trace Context headers

**Expected Output:**
```
✅ Trace ID MATCHES: 6ededc3c3616b8d661ef762652706938
✅ Trace context successfully propagated through NATS!
✅ Parent span ID preserved: 6f051f3e5cdce63d
```

### Method 2: Manual Log Inspection

#### Step 1: Create a Test User
```bash
curl -X POST http://localhost:8000/api/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Test User", "email": "test@example.com"}'
```

#### Step 2: Check Publisher Logs (Python Service)
```bash
docker logs k8s-observability-demo-python-user-service-1 --tail 20 | grep "NATS headers"
```

**Example Output:**
```json
{
  "timestamp": "2025-12-23 07:26:51,030",
  "level": "INFO",
  "message": "Published user.created event for user 541 with NATS headers: {'traceparent': '00-765d68aee5456f40082351d17e3d1d50-9ab03edb388b9645-01'}",
  "trace_id": "765d68aee5456f40082351d17e3d1d50",
  "span_id": "9ab03edb388b9645"
}
```

#### Step 3: Check Consumer Logs (Rust Service)
```bash
docker logs k8s-observability-demo-rust-order-service-1 --tail 20 | grep "Received NATS message"
```

**Example Output:**
```json
{
  "timestamp": "2025-12-23T07:26:51.031276Z",
  "level": "INFO",
  "fields": {
    "message": "Received NATS message with headers: HeaderMap { inner: {HeaderName { inner: Custom(CustomHeader { bytes: b\"traceparent\" }) }: [HeaderValue { inner: \"00-765d68aee5456f40082351d17e3d1d50-9ab03edb388b9645-01\" }]} }"
  },
  "target": "order_service"
}
```

#### Step 4: Verify Trace IDs Match
Compare the `trace_id` from both logs. They should be identical:
- Publisher: `765d68aee5456f40082351d17e3d1d50`
- Consumer: `765d68aee5456f40082351d17e3d1d50` ✅

### Method 3: Tempo Query

Query Tempo to see the complete distributed trace including the NATS consumer span:

```bash
# Replace TRACE_ID with your actual trace ID
curl -s "http://localhost:3200/api/traces/TRACE_ID" | \
  jq -r '.batches[].scopeSpans[].spans[] | "📍 \(.name)"'
```

**Expected Spans:**
```
📍 POST /api/users
📍 connect (PostgreSQL)
📍 INSERT demo
📍 handle_user_created  ← This is the NATS consumer span!
```

### Method 4: Grafana Visualization

1. Open Grafana: http://localhost:3000
2. Go to **Explore** → Select **Tempo** datasource
3. Use **TraceQL** query:
   ```
   {.messaging.system="nats"}
   ```
4. Or search by specific trace ID from the logs
5. You'll see the `handle_user_created` span connected to the `POST /api/users` span

## Understanding the Flow

```
1. HTTP Request comes in
   └─> Python user-service creates span (trace_id: xxx, span_id: yyy)

2. Python service publishes to NATS
   └─> Injects traceparent header: "00-xxx-yyy-01"

3. NATS delivers message with headers
   └─> Headers preserved during transit

4. Rust service receives message
   └─> Extracts traceparent from headers
   └─> Creates child span (trace_id: xxx, parent_span_id: yyy, new_span_id: zzz)

5. All spans share the same trace_id!
   └─> Enables distributed tracing across async boundaries
```

## Key Implementation Details

### Python Publisher (user-service)
```python
from opentelemetry import context
from opentelemetry.propagate import inject

headers = {}
inject(headers, context=context.get_current())

await nc.publish("user.created", json.dumps(event).encode(), headers=headers)
```

### Rust Consumer (order-service)
```rust
// Custom extractor for NATS headers
struct HeaderExtractor<'a>(&'a async_nats::header::HeaderMap);

impl<'a> Extractor for HeaderExtractor<'a> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).map(|v| v.as_ref())
    }
}

// Extract parent context from headers
let parent_ctx = if let Some(headers) = &msg.headers {
    global::get_text_map_propagator(|propagator| {
        propagator.extract(&HeaderExtractor(headers))
    })
} else {
    opentelemetry::Context::current()
};

// Create child span with parent context
let span = tracing::info_span!("handle_user_created");
span.set_parent(parent_ctx);
```

## Troubleshooting

### Issue: Trace IDs don't match
**Possible Causes:**
1. Headers not being injected properly
2. JSON serialization issues  
3. Consumer not extracting headers

**Solution:** Check the debug logs added to both services showing the actual headers.

### Issue: Consumer span not appearing in Tempo
**Possible Causes:**
1. Consumer not creating a span
2. Sampling disabled
3. OTLP exporter not configured

**Solution:** Verify the consumer logs show the span is being created with trace context.

### Issue: Headers not found in NATS message
**Possible Causes:**
1. NATS message published without `publish_with_headers()`
2. Headers dict empty before publishing

**Solution:** Check publisher logs showing `NATS headers: {'traceparent': '...'}`

## Benefits of NATS Trace Propagation

1. **End-to-End Visibility**: Track requests across synchronous (HTTP) and asynchronous (NATS) boundaries
2. **Performance Analysis**: Measure total latency including message queue time
3. **Error Correlation**: Link errors in consumers back to the original request
4. **Service Dependencies**: Visualize how services communicate via messages
5. **Debugging**: Follow the complete journey of a request through your system

## Standards Used

- **W3C Trace Context**: Industry standard for trace propagation
- **OpenTelemetry**: Vendor-neutral observability framework
- **NATS Headers**: Native header support in NATS 2.2+

## Related Files

- `verify-nats-trace.sh` - Automated verification script
- `services/python-user-service/main.py` - Publisher implementation
- `services/rust-order-service/src/main.rs` - Consumer implementation
- `trace-info.sh` - Query traces by trace_id across services
