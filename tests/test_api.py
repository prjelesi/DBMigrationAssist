"""
Integration tests for DBMigrationAssist API.
Uses httpx.AsyncClient with the FastAPI test client — no real Docker needed.

Run:
    pytest tests/ -v
    pytest tests/ -v --cov=api --cov-report=term-missing
"""

import json
import os
import sys
from pathlib import Path

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport

# Make sure the project root is on the path
ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))

# Set a dev API key before importing the app
os.environ.setdefault("API_KEY", "dev-local-key-change-me")
os.environ.setdefault("DATAVERSE_URL", "")  # Dataverse disabled in tests

from api.main import app  # noqa: E402


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest_asyncio.fixture
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"X-API-Key": "dev-local-key-change-me"},
    ) as c:
        yield c


SAMPLE_DB = {
    "DatabaseName": "TestDB",
    "SourceType": "PostgreSQL",
    "SourceVersion": "14",
    "SourceEnvironment": "OnPrem",
    "TargetType": "Undecided",
    "MaxDowntime": "hours",
    "Connectivity": "vpn",
    "LandingZone": "yes",
    "DataSize": "small",
    "StoredProcs": "none",
    "Dependencies": "",
    "SpecialFeatures": "",
    "TeamSkill": "moderate",
    "RollbackPlan": "yes_untested",
    "DatabaseCount": 1,
}

SAMPLE_REQUEST = {
    "customerName": "TestCustomer",
    "requestedBy": "pytest",
    "databases": [SAMPLE_DB],
    "runInfoGather": False,
}


# ── Health ────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_health(client):
    r = await client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert "version" in body
    assert "timestamp" in body


# ── Auth ──────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_wrong_api_key_rejected():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"X-API-Key": "wrong-key"},
    ) as bad_client:
        r = await bad_client.get("/migration-paths")
        assert r.status_code == 403


@pytest.mark.asyncio
async def test_missing_api_key_rejected():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as anon_client:
        r = await anon_client.get("/migration-paths")
        assert r.status_code == 403


# ── Migration paths ───────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_get_migration_paths(client):
    r = await client.get("/migration-paths")
    assert r.status_code == 200
    body = r.json()
    assert "paths" in body
    assert len(body["paths"]) >= 50, "Expected 50+ migration paths from service description"


@pytest.mark.asyncio
async def test_migration_paths_all_categories_present(client):
    r = await client.get("/migration-paths")
    paths = r.json()["paths"]
    source_types = {p["sourceType"] for p in paths}
    expected = {"SQL Server", "PostgreSQL", "MySQL", "MariaDB", "MongoDB", "Cassandra", "Oracle", "SybaseASE"}
    assert expected == source_types, f"Missing source types: {expected - source_types}"


@pytest.mark.asyncio
async def test_oracle_paths_require_ghcp(client):
    r = await client.get("/migration-paths")
    oracle_paths = [p for p in r.json()["paths"] if p["sourceType"] == "Oracle"]
    assert len(oracle_paths) >= 7
    for p in oracle_paths:
        assert p.get("requiresGHCP") is True, f"Oracle path {p['id']} missing requiresGHCP flag"


@pytest.mark.asyncio
async def test_sybasease_paths_heterogeneous(client):
    r = await client.get("/migration-paths")
    sybase_paths = [p for p in r.json()["paths"] if p["sourceType"] == "SybaseASE"]
    assert len(sybase_paths) >= 4
    for p in sybase_paths:
        assert p["migrationType"] == "Heterogeneous"


# ── Questionnaire ─────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_get_questionnaire(client):
    r = await client.get("/questionnaire")
    assert r.status_code == 200
    body = r.json()
    assert "sections" in body
    total_questions = sum(len(s["questions"]) for s in body["sections"])
    assert total_questions >= 20, f"Expected 20+ questions, got {total_questions}"


@pytest.mark.asyncio
async def test_questionnaire_has_sybasease_option(client):
    r = await client.get("/questionnaire")
    sections = r.json()["sections"]
    # Find the source DB type question
    q1 = next(
        q for s in sections for q in s["questions"]
        if q["id"] == "q1"
    )
    option_values = [o["value"] for o in q1["options"]]
    assert "SybaseASE" in option_values


# ── Assessment submission ─────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_submit_assessment_returns_202(client):
    r = await client.post("/assess", json=SAMPLE_REQUEST)
    assert r.status_code == 202
    body = r.json()
    assert "jobId" in body
    assert body["status"] == "queued"
    assert "/status/" in body["statusUrl"]


@pytest.mark.asyncio
async def test_submit_assessment_invalid_data(client):
    bad = {"customerName": "x", "requestedBy": "x", "databases": [{"DatabaseName": "missing-fields"}]}
    r = await client.post("/assess", json=bad)
    assert r.status_code == 422


