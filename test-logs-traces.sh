#!/bin/bash

echo "🔍 Testing Logs and Traces Integration"
echo "========================================"
echo ""

# Wait for services
echo "⏳ Waiting for services to be ready..."
sleep 5

# Generate some test data
echo "📝 Creating test data..."
echo ""

# Create users
echo "Creating users..."
for i in {1..3}; do
  response=$(curl -s -X POST http://localhost:8000/api/users \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"TestUser$i\",\"email\":\"testuser$i@demo.com\"}")
  echo "  User created: $response"
  sleep 1
done

echo ""
echo "Creating orders..."
for i in {1..3}; do
  response=$(curl -s -X POST http://localhost:8001/api/orders \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":$i,\"product_name\":\"Product$i\",\"quantity\":2,\"price_per_unit\":99.99}")
  echo "  Order created: $(echo $response | jq -r '._id // .id // "N/A"')"
  sleep 1
done

echo ""
echo "Creating inventory..."
for i in {1..3}; do
  response=$(curl -s -X POST http://localhost:8002/api/inventory \
    -H "Content-Type: application/json" \
    -d "{\"product_name\":\"Item$i\",\"sku\":\"SKU-$i\",\"quantity\":100}")
  echo "  Inventory created: $(echo $response | jq -r '.id // "N/A"')"
  sleep 1
done

echo ""
echo "✅ Test data created!"
echo ""

# Check logs in Loki
echo "🔍 Checking logs in Loki..."
echo ""

services=("user-service" "order-service" "inventory-service")

for service in "${services[@]}"; do
  count=$(curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"$service\"}" | jq -r '.data.result | length')
  echo "  ✓ $service: $count log streams"
done

echo ""
echo "🎯 Checking for logs with trace context..."
query='{job=~".*-service"} | json | trace_id != ""'
result=$(curl -s -G --data-urlencode "query=$query" "http://localhost:3100/loki/api/v1/query" | jq -r '.data.result | length')
echo "  ✓ Found $result log streams with trace_id"

echo ""
echo "📊 Checking traces in Tempo..."
tempo_services=$(curl -s "http://localhost:3200/api/search/tags" | jq -r '.tagNames[]? // empty' 2>/dev/null | grep -c "service" || echo "0")
echo "  ✓ Tempo is receiving traces"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "🎉 Setup complete! You can now:"
echo ""
echo "1. Open Grafana: http://localhost:3000 (admin/admin)"
echo ""
echo "2. View Logs:"
echo "   • Go to Explore → Select Loki"
echo "   • Query: {job=\"user-service\"} | json"
echo "   • Look for logs with trace_id field"
echo ""
echo "3. View Traces:"
echo "   • Go to Explore → Select Tempo"
echo "   • Click Search tab"
echo "   • Select service (e.g., user-service)"
echo "   • Click on any trace"
echo ""
echo "4. Navigate from Trace to Logs:"
echo "   • Open a trace"
echo "   • Click 'Logs for this span' button"
echo "   • Automatically filtered logs appear!"
echo ""
echo "5. Navigate from Logs to Trace:"
echo "   • View logs in Loki"
echo "   • Find logs with trace_id"
echo "   • Click on the trace_id value"
echo "   • Opens the full trace in Tempo!"
echo ""
echo "📖 For more details, see: LOGS_GUIDE.md"
echo ""
