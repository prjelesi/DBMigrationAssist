import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import {
  Database24Regular,
  Folder24Regular,
  PlugConnected24Regular,
  Warning24Regular,
  ArrowTrending24Regular,
  CheckmarkCircle24Regular,
} from "@fluentui/react-icons";
import { getAgents, getDatabases, getProjects } from "../lib/api";

const STATUS_BADGE: Record<string, string> = {
  Active: "badge-green", Registered: "badge-blue",
  Offline: "badge-yellow", Revoked: "badge-red",
};

const ENGINE_BADGE: Record<string, string> = {
  Oracle: "badge-red", PostgreSQL: "badge-blue", SqlServer: "badge-purple",
  MySQL: "badge-green", MongoDB: "badge-yellow", Unknown: "badge-gray",
};

const MODE_BADGE: Record<string, string> = {
  Connected: "badge-indigo", Standalone: "badge-gray", AirGapped: "badge-amber",
};

export default function Dashboard() {
  const projects = useQuery({ queryKey: ["projects"], queryFn: getProjects });
  const firstProjectId = projects.data?.[0]?.projectId;

  const agents = useQuery({
    queryKey: ["agents", firstProjectId],
    queryFn: () => getAgents(firstProjectId!),
    enabled: !!firstProjectId,
  });

  const databases = useQuery({
    queryKey: ["databases", firstProjectId],
    queryFn: () => getDatabases(firstProjectId!),
    enabled: !!firstProjectId,
  });

  const activeAgents  = agents.data?.filter(a => a.status === "Active").length ?? 0;
  const totalAgents   = agents.data?.length ?? 0;
  const totalDbs      = databases.data?.length ?? 0;
  const criticalDbs   = databases.data?.filter(d => d.criticality === "Critical" || d.criticality === "High").length ?? 0;
  const totalProjects = projects.data?.length ?? 0;

  const agentHealthy = totalAgents > 0 && activeAgents === totalAgents;

  return (
    <div>
      {/* Stat cards */}
      <div className="stat-grid">
        <div className="stat-card">
          <div className="stat-icon"><Folder24Regular /></div>
          <div className="stat-value">{totalProjects || "—"}</div>
          <div className="stat-label">Active Projects</div>
          <div className={`stat-delta ${totalProjects > 0 ? "up" : "warn"}`}>
            {totalProjects > 0 && <ArrowTrending24Regular />} {totalProjects > 0 ? "In progress" : "No projects yet"}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-icon"><Database24Regular /></div>
          <div className="stat-value">{totalDbs || "—"}</div>
          <div className="stat-label">Databases in Scope</div>
          <div className="stat-delta up"><ArrowTrending24Regular /> Across all environments</div>
        </div>
        <div className="stat-card">
          <div className="stat-icon"><PlugConnected24Regular /></div>
          <div className="stat-value" style={{ color: agentHealthy ? "var(--green-text)" : totalAgents > 0 ? "var(--amber-text)" : undefined }}>
            {totalAgents > 0 ? `${activeAgents}/${totalAgents}` : "—"}
          </div>
          <div className="stat-label">Agents Online</div>
          <div className={`stat-delta ${agentHealthy ? "up" : totalAgents > 0 ? "warn" : "warn"}`}>
            {agentHealthy && <CheckmarkCircle24Regular />} {agentHealthy ? "All agents healthy" : totalAgents > 0 ? "Some agents offline" : "No agents registered"}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-icon"><Warning24Regular /></div>
          <div className="stat-value" style={{ color: criticalDbs > 0 ? "var(--red-text)" : "var(--green-text)" }}>
            {criticalDbs || "0"}
          </div>
          <div className="stat-label">High / Critical DBs</div>
          <div className={`stat-delta ${criticalDbs > 0 ? "down" : "up"}`}>
            {criticalDbs === 0 && <CheckmarkCircle24Regular />} {criticalDbs > 0 ? `${criticalDbs} require attention` : "All within threshold"}
          </div>
        </div>
      </div>

      <div className="dashboard-panels">
        {/* Recent projects */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">Recent Projects</span>
            <Link to="/projects" className="btn btn-ghost btn-sm">View all</Link>
          </div>
          {projects.isLoading && <div className="loading" />}
          {!projects.isLoading && (projects.data?.length ?? 0) === 0 && (
            <div className="empty-state">
              <div className="empty-state-icon"><Folder24Regular /></div>
              <p>No projects yet.<br /><Link to="/projects">Create your first project</Link></p>
            </div>
          )}
          {(projects.data?.length ?? 0) > 0 && (
            <table className="data-table">
              <thead><tr><th>Project</th><th>Mode</th><th>Status</th></tr></thead>
              <tbody>
                {projects.data?.slice(0, 5).map(p => (
                  <tr key={p.projectId}>
                    <td>
                      <div style={{ fontWeight: 600 }}>{p.name}</div>
                      <div style={{ fontSize: 11.5, color: "var(--text-muted)" }}>{p.customer?.name}</div>
                    </td>
                    <td><span className={`badge ${MODE_BADGE[p.deploymentMode] ?? "badge-gray"}`}>{p.deploymentMode}</span></td>
                    <td><span className="badge badge-green">{p.status}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* Agent status */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">Agent Status</span>
            <Link to="/agents" className="btn btn-ghost btn-sm">Manage</Link>
          </div>
          {agents.isLoading && <div className="loading" />}
          {!agents.isLoading && !firstProjectId && (
            <div className="empty-state">
              <div className="empty-state-icon"><PlugConnected24Regular /></div>
              <p>Create a project first to view agents.</p>
            </div>
          )}
          {firstProjectId && !agents.isLoading && (agents.data?.length ?? 0) === 0 && (
            <div className="empty-state">
              <div className="empty-state-icon"><PlugConnected24Regular /></div>
              <p>No agents registered.<br /><Link to="/agents">Register an agent</Link></p>
            </div>
          )}
          {(agents.data?.length ?? 0) > 0 && (
            <table className="data-table">
              <thead><tr><th>Agent</th><th>Status</th><th>Heartbeat</th></tr></thead>
              <tbody>
                {agents.data?.map(a => {
                  const diff = a.lastHeartbeatAt ? Date.now() - new Date(a.lastHeartbeatAt).getTime() : null;
                  const hb = diff === null ? "—" : diff < 60_000 ? "Just now" : diff < 3_600_000 ? `${Math.floor(diff / 60_000)}m ago` : `${Math.floor(diff / 3_600_000)}h ago`;
                  return (
                    <tr key={a.agentId}>
                      <td>
                        <div style={{ fontWeight: 600 }}>{a.name}</div>
                        <div style={{ fontSize: 11.5, color: "var(--text-muted)" }}>
                          {a.allowedPlugins.map(p => <span key={p} className="tag">{p}</span>)}
                        </div>
                      </td>
                      <td><span className={`badge ${STATUS_BADGE[a.status] ?? "badge-gray"}`}>{a.status}</span></td>
                      <td style={{ color: "var(--text-muted)", fontSize: 12.5 }}>{hb}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* DB inventory preview */}
      {(databases.data?.length ?? 0) > 0 && (
        <div className="card">
          <div className="card-header">
            <span className="card-title">Database Inventory — {firstProjectId && projects.data?.[0]?.name}</span>
            <Link to="/inventory" className="btn btn-ghost btn-sm">Full inventory</Link>
          </div>
          <table className="data-table">
            <thead><tr><th>Name</th><th>Engine</th><th>Host</th><th>Criticality</th></tr></thead>
            <tbody>
              {databases.data?.slice(0, 6).map(db => (
                <tr key={db.databaseId}>
                  <td style={{ fontWeight: 600 }}>{db.name}</td>
                  <td><span className={`badge ${ENGINE_BADGE[db.engine] ?? "badge-gray"}`}>{db.engine}</span></td>
                  <td style={{ color: "var(--text-muted)", fontSize: 12.5 }}>{db.hostName ?? "—"}</td>
                  <td>{db.criticality}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
