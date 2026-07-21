"""
Agent Registry — tracks registered collector agents, their roles, and collection jobs.

Agents register on startup, heartbeat periodically, poll for pending jobs,
execute factory scripts against live databases, and report results back.
"""

import secrets
import uuid
from datetime import datetime, timezone, timedelta
from enum import Enum
from typing import Optional

from pydantic import BaseModel


HEARTBEAT_TIMEOUT_SECONDS = 90


class AgentRole(str, Enum):
    sqlserver  = "sqlserver"
    oracle     = "oracle"
    postgresql = "postgresql"
    mysql      = "mysql"
    mariadb    = "mariadb"
    mongodb    = "mongodb"
    cassandra  = "cassandra"


class AgentStatus(str, Enum):
    online  = "online"
    offline = "offline"
    busy    = "busy"


class CollectionJobStatus(str, Enum):
    pending   = "pending"
    assigned  = "assigned"
    running   = "running"
    completed = "completed"
    failed    = "failed"


# ── Pydantic models ───────────────────────────────────────────────────────────

class AgentRecord(BaseModel):
    agentId: str
    name: str
    roles: list[AgentRole]
    status: AgentStatus = AgentStatus.online
    hostname: Optional[str] = None
    version: str = "1.0.0"
    registeredAt: str
    lastHeartbeat: str
    activeJobCount: int = 0


class CollectionJob(BaseModel):
    jobId: str
    assessmentJobId: Optional[str] = None   # links back to an /assess job
    role: AgentRole
    databaseName: str
    host: str
    port: Optional[int] = None
    username: Optional[str] = None          # password stored separately
    additionalParams: dict = {}
    status: CollectionJobStatus = CollectionJobStatus.pending
    assignedAgentId: Optional[str] = None
    createdAt: str
    startedAt: Optional[str] = None
    completedAt: Optional[str] = None
    result: Optional[dict] = None
    error: Optional[str] = None


# ── Registry ──────────────────────────────────────────────────────────────────

class AgentRegistry:
    """In-memory agent registry. Replace _agents/_jobs with Redis/DB for HA deployments."""

    def __init__(self) -> None:
        self._agents: dict[str, AgentRecord] = {}
        self._tokens: dict[str, str] = {}        # agentId → bearer token
        self._jobs: dict[str, CollectionJob] = {}
        self._job_passwords: dict[str, str] = {}  # jobId → password (never in model)

    # ── Agent lifecycle ───────────────────────────────────────────────────────

    def register(
        self,
        name: str,
        roles: list[AgentRole],
        hostname: Optional[str],
        version: str,
    ) -> tuple[str, str]:
        """Register a new agent. Returns (agentId, agentToken)."""
        agent_id = str(uuid.uuid4())
        token = secrets.token_urlsafe(32)
        now = datetime.now(timezone.utc).isoformat()
        self._agents[agent_id] = AgentRecord(
            agentId=agent_id,
            name=name,
            roles=roles,
            hostname=hostname,
            version=version,
            registeredAt=now,
            lastHeartbeat=now,
        )
        self._tokens[agent_id] = token
        return agent_id, token

    def verify_token(self, agent_id: str, token: str) -> bool:
        return bool(token) and self._tokens.get(agent_id) == token

    def heartbeat(self, agent_id: str) -> bool:
        if agent_id not in self._agents:
            return False
        self._agents[agent_id].lastHeartbeat = datetime.now(timezone.utc).isoformat()
        self._agents[agent_id].status = AgentStatus.online
        return True

    def deregister(self, agent_id: str) -> bool:
        if agent_id not in self._agents:
            return False
        self._agents.pop(agent_id)
        self._tokens.pop(agent_id, None)
        return True

    def _refresh_statuses(self) -> None:
        cutoff = datetime.now(timezone.utc) - timedelta(seconds=HEARTBEAT_TIMEOUT_SECONDS)
        for rec in self._agents.values():
            last = datetime.fromisoformat(rec.lastHeartbeat)
            if last < cutoff:
                rec.status = AgentStatus.offline

    def list_agents(self) -> list[AgentRecord]:
        self._refresh_statuses()
        return list(self._agents.values())

    def get_agent(self, agent_id: str) -> Optional[AgentRecord]:
        self._refresh_statuses()
        return self._agents.get(agent_id)

    def agents_for_role(self, role: AgentRole) -> list[AgentRecord]:
        """Return online agents that can handle the given role, least busy first."""
        self._refresh_statuses()
        candidates = [
            a for a in self._agents.values()
            if role in a.roles and a.status != AgentStatus.offline
        ]
        return sorted(candidates, key=lambda a: a.activeJobCount)

    # ── Collection job lifecycle ──────────────────────────────────────────────

    def create_collection_job(
        self,
        role: AgentRole,
        database_name: str,
        host: str,
        port: Optional[int],
        username: Optional[str],
        password: Optional[str],
        additional_params: dict,
        assessment_job_id: Optional[str] = None,
    ) -> CollectionJob:
        job_id = str(uuid.uuid4())
        job = CollectionJob(
            jobId=job_id,
            assessmentJobId=assessment_job_id,
            role=role,
            databaseName=database_name,
            host=host,
            port=port,
            username=username,
            additionalParams=additional_params,
            createdAt=datetime.now(timezone.utc).isoformat(),
        )
        self._jobs[job_id] = job
        if password:
            self._job_passwords[job_id] = password
        return job

    def get_pending_jobs_for_agent(self, agent_id: str) -> list[CollectionJob]:
        """Return pending jobs whose role matches this agent's roles."""
        agent = self._agents.get(agent_id)
        if not agent:
            return []
        return [
            j for j in self._jobs.values()
            if j.status == CollectionJobStatus.pending and j.role in agent.roles
        ]

    def assign_job(self, job_id: str, agent_id: str) -> bool:
        job = self._jobs.get(job_id)
        agent = self._agents.get(agent_id)
        if not job or not agent:
            return False
        job.status = CollectionJobStatus.assigned
        job.assignedAgentId = agent_id
        job.startedAt = datetime.now(timezone.utc).isoformat()
        agent.activeJobCount += 1
        if agent.status == AgentStatus.online:
            agent.status = AgentStatus.busy
        return True

    def complete_job(
        self,
        job_id: str,
        success: bool,
        result: Optional[dict],
        error: Optional[str],
    ) -> bool:
        job = self._jobs.get(job_id)
        if not job:
            return False
        job.status = CollectionJobStatus.completed if success else CollectionJobStatus.failed
        job.completedAt = datetime.now(timezone.utc).isoformat()
        job.result = result
        job.error = error
        if job.assignedAgentId and job.assignedAgentId in self._agents:
            agent = self._agents[job.assignedAgentId]
            agent.activeJobCount = max(0, agent.activeJobCount - 1)
            if agent.activeJobCount == 0:
                agent.status = AgentStatus.online
        return True

    def get_job(self, job_id: str) -> Optional[CollectionJob]:
        return self._jobs.get(job_id)

    def get_job_password(self, job_id: str) -> Optional[str]:
        return self._job_passwords.get(job_id)

    def list_jobs(
        self,
        status: Optional[CollectionJobStatus] = None,
        role: Optional[AgentRole] = None,
    ) -> list[CollectionJob]:
        result = list(self._jobs.values())
        if status:
            result = [j for j in result if j.status == status]
        if role:
            result = [j for j in result if j.role == role]
        return result
