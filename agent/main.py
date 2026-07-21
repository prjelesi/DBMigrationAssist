"""
DB Migration Readiness — Collector Agent

Registers with the Hub on startup, declares its supported roles,
polls for pending collection jobs, runs the appropriate factory
scripts against live databases, and reports results back.

Environment variables
─────────────────────
  HUB_URL             URL of the Hub (e.g. http://hub:8000)
  AGENT_NAME          Human-readable name (default: auto-generated)
  AGENT_ROLES         Comma-separated roles:
                        sqlserver, postgresql, mysql, mariadb,
                        oracle, mongodb, cassandra
  AGENT_VERSION       Version string reported to hub (default: 1.0.0)
  HEARTBEAT_INTERVAL  Seconds between heartbeats (default: 30)
  POLL_INTERVAL       Seconds between job polls (default: 10)
"""

import asyncio
import logging
import os
import platform
import sys
import uuid

import httpx

from collectors import get_collector

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("agent")

# ── Config ────────────────────────────────────────────────────────────────────
HUB_URL            = os.environ.get("HUB_URL", "http://localhost:8000").rstrip("/")
AGENT_NAME         = os.environ.get("AGENT_NAME", f"agent-{uuid.uuid4().hex[:8]}")
AGENT_VERSION      = os.environ.get("AGENT_VERSION", "1.0.0")
AGENT_ROLES        = [r.strip() for r in os.environ.get("AGENT_ROLES", "").split(",") if r.strip()]
HEARTBEAT_INTERVAL = int(os.environ.get("HEARTBEAT_INTERVAL", "30"))
POLL_INTERVAL      = int(os.environ.get("POLL_INTERVAL", "10"))

# ── Runtime state ─────────────────────────────────────────────────────────────
_agent_id:    str | None = None
_agent_token: str | None = None
_active_jobs: set[str] = set()


# ── Registration ──────────────────────────────────────────────────────────────

async def register(client: httpx.AsyncClient) -> None:
    global _agent_id, _agent_token

    hostname = platform.node()
    payload = {
        "name":     AGENT_NAME,
        "roles":    AGENT_ROLES,
        "hostname": hostname,
        "version":  AGENT_VERSION,
    }
    resp = await client.post(f"{HUB_URL}/agents/register", json=payload, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    _agent_id    = data["agentId"]
    _agent_token = data["agentToken"]
    log.info(f"Registered  id={_agent_id}  name={AGENT_NAME}  roles={AGENT_ROLES}")


# ── Heartbeat loop ────────────────────────────────────────────────────────────

async def heartbeat_loop(client: httpx.AsyncClient) -> None:
    while True:
        await asyncio.sleep(HEARTBEAT_INTERVAL)
        try:
            resp = await client.post(
                f"{HUB_URL}/agents/{_agent_id}/heartbeat",
                headers={"X-Agent-Token": _agent_token},
                timeout=10,
            )
            if resp.status_code == 404:
                log.warning("Hub says agent unknown — re-registering")
                await register(client)
            elif resp.status_code != 200:
                log.warning(f"Heartbeat HTTP {resp.status_code}")
        except Exception as exc:
            log.warning(f"Heartbeat failed: {exc}")


# ── Job execution ─────────────────────────────────────────────────────────────

async def execute_job(client: httpx.AsyncClient, job: dict) -> None:
    """Run a single collection job and report results to the hub."""
    job_id = job["jobId"]
    role   = job["role"]
    _active_jobs.add(job_id)

    log.info(f"Job start  id={job_id}  role={role}  db={job['databaseName']}@{job['host']}")

    import time
    t0 = time.monotonic()
    try:
        collector = get_collector(role)
        collected = await collector.collect(job)
        elapsed   = time.monotonic() - t0

        await client.post(
            f"{HUB_URL}/agents/{_agent_id}/jobs/{job_id}/complete",
            headers={"X-Agent-Token": _agent_token},
            json={
                "success":              True,
                "collectedData":        collected,
                "executionTimeSeconds": round(elapsed, 2),
            },
            timeout=60,
        )
        log.info(f"Job done   id={job_id}  elapsed={elapsed:.1f}s")

    except Exception as exc:
        elapsed = time.monotonic() - t0
        log.error(f"Job failed id={job_id}  error={exc}")
        try:
            await client.post(
                f"{HUB_URL}/agents/{_agent_id}/jobs/{job_id}/complete",
                headers={"X-Agent-Token": _agent_token},
                json={
                    "success":              False,
                    "error":                str(exc),
                    "executionTimeSeconds": round(elapsed, 2),
                },
                timeout=30,
            )
        except Exception as report_exc:
            log.error(f"Could not report failure: {report_exc}")
    finally:
        _active_jobs.discard(job_id)


# ── Poll loop ─────────────────────────────────────────────────────────────────

async def poll_loop(client: httpx.AsyncClient) -> None:
    while True:
        await asyncio.sleep(POLL_INTERVAL)
        try:
            resp = await client.get(
                f"{HUB_URL}/agents/{_agent_id}/jobs/pending",
                headers={"X-Agent-Token": _agent_token},
                timeout=15,
            )
            if resp.status_code == 200:
                pending = resp.json()
                for job in pending:
                    if job["jobId"] not in _active_jobs:
                        asyncio.create_task(execute_job(client, job))
            elif resp.status_code == 403:
                log.error("Agent token rejected — re-registering")
                await register(client)
        except Exception as exc:
            log.warning(f"Poll failed: {exc}")


# ── Entry point ───────────────────────────────────────────────────────────────

async def main() -> None:
    if not AGENT_ROLES:
        log.error("AGENT_ROLES is required. Example: AGENT_ROLES=sqlserver,postgresql,mysql")
        sys.exit(1)

    log.info(f"Agent starting  name={AGENT_NAME}  hub={HUB_URL}  roles={AGENT_ROLES}")

    async with httpx.AsyncClient() as client:
        # Register with retry back-off
        for attempt in range(1, 7):
            try:
                await register(client)
                break
            except Exception as exc:
                wait = 5 * attempt
                log.warning(f"Registration attempt {attempt}/6 failed ({exc}) — retrying in {wait}s")
                await asyncio.sleep(wait)
        else:
            log.error("Could not register with hub after 6 attempts. Exiting.")
            sys.exit(1)

        log.info(f"Agent online  poll_interval={POLL_INTERVAL}s  heartbeat_interval={HEARTBEAT_INTERVAL}s")
        await asyncio.gather(
            heartbeat_loop(client),
            poll_loop(client),
        )


if __name__ == "__main__":
    asyncio.run(main())
