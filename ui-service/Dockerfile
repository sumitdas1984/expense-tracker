FROM python:3.13-slim

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy dependency files
COPY pyproject.toml uv.lock README.md ./

# Copy application code
COPY src/ src/

# Install dependencies and the project itself
RUN uv sync --frozen

# Start Streamlit
EXPOSE 8501

CMD ["uv", "run", "--no-sync", "streamlit", "run", "src/ui_service/main.py", "--server.address=0.0.0.0", "--server.port=8501"]
