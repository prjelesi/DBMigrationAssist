"""
DB Migration Readiness Assessment API
Receives assessment requests from Power Apps / Power Automate,
runs the PowerShell factory scripts, scores readiness,
and pushes results to Dataverse.
"""

import asyncio
import csv
import io
import json
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import httpx
from dotenv import load_dotenv
from fastapi import BackgroundTasks, Depends, FastAPI, File, HTTPException, Security, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security.api_key import APIKeyHeader
from msal import ConfidentialClientApplication
from pydantic import BaseModel, Field

from api.agent_registry import AgentRegistry, AgentRole, AgentStatus, CollectionJob, CollectionJobStatus

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

# ── Agent registry (singleton) ───────────────────────────────────────────────
registry = AgentRegistry()

# ── FastAPI app ───────────────────────────────────────────────────────────────
app = FastAPI(
    title="DB Migration Readiness Assessment API",
    description="Assessment engine for Azure database migration readiness. Integrates with Power Apps and Copilot Studio via Dataverse.",
    version="1.0.0",
)

# ── CORS ──────────────────────────────────────────────────────────────────────
_cors_origins = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── API key security ──────────────────────────────────────────────────────────
api_key_header    = APIKeyHeader(name="X-API-Key",    auto_error=True)
agent_token_header = APIKeyHeader(name="X-Agent-Token", auto_error=False)

def verify_api_key(key: str = Security(api_key_header)) -> str:
    if key != API_KEY:
        raise HTTPException(status_code=403, detail="Invalid API key")
    return key

def _verify_agent(agent_id: str, token: Optional[str]) -> None:
    if not registry.verify_token(agent_id, token or ""):
        raise HTTPException(status_code=403, detail="Invalid agent token")
    if not registry.get_agent(agent_id):
        raise HTTPException(status_code=404, detail="Agent not found — re-register")

# ── Request / Response models ─────────────────────────────────────────────────

class DatabaseEntry(BaseModel):
    DatabaseName: str
    SourceType: str = Field(..., description="SQL Server | Oracle | PostgreSQL | MySQL | MariaDB | MongoDB | Cassandra | SybaseASE")
    SourceVersion: str
    SourceEnvironment: str = Field(..., description="OnPrem | AzureVM | AzureVM_Windows | AzureVM_Linux | AzureArc | AzurePaaS_SingleServer | AzurePaaS_MariaDB | ODAA | OracleCloud | AWS_EC2 | AWS_RDS | AWS_Aurora | AWS_DocumentDB | GCP_CloudSQL | GCP_GCE")
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
    background_tasks: BackgroundTasks,
    _key: str = Depends(verify_api_key),
):
    """
    Submit a database assessment request.
    Returns immediately with a jobId; use GET /status/{jobId} to poll.
    Power Automate can also receive a callback via CALLBACK_WEBHOOK_URL.
    """
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
    background_tasks: BackgroundTasks,
    file: UploadFile = File(..., description="CSV file matching the sample-db-inventory.csv format"),
    customer_name: str = "BulkUpload",
    requested_by: str = "PowerApps",
    _key: str = Depends(verify_api_key),
):
    """
    Upload a CSV file (bulk DB inventory) directly from Power Apps.
    Power Apps file upload control sends the file here.
    """
    if not file.filename.endswith(".csv"):
        raise HTTPException(status_code=400, detail="Only CSV files are accepted")

    contents = await file.read()
    lines = contents.decode("utf-8-sig").strip().splitlines()
    if len(lines) < 2:
        raise HTTPException(status_code=400, detail="CSV must have a header row and at least one data row")

    # Parse CSV into DatabaseEntry list
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


# ══════════════════════════════════════════════════════════════════════════════
# AGENT REGISTRY ENDPOINTS
# Collector agents call these to register, heartbeat, and claim jobs.
# ══════════════════════════════════════════════════════════════════════════════

class AgentRegisterRequest(BaseModel):
    name: str = Field(..., description="Human-readable agent name, e.g. 'on-prem-collector-01'")
    roles: list[AgentRole] = Field(..., description="DB types this agent can collect from")
    hostname: Optional[str] = None
    version: str = "1.0.0"


class AgentRegisterResponse(BaseModel):
    agentId: str
    agentToken: str
    message: str


class CollectionJobCompleteRequest(BaseModel):
    success: bool
    collectedData: Optional[dict] = None
    error: Optional[str] = None
    executionTimeSeconds: Optional[float] = None


class CreateCollectionJobRequest(BaseModel):
    role: AgentRole
    databaseName: str
    host: str
    port: Optional[int] = None
    username: Optional[str] = None
    password: Optional[str] = None
    additionalParams: dict = {}
    assessmentJobId: Optional[str] = None


