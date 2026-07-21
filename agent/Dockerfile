# ─────────────────────────────────────────────────────────────────────────────
# DB Migration — Collector Agent
#
# Lightweight Python agent that:
#   1. Registers with the Hub on startup
#   2. Polls for collection jobs matching its declared roles
#   3. Runs factory scripts (PowerShell) or native Python collectors
#   4. Reports results back to the Hub
#
# Configure via environment variables — see agent/main.py for the full list.
# ─────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

LABEL maintainer="DBMigrationAssist"
LABEL description="DB Migration Readiness — Collector Agent"
LABEL org.opencontainers.image.source="https://github.com/prjelesi/DBMigrationAssist"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# ── System packages ───────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    python3-pip \
    curl \
    ca-certificates \
    gnupg \
    unixodbc \
    unixodbc-dev \
    libpq-dev \
    libaio1 \
    && rm -rf /var/lib/apt/lists/*

# ── SQL Server ODBC driver (for sqlserver role) ───────────────────────────────
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor -o /usr/share/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
        https://packages.microsoft.com/ubuntu/22.04/prod jammy main" \
        > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 && \
    rm -rf /var/lib/apt/lists/*

# ── Python deps ───────────────────────────────────────────────────────────────
WORKDIR /app

COPY agent/requirements.txt /app/requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

# ── Application code ──────────────────────────────────────────────────────────
COPY agent/ /app/
# Factory scripts are mounted or baked in at build time
COPY factory-scripts/ /app/factory-scripts/

# ── Entrypoint ────────────────────────────────────────────────────────────────
# Default roles — override via AGENT_ROLES env var
ENV AGENT_ROLES="sqlserver,postgresql,mysql,mariadb,mongodb,cassandra" \
    HUB_URL="http://hub:8000" \
    HEARTBEAT_INTERVAL="30" \
    POLL_INTERVAL="10"

CMD ["python3", "main.py"]
