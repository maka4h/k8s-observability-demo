#!/bin/bash

echo "Loading Docker images..."

# Load images - they will use the names from when they were saved
docker load -i python-user-service-1.0.0.tar
docker load -i rust-order-service-1.0.0.tar
docker load -i go-inventory-service-1.0.0.tar

echo ""
echo "✅ Images loaded successfully!"
echo ""
echo "Loaded images:"
docker images | grep -E "python-user-service|rust-order-service|go-inventory-service"

echo ""
echo "Images are ready to use with names:"
echo "  - python-user-service:1.0.0"
echo "  - rust-order-service:1.0.0"
echo "  - go-inventory-service:1.0.0"
echo ""
echo "To retag for a registry:"
echo "  docker tag python-user-service:1.0.0 myregistry.com/python-user-service:1.0.0"
