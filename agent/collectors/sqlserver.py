"""SQL Server collector — wraps the factory info-gather script with Python fallback."""

import json
from pathlib import Path

from collectors.base import BaseCollector, FACTORY_SCRIPTS_DIR


class SqlServerCollector(BaseCollector):

    SCRIPT = FACTORY_SCRIPTS_DIR / "SQL" / "csu-sql-mf-main" / "PUBLIC" / "Factory-SQL-Windows.ps1"

    async def collect(self, job: dict) -> dict:
        host     = job["host"]
        port     = job.get("port") or 1433
        db_name  = job["databaseName"]
        username = job.get("username", "sa")
        password = job.get("password", "")

        base = {
            "sourceType":   "SQL Server",
            "databaseName": db_name,
            "host":         host,
            "port":         port,
            "collectedAt":  self._now_iso(),
        }

        # ── Strategy 1: factory PowerShell script ─────────────────────────────
        if self.SCRIPT.exists():
            try:
                rc, stdout, stderr = await self._run_powershell(
                    self.SCRIPT,
                    [
                        "-ServerName", host,
                        "-Port", str(port),
                        "-DatabaseName", db_name,
                        "-UserName", username,
                        "-Password", password,
                        "-OutputFormat", "JSON",
                    ],
                )
                if rc == 0 and stdout.strip():
                    data = json.loads(stdout)
                    return {**base, **data, "collectionMethod": "factory-script"}
            except Exception as exc:
                pass  # fall through to Python fallback

        # ── Strategy 2: direct pyodbc / pymssql query ─────────────────────────
        return await self._python_collect(host, port, db_name, username, password, base)

    async def _python_collect(self, host, port, db_name, username, password, base) -> dict:
        import aioodbc
        dsn = (
            f"DRIVER={{ODBC Driver 18 for SQL Server}};"
            f"SERVER={host},{port};DATABASE={db_name};"
            f"UID={username};PWD={password};"
            f"TrustServerCertificate=yes;"
        )
        async with await aioodbc.connect(dsn=dsn) as conn:
            async with conn.cursor() as cur:
                # Server version
                await cur.execute("SELECT @@VERSION, @@SERVERNAME, SERVERPROPERTY('Edition')")
                row = await cur.fetchone()
                version = str(row[0]).split("\n")[0] if row else "Unknown"

                # Database list
                await cur.execute("SELECT name, create_date FROM sys.databases WHERE database_id > 4 ORDER BY name")
                databases = [{"name": r[0], "createDate": str(r[1])} for r in await cur.fetchall()]

                # Object counts in this DB
                await cur.execute("""
                    SELECT
                        SUM(CASE WHEN type='U' THEN 1 ELSE 0 END) AS tables,
                        SUM(CASE WHEN type='P' THEN 1 ELSE 0 END) AS stored_procs,
                        SUM(CASE WHEN type='V' THEN 1 ELSE 0 END) AS views,
                        SUM(CASE WHEN type='TR' THEN 1 ELSE 0 END) AS triggers
                    FROM sys.objects
                """)
                counts = await cur.fetchone()

                # Rough DB size
                await cur.execute(f"""
                    SELECT CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(18,2))
                    FROM sys.master_files WHERE database_id = DB_ID('{db_name}')
                """)
                size_mb = (await cur.fetchone() or [0])[0]

        return {
            **base,
            "version":          version,
            "serverName":       host,
            "databases":        databases,
            "tableCount":       counts[0] if counts else 0,
            "storedProcCount":  counts[1] if counts else 0,
            "viewCount":        counts[2] if counts else 0,
            "triggerCount":     counts[3] if counts else 0,
            "databaseSizeMB":   float(size_mb or 0),
            "collectionMethod": "python-direct",
        }
