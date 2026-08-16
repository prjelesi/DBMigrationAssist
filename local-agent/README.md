# Platform Local Agent

The core Docker Compose stack provisions and starts one **Platform Local Agent** automatically. Its identity and PSK are stored in the private `local_agent_bootstrap` Docker volume.

The agent can assess:

- Containers on the Compose network by service name, such as `postgres`.
- Databases running on the Docker host through `host.docker.internal`.
- Other database hosts reachable from the Docker network.

Ad-hoc credentials entered when dispatching a job require no local file. To keep credentials out of the portal, copy `databases.example.json` to `databases.json`, then map each profile to the database ID shown in the portal inventory. `databases.json` is excluded from Git.

Restart the agent after changing the file:

```powershell
docker compose restart local-agent
```