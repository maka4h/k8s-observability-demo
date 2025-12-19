#!/bin/bash

echo "🧪 Testing demo services..."

BASE_URL_USER=${1:-"http://localhost:8000"}
BASE_URL_ORDER=${2:-"http://localhost:8001"}
BASE_URL_INVENTORY=${3:-"http://localhost:8002"}

echo ""
echo "Testing User Service at $BASE_URL_USER"
echo "========================================"

# Health check
echo "✓ Health check..."
curl -s "$BASE_URL_USER/health" | jq '.'

# Create user
echo ""
echo "✓ Creating user..."
USER_RESPONSE=$(curl -s -X POST "$BASE_URL_USER/api/users" \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice Smith","email":"alice@example.com"}')
echo "$USER_RESPONSE" | jq '.'
USER_ID=$(echo "$USER_RESPONSE" | jq -r '.id')

# List users
echo ""
echo "✓ Listing users..."
curl -s "$BASE_URL_USER/api/users" | jq '.'

# Get specific user
echo ""
echo "✓ Getting user $USER_ID..."
curl -s "$BASE_URL_USER/api/users/$USER_ID" | jq '.'

echo ""
echo "Testing Order Service at $BASE_URL_ORDER"
echo "========================================"

# Health check
echo "✓ Health check..."
curl -s "$BASE_URL_ORDER/health" | jq '.'

# Create order
echo ""
echo "✓ Creating order..."
ORDER_RESPONSE=$(curl -s -X POST "$BASE_URL_ORDER/api/orders" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\":$USER_ID,\"product_name\":\"Gaming Laptop\",\"quantity\":1,\"price_per_unit\":1299.99}")
echo "$ORDER_RESPONSE" | jq '.'
ORDER_ID=$(echo "$ORDER_RESPONSE" | jq -r '._id // .id')

# List orders
echo ""
echo "✓ Listing orders..."
curl -s "$BASE_URL_ORDER/api/orders" | jq '.'

echo ""
echo "Testing Inventory Service at $BASE_URL_INVENTORY"
echo "================================================"

# Health check
echo "✓ Health check..."
curl -s "$BASE_URL_INVENTORY/health" | jq '.'

# Create inventory item
echo ""
echo "✓ Creating inventory item..."
INVENTORY_RESPONSE=$(curl -s -X POST "$BASE_URL_INVENTORY/api/inventory" \
  -H "Content-Type: application/json" \
  -d '{"product_name":"Gaming Mouse","sku":"MOUSE-001","quantity":150,"location":"Warehouse A"}')
echo "$INVENTORY_RESPONSE" | jq '.'
INVENTORY_ID=$(echo "$INVENTORY_RESPONSE" | jq -r '.id')

# List inventory
echo ""
echo "✓ Listing inventory..."
curl -s "$BASE_URL_INVENTORY/api/inventory" | jq '.'

# Get stock levels (MongoDB)
echo ""
echo "✓ Getting stock levels from MongoDB..."
curl -s "$BASE_URL_INVENTORY/api/stock-levels" | jq '.'

echo ""
echo "✅ All tests completed successfully!"
echo ""
echo "📊 Check metrics:"
echo "  curl $BASE_URL_USER/metrics"
echo "  curl $BASE_URL_ORDER/metrics"
echo "  curl $BASE_URL_INVENTORY/metrics"
