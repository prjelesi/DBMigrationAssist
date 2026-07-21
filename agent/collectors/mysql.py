"""MySQL collector."""

import json
from collectors.base import BaseCollector, FACTORY_SCRIPTS_DIR


class MySQLCollector(BaseCollector):

    SCRIPT = FACTORY_SCRIPTS_DIR / "MySQL" / "csu-mysql-mf-main" / "PUBLIC" / "Factory-MySQL-Windows.ps1"

    async def collect(self, job: dict) -> dict:
        host     = job["host"]
        port     = job.get("port") or 3306
        db_name  = job["databaseName"]
        username = job.get("username", "root")
        password = job.get("password", "")

        base = {
            "sourceType":   "MySQL",
            "databaseName": db_name,
            "host":         host,
            "port":         port,
            "collectedAt":  self._now_iso(),
        }

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

        return await self._python_collect(host, port, db_name, username, password, base)

    async def _python_collect(self, host, port, db_name, username, password, base) -> dict:
        import aiomysql
        conn = await aiomysql.connect(
            host=host, port=port, db=db_name,
            user=username, password=password,
            connect_timeout=30,
        )
        try:
            async with conn.cursor() as cur:
                await cur.execute("SELECT VERSION()")
                version = (await cur.fetchone())[0]

                await cur.execute(
                    "SELECT COUNT(*) FROM information_schema.tables "
                    "WHERE table_schema=%s AND table_type='BASE TABLE'", (db_name,)
                )
                table_count = (await cur.fetchone())[0]

                await cur.execute(
                    "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema=%s", (db_name,)
                )
                proc_count = (await cur.fetchone())[0]

                await cur.execute(
                    "SELECT SUM(data_length + index_length) FROM information_schema.tables "
                    "WHERE table_schema=%s", (db_name,)
                )
                size_bytes = (await cur.fetchone())[0] or 0

                await cur.execute("SHOW ENGINES")
                engines = [r[0] for r in await cur.fetchall() if r[1] == "YES" or r[1] == "DEFAULT"]
        finally:
            conn.close()

        return {
            **base,
            "version":          version,
            "tableCount":       table_count,
            "storedProcCount":  proc_count,
            "databaseSizeMB":   round(size_bytes / 1024 / 1024, 2),
            "storageEngines":   engines,
            "collectionMethod": "python-direct",
        }
