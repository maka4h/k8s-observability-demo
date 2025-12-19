# Frequently Asked Questions (FAQ)

## General Questions

### Q: What is this project?
**A:** A complete demonstration of Kubernetes observability with three microservices (Python/Rust/Go) integrated with Prometheus, Loki, Tempo, and Grafana. It shows how to add comprehensive observability with minimal code changes.

### Q: Do I need Kubernetes to run this?
**A:** No! You can run everything locally with Docker Compose. Kubernetes deployment is optional for testing in a more production-like environment.

### Q: How much does this cost?
**A:** $0! Everything uses open-source tools. You only pay for infrastructure (compute, storage) if deploying to a cloud provider.

### Q: Is this production-ready?
**A:** The patterns and code are production-ready, but you'd want to add:
- Persistent storage for databases
- High availability (multiple replicas)
- Security (TLS, authentication, RBAC)
- Backup strategies
- Resource limits tuning

---

## Setup and Installation

### Q: What are the minimum system requirements?
**A:** 
- **Docker Compose**: 8GB RAM, 4 CPU cores, 20GB disk
- **Kubernetes**: Same as above + kubectl, Helm 3, and a K8s cluster

### Q: Which operating systems are supported?
**A:** macOS, Linux, and Windows (with WSL2). All examples work on any platform with Docker.

### Q: How long does initial setup take?
**A:**
- Docker Compose: ~5-10 minutes (including image builds)
- Kubernetes: ~15-20 minutes (including Helm installs)

### Q: Can I run this on minikube/kind/k3s?
**A:** Yes! Any Kubernetes distribution works. Just ensure you have enough resources allocated.

### Q: Do I need to know Rust/Go/Python to use this?
**A:** No. The services are pre-built. You can run and observe them without modifying code. However, understanding helps if you want to customize.

---

## Architecture Questions

### Q: Why three different languages?
**A:** To demonstrate that observability patterns work across languages. You can pick the approach that matches your stack.

### Q: Can I add more services?
**A:** Absolutely! Follow the pattern from any existing service:
1. Add OpenTelemetry instrumentation (1-2 lines)
2. Expose `/metrics` endpoint
3. Create K8s manifests
4. Deploy

### Q: Why both PostgreSQL and MongoDB?
**A:** To show polyglot persistence - a realistic pattern where different services use different databases based on their needs.

### Q: What does NATS do here?
**A:** Provides asynchronous communication between services. Shows how to maintain observability across message boundaries.

### Q: Can I replace PostgreSQL with MySQL?
**A:** Yes! The pattern is the same:
1. Change connection string
2. Update driver (e.g., `mysqlclient` for Python)
3. Adjust SQL syntax if needed

### Q: Can I use Redis/RabbitMQ/Kafka instead of NATS?
**A:** Yes. The observability approach doesn't depend on the message queue. Just update the client code and ensure trace context propagation.

---

## Observability Questions

### Q: What is the "Three Pillars of Observability"?
**A:**
1. **Metrics** - Numerical data over time (CPU, requests/sec)
2. **Logs** - Discrete events with context
3. **Traces** - Request flows across services

This demo implements all three!

### Q: How does distributed tracing work?
**A:** 
1. Service A creates a trace with unique ID
2. Passes trace ID in HTTP headers to Service B
3. Service B continues the same trace
4. Both send spans to Tempo
5. Tempo links them into one trace
6. You see the complete request flow in Grafana

### Q: What's the difference between metrics and logs?
**A:**
- **Metrics**: Aggregated, efficient, good for trends and alerts
- **Logs**: Detailed, contextual, good for debugging specific issues

Use both! Metrics tell you *what's* wrong, logs tell you *why*.

### Q: How much overhead does observability add?
**A:**
- **Metrics**: <1% CPU, minimal memory
- **Logs**: 2-5% overhead depending on volume
- **Traces**: 1-3% with sampling

Total: Usually <5% with proper configuration.

### Q: What is trace sampling?
**A:** Instead of tracing 100% of requests, you trace a percentage (e.g., 10%). This reduces overhead while still giving visibility. Increase during debugging.

### Q: Can I trace database queries automatically?
**A:** Yes! 
- **Python**: OpenTelemetry auto-instruments SQLAlchemy
- **Rust**: Use `#[instrument]` on functions that query
- **Go**: Manual spans or use OTel database drivers

### Q: How do I correlate logs with traces?
**A:** The OpenTelemetry libraries automatically inject trace IDs into logs. In Grafana, click a log line and jump to its trace!

---

## Development Questions

### Q: How do I test changes to a service?
**A:**
```bash
# Rebuild and restart single service
docker-compose build python-user-service
docker-compose up -d python-user-service

# Or for development
cd services/python-user-service
python main.py
```

### Q: How do I add a custom metric?
**A:**
**Python:**
```python
from prometheus_client import Counter
my_metric = Counter('my_custom_metric', 'Description')
my_metric.inc()
```

