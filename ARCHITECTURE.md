# Architecture Diagrams

## Overall System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           Kubernetes Cluster / Docker Compose                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                          Microservices Layer                             │   │
│  │                                                                           │   │
│  │  ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐   │   │
│  │  │  Python Service  │   │   Rust Service   │   │   Go Service     │   │   │
│  │  │   User API       │   │   Order API      │   │  Inventory API   │   │   │
│  │  │  (FastAPI)       │   │    (Axum)        │   │     (Gin)        │   │   │
│  │  │  Port: 8000      │   │  Port: 8001      │   │   Port: 8002     │   │   │
│  │  └────────┬─────────┘   └────────┬─────────┘   └────────┬─────────┘   │   │
│  │           │                      │                      │              │   │
│  │           │ /metrics             │ /metrics             │ /metrics     │   │
│  │           │ /health              │ /health              │ /health      │   │
│  │           │ traces               │ traces               │ traces       │   │
│  │           │                      │                      │              │   │
│  └───────────┼──────────────────────┼──────────────────────┼──────────────┘   │
│              │                      │                      │                   │
│              ▼                      ▼                      ▼                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                         Data Layer                                       │   │
│  │                                                                           │   │
│  │  ┌──────────────┐        ┌──────────────┐       ┌──────────────┐       │   │
│  │  │  PostgreSQL  │◄───────┤     NATS     │──────►│   MongoDB    │       │   │
│  │  │              │        │  (JetStream) │       │              │       │   │
│  │  │  Port: 5432  │        │  Port: 4222  │       │  Port: 27017 │       │   │
│  │  └──────────────┘        └──────────────┘       └──────────────┘       │   │
│  │        ▲                                                  ▲              │   │
│  │        │                                                  │              │   │
│  │        └──────────────────────────────────────────────────┘              │   │
│  │                     User Service & Inventory Service                     │   │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│              │                      │                      │                   │
│              ▼                      ▼                      ▼                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      Observability Layer                                 │   │
│  │                                                                           │   │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │   │
│  │  │  Prometheus  │   │     Loki     │   │    Tempo     │                │   │
│  │  │  (Metrics)   │   │    (Logs)    │   │  (Traces)    │                │   │
│  │  │  Port: 9090  │   │  Port: 3100  │   │  Port: 3200  │                │   │
│  │  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘                │   │
│  │         │                  │                  │                          │   │
│  │         └──────────────────┴──────────────────┘                          │   │
│  │                            │                                             │   │
│  │                            ▼                                             │   │
│  │                  ┌──────────────────┐                                    │   │
│  │                  │     Grafana      │                                    │   │
│  │                  │  (Visualization) │                                    │   │
│  │                  │   Port: 3000     │                                    │   │
│  │                  └──────────────────┘                                    │   │
│  │                                                                           │   │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Request Flow with Observability

