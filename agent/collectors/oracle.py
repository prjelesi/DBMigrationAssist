"""Oracle collector — wraps Oracle_Info_Gathering_Automation.ps1 with cx_Oracle fallback."""

import json
from collectors.base import BaseCollector, FACTORY_SCRIPTS_DIR


class OracleCollector(BaseCollector):

    SCRIPT = FACTORY_SCRIPTS_DIR / "Heterogeneous" / "Oracle_Info_Gathering_Automation.ps1"

    async def collect(self, job: dict) -> dict:
        host     = job["host"]
        port     = job.get("port") or 1521
        db_name  = job["databaseName"]   # Oracle SID or service name
        username = job.get("username", "system")
        password = job.get("password", "")
        # Extra Oracle params
        service_name = job.get("additionalParams", {}).get("serviceName", db_name)

        base = {
            "sourceType":   "Oracle",
            "databaseName": db_name,
            "host":         host,
            "port":         port,
            "serviceName":  service_name,
            "collectedAt":  self._now_iso(),
        }

        # ── Strategy 1: factory PowerShell script ─────────────────────────────
        if self.SCRIPT.exists():
            # Build CSV input file the script expects
            import tempfile, os
            csv_content = (
                "ServerName,Port,ServiceName,UserName,Password\n"
                f"{host},{port},{service_name},{username},{password}\n"
            )
            with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
                f.write(csv_content)
                csv_path = f.name
            try:
                rc, stdout, _ = await self._run_powershell(
                    self.SCRIPT,
                    ["-InputFile", csv_path, "-OutputFormat", "JSON"],
                    timeout=120,
                )
                if rc == 0 and stdout.strip():
                    return {**base, **json.loads(stdout), "collectionMethod": "factory-script"}
            except Exception:
                pass
            finally:
                try:
                    os.unlink(csv_path)
                except OSError:
                    pass

        # ── Strategy 2: cx_Oracle (thin mode, no Instant Client needed) ───────
        return await self._python_collect(host, port, service_name, username, password, base)

    async def _python_collect(self, host, port, service_name, username, password, base) -> dict:
        import asyncio
        import oracledb  # python-oracledb thin mode

        # oracledb is synchronous; run in executor to not block event loop
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            lambda: self._sync_oracle_query(host, port, service_name, username, password),
        )
        return {**base, **result, "collectionMethod": "python-direct"}

    @staticmethod
    def _sync_oracle_query(host, port, service_name, username, password) -> dict:
        import oracledb
        oracledb.init_oracle_client()  # thin mode — no client libs needed
        dsn = f"{host}:{port}/{service_name}"
        with oracledb.connect(user=username, password=password, dsn=dsn) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT BANNER FROM V$VERSION WHERE ROWNUM=1")
                version = (cur.fetchone() or ["Unknown"])[0]

                cur.execute("SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER NOT IN ('SYS','SYSTEM','DBSNMP','OUTLN')")
                table_count = (cur.fetchone() or [0])[0]

                cur.execute("SELECT COUNT(*) FROM DBA_PROCEDURES WHERE OBJECT_TYPE IN ('PROCEDURE','FUNCTION','PACKAGE') AND OWNER NOT IN ('SYS','SYSTEM')")
                proc_count = (cur.fetchone() or [0])[0]

                cur.execute("SELECT COUNT(*) FROM DBA_TRIGGERS WHERE OWNER NOT IN ('SYS','SYSTEM')")
                trigger_count = (cur.fetchone() or [0])[0]

                cur.execute("SELECT ROUND(SUM(BYTES)/1024/1024,2) FROM DBA_SEGMENTS")
                size_mb = (cur.fetchone() or [0])[0]

                cur.execute("SELECT COMP_NAME, VERSION, STATUS FROM DBA_REGISTRY")
                components = [{"name": r[0], "version": r[1], "status": r[2]} for r in cur.fetchall()]

        return {
            "version":          version,
            "tableCount":       table_count,
            "storedProcCount":  proc_count,
            "triggerCount":     trigger_count,
            "databaseSizeMB":   float(size_mb or 0),
            "installedComponents": components,
        }
