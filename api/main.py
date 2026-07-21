"""
DB Migration Readiness Assessment API
Receives assessment requests from Power Apps / Power Automate,
runs the PowerShell factory scripts, scores readiness,
and pushes results to Dataverse.
"""

import asyncio
import json
import os
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, HTTPException, Security, UploadFile
from fastapi.security.api_key import APIKeyHeader
from msal import ConfidentialClientApplication
from pydantic import BaseModel, Field

load_dotenv()

# ── Config ────────────────────────────────────────────────────────────────────
APP_DIR        = Path(__file__).parent.parent
OUTPUT_DIR     = APP_DIR / "output"
INPUT_DIR      = APP_DIR / "input"
ASSESS_SCRIPT  = APP_DIR / "Invoke-Assessment.ps1"

DATAVERSE_URL      = os.getenv("DATAVERSE_URL", "")
AZURE_CLIENT_ID    = os.getenv("AZURE_CLIENT_ID", "")
AZURE_CLIENT_SECRET= os.getenv("AZURE_CLIENT_SECRET", "")
AZURE_TENANT_ID    = os.getenv("AZURE_TENANT_ID", "")
API_KEY            = os.getenv("API_KEY", "dev-key-change-me")
CALLBACK_URL       = os.getenv("CALLBACK_WEBHOOK_URL", "")

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
INPUT_DIR.mkdir(parents=True, exist_ok=True)

# ── In-memory job store (replace with Redis/DB for production) ─────────────────
jobs: dict[str, dict] = {}

# ── FastAPI app ───────────────────────────────────────────────────────────────
app = FastAPI(
    title="DB Migration Readiness Assessment API",
    description="Assessment engine for Azure database migration readiness. Integrates with Power Apps and Copilot Studio via Dataverse.",
    version="1.0.0",
)

# ── API key security ──────────────────────────────────────────────────────────
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=True)

def verify_api_key(key: str = Security(api_key_header)) -> str:
    if key != API_KEY:
        raise HTTPException(status_code=403, detail="Invalid API key")
    return key

# ── Request / Response models ─────────────────────────────────────────────────

class DatabaseEntry(BaseModel):
    DatabaseName: str
    SourceType: str = Field(..., description="SQL Server | Oracle | PostgreSQL | MySQL | MariaDB | MongoDB | Cassandra")
    SourceVersion: str
    SourceEnvironment: str = Field(..., description="OnPrem | AzureVM | AWS_RDS | GCP_CloudSQL | AzurePaaS")
    TargetType: str = Field(default="Undecided")
    MaxDowntime: str = Field(..., description="zero | hours | days")
    Connectivity: str = Field(..., description="expressroute | vpn | internet | none")
    LandingZone: str = Field(..., description="yes | partial | no")
    DataSize: str = Field(..., description="small | medium | large")
    StoredProcs: str = Field(default="none", description="none | few | many | extensive")
    Dependencies: str = Field(default="", description="Pipe-separated: linked_servers|ssis|replication|cdc")
    SpecialFeatures: str = Field(default="", description="Pipe-separated: plsql|oracle_specific|sql_agent|clr")
    TeamSkill: str = Field(..., description="expert | moderate | beginner")
    RollbackPlan: str = Field(..., description="yes_tested | yes_untested | partial | no")
    DatabaseCount: int = Field(default=1)

class AssessmentRequest(BaseModel):
    customerName: str
    requestedBy: str
    databases: list[DatabaseEntry]
    runInfoGather: bool = Field(default=False, description="Set true to also run factory info-gather scripts")

class AssessmentResponse(BaseModel):
    jobId: str
    status: str
    message: str
    statusUrl: str

class JobStatus(BaseModel):
    jobId: str
    status: str
    createdAt: str
    completedAt: Optional[str] = None
    customerName: Optional[str] = None
    dbCount: Optional[int] = None
    reportUrl: Optional[str] = None
    dataverseRecordId: Optional[str] = None
    error: Optional[str] = None