```
┌──────────┐
│  Client  │
└────┬─────┘
     │ HTTP POST /api/users
     │ X-Request-ID: abc123
     ▼
┌─────────────────────────────────────┐
│  Python User Service                │
│  ┌─────────────────────────────┐   │
│  │ OpenTelemetry Instrumentation│   │ ← Auto-instrumentation
│  │ - Start Span: POST /users   │   │
│  │ - Trace ID: xyz789          │   │
│  └───────────┬─────────────────┘   │
│              ▼                      │
│  ┌───────────────────────────┐     │
│  │  FastAPI Handler          │     │
│  │  create_user()            │     │
│  └───────┬───────────────────┘     │
│          │                          │
│          ▼                          │
│  ┌───────────────────────────┐     │
│  │  SQLAlchemy ORM           │     │ ← Auto-traced by OTel
│  │  INSERT INTO users...     │     │
│  └───────┬───────────────────┘     │
│          │                          │
│          ▼                          │
│  ┌───────────────────────────┐     │
│  │  PostgreSQL Query         │     │
│  │  (Span: db.query)         │     │
│  └───────┬───────────────────┘     │
│          │                          │
│          ▼                          │
│  ┌───────────────────────────┐     │
│  │  NATS Publisher           │     │
│  │  Publish: user.created    │     │
│  └───────┬───────────────────┘     │
│          │                          │
└──────────┼──────────────────────────┘
           │
           │ user.created event
           │ Trace Context: xyz789
           ▼
┌──────────────────────────────────────┐
│  NATS Message Queue                  │
│  - Topic: user.created               │
│  - Trace Context Propagated          │
└──────────┬───────────────────────────┘
           │
           │ Subscriber reads
           ▼
┌─────────────────────────────────────┐
│  Rust Order Service                 │
│  ┌─────────────────────────────┐   │
│  │ Tracing Instrumentation     │   │ ← #[instrument] macro
│  │ - Continue Span: xyz789     │   │
│  │ - New Span: process_event   │   │
│  └───────────┬─────────────────┘   │
│              ▼                      │
│  ┌───────────────────────────┐     │
│  │  MongoDB Insert           │     │
│  │  orders.insert_one()      │     │
│  │  (Span: mongodb.insert)   │     │
│  └───────────────────────────┘     │
│                                     │
└─────────────────────────────────────┘

Meanwhile, in parallel:

┌──────────────────────────┐      ┌──────────────────────────┐
│  Prometheus              │      │  Loki                    │
│                          │      │                          │
│  Scraping /metrics:      │      │  Collecting logs:        │
│  ┌────────────────────┐  │      │  ┌────────────────────┐ │
│  │ http_requests_total│  │      │  │ {"level":"info",   │ │
│  │   +1               │  │      │  │  "trace_id":"xyz", │ │
│  │ users_created +1   │  │      │  │  "msg":"Created"}  │ │
│  └────────────────────┘  │      │  └────────────────────┘ │
└──────────────────────────┘      └──────────────────────────┘

                    ▼
         ┌──────────────────────────┐
         │  Tempo                   │
         │                          │
         │  Storing trace:          │
         │  ┌────────────────────┐  │
         │  │ Trace ID: xyz789   │  │
         │  │ Spans:             │  │
         │  │  - POST /users     │  │
         │  │  - db.query        │  │
         │  │  - nats.publish    │  │
         │  │  - process_event   │  │
         │  │  - mongodb.insert  │  │
         │  └────────────────────┘  │
         └──────────────────────────┘

                    ▼
         ┌──────────────────────────┐
         │  Grafana                 │
         │                          │
         │  Unified View:           │
         │  - Metrics dashboard     │
         │  - Trace visualization   │
         │  - Log correlation       │
         │  - Service map           │
         └──────────────────────────┘
```

## Service-to-Service Communication

```
┌──────────────────────────────────────────────────────────┐
│                  API Request Flow                         │
└──────────────────────────────────────────────────────────┘

1. User Creation Flow
   ────────────────────
   
   Client → POST /api/users → Python Service
                                     │
                                     ├─► PostgreSQL (INSERT)
                                     │
                                     └─► NATS publish("user.created")

2. Order Creation Flow
   ───────────────────
   
   Client → POST /api/orders → Rust Service
                                      │
                                      ├─► MongoDB (insert)
                                      │
                                      └─► NATS publish("order.created")

3. Inventory Check Flow
   ────────────────────
   
   Client → POST /api/inventory → Go Service
                                        │
                                        ├─► PostgreSQL (INSERT)
                                        │
                                        └─► MongoDB (insert stock_levels)
   
   Client → GET /api/stock-levels → Go Service
                                          │
                                          └─► MongoDB (find)

4. Cross-Service Flow (Example)
   ────────────────────────────
   
   Client → POST /api/users → Python Service
                                     │
                                     ├─► PostgreSQL
                                     │
                                     └─► NATS("user.created")
                                              │
                                              └──► [Could trigger]
                                                   Rust Service → Create welcome order
                                                                    │
                                                                    └─► MongoDB
```

## Observability Data Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                      Telemetry Pipeline                              │
└──────────────────────────────────────────────────────────────────────┘

  Application Code
        │
        ├──────────────────┬──────────────────┬─────────────────
        │                  │                  │
        ▼                  ▼                  ▼
   ┌─────────┐       ┌──────────┐      ┌──────────┐
   │ Metrics │       │  Logs    │      │ Traces   │
   │ /metrics│       │ stdout   │      │ OTLP     │
   └────┬────┘       └────┬─────┘      └────┬─────┘
        │                 │                  │
        │                 │                  │
        ▼                 ▼                  ▼
   ┌─────────┐       ┌──────────┐      ┌──────────┐
   │Prometheus│       │Promtail  │      │  Tempo   │
   │         │       │(log      │      │          │
   │Scraper  │       │collector)│      │Receiver  │
   └────┬────┘       └────┬─────┘      └────┬─────┘
        │                 │                  │
        │                 ▼                  │
        │            ┌──────────┐            │
        │            │   Loki   │            │
        │            │          │            │
        │            └────┬─────┘            │
        │                 │                  │
        └─────────────────┴──────────────────┘
                          │
                          ▼
                    ┌──────────┐
                    │ Grafana  │
                    │          │
                    │ - Query  │
                    │ - Viz    │
                    │ - Alert  │
                    │ - Explore│
                    └──────────┘
                          │
                          ▼
                    ┌──────────┐
                    │   User   │
                    └──────────┘
