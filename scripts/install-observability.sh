#!/bin/bash

set -e

echo "🚀 Installing Observability Stack..."

# Create observability namespace
echo "📦 Creating observability namespace..."
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repositories
echo "📚 Adding Helm repositories..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
echo "📊 Installing Prometheus and Grafana..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=10Gi \
  --set prometheus.prometheusSpec.retention=15d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --wait

# Install Loki
echo "📝 Installing Loki..."
helm upgrade --install loki grafana/loki-stack \
  --namespace observability \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=10Gi \
  --set promtail.enabled=true \
  --set grafana.enabled=false \
  --set loki.config.table_manager.retention_deletes_enabled=true \
  --set loki.config.table_manager.retention_period=168h \
  --wait

# Install Tempo
echo "🔍 Installing Tempo..."
helm upgrade --install tempo grafana/tempo \
  --namespace observability \
  --set tempo.retention=24h \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --wait

# Wait for pods to be ready
echo "⏳ Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod \
  --all \
  --namespace=observability \
  --timeout=300s

# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret --namespace observability kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

echo ""
echo "✅ Observability Stack installed successfully!"
echo ""
echo "📊 Access URLs (use port-forward):"
echo "  Grafana:    kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80"
echo "              http://localhost:3000 (admin / ${GRAFANA_PASSWORD})"
echo ""
echo "  Prometheus: kubectl port-forward -n observability svc/kube-prometheus-stack-prometheus 9090:9090"
echo "              http://localhost:9090"
echo ""
echo "  Alertmanager: kubectl port-forward -n observability svc/kube-prometheus-stack-alertmanager 9093:9093"
echo "                http://localhost:9093"
echo ""
echo "📝 Configure Grafana datasources:"
echo "  - Loki:  http://loki:3100"
echo "  - Tempo: http://tempo:3100"
echo ""
echo "🎉 Done! You can now deploy your services."