# ── Dataverse helpers ─────────────────────────────────────────────────────────

def _get_dataverse_token() -> Optional[str]:
    """Acquire an Entra ID token for Dataverse using client credentials."""
    if not all([DATAVERSE_URL, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID]):
        return None
    authority = f"https://login.microsoftonline.com/{AZURE_TENANT_ID}"
    scope = [f"{DATAVERSE_URL}/.default"]
    app_msal = ConfidentialClientApplication(
        AZURE_CLIENT_ID,
        authority=authority,
        client_credential=AZURE_CLIENT_SECRET,
    )
    result = app_msal.acquire_token_for_client(scopes=scope)
    return result.get("access_token")


async def push_to_dataverse(job_id: str, report: dict, customer_name: str) -> Optional[str]:
    """
    Push assessment run summary to Dataverse table 'cr_assessmentruns'.
    Returns the Dataverse record ID or None if Dataverse is not configured.
    """
    token = _get_dataverse_token()
    if not token:
        return None

    payload = {
        "cr_jobid": job_id,
        "cr_customername": customer_name,
        "cr_assessmentdate": datetime.now(timezone.utc).isoformat(),
        "cr_totaldbcount": len(report) if isinstance(report, list) else 1,
        "cr_reportjson": json.dumps(report),
        "cr_status": "Completed",
    }
    url = f"{DATAVERSE_URL}/api/data/v9.2/cr_assessmentruns"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0",
        "Prefer": "return=representation",
    }
    async with httpx.AsyncClient() as client:
        resp = await client.post(url, json=payload, headers=headers, timeout=30)
    if resp.status_code in (200, 201, 204):
        data = resp.json() if resp.content else {}
        return data.get("cr_assessmentrunid")
    return None


async def push_db_items_to_dataverse(job_id: str, items: list[dict]) -> None:
    """Push individual DB assessment items to Dataverse table 'cr_assessmentitems'."""
    token = _get_dataverse_token()
    if not token:
        return

    url = f"{DATAVERSE_URL}/api/data/v9.2/cr_assessmentitems"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0",
    }
    async with httpx.AsyncClient() as client:
        for item in items:
            payload = {
                "cr_jobid": job_id,
                "cr_databasename": item.get("DatabaseName"),
                "cr_sourcetype": item.get("SourceType"),
                "cr_targettype": item.get("TargetType"),
                "cr_migrationtype": item.get("MigrationType"),
                "cr_readinessscore": item.get("ReadinessScore"),
                "cr_readinessband": item.get("ReadinessBand"),
                "cr_recommendation": item.get("Recommendation"),
                "cr_blockers": json.dumps(item.get("Blockers", [])),
                "cr_findings": json.dumps(item.get("Findings", [])),
                "cr_efforttotaldays": item.get("EffortTotalDays"),
                "cr_effortweeks": item.get("EffortWeeks"),
                "cr_migrationtools": json.dumps(item.get("MigrationTools", [])),
                "cr_factoryscript": item.get("FactoryScript"),
            }
            await client.post(url, json=payload, headers=headers, timeout=30)


