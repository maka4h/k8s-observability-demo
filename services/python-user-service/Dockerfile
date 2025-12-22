FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .
COPY log_config.json .

# Expose port
EXPOSE 8000

# Run application with JSON logging and no access logs
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--log-config", "log_config.json"]
