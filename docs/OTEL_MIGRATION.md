# Migration to OpenTelemetry Collector

This document describes the migration from Promtail + direct Tempo integration to using OpenTelemetry Collector as a unified observability agent.

## What Changed

### Before: Multiple Collection Agents

```
Logs:    Services → Docker logs ← Promtail (pulls) → Loki
Metrics: Services /metrics ← Prometheus (scrapes) → Prometheus storage
Traces:  Services → Tempo (direct push via OTLP)
```

**Issues:**
- ❌ Promtail is deprecated (EOL March 2, 2026)
- ❌ No buffering/routing layer for traces
- ❌ Two separate agents to maintain
- ❌ Services tightly coupled to backends

### After: Unified OpenTelemetry Collector

```
Logs:    Services → Docker logs ← OTel Collector → Loki
Metrics: Services /metrics ← OTel Collector → Prometheus storage  
Traces:  Services → OTel Collector (OTLP) → Tempo
```

**Benefits:**
- ✅ Single, vendor-agnostic agent
- ✅ Buffering prevents data loss
- ✅ Easy to route to multiple backends
- ✅ Centralized data processing (sampling, filtering, enrichment)
- ✅ Production best practice architecture

## Architecture Changes

### Docker Compose Environment

**Removed:**
- `promtail` service

**Added:**
- `otel-collector` service with:
  - OTLP receivers (ports 4317/4318)
  - Filelog receiver for Docker logs
  - Prometheus scraper
  - Exporters for Loki, Tempo, Prometheus

**Modified:**
- All services now send traces to `otel-collector:4317` instead of `tempo:4317`
- Prometheus enabled remote write receiver to accept metrics from OTel Collector
- Tempo no longer exposes OTLP ports (only accessed via collector)

### Kubernetes Environment

**Removed:**
- Promtail DaemonSet

**Added:**
- OTel Collector DaemonSet with:
  - ServiceAccount and RBAC for Kubernetes metadata
  - K8s attributes processor for pod/namespace enrichment
  - Filelog receiver for pod logs
  - Service discovery for metrics scraping

**Modified:**
- All service manifests updated to send traces to `otel-collector.observability.svc.cluster.local:4317`

## Configuration Files

### New Files

1. **`otel-collector-config.yaml`** (Docker Compose)
   - Receivers: OTLP, Prometheus, Filelog (Docker)
   - Processors: Batch, Memory Limiter, Resource Attributes
   - Exporters: Loki, Tempo, Prometheus Remote Write

2. **`k8s/observability/otel-collector.yaml`** (Kubernetes)
   - ConfigMap with collector configuration
   - DaemonSet deployment
   - Service for OTLP endpoints
   - ServiceAccount + RBAC

### Modified Files

1. **`docker-compose.yml`**
   - Removed: `promtail` service
   - Added: `otel-collector` service
   - Updated: All service environment variables
   - Updated: Prometheus command flags

2. **Service Manifests** (K8s)
   - `k8s/services/python-user-service.yaml`
   - `k8s/services/rust-order-service.yaml`
   - `k8s/services/go-inventory-service.yaml`

3. **Documentation**
   - `README.md`
   - `docs/ARCHITECTURE.md`

## Migration Steps (Completed)

✅ 1. Created OTel Collector configuration files  
✅ 2. Updated Docker Compose to use OTel Collector  
✅ 3. Updated service configurations to route through collector  
✅ 4. Created Kubernetes OTel Collector manifest  
✅ 5. Updated all K8s service manifests  
✅ 6. Updated documentation

## Testing the Migration

### Docker Compose

```bash
# Stop existing stack
docker-compose down

# Start with OTel Collector
docker-compose up -d

# Verify OTel Collector is healthy
curl http://localhost:8888/metrics  # Collector's own metrics

# Generate test traffic
curl -X POST http://localhost:8000/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com"}'

# Check in Grafana (http://localhost:3000)
# 1. Explore → Loki → Query logs
# 2. Explore → Tempo → Query traces
# 3. Explore → Prometheus → Query metrics
```

### Kubernetes

```bash
# Deploy OTel Collector
kubectl apply -f k8s/observability/otel-collector.yaml

# Verify DaemonSet
kubectl get daemonset -n observability otel-collector
kubectl logs -n observability -l app=otel-collector

# Redeploy services
kubectl rollout restart deployment -n demo python-user-service
kubectl rollout restart deployment -n demo rust-order-service
kubectl rollout restart deployment -n demo go-inventory-service

# Generate test traffic
kubectl run curl --image=curlimages/curl -i --rm --restart=Never -- \
  curl -X POST http://python-user-service.demo:8000/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com"}'
```

## Verification Checklist

- [ ] OTel Collector is running and healthy
- [ ] Logs appear in Loki with correct labels
- [ ] Traces appear in Tempo with all spans
- [ ] Metrics appear in Prometheus from all services
- [ ] Trace-to-logs correlation works in Grafana
- [ ] No errors in OTel Collector logs

## Rollback (If Needed)

If you need to rollback to the old Promtail-based setup:

```bash
# Docker Compose
git checkout HEAD~1 docker-compose.yml promtail-docker-config.yaml
docker-compose up -d

# Kubernetes
git checkout HEAD~1 k8s/
kubectl delete -f k8s/observability/otel-collector.yaml
kubectl apply -f k8s/observability/promtail-config.yaml
```

## Future Enhancements

Now that we have OTel Collector in place, we can easily:

1. **Route to multiple backends** - Send traces to both Tempo and Jaeger
2. **Add sampling** - Reduce trace volume for high-traffic services
3. **Enrich data** - Add custom attributes at collector level
4. **Switch backends** - Change from Loki to Elasticsearch without touching services
5. **Add profiling** - Forward continuous profiling data to Pyroscope

## References

- [OpenTelemetry Collector Documentation](https://opentelemetry.io/docs/collector/)
- [OTel Collector Contrib Components](https://github.com/open-telemetry/opentelemetry-collector-contrib)
- [Best Practices for OTel Collector](https://opentelemetry.io/docs/collector/deployment/)
- [Grafana Loki with OTel Collector](https://grafana.com/docs/loki/latest/send-data/otel/)
