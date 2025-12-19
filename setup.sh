#!/bin/bash

# K8s Observability Demo - All-in-One Setup Script
# This script sets up everything you need to get started

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║     Kubernetes Observability Demo - Setup Wizard              ║"
echo "║                                                                ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "🔍 Checking prerequisites..."
echo ""

MISSING_DEPS=()

if ! command_exists docker; then
    MISSING_DEPS+=("docker")
fi

if ! command_exists docker-compose; then
    MISSING_DEPS+=("docker-compose")
fi

if ! command_exists kubectl; then
    echo "⚠️  kubectl not found (optional - only needed for Kubernetes deployment)"
fi

if ! command_exists helm; then
    echo "⚠️  Helm not found (optional - only needed for Kubernetes deployment)"
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "❌ Missing required dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "Please install:"
    echo "  Docker: https://docs.docker.com/get-docker/"
    echo "  Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✅ All required dependencies found!"
echo ""

# Ask user what they want to do
echo "What would you like to do?"
echo ""
echo "  1) Quick start with Docker Compose (recommended for first-time users)"
echo "  2) Deploy to Kubernetes cluster"
echo "  3) Just build Docker images"
echo "  4) Show me the documentation"
echo "  5) Exit"
echo ""
read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        echo ""
        echo "🚀 Starting local environment with Docker Compose..."
        echo ""
        
        # Build images
        echo "📦 Building Docker images (this may take a few minutes)..."
        docker-compose build
        
        # Start services
        echo "🎬 Starting all services..."
        docker-compose up -d
        
        # Wait for services to be ready
        echo "⏳ Waiting for services to be ready..."
        sleep 15
        
        # Check health
        echo "🏥 Checking service health..."
        
        if curl -s http://localhost:8000/health >/dev/null 2>&1; then
            echo "  ✅ Python User Service: http://localhost:8000"
        else
            echo "  ⚠️  Python User Service: Not ready yet"
        fi
        
        if curl -s http://localhost:8001/health >/dev/null 2>&1; then
            echo "  ✅ Rust Order Service: http://localhost:8001"
        else
            echo "  ⚠️  Rust Order Service: Not ready yet (may need more time to compile)"
        fi
        
        if curl -s http://localhost:8002/health >/dev/null 2>&1; then
            echo "  ✅ Go Inventory Service: http://localhost:8002"
        else
            echo "  ⚠️  Go Inventory Service: Not ready yet"
        fi
        
        if curl -s http://localhost:3000 >/dev/null 2>&1; then
            echo "  ✅ Grafana: http://localhost:3000 (admin/admin)"
        else
            echo "  ⚠️  Grafana: Not ready yet"
        fi
        
        echo ""
        echo "🎉 Setup complete!"
        echo ""
        echo "📊 Access points:"
        echo "  • Grafana:         http://localhost:3000 (admin/admin)"
        echo "  • Prometheus:      http://localhost:9090"
        echo "  • User Service:    http://localhost:8000"
        echo "  • Order Service:   http://localhost:8001"
        echo "  • Inventory Service: http://localhost:8002"
        echo ""
        echo "🧪 Test the setup:"
        echo "  ./scripts/test-services.sh"
        echo ""
        echo "🔥 Generate load:"
        echo "  ./scripts/load-test.sh"
        echo ""
        echo "📖 View logs:"
        echo "  docker-compose logs -f"
        echo ""
        echo "🛑 Stop everything:"
        echo "  docker-compose down"
        ;;
        
    2)
        echo ""
        echo "☸️  Deploying to Kubernetes..."
        echo ""
        
        if ! command_exists kubectl; then
            echo "❌ kubectl is required for Kubernetes deployment"
            exit 1
        fi
        
        if ! command_exists helm; then
            echo "❌ Helm is required for Kubernetes deployment"
            exit 1
        fi
        
        # Check if connected to cluster
        if ! kubectl cluster-info >/dev/null 2>&1; then
            echo "❌ Cannot connect to Kubernetes cluster"
            echo "Please ensure kubectl is configured correctly"
            exit 1
        fi
        
        echo "📊 Installing observability stack..."
        ./scripts/install-observability.sh
        
        echo ""
        echo "🚀 Building and deploying services..."
        ./scripts/deploy-services.sh
        
        echo ""
        echo "✅ Deployment complete!"
        echo ""
        echo "📊 Access services:"
        echo "  Grafana:       kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80"
        echo "  User Service:  kubectl port-forward -n demo svc/python-user-service 8000:8000"
        echo "  Order Service: kubectl port-forward -n demo svc/rust-order-service 8001:8001"
        echo "  Inventory:     kubectl port-forward -n demo svc/go-inventory-service 8002:8002"
        echo ""
        echo "🧪 Test the setup:"
        echo "  ./scripts/test-services.sh"
        ;;
        
    3)
        echo ""
        echo "🔨 Building Docker images..."
        echo ""
        
        echo "Building Python User Service..."
        docker build -t python-user-service:latest ./services/python-user-service
        
        echo "Building Rust Order Service..."
        docker build -t rust-order-service:latest ./services/rust-order-service
        
        echo "Building Go Inventory Service..."
        docker build -t go-inventory-service:latest ./services/go-inventory-service
        
        echo ""
        echo "✅ All images built successfully!"
        echo ""
        echo "📋 Images:"
        docker images | grep -E "python-user-service|rust-order-service|go-inventory-service"
        ;;
        
    4)
        echo ""
        echo "📚 Documentation Guide:"
        echo ""
        echo "Start here:"
        echo "  📖 README.md          - Project overview and introduction"
        echo "  🚀 QUICKSTART.md      - Step-by-step getting started guide"
        echo ""
        echo "Deep dives:"
        echo "  🏗️  ARCHITECTURE.md    - System architecture and diagrams"
        echo "  👁️  OBSERVABILITY.md   - How observability is implemented"
        echo "  📋 SUMMARY.md         - Complete project summary"
        echo ""
        echo "Reference:"
        echo "  ❓ FAQ.md             - Frequently asked questions"
        echo "  📁 services/*/README.md - Service-specific documentation"
        echo ""
        echo "Quick commands:"
        echo "  • make help           - Show all available Make targets"
        echo "  • make deploy-local   - Start everything locally"
        echo "  • make test-local     - Test local services"
        echo ""
        cat README.md
        ;;
        
    5)
        echo "Goodbye! 👋"
        exit 0
        ;;
        
    *)
        echo "❌ Invalid choice. Please run the script again."
        exit 1
        ;;
esac

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
