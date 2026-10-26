FROM python:3.13-slim

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy dependency files
COPY pyproject.toml uv.lock README.md ./

# Copy application code
COPY src/ ./src/

# Install dependencies and the project itself
RUN uv sync --frozen

# Expose Category Service port
EXPOSE 8002

# Start the application
CMD ["uv", "run", "--no-sync", "uvicorn", "category_service.main:app", "--host", "0.0.0.0", "--port", "8002"]
