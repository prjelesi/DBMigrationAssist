# ─────────────────────────────────────────────────────────────────────────────
# Base image: Ubuntu with PowerShell 7 pre-installed
# ─────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

LABEL maintainer="DBMigrationReady"
LABEL description="Database Migration Readiness Assessment Engine"

# ─── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # PostgreSQL client
    postgresql-client \
    # MySQL client
    mysql-client \
    # Python 3.11 + pip
    python3.11 \
    python3.11-venv \
    python3-pip \
    # Utilities
    curl \
    unzip \
    jq \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# ─── MongoDB Shell (mongosh) ──────────────────────────────────────────────────
RUN curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
    gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor && \
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
    https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
    > /etc/apt/sources.list.d/mongodb-org-7.0.list && \
    apt-get update && apt-get install -y --no-install-recommends mongodb-mongosh \
    && rm -rf /var/lib/apt/lists/*

# ─── Azure CLI ────────────────────────────────────────────────────────────────
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# ─── Python API dependencies ──────────────────────────────────────────────────
WORKDIR /app/api
COPY api/requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# ─── Copy project files ───────────────────────────────────────────────────────
WORKDIR /app
COPY assessment-engine/  ./assessment-engine/
COPY factory-scripts/    ./factory-scripts/
COPY Invoke-Assessment.ps1 .
COPY api/                ./api/

# ─── PowerShell execution policy ─────────────────────────────────────────────
RUN pwsh -Command "Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force"

# ─── Output / tmp directories ─────────────────────────────────────────────────
RUN mkdir -p /app/output /app/input /tmp/factory-output

# ─── Expose API port ──────────────────────────────────────────────────────────
EXPOSE 8000

# ─── Start FastAPI server ─────────────────────────────────────────────────────
CMD ["python3", "-m", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
