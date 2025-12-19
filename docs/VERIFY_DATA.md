# How to View Observability Data in Grafana

## ✅ Summary

Your observability stack is **working**! Here's what's functional:

- **Metrics**: ✅ All services exposing metrics, Prometheus scraping successfully
- **Traces**: ✅ Tempo receiving traces from all services
- **Logs**: ⚠️ Promtail needs configuration fix (see below)

## 🎯 How to View Data

### 1. Access Grafana

Open your browser: **http://localhost:3000**

- Username: `admin`
- Password: `admin`

### 2. View Metrics (WORKING)

**Option A: Explore**
1. Click **Explore** (compass icon) in the left menu
2. Select **Prometheus** from the dropdown
3. Try these queries:

```promql
# Request rate per service
rate(http_requests_total[5m])

# Total requests by service
http_requests_total

# Orders created
orders_created_total

# Inventory items
inventory_items_created_total

# Request duration histogram
http_request_duration_seconds_bucket
```

**Option B: Create a Dashboard**
1. Click **+** → **Dashboard** → **Add visualization**
2. Select **Prometheus** datasource
3. Add the queries above
4. Click **Apply**

### 3. View Traces (WORKING)

1. Go to **Explore**
2. Select **Tempo** from the dropdown
3. Click the **Search** tab
4. In the filters:
   - Service Name: Select `order-service`, `user-service`, or `inventory-service`
   - Click **Run Query**
5. Click on any trace to see the full waterfall view

**What you'll see:**
- Service-to-service calls
- Database queries
- NATS message publishing
- Request durations
- Error tracking

### 4. Logs (Needs Fix)

Promtail is currently configured to read from `/var/log` (system logs), but Docker containers log to stdout/stderr. 

**Quick Fix Options:**

**Option 1: Docker Compose Logs (Immediate)**
```bash
# View Python service logs
docker compose logs -f python-user-service

# View Rust service logs  
docker compose logs -f rust-order-service

# View Go service logs
docker compose logs -f go-inventory-service
```

**Option 2: Configure Promtail for Docker (Recommended)**

Edit `docker-compose.yml` to mount Docker socket:

```yaml
promtail:
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - ./promtail-docker-config.yaml:/etc/promtail/config.yaml
```

## 🧪 Generate Test Data

Run these commands to see live data flowing:

```bash
# Generate user traffic
for i in {1..20}; do
  curl -X POST http://localhost:8000/api/users \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Test User $i\",\"email\":\"user$i@demo.com\"}" &
done
wait

# Generate order traffic
for i in {1..20}; do
  curl -X POST http://localhost:8001/api/orders \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":$i,\"product_name\":\"Product $i\",\"quantity\":$((RANDOM % 10 + 1)),\"price\":$((RANDOM % 100 + 10)).99}" &
done
wait

# Generate inventory traffic
for i in {1..20}; do
  curl -X POST http://localhost:8002/api/items \
    -H "Content-Type: application/json" \
    -d "{\"product_name\":\"Item $i\",\"sku\":\"SKU-$i\",\"quantity\":$((RANDOM % 100 + 50))}" &
done
wait

echo "✅ Test data generated! Refresh Grafana to see the results."
```

## 📊 Sample Grafana Queries

### Request Rate Dashboard

```promql
# Panel 1: Request Rate by Service
sum(rate(http_requests_total[5m])) by (job)

# Panel 2: Error Rate
sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)

# Panel 3: P95 Latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Panel 4: Database Operations
rate(inventory_items_created_total[5m])
rate(orders_created_total[5m])
rate(users_created_total[5m])
```

### Service Health

```promql
# Services up/down
up{job=~".*-service"}

# Goroutines (Go service)
go_goroutines{job="inventory-service"}

# Python GC collections
rate(python_gc_collections_total[5m])
```

## 🔍 Trace Search Examples

In Grafana Explore → Tempo:

1. **Find slow requests:**
   - Min Duration: `500ms`
   - Click Search

2. **Find errors:**
   - Tags: Add `error=true` or `status.code=ERROR`

3. **Find by operation:**
   - Operation: Select `/api/users` or `/api/orders`

4. **Service dependencies:**
   - Click on any trace
   - View the "Node Graph" tab to see service interactions

## 🎨 Pre-built Dashboard Ideas

### Dashboard 1: Service Overview
- Request rate (line graph)
- Error rate (line graph)
- P95/P99 latency (gauge)
- Active requests (stat)

### Dashboard 2: Business Metrics
- Users created (counter)
- Orders created (counter)
- Inventory items (counter)
- Revenue by hour (if you add price tracking)

### Dashboard 3: Infrastructure
- CPU usage per service
- Memory usage per service
- Database connection pool
- NATS message throughput

## 🐛 Troubleshooting

### No Data in Grafana?

**Check Prometheus:**
```bash
# Are services being scraped?
curl -s http://localhost:9090/api/v1/targets | grep -A 5 "user-service\|order-service\|inventory"

# Query directly
curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool
```

**Check Tempo:**
```bash
# Are traces being received?
curl -s http://localhost:3200/api/search?limit=5 | python3 -m json.tool
```

**Check Services:**
```bash
# Metrics endpoints
curl http://localhost:8000/metrics | grep http_requests_total
curl http://localhost:8001/metrics | grep http_requests_total  
curl http://localhost:8002/metrics | grep http_requests_total
```

### Data Shows But Looks Old?

Grafana might be showing an old time range:
1. In Explore, change time range to "Last 5 minutes"
2. Click the refresh button
3. Enable auto-refresh (dropdown next to refresh)

### Traces Not Showing Service Names?

Check environment variables:
```bash
docker compose exec python-user-service env | grep OTEL
docker compose exec rust-order-service env | grep OTEL
docker compose exec go-inventory-service env | grep OTEL
```

## 🎓 Next Steps

1. **Import Community Dashboards:**
   - Go to Dashboards → Import
   - Try ID `13639` (Go Metrics)
   - Try ID `11074` (Node Exporter)

2. **Set Up Alerts:**
   - Create alert rules in Prometheus
   - Configure notification channels
   - Test alert conditions

3. **Explore Correlations:**
   - In a trace, click "Logs for this span"
   - See how traces link to logs automatically
   - Use exemplars to jump from metrics to traces

4. **Add Custom Metrics:**
   - Track business KPIs (conversion rates, etc.)
   - Add custom labels
   - Create SLO dashboards

## 📚 Useful Links

- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Prometheus Targets: http://localhost:9090/targets
- Tempo: http://localhost:3200
- Loki: http://localhost:3100

- Python Service: http://localhost:8000/docs (Swagger UI)
- Rust Service: http://localhost:8001/health
- Go Service: http://localhost:8002/health

---

**Your observability stack is ready! 🎉**

Start exploring your metrics and traces in Grafana now!
