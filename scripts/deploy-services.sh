#!/bin/bash

set -e

echo "🏗️  Building and deploying demo services..."

# Build Docker images
echo "🐳 Building Docker images..."

echo "  Building Python user service..."
docker build -t python-user-service:latest ./services/python-user-service

echo "  Building Rust order service..."
docker build -t rust-order-service:latest ./services/rust-order-service

echo "  Building Go inventory service..."
docker build -t go-inventory-service:latest ./services/go-inventory-service

# Create demo namespace
echo "📦 Creating demo namespace..."
kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -

# Deploy infrastructure
echo "🗄️  Deploying infrastructure (PostgreSQL, MongoDB, NATS)..."
kubectl apply -f k8s/infrastructure/

# Wait for infrastructure to be ready
echo "⏳ Waiting for infrastructure to be ready..."
kubectl wait --for=condition=ready pod \
  -l app=postgres \
  --namespace=demo \
  --timeout=120s

kubectl wait --for=condition=ready pod \
  -l app=mongodb \
  --namespace=demo \
  --timeout=120s

kubectl wait --for=condition=ready pod \
  -l app=nats \
  --namespace=demo \
  --timeout=120s

# Deploy services
echo "🚀 Deploying microservices..."
kubectl apply -f k8s/services/

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

kubectl wait --for=condition=ready pod \
  -l app=python-user-service \
  --namespace=demo \
  --timeout=120s || echo "⚠️  Python service not ready yet"

kubectl wait --for=condition=ready pod \
  -l app=rust-order-service \
  --namespace=demo \
  --timeout=120s || echo "⚠️  Rust service not ready yet"

kubectl wait --for=condition=ready pod \
  -l app=go-inventory-service \
  --namespace=demo \
  --timeout=120s || echo "⚠️  Go service not ready yet"

echo ""
echo "✅ Demo services deployed successfully!"
echo ""
echo "📊 Service URLs (use port-forward):"
echo "  User Service:      kubectl port-forward -n demo svc/python-user-service 8000:8000"
echo "                     http://localhost:8000"
echo ""
echo "  Order Service:     kubectl port-forward -n demo svc/rust-order-service 8001:8001"
echo "                     http://localhost:8001"
echo ""
echo "  Inventory Service: kubectl port-forward -n demo svc/go-inventory-service 8002:8002"
echo "                     http://localhost:8002"
echo ""
echo "🧪 Test the services:"
echo "  ./scripts/test-services.sh"
echo ""
echo "📈 Generate load:"
echo "  ./scripts/load-test.sh"
