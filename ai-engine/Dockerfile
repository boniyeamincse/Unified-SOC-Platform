FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Create non-root user
RUN groupadd -r aiengine && useradd -r -g aiengine aiengine

# Install system dependencies and security updates
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        && \
    apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create directories with proper permissions
RUN mkdir -p /models /logs && \
    chown -R aiengine:aiengine /app /models /logs

# Set security-focused permissions
RUN chmod 755 /app && \
    find /app -name "*.py" -exec chmod 644 {} \; && \
    chmod +x /app/model.py

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# Switch to non-root user
USER aiengine

# Expose port
EXPOSE 8000

# Run the application
CMD ["python", "model.py"]
