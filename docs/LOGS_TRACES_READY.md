# ✅ Logs and Traces Integration - Complete!

Your observability stack now has **full logs and traces integration** working in Grafana!

## 🎯 What's Now Available

### 1. **Logs Collection** ✅

- ✅ Promtail collecting logs from all Docker containers
- ✅ Logs automatically labeled with `job`, `container`, `namespace`
- ✅ JSON logs parsed and structured

### 2. **Trace Context in Logs** ✅

- ✅ Python service outputs JSON logs with `trace_id` and `span_id`
- ✅ OpenTelemetry automatically injects trace context
- ✅ All logs correlated with distributed traces

### 3. **Bi-directional Navigation** ✅

- ✅ **Trace → Logs**: Click "Logs for this span" in any trace
- ✅ **Logs → Trace**: Click `trace_id` in logs to open trace
- ✅ Automatic time range filtering

### 4. **Grafana Datasources** ✅

- ✅ Loki configured with trace_id derived field
- ✅ Tempo configured with logs correlation
- ✅ Automatic service name mapping

## 🚀 Quick Access

### Open Grafana

```bash
open http://localhost:3000
# Login: admin / admin
```

### View Logs (Loki)

1. Click **Explore** (compass icon)
2. Select **Loki** from dropdown
3. Try these queries:

```logql
# All logs from user service
{job="user-service"}

# Logs with trace context
{job="user-service"} | json | trace_id != ""

# Error logs only
{job=~".*-service"} | json | level="ERROR"

# Search for specific message
{job="user-service"} |= "Creating user"
```

### View Traces (Tempo)

1. Click **Explore**
2. Select **Tempo** from dropdown
3. Click **Search** tab
4. Select **Service Name**: `user-service`, `order-service`, or `inventory-service`
5. Click **Run Query**
6. Click any trace to explore

### Test Trace → Logs Navigation

1. Open Tempo Explore
2. Find any trace
3. Click on a span
4. Look for **"Logs for this span"** button (usually at bottom right)
5. Click it → **Automatically switches to Loki with filtered logs!**

### Test Logs → Trace Navigation

1. Open Loki Explore
2. Query: `{job="user-service"} | json | trace_id != ""`
3. Expand a log entry
4. Find the `trace_id` field
5. Click the **trace_id value** → **Opens the trace in Tempo!**

## 📊 Example Workflow

### Scenario: Debug a slow user creation

1. **Start in Tempo**:

   ```
   Search for traces with duration > 500ms
   Service: user-service
   ```
2. **Find slow trace** → Click to open
3. **See database query is slow** (PostgreSQL span)
4. **Click "Logs for this span"** → View logs during that exact timeframe
5. **See detailed log messages**:

   ```json
   {
     "level": "INFO",
     "message": "Creating user: alice@example.com",
     "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736"
   }
   ```
6. **Root cause identified!**

## 🎨 Create a Combined Dashboard

### Panel 1: Recent Logs

- **Visualization**: Logs
- **Datasource**: Loki
- **Query**: `{job=~".*-service"} | json`

### Panel 2: Active Traces

- **Visualization**: Table
- **Datasource**: Tempo
- **Use Tempo search to show recent traces**

### Panel 3: Error Rate

- **Visualization**: Time series
- **Datasource**: Loki
- **Query**:
  ```logql
  sum by (job) (rate({job=~".*-service"} | json | level="ERROR" [5m]))
  ```

### Panel 4: Trace Duration

- **Visualization**: Histogram
- **Datasource**: Tempo
- **Shows P50, P95, P99 latencies**

## 🐛 Troubleshooting

### Logs not appearing?

**Check Promtail:**

```bash
docker-compose logs promtail
docker-compose ps promtail
```

**Verify Docker socket mount:**

```bash
docker-compose exec promtail ls -la /var/run/docker.sock
```

### Trace IDs not linking?

**Check log format:**

```bash
docker-compose logs python-user-service --tail=10
```

Should see JSON with `trace_id`:

```json
{"timestamp":"...","level":"INFO","message":"...","trace_id":"abc123..."}
```

**Regenerate activity:**

```bash
./test-logs-traces.sh
```

### "Logs for this span" button missing?

1. Go to **Configuration** → **Data Sources** → **Tempo**
2. Scroll to **Trace to logs** section
3. Verify:
   - Datasource: `loki`
   - Tags: `job`, `container`
   - Filter by Trace ID: `true`

## 📖 Learn More

- [LOGS_GUIDE.md](LOGS_GUIDE.md) - Detailed guide with LogQL examples
- [Grafana Docs: Trace to Logs](https://grafana.com/docs/grafana/latest/datasources/tempo/#trace-to-logs)
- [LogQL Cheat Sheet](https://grafana.com/docs/loki/latest/logql/)

## 🎓 Key Files Modified

1. **`promtail-docker-config.yaml`** - New Promtail config for Docker logs
2. **`docker-compose.yml`** - Updated Promtail to mount Docker socket
3. **`services/python-user-service/main.py`** - Added JSON logging with trace context
4. **`k8s/observability/grafana-datasources.yaml`** - Enhanced trace ↔ logs correlation

## 🔐 Architecture

```
┌─────────────────────────────────────────────────────┐
│             Your Microservices                      │
│  (Python, Rust, Go with OpenTelemetry)              │
│  - Generate structured JSON logs                    │
│  - Include trace_id from OpenTelemetry context      │
└─────────────────────────────────────────────────────┘
            ↓                           ↓
     stdout/stderr               OTLP Protocol
            ↓                           ↓
    ┌─────────────┐            ┌─────────────┐
    │  Promtail   │            │    Tempo    │
    │  (Docker)   │            │  (Traces)   │
    └─────────────┘            └─────────────┘
            ↓                           ↓
    ┌─────────────┐                     │
    │    Loki     │←────────────────────┘
    │   (Logs)    │    Correlation
    └─────────────┘
            ↓
    ┌─────────────────────────────────┐
    │          Grafana                │
    │  - View logs (Loki)             │
    │  - View traces (Tempo)          │
    │  - Navigate between them        │
    │  - View metrics (Prometheus)    │
    └─────────────────────────────────┘
```

## 🎉 Success!

You now have the **complete observability trifecta**:

- ✅ **Metrics** (Prometheus) - What is happening
- ✅ **Traces** (Tempo) - Where it's happening
- ✅ **Logs** (Loki) - Why it's happening

All seamlessly integrated and navigable in Grafana! 🚀

---

**Next Steps**: Try the [LOGS_GUIDE.md](LOGS_GUIDE.md) for advanced LogQL queries and dashboard creation!
