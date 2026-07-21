#!/bin/bash
set -e

echo "=================================================="
echo " DB Migration Readiness Assessment Engine"
echo " Starting up..."
echo "=================================================="

# ── Validate required environment variables ────────────────────────────────────
if [ -z "${API_KEY}" ]; then
    echo "[WARN] API_KEY not set — using insecure default. Set API_KEY in production!"
    export API_KEY="dev-key-not-secure"
fi

# ── Print client versions ──────────────────────────────────────────────────────
echo ""
echo "[INFO] Installed database clients:"
echo "  psql    : $(psql --version 2>/dev/null || echo 'not found')"
echo "  mysql   : $(mysql --version 2>/dev/null | head -1 || echo 'not found')"
echo "  sqlcmd  : $(sqlcmd -? 2>/dev/null | head -1 || echo 'not found')"
echo "  mongosh : $(mongosh --version 2>/dev/null || echo 'not found')"
echo "  cqlsh   : $(cqlsh --version 2>/dev/null || echo 'not found')"
echo "  pwsh    : $(pwsh --version 2>/dev/null || echo 'not found')"
echo "  az      : $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo 'not found')"
echo "  aws     : $(aws --version 2>/dev/null || echo 'not found')"
echo ""

# ── Validate data files ────────────────────────────────────────────────────────
PATHS_FILE="/app/assessment-engine/data/migration-paths.json"
if [ -f "$PATHS_FILE" ]; then
    COUNT=$(python3 -c "import json; d=json.load(open('$PATHS_FILE')); print(len(d['paths']))")
    echo "[INFO] Migration paths loaded: $COUNT"
else
    echo "[ERROR] migration-paths.json not found at $PATHS_FILE"
    exit 1
fi

# ── Dataverse connection (optional) ───────────────────────────────────────────
if [ -n "${DATAVERSE_URL}" ]; then
    echo "[INFO] Dataverse: ${DATAVERSE_URL}"
else
    echo "[INFO] Dataverse: not configured (results stored locally only)"
fi

echo ""
echo "[INFO] Output directory : /app/output"
echo "[INFO] Input directory  : /app/input"
echo "[INFO] API port         : 8000"
echo "[INFO] API key set      : $([ -n "$API_KEY" ] && echo 'yes' || echo 'no')"
echo ""
echo "=================================================="
echo " Starting FastAPI server..."
echo "=================================================="

exec python3 -m uvicorn api.main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --workers 2 \
    --log-level info \
    --access-log
