"""PostgreSQL collector."""

import json
from pathlib import Path

from collectors.base import BaseCollector, FACTORY_SCRIPTS_DIR


class PostgreSQLCollector(BaseCollector):

    SCRIPT = FACTORY_SCRIPTS_DIR / "PostgreSQL" / "csu-postgresql-mf-main" / "PUBLIC" / "Factory-PostgreSQL-Windows.ps1"

    async def collect(self, job: dict) -> dict:
        host     = job["host"]
        port     = job.get("port") or 5432
        db_name  = job["databaseName"]
        username = job.get("username", "postgres")
        password = job.get("password", "")

        base = {
            "sourceType":   "PostgreSQL",
            "databaseName": db_name,
            "host":         host,
            "port":         port,
            "collectedAt":  self._now_iso(),
        }

        # ── Strategy 1: factory script ────────────────────────────────────────
        if self.SCRIPT.exists():
            try:
                rc, stdout, _ = await self._run_powershell(
                    self.SCRIPT,
                    ["-ServerName", host, "-Port", str(port), "-DatabaseName", db_name,
                     "-UserName", username, "-Password", password, "-OutputFormat", "JSON"],
                )
                if rc == 0 and stdout.strip():
                    return {**base, **json.loads(stdout), "collectionMethod": "factory-script"}
            except Exception:
                pass

        # ── Strategy 2: asyncpg ───────────────────────────────────────────────
        return await self._python_collect(host, port, db_name, username, password, base)

    async def _python_collect(self, host, port, db_name, username, password, base) -> dict:
        import asyncpg
        conn = await asyncpg.connect(
            host=host, port=port, database=db_name,
            user=username, password=password, timeout=30,
        )
        try:
            version = await conn.fetchval("SELECT version()")
            table_count = await conn.fetchval(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'"
            )
            view_count = await conn.fetchval(
                "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='public'"
            )
            func_count = await conn.fetchval(
                "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='public'"
            )
            size_bytes = await conn.fetchval(f"SELECT pg_database_size('{db_name}')")
            extensions = [r["extname"] for r in await conn.fetch("SELECT extname FROM pg_extension")]
        finally:
            await conn.close()

        return {
            **base,
            "version":          version,
            "tableCount":       table_count,
            "viewCount":        view_count,
            "functionCount":    func_count,
            "databaseSizeMB":   round((size_bytes or 0) / 1024 / 1024, 2),
            "extensions":       extensions,
            "collectionMethod": "python-direct",
        }
