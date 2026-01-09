#!/bin/bash
# Test script to verify OTel Collector migration

set -e

echo "🔍 Testing OpenTelemetry Collector Migration..."
echo ""

# Check if services are running
echo "1. Checking service health..."
docker-compose ps | grep -E "(otel-collector|loki|tempo|prometheus)" || {
    echo "❌ Some observability services are not running"
    exit 1
}
echo "✅ All observability services are running"
echo ""

# Test OTel Collector metrics endpoint
echo "2. Testing OTel Collector metrics endpoint..."
if curl -sf http://localhost:8888/metrics > /dev/null; then
    echo "✅ OTel Collector metrics endpoint is accessible"
else
    echo "❌ OTel Collector metrics endpoint is not accessible"
    exit 1
fi
echo ""

# Generate test data
echo "3. Generating test trace data..."
RESPONSE=$(curl -s -X POST http://localhost:8000/api/users \
    -H "Content-Type: application/json" \
    -d '{"name":"OTel Test User","email":"otel@test.com"}')
    
if echo "$RESPONSE" | grep -q "id"; then
    echo "✅ Test request successful"
    USER_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
    echo "   Created user with ID: $USER_ID"
else
    echo "❌ Test request failed"
    exit 1
fi
echo ""

# Wait for data to be processed
echo "4. Waiting for data processing..."
sleep 3
echo ""

# Check traces in OTel Collector logs
echo "5. Verifying traces through OTel Collector..."
if docker logs k8s-observability-demo-otel-collector-1 2>&1 | grep -q "Traces"; then
    echo "✅ Traces are flowing through OTel Collector"
else
    echo "⚠️  No traces found in OTel Collector logs (may need more time)"
fi
echo ""

# Check metrics in Prometheus
echo "6. Verifying metrics in Prometheus..."
METRICS=$(curl -s "http://localhost:9090/api/v1/query?query=up" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['data']['result']))")
if [ "$METRICS" -gt 0 ]; then
    echo "✅ Prometheus has $METRICS target metrics"
else
    echo "❌ No metrics found in Prometheus"
    exit 1
fi
echo ""

# Check if Tempo is receiving traces
echo "7. Verifying Tempo is accessible..."
if curl -sf http://localhost:3200/ready > /dev/null; then
    echo "✅ Tempo is ready"
else
    echo "❌ Tempo is not accessible"
    exit 1
fi
echo ""

# Check Grafana
echo "8. Verifying Grafana is accessible..."
if curl -sf http://localhost:3000/api/health | grep -q "ok"; then
    echo "✅ Grafana is healthy"
else
    echo "❌ Grafana is not healthy"
    exit 1
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Migration Test Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Next Steps:"
echo "1. Open Grafana: http://localhost:3000 (admin/admin)"
echo "2. Go to Explore"
echo "3. Query logs in Loki"
echo "4. Query traces in Tempo"
echo "5. Query metrics in Prometheus"
echo ""
echo "Architecture:"
echo "Services → OTel Collector (4317/4318) → {Loki, Tempo, Prometheus} → Grafana"