@app.post("/agents/register", response_model=AgentRegisterResponse, tags=["Agents"])
async def register_agent(request: AgentRegisterRequest):
    """
    Called by a collector agent on startup.
    No hub API key required — any Docker container can register.
    Returns agentId + agentToken that the agent must include in all subsequent calls.
    """
    agent_id, token = registry.register(
        name=request.name,
        roles=request.roles,
        hostname=request.hostname,
        version=request.version,
    )
    return AgentRegisterResponse(
        agentId=agent_id,
        agentToken=token,
        message=f"Registered '{request.name}' with roles: {[r.value for r in request.roles]}",
    )


@app.post("/agents/{agent_id}/heartbeat", tags=["Agents"])
async def agent_heartbeat(
    agent_id: str,
    x_agent_token: Optional[str] = Security(agent_token_header),
):
    """Agents call this every 30 s to stay 'online'. Missed for 90 s → marked offline."""
    _verify_agent(agent_id, x_agent_token)
    registry.heartbeat(agent_id)
    return {"status": "ok", "timestamp": datetime.now(timezone.utc).isoformat()}


@app.delete("/agents/{agent_id}", tags=["Agents"])
async def deregister_agent(
    agent_id: str,
    x_agent_token: Optional[str] = Security(agent_token_header),
):
    """Called by agent on graceful shutdown."""
    _verify_agent(agent_id, x_agent_token)
    registry.deregister(agent_id)
    return {"status": "deregistered"}


@app.get("/agents", tags=["Agents"])
async def list_agents(
    role: Optional[AgentRole] = None,
    _key: str = Depends(verify_api_key),
):
    """List all registered agents. Power Apps admin screen / Copilot Studio can call this."""
    agents = registry.list_agents()
    if role:
        agents = [a for a in agents if role in a.roles]
    return agents


@app.get("/agents/{agent_id}/jobs/pending", tags=["Agents"])
async def get_pending_jobs(
    agent_id: str,
    x_agent_token: Optional[str] = Security(agent_token_header),
):
    """
    Agent polls this endpoint every 10 s.
    Returns pending collection jobs that match the agent's roles.
    Automatically marks returned jobs as 'assigned' to this agent.
    Password is included in the response (over TLS only in production).
    """
    _verify_agent(agent_id, x_agent_token)
    pending = registry.get_pending_jobs_for_agent(agent_id)
    result = []
    for job in pending:
        registry.assign_job(job.jobId, agent_id)
        j = job.model_dump()
        j["password"] = registry.get_job_password(job.jobId)
        result.append(j)
    return result


@app.post("/agents/{agent_id}/jobs/{job_id}/complete", tags=["Agents"])
async def complete_collection_job(
    agent_id: str,
    job_id: str,
    request: CollectionJobCompleteRequest,
    x_agent_token: Optional[str] = Security(agent_token_header),
):
    """Agent posts results here when a collection job finishes (success or failure)."""
    _verify_agent(agent_id, x_agent_token)
    ok = registry.complete_job(
        job_id=job_id,
        success=request.success,
        result=request.collectedData,
        error=request.error,
    )
    if not ok:
        raise HTTPException(status_code=404, detail=f"Collection job {job_id} not found")
    return {"status": "ok"}


# ══════════════════════════════════════════════════════════════════════════════
# COLLECTION JOB ENDPOINTS (called by Power Apps / Power Automate)
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/collect", status_code=202, tags=["Collection"])
async def create_collection_job(
    request: CreateCollectionJobRequest,
    _key: str = Depends(verify_api_key),
):
    """
    Submit a live database collection job.
    The hub will assign it to an online agent with the matching role.
    Returns jobId to poll with GET /collect/{jobId}.
    """
    # Check at least one agent with this role is online
    candidates = registry.agents_for_role(request.role)
    job = registry.create_collection_job(
        role=request.role,
        database_name=request.databaseName,
        host=request.host,
        port=request.port,
        username=request.username,
        password=request.password,
        additional_params=request.additionalParams,
        assessment_job_id=request.assessmentJobId,
    )
    agent_warning = None if candidates else f"No online agents with role '{request.role.value}' — job queued, will run when an agent connects."
    return {
        "jobId": job.jobId,
        "status": "pending",
        "role": request.role,
        "availableAgents": len(candidates),
        "warning": agent_warning,
        "pollUrl": f"/collect/{job.jobId}",
    }


@app.get("/collect/{job_id}", tags=["Collection"])
async def get_collection_job(
    job_id: str,
    _key: str = Depends(verify_api_key),
):
    """Poll status of a collection job. Returns result once completed."""
    job = registry.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail=f"Collection job {job_id} not found")
    return job


@app.get("/collect", tags=["Collection"])
async def list_collection_jobs(
    status: Optional[CollectionJobStatus] = None,
    role: Optional[AgentRole] = None,
    _key: str = Depends(verify_api_key),
):
    """List collection jobs, optionally filtered by status or role."""
    return registry.list_jobs(status=status, role=role)
