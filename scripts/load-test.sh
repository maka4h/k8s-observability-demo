#!/bin/bash

echo "🔥 Starting load test..."

BASE_URL_USER=${1:-"http://localhost:8000"}
BASE_URL_ORDER=${2:-"http://localhost:8001"}
BASE_URL_INVENTORY=${3:-"http://localhost:8002"}

DURATION=${4:-60}  # Duration in seconds
REQUESTS_PER_SECOND=${5:-10}

echo "Configuration:"
echo "  User Service: $BASE_URL_USER"
echo "  Order Service: $BASE_URL_ORDER"
echo "  Inventory Service: $BASE_URL_INVENTORY"
echo "  Duration: ${DURATION}s"
echo "  Target: ${REQUESTS_PER_SECOND} req/s per service"
echo ""

# Calculate sleep time between requests
SLEEP_TIME=$(echo "scale=4; 1 / $REQUESTS_PER_SECOND" | bc)

END_TIME=$(($(date +%s) + DURATION))
REQUEST_COUNT=0

echo "Starting load test... Press Ctrl+C to stop"
echo ""

while [ $(date +%s) -lt $END_TIME ]; do
  REQUEST_COUNT=$((REQUEST_COUNT + 1))
  
  # User service requests
  (
    # Create user
    curl -s -X POST "$BASE_URL_USER/api/users" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"User$REQUEST_COUNT\",\"email\":\"user$REQUEST_COUNT@example.com\"}" \
      > /dev/null 2>&1
    
    # List users
    curl -s "$BASE_URL_USER/api/users?limit=10" > /dev/null 2>&1
  ) &
  
  # Order service requests
  (
    USER_ID=$((RANDOM % 100 + 1))
    # Create order
    curl -s -X POST "$BASE_URL_ORDER/api/orders" \
      -H "Content-Type: application/json" \
      -d "{\"user_id\":$USER_ID,\"product_name\":\"Product$REQUEST_COUNT\",\"quantity\":$((RANDOM % 5 + 1)),\"price_per_unit\":$((RANDOM % 1000 + 10))}" \
      > /dev/null 2>&1
    
    # List orders
    curl -s "$BASE_URL_ORDER/api/orders?limit=10" > /dev/null 2>&1
  ) &
  
  # Inventory service requests
  (
    # Create inventory
    curl -s -X POST "$BASE_URL_INVENTORY/api/inventory" \
      -H "Content-Type: application/json" \
      -d "{\"product_name\":\"Product$REQUEST_COUNT\",\"sku\":\"SKU-$REQUEST_COUNT\",\"quantity\":$((RANDOM % 200 + 50)),\"location\":\"Warehouse $((RANDOM % 3 + 1))\"}" \
      > /dev/null 2>&1
    
    # List inventory
    curl -s "$BASE_URL_INVENTORY/api/inventory?limit=10" > /dev/null 2>&1
    
    # Get stock levels
    curl -s "$BASE_URL_INVENTORY/api/stock-levels" > /dev/null 2>&1
  ) &
  
  # Progress indicator
  if [ $((REQUEST_COUNT % 10)) -eq 0 ]; then
    ELAPSED=$(($(date +%s) - (END_TIME - DURATION)))
    echo "⏱️  ${ELAPSED}s elapsed - ${REQUEST_COUNT} request cycles sent"
  fi
  
  sleep $SLEEP_TIME
done

# Wait for background jobs to complete
wait

echo ""
echo "✅ Load test completed!"
echo "   Total request cycles: $REQUEST_COUNT"
echo "   Total requests sent: ~$((REQUEST_COUNT * 7)) (approx)"
echo ""
echo "📊 View results in Grafana:"
echo "   - Go to http://localhost:3000"
echo "   - Check service dashboards"
echo "   - Explore traces in Tempo"
echo "   - Query logs in Loki"
