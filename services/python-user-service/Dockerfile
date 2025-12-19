FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Expose port
EXPOSE 8000

# Run with OpenTelemetry auto-instrumentation
CMD ["opentelemetry-instrument", \
     "--traces_exporter", "otlp", \
     "--metrics_exporter", "none", \
     "--logs_exporter", "none", \
     "--service_name", "user-service", \
     "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
