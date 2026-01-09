# Logs and Traces Integration Guide

This guide shows how to use logs and traces together in Grafana.

## 🔧 What's Been Configured

### 1. **OpenTelemetry Collector** - Unified Observability Agent
- Collects logs from Docker containers via Docker socket (filelog receiver)
- Collects traces via OTLP from services
- Collects metrics by scraping Prometheus endpoints
- Automatically adds labels: `service_name`, `deployment_environment`
- Exports to Loki (logs), Tempo (traces), and Prometheus (metrics)

### 2. **Python Service** - JSON Logging with Trace Context
- All logs output as JSON
- Automatically includes `trace_id` and `span_id` from OpenTelemetry
- Example log entry:
```json
{
  "timestamp": "2024-12-19T16:30:45Z",
  "level": "INFO",
  "message": "Creating user: alice@example.com",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7"
}
```

### 3. **Grafana Datasources** - Trace ↔ Logs Navigation
- **From Trace → Logs**: Click "Logs for this span" in trace view
- **From Logs → Trace**: Click trace ID link in log entry
- Automatic time range adjustment

## 🚀 Quick Start

### Step 1: Restart Services
```bash
# Stop current services
docker-compose down

# Start with new configuration
docker-compose up -d

# Wait for services to be ready
sleep 15
```

### Step 2: Generate Some Activity
```bash
# Create users (generates logs and traces)
for i in {1..5}; do
  curl -X POST http://localhost:8000/api/users \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"User$i\",\"email\":\"user$i@demo.com\"}"
  sleep 1
done

# Create orders
for i in {1..5}; do
  curl -X POST http://localhost:8001/api/orders \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":$i,\"product_name\":\"Product$i\",\"quantity\":2,\"price_per_unit\":99.99}"
  sleep 1
done
```

### Step 3: View Logs in Grafana

1. **Open Grafana**: http://localhost:3000 (admin/admin)

2. **Go to Explore** (compass icon on left sidebar)

3. **Select Loki** datasource from dropdown

4. **Query logs**:
```logql
# All logs from user service
{job="user-service"}

# Logs from a specific trace
{job="user-service"} | json | trace_id="<paste-trace-id-here>"

# Error logs only
{job=~"user-service|order-service|inventory-service"} | json | level="ERROR"

# Logs with trace context
{job="user-service"} | json | trace_id != ""
```

## 🔍 Trace → Logs Workflow

### From Tempo to Loki:

1. **Open Explore** → Select **Tempo**
2. Click **Search** tab
3. Filter by **Service Name** (e.g., `user-service`)
4. Click **Run Query**
5. Click on any trace to open it
6. In the trace view, click **"Logs for this span"** button
   - This automatically switches to Loki
   - Filters logs by trace_id
   - Adjusts time range to span duration

### From Loki to Tempo:

1. **Open Explore** → Select **Loki**
2. Query logs: `{job="user-service"} | json`
3. In the results, find logs with `trace_id`
4. Click on the **trace_id** field value
   - This opens the trace in Tempo
   - Shows full distributed trace

## 📊 Useful LogQL Queries

### Find logs by service
```logql
{job="user-service"}
{job="order-service"}
{job="inventory-service"}
```

### Filter by log level
```logql
{job=~".*-service"} | json | level="ERROR"
{job=~".*-service"} | json | level="INFO"
```

### Search for specific messages
```logql
{job="user-service"} |= "Creating user"
{job="order-service"} |= "Order created"
```

### Find logs with trace context
```logql
{job=~".*-service"} | json | trace_id != ""
```

### Aggregate log counts
```logql
sum(count_over_time({job=~".*-service"}[5m])) by (job)
```

### Error rate over time
```logql
sum(rate({job=~".*-service"} | json | level="ERROR" [5m])) by (job)
```

## 🎯 Creating a Logs Dashboard

### Panel 1: Log Stream
- Visualization: Logs
- Query: `{job=~".*-service"} | json`

### Panel 2: Log Level Distribution
- Visualization: Pie Chart
- Query: `sum by (level) (count_over_time({job=~".*-service"} | json [1h]))`

### Panel 3: Error Rate
- Visualization: Time series
- Query: `sum by (job) (rate({job=~".*-service"} | json | level="ERROR" [5m]))`

### Panel 4: Logs Per Service
- Visualization: Bar gauge
- Query: `sum by (job) (count_over_time({job=~".*-service"}[5m]))`

## 🐛 Troubleshooting

### No Logs Appearing?

**Check OpenTelemetry Collector is running:**
```bash
docker-compose ps otel-collector
docker-compose logs otel-collector
```

**Check Docker socket is mounted:**
```bash
docker-compose exec otel-collector ls -la /var/run/docker.sock
```

**Verify Loki is receiving logs:**
```bash
curl -s http://localhost:3100/loki/api/v1/labels | jq
```

### Trace IDs Not Linking?

**Check log format:**
```bash
docker-compose logs python-user-service | tail -n 5
```

Should see JSON like:
```json
{"timestamp":"...","level":"INFO","message":"...","trace_id":"...","span_id":"..."}
```

**Verify Grafana datasource config:**
- Go to Configuration → Data Sources → Loki
- Check "Derived fields" section
- Should have regex: `"trace_id":"([0-9a-f]+)"`

### Logs Missing Trace IDs?

**Ensure OpenTelemetry is running:**
```bash
# Check services have OTEL environment variables
docker-compose exec python-user-service env | grep OTEL
```

**Generate new activity:**
```bash
# Create more requests
curl -X POST http://localhost:8000/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com"}'
```

## 📚 Advanced: Custom Log Labels

You can add custom labels to logs by modifying the OpenTelemetry Collector config:

```yaml
# In otel-collector-config.yaml
processors:
  resource:
    attributes:
      - key: custom_label
        value: custom_value
        action: insert
pipeline_stages:
  - json:
      expressions:
        level: level
        user_id: user_id        # Extract custom fields
        endpoint: endpoint
  
  - labels:
      level:
      user_id:                  # Add as label for filtering
```

## 🎓 Best Practices

1. **Always use JSON logging** for structured data
2. **Include trace context** in every log entry
3. **Use appropriate log levels**: DEBUG, INFO, WARN, ERROR
4. **Add business context**: user_id, order_id, etc.
5. **Keep messages concise** but informative
6. **Use consistent field names** across services

## 🔗 Related Documentation

- [Loki LogQL Documentation](https://grafana.com/docs/loki/latest/logql/)
- [OpenTelemetry Logging](https://opentelemetry.io/docs/specs/otel/logs/)
- [Grafana Trace to Logs](https://grafana.com/docs/grafana/latest/datasources/tempo/#trace-to-logs)

---

**Now you have full observability**: Metrics → Traces → Logs all connected! 🎉
