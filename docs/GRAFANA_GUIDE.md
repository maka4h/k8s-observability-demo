# Grafana Observability Guide

## Accessing Grafana

1. **Open Grafana**: http://localhost:3000
2. **Login** (if needed):
   - Username: `admin`
   - Password: `admin`

## Viewing Distributed Traces

### Option 1: Explore View (Recommended)

1. Click **Explore** (compass icon) in the left sidebar
2. Select **Tempo** from the data source dropdown at the top
3. Choose a query method:

   **Method A: Search by Service**
   - Click on "Search" tab
   - Service Name: `order-service` (or `user-service`, `inventory-service`)
   - Click "Run query"
   - You'll see a list of traces with duration and timestamp
   - Click on any trace to see the full distributed trace

   **Method B: Search by TraceID**
   - Click on "TraceQL" tab
   - Use queries like:
     ```
     { service.name = "order-service" }
     ```
   - Or find traces with errors:
     ```
     { status = error }
     ```

4. **Understanding the Trace View**:
   - **Timeline**: Shows all spans across services
   - **Spans**: Each service call is a span
   - **Duration**: Time taken by each operation
   - **Service Tags**: Metadata about the request

### What You'll See in a Validated Order Trace:

```
order-service (Rust)
├── HTTP POST /api/orders/validated
    ├── HTTP GET → user-service (Python)
    │   └── PostgreSQL query
    ├── HTTP GET → inventory-service (Go)
    │   └── PostgreSQL query
    └── MongoDB insert
```

## Viewing Logs

### Option 1: Explore View

1. Click **Explore** in the left sidebar
2. Select **Loki** from the data source dropdown
3. Use LogQL queries:

   **See all logs from order service:**
   ```logql
   {container_name="rust-order-service"}
   ```

   **See logs from all services:**
   ```logql
   {container_name=~".*-service"}
   ```

   **Filter by log level:**
   ```logql
   {container_name="rust-order-service"} |= "ERROR"
   ```

   **See validated order logs:**
   ```logql
   {container_name="rust-order-service"} |= "VALIDATED order"
   ```

4. Click "Run query" to see the logs

### Log Aggregation and Patterns

```logql
# Count errors by service
sum by (container_name) (count_over_time({container_name=~".*-service"} |= "ERROR" [5m]))

# Show order creation events
{container_name="rust-order-service"} |= "order created"
```

## Correlating Traces and Logs

### Method 1: From Trace to Logs

1. Open a trace in **Explore → Tempo**
2. Click on any span
3. In the span details, look for the "Logs for this span" button
4. Click it to see logs generated during that specific span

### Method 2: From Logs to Traces

1. Open logs in **Explore → Loki**
2. Find a log entry with a trace ID
3. Click on the "Tempo" or "trace_id" field
4. It will open the corresponding trace

### Method 3: Split View (Best for Correlation)

1. In Explore view, click the **Split** button (top right)
2. Left panel: Select **Loki** and show logs
3. Right panel: Select **Tempo** and show traces
4. Filter by the same time range
5. You can now see logs and traces side by side!

## Viewing Metrics

1. Click **Explore** → Select **Prometheus**
2. Try these queries:

   **Request rate:**
   ```promql
   rate(http_requests_total[5m])
   ```

   **Order creation rate:**
   ```promql
   rate(orders_created_total[5m])
   ```

   **Request duration:**
   ```promql
   histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
   ```

## Creating a Dashboard

### Quick Dashboard Setup

1. Click **Dashboards** (four squares icon) → **New** → **New Dashboard**
2. Click **Add visualization**
3. Select your data source

#### Panel 1: Service Map (Traces)
- Data source: **Tempo**
- Query: `{ service.name != "" }`
- Visualization: **Node Graph**

#### Panel 2: Service Logs
- Data source: **Loki**
- Query: `{container_name=~".*-service"}`
- Visualization: **Logs**

#### Panel 3: Request Rate
- Data source: **Prometheus**
- Query: `rate(http_requests_total[5m])`
- Visualization: **Time series**

#### Panel 4: Error Logs
- Data source: **Loki**
- Query: `{container_name=~".*-service"} |= "ERROR"`
- Visualization: **Logs**

## Useful Queries for Your Services

### Traces (Tempo/TraceQL)

```traceql
# All order-service traces
{ service.name = "order-service" }

# Slow requests (> 100ms)
{ duration > 100ms }

# Traces with specific user
{ resource.user_id = "533" }

# Failed requests
{ status = error }

# Traces calling inventory service
{ span.http.url =~ ".*inventory.*" }
```

### Logs (Loki/LogQL)

```logql
# Order service logs
{container_name="rust-order-service"}

# User service logs
{container_name="python-user-service"}

# Inventory service logs
{container_name="go-inventory-service"}

# All service errors
{container_name=~".*-service"} |= "ERROR"

# JSON parsing for structured logs
{container_name="rust-order-service"} | json | level="ERROR"

# Logs with trace correlation
{container_name="rust-order-service"} | json | trace_id != ""

# Order creation flow
{container_name="rust-order-service"} |= "Validated order created"
```

### Metrics (Prometheus/PromQL)

```promql
# Total requests
sum(http_requests_total)

# Requests by service
sum by (job) (http_requests_total)

# Order creation rate
rate(orders_created_total[5m])

# Request duration 95th percentile
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate
rate(http_requests_total{status=~"5.."}[5m])
```

## Testing the Observability Stack

Run these commands to generate data:

```bash
# Create some successful orders
curl -X POST http://localhost:8001/api/orders/validated \
  -H "Content-Type: application/json" \
  -d '{"user_id":533,"product_id":"528","quantity":1}'

# Try with different products
curl -X POST http://localhost:8001/api/orders/validated \
  -H "Content-Type: application/json" \
  -d '{"user_id":533,"product_id":"529","quantity":3}'

# Generate an error (invalid user)
curl -X POST http://localhost:8001/api/orders/validated \
  -H "Content-Type: application/json" \
  -d '{"user_id":999999,"product_id":"528","quantity":1}'

# Generate an error (insufficient inventory)
curl -X POST http://localhost:8001/api/orders/validated \
  -H "Content-Type: application/json" \
  -d '{"user_id":533,"product_id":"528","quantity":1000}'
```

Then go to Grafana and:
1. View the traces in Tempo to see the request flow
2. View the logs in Loki to see what happened
3. Correlate trace IDs between logs and traces

## Pro Tips

1. **Time Range**: Always check the time range selector (top right). Set it to "Last 15 minutes" when testing
2. **Live Tail**: In Loki logs, click "Live" to stream logs in real-time
3. **Trace to Logs**: Look for `trace_id` or `traceID` fields in logs to correlate with traces
4. **Labels**: Use labels to filter - click on any label in logs/traces to add it to your query
5. **Share**: You can share queries and dashboards using the share button

## Common Issues

**No traces showing up?**
- Check time range (last 15-30 minutes)
- Verify services are running: `docker-compose ps`
- Make sure you've made API calls to generate traces

**No logs appearing?**
- Wait a few seconds for OpenTelemetry Collector to collect logs
- Check if containers are running
- Try query: `{container_name=~".*"}` to see all logs

**Traces and logs not correlating?**
- Verify trace IDs are being logged by services
- Check if OpenTelemetry is properly configured
- Look for `trace_id` fields in the logs
