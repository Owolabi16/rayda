# Multi-stage Dockerfile for FastAPI service
# Stage 1: Build stage
FROM python:3.11-slim-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for build
RUN useradd -m -u 1001 appuser

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --user -r requirements.txt

# Copy application code
COPY --chown=appuser:appuser . .

# Stage 2: Production stage using distroless
FROM gcr.io/distroless/python3-debian12

# Copy Python packages from builder
COPY --from=builder /home/appuser/.local /home/appuser/.local

# Copy application from builder
COPY --from=builder --chown=nonroot:nonroot /app /app

# Set Python path
ENV PYTHONPATH=/home/appuser/.local/lib/python3.11/site-packages
ENV PATH=/home/appuser/.local/bin:$PATH

# Set working directory
WORKDIR /app

# Use non-root user (distroless default)
USER nonroot

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import requests; requests.get('http://localhost:8000/health').raise_for_status()"]

# Run the application
ENTRYPOINT ["python", "-m", "uvicorn"]
CMD ["main:app", "--host", "0.0.0.0", "--port", "8000"]
