"""Cassandra collector."""

import json
from collectors.base import BaseCollector, FACTORY_SCRIPTS_DIR


class CassandraCollector(BaseCollector):

    SCRIPT = FACTORY_SCRIPTS_DIR / "Cassandra" / "Info-Gather-Cassandra" / "csu-cassandra-mf-main" / "PUBLIC" / "Factory-Cassandra-CLI-Windows.ps1"

    async def collect(self, job: dict) -> dict:
        host      = job["host"]
        port      = job.get("port") or 9042
        keyspace  = job["databaseName"]   # Cassandra uses keyspaces
        username  = job.get("username", "")
        password  = job.get("password", "")

        base = {
            "sourceType":   "Cassandra",
            "databaseName": keyspace,
            "host":         host,
            "port":         port,
            "collectedAt":  self._now_iso(),
        }

        if self.SCRIPT.exists():
            try:
                args = ["-ContactPoint", host, "-Port", str(port), "-Keyspace", keyspace, "-OutputFormat", "JSON"]
                if username:
                    args += ["-UserName", username, "-Password", password]
                rc, stdout, _ = await self._run_powershell(self.SCRIPT, args)
                if rc == 0 and stdout.strip():
                    return {**base, **json.loads(stdout), "collectionMethod": "factory-script"}
            except Exception:
                pass

        return await self._python_collect(host, port, keyspace, username, password, base)

    async def _python_collect(self, host, port, keyspace, username, password, base) -> dict:
        import asyncio
        from cassandra.cluster import Cluster
        from cassandra.auth import PlainTextAuthProvider

        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            lambda: self._sync_cassandra_query(host, port, keyspace, username, password),
        )
        return {**base, **result, "collectionMethod": "python-direct"}

    @staticmethod
    def _sync_cassandra_query(host, port, keyspace, username, password) -> dict:
        from cassandra.cluster import Cluster
        from cassandra.auth import PlainTextAuthProvider

        auth = PlainTextAuthProvider(username=username, password=password) if username else None
        cluster = Cluster([host], port=port, auth_provider=auth, connect_timeout=20)
        session = cluster.connect()
        try:
            # Cassandra version
            rows = list(session.execute("SELECT release_version FROM system.local"))
            version = rows[0].release_version if rows else "Unknown"

            # Keyspace tables
            rows = list(session.execute(
                "SELECT table_name FROM system_schema.tables WHERE keyspace_name=%s", (keyspace,)
            ))
            tables = [r.table_name for r in rows]

            # UDTs
            rows = list(session.execute(
                "SELECT type_name FROM system_schema.types WHERE keyspace_name=%s", (keyspace,)
            ))
            udts = [r.type_name for r in rows]

            # Replication strategy
            rows = list(session.execute(
                "SELECT replication FROM system_schema.keyspaces WHERE keyspace_name=%s", (keyspace,)
            ))
            replication = dict(rows[0].replication) if rows else {}
        finally:
            cluster.shutdown()

        return {
            "version":           version,
            "tableCount":        len(tables),
            "tables":            tables[:50],  # cap
            "udtCount":          len(udts),
            "replicationConfig": replication,
        }
