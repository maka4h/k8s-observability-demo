.PHONY: help build-images deploy-k8s deploy-local clean test load-test

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Docker Compose (Local Development)
build-local: ## Build all Docker images for local development
	@echo "🐳 Building Docker images..."
	docker-compose build

deploy-local: ## Start all services locally with docker-compose
	@echo "🚀 Starting local environment..."
	docker-compose up -d
	@echo "✅ Services started! Access:"
	@echo "   User Service: http://localhost:8000"
	@echo "   Order Service: http://localhost:8001"
	@echo "   Inventory Service: http://localhost:8002"
	@echo "   Grafana: http://localhost:3000 (admin/admin)"
	@echo "   Prometheus: http://localhost:9090"

logs-local: ## View logs from local services
	docker-compose logs -f

stop-local: ## Stop local services
	docker-compose down

clean-local: ## Stop and remove all local containers and volumes
	docker-compose down -v

# Kubernetes Deployment
build-images: ## Build Docker images for Kubernetes
	@echo "🐳 Building Docker images..."
	docker build -t python-user-service:latest ./services/python-user-service
	docker build -t rust-order-service:latest ./services/rust-order-service
	docker build -t go-inventory-service:latest ./services/go-inventory-service

install-observability: ## Install observability stack (Prometheus, Grafana, Loki, Tempo)
	@chmod +x scripts/install-observability.sh
	@./scripts/install-observability.sh

deploy-k8s: build-images ## Build images and deploy to Kubernetes
	@chmod +x scripts/deploy-services.sh
	@./scripts/deploy-services.sh

port-forward-grafana: ## Port forward Grafana
	@echo "🌐 Accessing Grafana at http://localhost:3000"
	kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80

port-forward-services: ## Port forward all microservices
	@echo "🌐 Port forwarding services..."
	@kubectl port-forward -n demo svc/python-user-service 8000:8000 &
	@kubectl port-forward -n demo svc/rust-order-service 8001:8001 &
	@kubectl port-forward -n demo svc/go-inventory-service 8002:8002 &
	@echo "✅ Services accessible:"
	@echo "   User Service: http://localhost:8000"
	@echo "   Order Service: http://localhost:8001"
	@echo "   Inventory Service: http://localhost:8002"
	@echo ""
	@echo "Press Ctrl+C to stop port forwarding"

# Testing
test: ## Run service tests
	@chmod +x scripts/test-services.sh
	@./scripts/test-services.sh

test-local: ## Test local docker-compose services
	@chmod +x scripts/test-services.sh
	@./scripts/test-services.sh http://localhost:8000 http://localhost:8001 http://localhost:8002

load-test: ## Run load test (default: 60s, 10 req/s)
	@chmod +x scripts/load-test.sh
	@./scripts/load-test.sh

load-test-local: ## Run load test on local services
	@chmod +x scripts/load-test.sh
	@./scripts/load-test.sh http://localhost:8000 http://localhost:8001 http://localhost:8002

# Cleanup
clean-k8s: ## Delete all Kubernetes resources
	@echo "🗑️  Cleaning up Kubernetes resources..."
	kubectl delete namespace demo --ignore-not-found=true
	kubectl delete namespace observability --ignore-not-found=true

clean: clean-local clean-k8s ## Clean up everything

# Status
status-local: ## Show status of local services
	docker-compose ps

status-k8s: ## Show status of Kubernetes resources
	@echo "📊 Observability Stack:"
	@kubectl get pods -n observability
	@echo ""
	@echo "🚀 Demo Services:"
	@kubectl get pods -n demo

# Development helpers
dev-python: ## Run Python service in development mode
	cd services/python-user-service && pip install -r requirements.txt && python main.py

dev-rust: ## Run Rust service in development mode
	cd services/rust-order-service && cargo run

dev-go: ## Run Go service in development mode
	cd services/go-inventory-service && go run main.go