**Rust:**
```rust
use prometheus::{IntCounter, register_int_counter};
let my_metric = register_int_counter!("my_custom_metric", "Description").unwrap();
my_metric.inc();
```

**Go:**
```go
myMetric := promauto.NewCounter(prometheus.CounterOpts{
    Name: "my_custom_metric",
    Help: "Description",
})
myMetric.Inc()
```

### Q: How do I add manual tracing spans?
**A:**
**Python:**
```python
from opentelemetry import trace
tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("my_operation"):
    # your code here
```

**Rust:**
```rust
use tracing::info_span;

let span = info_span!("my_operation");
let _enter = span.enter();
// your code here
```

**Go:**
```go
ctx, span := tracer.Start(ctx, "my_operation")
defer span.End()
// your code here
```

### Q: How do I change log levels?
**A:** Set environment variables:
- Python: `LOG_LEVEL=DEBUG`
- Rust: `RUST_LOG=debug`
- Go: `LOG_LEVEL=debug`

### Q: Can I use this with my existing services?
**A:** Yes! The patterns demonstrated here can be added to existing services. Start with:
1. Add OpenTelemetry library
2. Initialize at startup
3. Add middleware
4. Expose `/metrics` endpoint

---

## Kubernetes Questions

### Q: Why use Helm?
**A:** Helm simplifies deploying complex stacks like Prometheus + Grafana. It handles dependencies and configuration automatically.

### Q: What are ServiceMonitors?
**A:** Kubernetes custom resources that tell Prometheus which services to scrape. The Prometheus Operator watches for these and automatically updates Prometheus configuration.

### Q: Can I use this without the Prometheus Operator?
**A:** Yes, but you'll need to manually configure Prometheus scrape targets. ServiceMonitors make it automatic.

### Q: How do I access services in Kubernetes?
**A:**
```bash
# Port forward
kubectl port-forward -n demo svc/python-user-service 8000:8000

# Or create Ingress
# Or use LoadBalancer service type
```

### Q: How do I scale services?
**A:**
```bash
kubectl scale deployment -n demo python-user-service --replicas=5
```

Observability continues working - Prometheus discovers all replicas automatically!

### Q: What about persistent storage?
**A:** The demo uses `emptyDir` for simplicity. For production:
```yaml
volumes:
- name: data
  persistentVolumeClaim:
    claimName: my-pvc
```

---

## Grafana Questions

### Q: What's the default Grafana login?
**A:** Username: `admin`, Password: `admin` (for local Docker Compose) or check the Helm output for Kubernetes.

### Q: How do I create a dashboard?
**A:**
1. Go to Dashboards → New Dashboard
2. Add Panel
3. Select datasource (Prometheus/Loki/Tempo)
4. Write query
5. Choose visualization
6. Save

