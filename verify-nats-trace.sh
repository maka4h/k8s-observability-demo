#!/bin/bash

# Script to verify NATS trace propagation
# This checks that trace context is properly propagated through NATS messages

echo "🔍 NATS Trace Propagation Verification"
echo "======================================="
echo ""

# Create a test user
echo "📤 Creating test user..."
RESPONSE=$(curl -s -X POST http://localhost:8000/api/users \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"NATS Trace Test $(date +%s)\", \"email\": \"test-$(date +%s)@example.com\"}")

USER_ID=$(echo $RESPONSE | jq -r '.id')
echo "✅ Created user ID: $USER_ID"
echo ""

# Wait a moment for NATS message to be processed
sleep 1

echo "📊 Checking Python Publisher Logs..."
echo "-----------------------------------"
PYTHON_LOG=$(docker logs k8s-observability-demo-python-user-service-1 2>&1 | grep "Published user.created event for user $USER_ID" | tail -1)

if [ -n "$PYTHON_LOG" ]; then
    TRACE_ID=$(echo "$PYTHON_LOG" | jq -r '.trace_id')
    SPAN_ID=$(echo "$PYTHON_LOG" | jq -r '.span_id')
    HEADERS=$(echo "$PYTHON_LOG" | jq -r '.message' | grep -o "{'traceparent': '[^']*'}")
    
    echo "🔖 Trace ID: $TRACE_ID"
    echo "🔖 Span ID: $SPAN_ID"
    echo "📋 NATS Headers: $HEADERS"
else
    echo "❌ No publisher log found"
    exit 1
fi

echo ""
echo "📥 Checking Rust Consumer Logs..."
echo "-----------------------------------"
RUST_LOG=$(docker logs k8s-observability-demo-rust-order-service-1 2>&1 | grep "Received NATS message with headers" | tail -1)

if [ -n "$RUST_LOG" ]; then
    TRACEPARENT=$(echo "$RUST_LOG" | grep -o '00-[a-f0-9]*-[a-f0-9]*-[0-9]*')
    RECEIVED_TRACE_ID=$(echo "$TRACEPARENT" | cut -d'-' -f2)
    RECEIVED_PARENT_SPAN=$(echo "$TRACEPARENT" | cut -d'-' -f3)
    
    echo "📨 Received traceparent: $TRACEPARENT"
    echo "🔖 Extracted Trace ID: $RECEIVED_TRACE_ID"
    echo "🔗 Parent Span ID: $RECEIVED_PARENT_SPAN"
else
    echo "❌ No consumer log found"
    exit 1
fi

echo ""
echo "✅ Verification Results"
echo "======================="

if [ "$TRACE_ID" = "$RECEIVED_TRACE_ID" ]; then
    echo "✅ Trace ID MATCHES: $TRACE_ID"
    echo "✅ Trace context successfully propagated through NATS!"
    
    if [ "$SPAN_ID" = "$RECEIVED_PARENT_SPAN" ]; then
        echo "✅ Parent span ID preserved: $SPAN_ID"
    else
        echo "ℹ️  Parent span: $SPAN_ID → Consumer received: $RECEIVED_PARENT_SPAN"
    fi
else
    echo "❌ Trace ID MISMATCH!"
    echo "   Publisher: $TRACE_ID"
    echo "   Consumer:  $RECEIVED_TRACE_ID"
    exit 1
fi

echo ""
echo "🎉 NATS trace propagation is working correctly!"
echo ""
echo "💡 The W3C Trace Context 'traceparent' header format is:"
echo "   version-trace_id-parent_span_id-flags"
echo "   Example: 00-$TRACE_ID-$SPAN_ID-01"