async def fire_callback(job_id: str, report_path: str) -> None:
    """Notify Power Automate webhook that assessment is complete."""
    if not CALLBACK_URL:
        return
    payload = {
        "jobId": job_id,
        "status": "Completed",
        "reportPath": report_path,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    async with httpx.AsyncClient() as client:
        try:
            await client.post(CALLBACK_URL, json=payload, timeout=15)
        except Exception:
            pass  # Webhook failure is non-fatal


# ── Assessment runner ──────────────────────────────────────────────────────────

async def run_assessment(job_id: str, request: AssessmentRequest) -> None:
    """Background task: write input CSV → run PowerShell → parse output → push to Dataverse."""
    jobs[job_id]["status"] = "running"

    try:
        # 1. Write input CSV for PowerShell script
        csv_path = INPUT_DIR / f"assess-{job_id}.csv"
        headers = [
            "DatabaseName", "SourceType", "SourceVersion", "SourceEnvironment",
            "TargetType", "MaxDowntime", "Connectivity", "LandingZone", "DataSize",
            "StoredProcs", "Dependencies", "SpecialFeatures", "TeamSkill",
            "RollbackPlan", "DatabaseCount",
        ]
        rows = [",".join(headers)]
        for db in request.databases:
            row = [
                db.DatabaseName, db.SourceType, db.SourceVersion, db.SourceEnvironment,
                db.TargetType, db.MaxDowntime, db.Connectivity, db.LandingZone,
                db.DataSize, db.StoredProcs, db.Dependencies, db.SpecialFeatures,
                db.TeamSkill, db.RollbackPlan, str(db.DatabaseCount),
            ]
            rows.append(",".join(f'"{v}"' for v in row))
        csv_path.write_text("\n".join(rows), encoding="utf-8")

        # 2. Run PowerShell assessment script
        report_dir = OUTPUT_DIR / job_id
        report_dir.mkdir(parents=True, exist_ok=True)
        skip_flag = "" if request.runInfoGather else "-SkipInfoGather"
        cmd = [
            "pwsh", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-File", str(ASSESS_SCRIPT),
            "-InputFile", str(csv_path),
            "-OutputDir", str(report_dir),
        ]
        if skip_flag:
            cmd.append(skip_flag)

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=600)

        if proc.returncode != 0:
            raise RuntimeError(f"Assessment script failed:\n{stderr.decode()}")

        # 3. Find and parse the JSON report
        report_files = sorted(report_dir.glob("assessment-report-*.json"))
        if not report_files:
            raise RuntimeError("Assessment script produced no JSON report")
        report_path = report_files[-1]
        report_data = json.loads(report_path.read_text(encoding="utf-8"))

        # 4. Push to Dataverse
        run_record_id = await push_to_dataverse(job_id, report_data, request.customerName)
        await push_db_items_to_dataverse(job_id, report_data if isinstance(report_data, list) else [report_data])

        # 5. Fire callback webhook (Power Automate)
        await fire_callback(job_id, str(report_path))

        # 6. Update job state
        jobs[job_id].update({
            "status": "completed",
            "completedAt": datetime.now(timezone.utc).isoformat(),
            "reportPath": str(report_path),
            "dataverseRecordId": run_record_id,
            "reportData": report_data,
        })

    except Exception as exc:
        jobs[job_id].update({
            "status": "failed",
            "completedAt": datetime.now(timezone.utc).isoformat(),
            "error": str(exc),
        })
    finally:
        # Clean up temp input file
        try:
            csv_path.unlink(missing_ok=True)
        except Exception:
            pass


# ── API endpoints ──────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "version": "1.0.0", "timestamp": datetime.now(timezone.utc).isoformat()}


@app.post("/assess", response_model=AssessmentResponse, status_code=202)
async def start_assessment(
    request: AssessmentRequest,
    background_tasks,
    _key: str = Depends(verify_api_key),
):
    """
    Submit a database assessment request.
    Returns immediately with a jobId; use GET /status/{jobId} to poll.
    Power Automate can also receive a callback via CALLBACK_WEBHOOK_URL.
    """
    from fastapi import BackgroundTasks
    job_id = str(uuid.uuid4())
    jobs[job_id] = {
        "jobId": job_id,
        "status": "queued",
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "customerName": request.customerName,
        "dbCount": len(request.databases),
    }
    # Use BackgroundTasks to run async without blocking
    background_tasks.add_task(run_assessment, job_id, request)
    return AssessmentResponse(
        jobId=job_id,
        status="queued",
        message=f"Assessment queued for {len(request.databases)} database(s). Poll /status/{job_id} for updates.",
        statusUrl=f"/status/{job_id}",
    )