### Q: Where can I find pre-built dashboards?
**A:** 
- [Grafana Dashboard Library](https://grafana.com/grafana/dashboards/)
- Search for: "FastAPI", "Kubernetes", "MongoDB", etc.
- Import by ID or JSON

### Q: How do I query traces?
**A:**
1. Go to Explore
2. Select Tempo datasource
3. Search by:
   - Service name
   - Duration
   - Tags
   - Trace ID

### Q: What's the difference between Dashboard and Explore?
**A:**
- **Dashboard**: Pre-configured panels for monitoring
- **Explore**: Ad-hoc querying and investigation

Use Dashboards for monitoring, Explore for debugging.

---

## Troubleshooting

### Q: Service won't start - "port already in use"
**A:**
```bash
# Find what's using the port
lsof -i :8000

# Kill it or change the port in docker-compose.yml
```

### Q: No metrics appearing in Prometheus
**A:**
1. Check service is exposing `/metrics`: `curl http://localhost:8000/metrics`
2. Check Prometheus targets: http://localhost:9090/targets
3. Verify ServiceMonitor created: `kubectl get servicemonitors -n demo`
4. Check Prometheus logs: `kubectl logs -n observability -l app=prometheus`

### Q: No traces in Tempo
**A:**
1. Verify `OTEL_EXPORTER_OTLP_ENDPOINT` is set correctly
2. Check sampling rate isn't 0
3. Look for export errors in service logs
4. Verify Tempo is running: `kubectl get pods -n observability`
5. Check Tempo logs: `kubectl logs -n observability -l app=tempo`

### Q: Can't connect to database
**A:**
1. Ensure database is ready: `docker-compose ps`
2. Check connection string environment variables
3. Test connectivity: `docker-compose exec postgres pg_isready`
4. Look at service logs: `docker-compose logs python-user-service`

### Q: Grafana shows "No data"
**A:**
1. Check datasource configuration
2. Verify time range (top-right in Grafana)
3. Ensure data exists: query Prometheus directly
4. Check datasource health: Configuration → Data Sources

### Q: Services crash immediately
**A:**
```bash
# Check logs
docker-compose logs service-name

# Common issues:
# - Missing environment variables
# - Database not ready
# - Port conflicts
# - Insufficient resources
```

---

## Performance and Scaling

### Q: How much storage does observability need?
**A:**
- **Prometheus**: ~1-2GB per day per 100 services (15-day retention)
- **Loki**: ~500MB per day per 100 services (7-day retention)
- **Tempo**: ~2-5GB per day per 100 services (24-hour retention, 10% sampling)

### Q: Can this handle production traffic?
**A:** The patterns scale, but you'd need to:
1. Use persistent storage (not emptyDir)
2. Configure high availability (multiple replicas)
3. Add load balancing
4. Tune resource limits
5. Consider long-term storage (S3, GCS)

### Q: What's a good trace sampling rate?
**A:**
- **Development**: 100% (see everything)
- **Staging**: 50-100%
- **Production**: 1-10% (adjust based on traffic)
- **High-traffic**: 0.1-1%

Higher = more overhead but more visibility.

### Q: How do I reduce observability costs?
**A:**
1. **Metrics**: Reduce scrape frequency, shorter retention
2. **Logs**: Filter out debug logs in production, shorter retention
3. **Traces**: Lower sampling rate, shorter retention
4. **Storage**: Use object storage (S3) for long-term retention

### Q: Can I use this with 1000+ requests/second?
**A:** Yes, but:
1. Reduce trace sampling (0.1-1%)
2. Use tail-based sampling (keep errors, drop successful traces)
3. Scale observability stack (multiple Tempo/Loki instances)
4. Consider managed services (Grafana Cloud, Datadog)

---

## Customization

### Q: Can I use Jaeger instead of Tempo?
**A:** Yes! Just change `OTEL_EXPORTER_OTLP_ENDPOINT` to Jaeger's OTLP endpoint. The services don't change.

### Q: Can I add authentication?
**A:** Yes:
- **Services**: Add auth middleware (JWT, OAuth2, etc.)
- **Grafana**: Configure LDAP, OAuth, or SAML
- **Databases**: Use TLS and strong passwords

### Q: How do I add alerts?
**A:**
1. Create alert rules in Prometheus:
```yaml
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
```
2. Configure AlertManager
3. Set notification channels (Slack, PagerDuty, email)

### Q: Can I deploy just one service?
**A:** Yes! Each service is independent. Just deploy the one you need plus its dependencies (database, NATS, observability stack).

---

## Learning and Best Practices

### Q: Where should I start?
**A:**
1. Read QUICKSTART.md
2. Run `make deploy-local`
3. Explore Grafana
4. Generate load with `make load-test-local`
5. Read OBSERVABILITY.md for deep dive

### Q: What are the key takeaways?
**A:**
1. Observability requires all three pillars (metrics, logs, traces)
2. Auto-instrumentation minimizes code changes
3. Trace context propagation is crucial for distributed systems
4. Sampling reduces overhead while maintaining visibility
5. Correlation (logs↔traces, metrics↔traces) is powerful

### Q: What should I do next?
**A:**
1. Create custom dashboards
2. Add alerts for your SLOs
3. Experiment with trace queries
4. Add a new service
5. Deploy to Kubernetes
6. Integrate with CI/CD

---

## Common Errors

### Error: "Cannot connect to Docker daemon"
**Solution:**
```bash
# Start Docker
sudo systemctl start docker  # Linux
open -a Docker               # macOS
```

### Error: "Helm not found"
**Solution:**
```bash
# Install Helm
brew install helm            # macOS
# Or see: https://helm.sh/docs/intro/install/
```

### Error: "Port 8000 already in use"
**Solution:**
```bash
# Find and kill the process
lsof -i :8000
kill -9 <PID>

# Or change the port in docker-compose.yml
```

### Error: "insufficient memory"
**Solution:**
Increase Docker memory allocation:
- Docker Desktop → Settings → Resources → Memory → 8GB+

---

## Additional Resources

### Documentation
- [QUICKSTART.md](QUICKSTART.md) - Getting started guide
- [OBSERVABILITY.md](OBSERVABILITY.md) - Implementation deep dive
- [ARCHITECTURE.md](ARCHITECTURE.md) - Architecture diagrams
- [SUMMARY.md](SUMMARY.md) - Project overview

### External Resources
- [OpenTelemetry Docs](https://opentelemetry.io/docs/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Grafana Tutorials](https://grafana.com/tutorials/)
- [Kubernetes Patterns](https://kubernetes.io/docs/concepts/)

### Community
- OpenTelemetry Slack: https://cloud-native.slack.com
- Prometheus Users: https://prometheus.io/community/
- Grafana Community: https://community.grafana.com/

---

**Still have questions?** Check the service-specific READMEs or create an issue!
