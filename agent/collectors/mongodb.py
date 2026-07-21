"""MongoDB collector."""

import json
from collectors.base import BaseCollector, FACTORY_SCRIPTS_DIR


class MongoDBCollector(BaseCollector):

    SCRIPT = FACTORY_SCRIPTS_DIR / "Mongo" / "csu-mongo-mf-main" / "PUBLIC" / "Factory-MongoDB-CLI-Windows.ps1"

    async def collect(self, job: dict) -> dict:
        host     = job["host"]
        port     = job.get("port") or 27017
        db_name  = job["databaseName"]
        username = job.get("username", "")
        password = job.get("password", "")
        auth_db  = job.get("additionalParams", {}).get("authDatabase", "admin")

        # Build connection URI (no auth if username empty)
        if username:
            from urllib.parse import quote_plus
            uri = f"mongodb://{quote_plus(username)}:{quote_plus(password)}@{host}:{port}/{db_name}?authSource={auth_db}"
        else:
            uri = f"mongodb://{host}:{port}/{db_name}"

        base = {
            "sourceType":   "MongoDB",
            "databaseName": db_name,
            "host":         host,
            "port":         port,
            "collectedAt":  self._now_iso(),
        }

        if self.SCRIPT.exists():
            try:
                rc, stdout, _ = await self._run_powershell(
                    self.SCRIPT,
                    ["-ConnectionString", uri, "-DatabaseName", db_name, "-OutputFormat", "JSON"],
                )
                if rc == 0 and stdout.strip():
                    return {**base, **json.loads(stdout), "collectionMethod": "factory-script"}
            except Exception:
                pass

        return await self._python_collect(uri, db_name, base)

    async def _python_collect(self, uri, db_name, base) -> dict:
        import asyncio
        import motor.motor_asyncio as motor

        client = motor.AsyncIOMotorClient(uri, serverSelectionTimeoutMS=10_000)
        try:
            db = client[db_name]
            server_info = await client.server_info()
            collection_names = await db.list_collection_names()

            # Sample stats from each collection
            collections = []
            for coll_name in collection_names[:20]:  # cap at 20
                coll  = db[coll_name]
                count = await coll.estimated_document_count()
                stats = await db.command("collStats", coll_name)
                collections.append({
                    "name":        coll_name,
                    "count":       count,
                    "storageMB":   round(stats.get("storageSize", 0) / 1024 / 1024, 2),
                    "hasIndexes":  stats.get("nindexes", 0) > 1,
                })

            db_stats = await db.command("dbStats")
        finally:
            client.close()

        return {
            **base,
            "version":          server_info.get("version", "Unknown"),
            "collectionCount":  len(collection_names),
            "collections":      collections,
            "databaseSizeMB":   round(db_stats.get("storageSize", 0) / 1024 / 1024, 2),
            "collectionMethod": "python-direct",
        }