@pytest.mark.asyncio
async def test_status_not_found(client):
    r = await client.get("/status/nonexistent-job-id")
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_report_not_found(client):
    r = await client.get("/report/nonexistent-job-id")
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_full_assessment_flow(client, tmp_path, monkeypatch):
    """
    End-to-end test: submit → poll status → retrieve report.
    Mocks the PowerShell runner to avoid needing pwsh in CI.
    """
    import api.main as main_module

    # Mock run_assessment to complete immediately with fake data
    fake_report = [
        {
            "AssessmentId": "test-id",
            "Timestamp": "2026-07-21T00:00:00Z",
            "DatabaseName": "TestDB",
            "SourceType": "PostgreSQL",
            "SourceVersion": "14",
            "SourceEnv": "OnPrem",
            "TargetType": "Azure Database for PostgreSQL Flexible Server",
            "MigrationPathId": "postgresql-onprem-to-azure-postgresql-flex",
            "MigrationType": "Homogeneous",
            "MigrationTools": ["Azure Database Migration Service"],
            "OnlineMigration": True,
            "ReadinessScore": 82,
            "ReadinessBand": "Ready to Migrate",
            "Recommendation": "Proceed with migration planning.",
            "Blockers": [],
            "Findings": ["Clear homogeneous path (+20)", "ExpressRoute (+15)"],
            "EffortDaysPerDB": 1,
            "EffortTotalDays": 1,
            "EffortWeeks": 1,
            "Prerequisites": ["PowerShell 7.x", "psql"],
            "FactoryScript": "factory-scripts/PostgreSQL/.../Factory-PostgreSQL-Windows.ps1",
            "InfoGatherStatus": "Skipped",
        }
    ]

    async def fake_runner(job_id: str, request):
        main_module.jobs[job_id].update({
            "status": "completed",
            "completedAt": "2026-07-21T00:00:01Z",
            "reportData": fake_report,
            "dataverseRecordId": None,
        })

    monkeypatch.setattr(main_module, "run_assessment", fake_runner)

    # Submit
    r = await client.post("/assess", json=SAMPLE_REQUEST)
    assert r.status_code == 202
    job_id = r.json()["jobId"]

    # Poll status - job completes synchronously in test (monkeypatched)
    r = await client.get(f"/status/{job_id}")
    # Status may be queued still if background task hasn't run; either is valid here
    assert r.status_code == 200
    assert r.json()["jobId"] == job_id

    # Manually mark as completed to test report retrieval
    main_module.jobs[job_id]["status"] = "completed"
    main_module.jobs[job_id]["reportData"] = fake_report

    r = await client.get(f"/report/{job_id}")
    assert r.status_code == 200
    report = r.json()
    assert isinstance(report, list)
    assert report[0]["ReadinessScore"] == 82
    assert report[0]["ReadinessBand"] == "Ready to Migrate"


# ── Assessment scoring (via PowerShell) ───────────────────────────────────────

def test_powershell_assessment_smoke():
    """
    Runs Invoke-Assessment.ps1 directly against the sample CSV.
    Requires pwsh to be installed.
    Skipped in CI if pwsh is not available.
    """
    import shutil
    import subprocess
    import tempfile

    if not shutil.which("pwsh"):
        pytest.skip("pwsh not available")

    sample_csv = ROOT / "input" / "sample-db-inventory.csv"
    if not sample_csv.exists():
        pytest.skip("sample-db-inventory.csv not found")

    with tempfile.TemporaryDirectory() as tmp:
        result = subprocess.run(
            [
                "pwsh", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                "-File", str(ROOT / "Invoke-Assessment.ps1"),
                "-InputFile", str(sample_csv),
                "-OutputDir", tmp,
                "-SkipInfoGather",
            ],
            capture_output=True, text=True, timeout=120,
        )
        assert result.returncode == 0, f"Assessment script failed:\n{result.stderr}"

        reports = list(Path(tmp).glob("assessment-report-*.json"))
        assert len(reports) == 1, "Expected exactly one report file"

        report = json.loads(reports[0].read_text())
        assert isinstance(report, list), "Report should be a JSON array"
        assert len(report) == 5, "Sample CSV has 5 databases"

        for item in report:
            assert 0 <= item["ReadinessScore"] <= 100
            assert item["ReadinessBand"] in [
                "Ready to Migrate", "Conditionally Ready",
                "Needs Preparation", "Not Ready"
            ]
            assert item["MigrationPathId"] != "unknown", \
                f"{item['DatabaseName']} has unknown migration path"


def test_migration_paths_json_schema():
    """Validate migration-paths.json structure."""
    paths_file = ROOT / "assessment-engine" / "data" / "migration-paths.json"
    data = json.loads(paths_file.read_text())

    assert "paths" in data
    assert "outOfScope" in data
    assert "summary" in data

    required_fields = ["id", "sourceType", "sourceVersions", "sourceEnvironments",
                       "targetType", "migrationType", "migrationTools",
                       "onlineMigration", "offlineMigration"]
    for path in data["paths"]:
        for field in required_fields:
            assert field in path, f"Path '{path.get('id', '?')}' missing field '{field}'"
        assert path["migrationType"] in ("Homogeneous", "Heterogeneous")
        assert isinstance(path["onlineMigration"], bool)
        assert isinstance(path["offlineMigration"], bool)


def test_scoring_matrix_bands_cover_full_range():
    """Ensure readiness bands cover 0-100 with no gaps."""
    sm_file = ROOT / "assessment-engine" / "data" / "scoring-matrix.json"
    data = json.loads(sm_file.read_text())

    bands = sorted(data["readinessBands"], key=lambda b: b["min"])
    assert bands[0]["min"] == 0
    assert bands[-1]["max"] == 100

    for i in range(len(bands) - 1):
        assert bands[i]["max"] + 1 == bands[i + 1]["min"], \
            f"Gap between bands at {bands[i]['max']} → {bands[i+1]['min']}"