```

## Technology Stack

```
┌─────────────────────────────────────────────────────────┐
│                   Technology Choices                     │
└─────────────────────────────────────────────────────────┘

Services:
  ├─ Python Service
  │   ├─ FastAPI (web framework)
  │   ├─ SQLAlchemy (ORM)
  │   ├─ psycopg2 (PostgreSQL driver)
  │   ├─ nats-py (NATS client)
  │   └─ opentelemetry-instrumentation (auto-instrument)
  │
  ├─ Rust Service
  │   ├─ Axum (web framework)
  │   ├─ MongoDB driver (async)
  │   ├─ async-nats (NATS client)
  │   ├─ tracing (instrumentation)
  │   └─ opentelemetry-otlp (trace export)
  │
  └─ Go Service
      ├─ Gin (web framework)
      ├─ lib/pq (PostgreSQL driver)
      ├─ mongo-driver (MongoDB driver)
      ├─ otelgin (OTel middleware)
      └─ otlptracegrpc (trace export)

Infrastructure:
  ├─ PostgreSQL 16 (relational database)
  ├─ MongoDB 7 (document database)
  └─ NATS 2.10 (message queue)

Observability:
  ├─ Prometheus (metrics storage)
  ├─ Loki (log aggregation)
  ├─ Tempo (trace storage)
  ├─ Grafana (visualization)
  └─ Promtail (log collector)

Deployment:
  ├─ Docker & Docker Compose (local)
  ├─ Kubernetes (production)
  └─ Helm (package management)
```

## Metrics Collection Pattern

┌────────────────────────────────────────────────────────┐
│          Prometheus Scraping Pattern                    │
└────────────────────────────────────────────────────────┘

Every 30 seconds:

Prometheus                          Service
    │                                  │
    │  GET /metrics                    │
    ├─────────────────────────────────►│
    │                                  │
    │                                  │ Expose metrics:
    │                                  │ - http_requests_total
    │                                  │ - request_duration
    │                                  │ - custom metrics
    │                                  │
    │  200 OK                          │
    │  # TYPE http_requests_total...   │
    │◄─────────────────────────────────┤
    │                                  │
    │ Store time series:               │
    │ http_requests_total{             │
    │   service="user-service",        │
    │   method="POST",                 │
    │   endpoint="/api/users",         │
    │   status="201"                   │
    │ } = 150                          │
    │                                  │
    ▼                                  ▼

Kubernetes ServiceMonitor (optional):
  - Automatic service discovery
  - Label-based selection
  - No manual configuration needed

## Trace Context Propagation

```
┌────────────────────────────────────────────────────────┐
│           OpenTelemetry Context Propagation            │
└────────────────────────────────────────────────────────┘

Service A                           Service B
    │                                  │
    │ Start Span: operation_a          │
    │ Trace ID: abc123                 │
    │ Span ID: span001                 │
    │                                  │
    │ HTTP Request                     │
    │ Headers:                         │
    │   traceparent:                   │
    │     00-abc123-span001-01         │
    ├─────────────────────────────────►│
    │                                  │
    │                                  │ Extract context
    │                                  │ Continue Trace: abc123
    │                                  │ New Span: operation_b
    │                                  │ Parent: span001
    │                                  │ Span ID: span002
    │                                  │
    │                                  │ Process request
    │                                  │
    │                                  │ Export spans to Tempo:
    │                                  │ - span002 (parent: span001)
    │                                  │
    │ HTTP Response                    │
    │◄─────────────────────────────────┤
    │                                  │
    │ End Span: operation_a            │
    │                                  │
    │ Export spans to Tempo:           │
    │ - span001 (root)                 │
    │                                  │
    ▼                                  ▼

Result in Tempo:
  Trace abc123
    └─ span001: operation_a (120ms)
       └─ span002: operation_b (80ms)
```

This architecture demonstrates:

- ✅ Microservices best practices
- ✅ Multiple databases and message queues
- ✅ Distributed tracing across services
- ✅ Centralized observability
- ✅ Production-ready patterns
