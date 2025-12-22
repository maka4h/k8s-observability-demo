#!/bin/bash

# Script to get trace information by trace ID
# Usage: ./trace-info.sh <trace_id>

TRACE_ID=$1

if [ -z "$TRACE_ID" ]; then
    echo "Usage: $0 <trace_id>"
    echo ""
    echo "Example: $0 c95e77ae3077f76c26bf8840fe442c9b"
    exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo "  🔍 Trace Information for: $TRACE_ID"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Function to check if a service has logs with this trace ID
check_service_logs() {
    local service_name=$1
    local container_name=$2
    local log_count=$(docker logs "$container_name" 2>&1 | grep -c "$TRACE_ID")
    
    if [ "$log_count" -gt 0 ]; then
        echo "✅ $service_name: $log_count log entries"
        return 0
    else
        echo "❌ $service_name: No logs found"
        return 1
    fi
}

# Check each service
echo "📊 Service Coverage:"
echo "─────────────────────────────────────────────────────────────────"
check_service_logs "Order Service (Rust)" "k8s-observability-demo-rust-order-service-1"
check_service_logs "User Service (Python)" "k8s-observability-demo-python-user-service-1"
check_service_logs "Inventory Service (Go)" "k8s-observability-demo-go-inventory-service-1"
echo ""

# Get trace details from Tempo
echo "🔗 Trace Details from Tempo:"
echo "─────────────────────────────────────────────────────────────────"
TRACE_JSON=$(curl -s "http://localhost:3200/api/traces/$TRACE_ID")

if echo "$TRACE_JSON" | jq -e . >/dev/null 2>&1; then
    # Parse trace information
    SPANS=$(echo "$TRACE_JSON" | jq -r '.batches[].scopeSpans[].spans[] | "\(.name) [\(.startTimeUnixNano | tonumber / 1000000000 | strftime("%H:%M:%S"))] - Duration: \((.endTimeUnixNano - .startTimeUnixNano) / 1000000)ms"' 2>/dev/null)
    
    if [ -n "$SPANS" ]; then
        echo "$SPANS"
    else
        echo "⚠️  Trace found but no spans could be parsed"
    fi
    
    # Get service names involved
    echo ""
    echo "🏢 Services Involved:"
    echo "$TRACE_JSON" | jq -r '.batches[].resource.attributes[] | select(.key == "service.name") | "  • \(.value.stringValue)"' 2>/dev/null | sort -u
else
    echo "⚠️  Trace not found in Tempo (may still be ingesting)"
fi
echo ""

# Show detailed logs from each service
echo "📝 Detailed Logs by Service:"
echo "─────────────────────────────────────────────────────────────────"

# Order Service logs
ORDER_LOGS=$(docker logs k8s-observability-demo-rust-order-service-1 2>&1 | grep "$TRACE_ID")
if [ -n "$ORDER_LOGS" ]; then
    echo ""
    echo "📦 Order Service (Rust):"
    echo "$ORDER_LOGS" | jq -r '"[order-service] \(.timestamp) [\(.level)] \(.fields.message)"' 2>/dev/null || echo "$ORDER_LOGS" | sed 's/^/[order-service] /'
fi

# User Service logs
USER_LOGS=$(docker logs k8s-observability-demo-python-user-service-1 2>&1 | grep "$TRACE_ID")
if [ -n "$USER_LOGS" ]; then
    echo ""
    echo "👤 User Service (Python):"
    echo "$USER_LOGS" | jq -r '"[user-service] \(.timestamp) [\(.level)] \(.message)"' 2>/dev/null || echo "$USER_LOGS" | sed 's/^/[user-service] /'
fi

# Inventory Service logs
INVENTORY_LOGS=$(docker logs k8s-observability-demo-go-inventory-service-1 2>&1 | grep "$TRACE_ID")
if [ -n "$INVENTORY_LOGS" ]; then
    echo ""
    echo "📊 Inventory Service (Go):"
    echo "$INVENTORY_LOGS" | jq -r '"[inventory-service] \(.timestamp) [\(.level)] \(.message)"' 2>/dev/null || echo "$INVENTORY_LOGS" | sed 's/^/[inventory-service] /'
fi

echo ""
echo "⏱️  Chronological View (All Services):"
echo "─────────────────────────────────────────────────────────────────"

# Collect and merge all logs with timestamps
{
    # Order Service logs with normalized format
    docker logs k8s-observability-demo-rust-order-service-1 2>&1 | grep "$TRACE_ID" | \
        jq -r '"\(.timestamp)|[order-service]|\(.level)|\(.fields.message)"' 2>/dev/null
    
    # User Service logs with normalized format
    docker logs k8s-observability-demo-python-user-service-1 2>&1 | grep "$TRACE_ID" | \
        jq -r '"\(.timestamp)|[user-service]|\(.level)|\(.message)"' 2>/dev/null
    
    # Inventory Service logs with normalized format
    docker logs k8s-observability-demo-go-inventory-service-1 2>&1 | grep "$TRACE_ID" | \
        jq -r '"\(.timestamp)|[inventory-service]|\(.level)|\(.message)"' 2>/dev/null
} | sort | awk -F'|' '{printf "%-32s %-20s [%-5s] %s\n", $1, $2, $3, $4}'

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "🌐 View in Grafana: http://localhost:3000/explore"
echo "   → Select Tempo datasource"
echo "   → Search for trace ID: $TRACE_ID"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check Loki for correlated logs
echo "🔍 Querying Loki for correlated logs..."
LOKI_RESULT=$(curl -s -G --data-urlencode "query={job=~\".*-service\"} |= \"$TRACE_ID\"" "http://localhost:3100/loki/api/v1/query" | jq -r '.data.result | length' 2>/dev/null)

if [ "$LOKI_RESULT" != "null" ] && [ "$LOKI_RESULT" != "" ]; then
    echo "✅ Found $LOKI_RESULT log stream(s) in Loki with this trace ID"
    echo "   Query: {job=~\".*-service\"} |= \"$TRACE_ID\""
else
    echo "⚠️  Loki may still be ingesting logs"
fi

echo ""
