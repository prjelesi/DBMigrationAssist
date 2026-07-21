# ─────────────────────────────────────────────────────────────────────────────
# DB Migration Readiness Assessment Engine
# Supports: SQL Server, PostgreSQL, MySQL, MariaDB, MongoDB, Cassandra, Oracle
#
# Deployment modes:
#   Local:  docker compose up --build
#   Azure:  push to ACR → deploy to Azure Container Apps
# ─────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

LABEL maintainer="DBMigrationAssist"
LABEL description="Database Migration Readiness Assessment Engine — all DB clients included"
LABEL org.opencontainers.image.source="https://github.com/prjelesi/DBMigrationAssist"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# ─── System packages + PostgreSQL client ──────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Utilities
    curl \
    wget \
    unzip \
    jq \
    ca-certificates \
    gnupg \
    lsb-release \
    # PostgreSQL 14 client (psql)
    postgresql-client \
    # Python 3.11
    python3.11 \
    python3.11-venv \
    python3-pip \
    # Oracle thin-mode requirements
    libaio1 \
    # For factory scripts
    bash \
    && rm -rf /var/lib/apt/lists/*

# ─── MySQL / MariaDB client ───────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    mysql-client \
    && rm -rf /var/lib/apt/lists/*

# ─── SQL Server client (sqlcmd) ───────────────────────────────────────────────
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor -o /usr/share/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
        https://packages.microsoft.com/ubuntu/22.04/prod jammy main" \
        > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y --no-install-recommends mssql-tools18 unixodbc-dev && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="$PATH:/opt/mssql-tools18/bin"

# ─── MongoDB Shell (mongosh) ──────────────────────────────────────────────────
RUN curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
        gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor && \
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
        https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
        > /etc/apt/sources.list.d/mongodb-org-7.0.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends mongodb-mongosh && \
    rm -rf /var/lib/apt/lists/*

# ─── Azure CLI ────────────────────────────────────────────────────────────────
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    rm -rf /var/lib/apt/lists/*

# ─── AWS CLI (for AWS RDS info gathering) ────────────────────────────────────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# ─── Python packages ─────────────────────────────────────────────────────────
WORKDIR /app
COPY api/requirements.txt ./api/requirements.txt

RUN pip3 install --no-cache-dir \
    # API + assessment engine
    -r api/requirements.txt \
    # Cassandra CQL shell (cqlsh)
    cqlsh \
    # Oracle thin driver — no Oracle Client install needed
    oracledb

# ─── PowerShell execution policy ─────────────────────────────────────────────
RUN pwsh -Command "Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force"

# ─── Non-root user ────────────────────────────────────────────────────────────
RUN groupadd -r appgroup && useradd -r -g appgroup -d /app -s /bin/bash appuser

# ─── Copy application files ───────────────────────────────────────────────────
COPY --chown=appuser:appgroup assessment-engine/  ./assessment-engine/
COPY --chown=appuser:appgroup factory-scripts/    ./factory-scripts/
COPY --chown=appuser:appgroup api/               ./api/
COPY --chown=appuser:appgroup Invoke-Assessment.ps1 .

# ─── Directories ─────────────────────────────────────────────────────────────
RUN mkdir -p /app/output /app/input && \
    chown -R appuser:appgroup /app

# ─── Entrypoint ──────────────────────────────────────────────────────────────
COPY --chown=appuser:appgroup docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER appuser
WORKDIR /app

# ─── Health check ─────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