@app.get("/status/{job_id}", response_model=JobStatus)
async def get_status(job_id: str, _key: str = Depends(verify_api_key)):
    """Poll assessment job status. Power Automate 'Do Until' loop uses this."""
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    j = jobs[job_id]
    return JobStatus(
        jobId=j["jobId"],
        status=j["status"],
        createdAt=j["createdAt"],
        completedAt=j.get("completedAt"),
        customerName=j.get("customerName"),
        dbCount=j.get("dbCount"),
        reportUrl=f"/report/{job_id}" if j["status"] == "completed" else None,
        dataverseRecordId=j.get("dataverseRecordId"),
        error=j.get("error"),
    )


@app.get("/report/{job_id}")
async def get_report(job_id: str, _key: str = Depends(verify_api_key)):
    """Return the full JSON assessment report. Copilot Studio topics call this."""
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    j = jobs[job_id]
    if j["status"] != "completed":
        raise HTTPException(status_code=409, detail=f"Job status is '{j['status']}', not completed")
    return j.get("reportData", {})


@app.post("/assess/bulk", response_model=AssessmentResponse, status_code=202)
async def start_bulk_assessment(
    file: UploadFile = File(..., description="CSV file matching the sample-db-inventory.csv format"),
    customer_name: str = "BulkUpload",
    requested_by: str = "PowerApps",
    background_tasks = None,
    _key: str = Depends(verify_api_key),
):
    """
    Upload a CSV file (bulk DB inventory) directly from Power Apps.
    Power Apps file upload control sends the file here.
    """
    from fastapi import BackgroundTasks
    if not file.filename.endswith(".csv"):
        raise HTTPException(status_code=400, detail="Only CSV files are accepted")

    contents = await file.read()
    lines = contents.decode("utf-8-sig").strip().splitlines()
    if len(lines) < 2:
        raise HTTPException(status_code=400, detail="CSV must have a header row and at least one data row")

    # Parse CSV into DatabaseEntry list
    import csv, io
    reader = csv.DictReader(io.StringIO("\n".join(lines)))
    databases = []
    for row in reader:
        try:
            databases.append(DatabaseEntry(**{k: v for k, v in row.items() if v is not None}))
        except Exception as e:
            raise HTTPException(status_code=422, detail=f"CSV row error: {e}")

    req = AssessmentRequest(
        customerName=customer_name,
        requestedBy=requested_by,
        databases=databases,
        runInfoGather=False,
    )

    job_id = str(uuid.uuid4())
    jobs[job_id] = {
        "jobId": job_id,
        "status": "queued",
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "customerName": customer_name,
        "dbCount": len(databases),
    }
    background_tasks.add_task(run_assessment, job_id, req)
    return AssessmentResponse(
        jobId=job_id,
        status="queued",
        message=f"Bulk assessment queued for {len(databases)} database(s). Poll /status/{job_id} for updates.",
        statusUrl=f"/status/{job_id}",
    )


@app.get("/migration-paths")
async def get_migration_paths(_key: str = Depends(verify_api_key)):
    """Return all supported migration paths. Power Apps dropdown population."""
    paths_file = APP_DIR / "assessment-engine" / "data" / "migration-paths.json"
    if not paths_file.exists():
        raise HTTPException(status_code=404, detail="migration-paths.json not found")
    return json.loads(paths_file.read_text(encoding="utf-8"))


@app.get("/questionnaire")
async def get_questionnaire(_key: str = Depends(verify_api_key)):
    """Return the assessment questionnaire. Power Apps form generation."""
    q_file = APP_DIR / "assessment-engine" / "data" / "questionnaire.json"
    if not q_file.exists():
        raise HTTPException(status_code=404, detail="questionnaire.json not found")
    return json.loads(q_file.read_text(encoding="utf-8"))
