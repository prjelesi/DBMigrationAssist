import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { dispatchJob, getAgentJobs, getAgents, getProjects, registerAgent } from "../lib/api";
import type { Agent, AgentJobSummary, PskMode, RegisterAgentResponse } from "../types";

const STATUS_BADGE: Record<string, string> = {
  Active: "badge-green", Registered: "badge-blue",
  Offline: "badge-yellow", Revoked: "badge-red",
};

const JOB_BADGE: Record<string, string> = {
  Pending: "badge-gray", Assigned: "badge-blue", Running: "badge-indigo",
  Completed: "badge-green", Failed: "badge-red", Cancelled: "badge-gray",
};

const ALL_PLUGINS = ["oracle", "postgresql", "sqlserver", "mysql", "mongodb"];

const DEFAULT_PORTS: Record<string, number> = {
  oracle: 1521, postgresql: 5432, sqlserver: 1433, mysql: 3306, mongodb: 27017,
};

export default function Agents() {
  const qc = useQueryClient();
  const [selectedProject, setSelectedProject] = useState("");
  const [showRegister, setShowRegister] = useState(false);
  const [bootstrapResult, setBootstrapResult] = useState<RegisterAgentResponse | null>(null);
  const [dispatchTarget, setDispatchTarget] = useState<Agent | null>(null);
  const [jobHistoryAgent, setJobHistoryAgent] = useState<Agent | null>(null);

  const [regForm, setRegForm] = useState({
    name: "", pskMode: "SystemGenerated" as PskMode,
    userPsk: "", allowedPlugins: ["postgresql"] as string[], createdBy: "admin",
  });

  const [jobForm, setJobForm] = useState({
    pluginId: "postgresql", host: "", port: 5432,
    database: "", username: "", password: "",
  });

  const projects = useQuery({ queryKey: ["projects"], queryFn: getProjects });

  const agents = useQuery({
    queryKey: ["agents", selectedProject],
    queryFn: () => getAgents(selectedProject),
    enabled: !!selectedProject,
    refetchInterval: 30_000,
  });

  const jobHistory = useQuery({
    queryKey: ["agentJobs", jobHistoryAgent?.agentId],
    queryFn: () => getAgentJobs(jobHistoryAgent!.agentId),
    enabled: !!jobHistoryAgent,
    refetchInterval: 10_000,
  });

  const registerMutation = useMutation({
    mutationFn: registerAgent,
    onSuccess: (data) => {
      qc.invalidateQueries({ queryKey: ["agents"] });
      setBootstrapResult(data as RegisterAgentResponse);
      setShowRegister(false);
    },
  });

  const dispatchMutation = useMutation({
    mutationFn: ({ agent, form }: { agent: Agent; form: typeof jobForm }) =>
      dispatchJob(agent.agentId, {
        pluginId: form.pluginId,
        parametersJson: JSON.stringify({
          host: form.host, port: form.port,
          database: form.database,
          username: form.username,
          password: form.password,
        }),
      }),
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ["agentJobs", vars.agent.agentId] });
      setJobHistoryAgent(vars.agent);
      setDispatchTarget(null);
      setJobForm({ pluginId: "postgresql", host: "", port: 5432, database: "", username: "", password: "" });
    },
  });

  const togglePlugin = (p: string) =>
    setRegForm(f => ({
      ...f,
      allowedPlugins: f.allowedPlugins.includes(p)
        ? f.allowedPlugins.filter(x => x !== p)
        : [...f.allowedPlugins, p],
    }));

  const hbAge = (ts?: string) => {
    if (!ts) return "—";
    const d = Date.now() - new Date(ts).getTime();
    if (d < 60_000) return "Just now";
    if (d < 3_600_000) return `${Math.floor(d / 60_000)}m ago`;
    return `${Math.floor(d / 3_600_000)}h ago`;
  };

  const duration = (start?: string, end?: string) => {
    if (!start) return "—";
    const ms = new Date(end ?? Date.now()).getTime() - new Date(start).getTime();
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
    return `${Math.floor(ms / 60_000)}m ${Math.floor((ms % 60_000) / 1000)}s`;
  };

  return (
    <div>
      <div className="page-header">
        <h2>Assessment Agents</h2>
        <button className="btn btn-primary" disabled={!selectedProject} onClick={() => setShowRegister(true)}>
          + Register Agent
        </button>
      </div>

      {/* Project selector */}
      <div className="filter-bar">
        <div className="form-row" style={{ marginBottom: 0, minWidth: 300 }}>
          <label>Project</label>
          <select value={selectedProject} onChange={e => { setSelectedProject(e.target.value); setJobHistoryAgent(null); }}>
            <option value="">Choose a project…</option>
            {projects.data?.map(p => <option key={p.projectId} value={p.projectId}>{p.name}</option>)}
          </select>
        </div>
      </div>

      {/* Agent table */}
      {selectedProject && (
        <div className="card">
          <div className="card-header">
            <span className="card-title">Registered Agents</span>
            <span style={{ fontSize: 12, color: "var(--text-muted)" }}>Refreshes every 30s</span>
          </div>
          {agents.isLoading && <div className="loading" />}
          {!agents.isLoading && (agents.data?.length ?? 0) === 0 && (
            <div className="empty-state">
              <div className="empty-state-icon">🔌</div>
              <p>No agents registered for this project.</p>
            </div>
          )}
          {(agents.data?.length ?? 0) > 0 && (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Agent</th><th>Status</th><th>Plugins</th>
                  <th>Last Heartbeat</th><th>Registered</th><th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {agents.data?.map((a: Agent) => (
                  <tr key={a.agentId}>
                    <td>
                      <div style={{ fontWeight: 600 }}>{a.name}</div>
                      <div style={{ fontSize: 11, color: "var(--text-muted)", marginTop: 2, fontFamily: "monospace" }}>
                        {a.agentId.slice(0, 18)}…
                      </div>
                    </td>
                    <td>
                      <span className={`badge ${STATUS_BADGE[a.status] ?? "badge-gray"}`}>{a.status}</span>
                    </td>
                    <td>{a.allowedPlugins.map(p => <span key={p} className="tag">{p}</span>)}</td>
                    <td style={{ color: "var(--text-muted)", fontSize: 12.5 }}>{hbAge(a.lastHeartbeatAt)}</td>
                    <td style={{ color: "var(--text-muted)", fontSize: 12.5 }}>
                      {new Date(a.createdAt).toLocaleDateString()}
                    </td>
                    <td>
                      <div style={{ display: "flex", gap: 6 }}>
                        <button
                          className="btn btn-primary btn-sm"
                          onClick={() => {
                            setDispatchTarget(a);
                            setJobForm(f => ({ ...f, pluginId: a.allowedPlugins[0] ?? "postgresql", port: DEFAULT_PORTS[a.allowedPlugins[0]] ?? 5432 }));
                          }}
                        >
                          ▶ Dispatch Job
                        </button>
                        <button
                          className="btn btn-secondary btn-sm"
                          onClick={() => setJobHistoryAgent(jobHistoryAgent?.agentId === a.agentId ? null : a)}
                        >
                          {jobHistoryAgent?.agentId === a.agentId ? "Hide Jobs" : "Job History"}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* Job history panel */}
      {jobHistoryAgent && (
        <div className="card">
          <div className="card-header">
            <span className="card-title">Job History — {jobHistoryAgent.name}</span>
            <span style={{ fontSize: 12, color: "var(--text-muted)" }}>Auto-refreshes every 10s</span>
          </div>
          {jobHistory.isLoading && <div className="loading" />}
          {!jobHistory.isLoading && (jobHistory.data?.length ?? 0) === 0 && (
            <div className="empty-state">
              <div className="empty-state-icon">📋</div>
              <p>No jobs dispatched yet. Click <strong>Dispatch Job</strong> to create one.</p>
            </div>
          )}
          {(jobHistory.data?.length ?? 0) > 0 && (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Job ID</th><th>Plugin</th><th>Database</th>
                  <th>Status</th><th>Duration</th><th>Results</th><th>Dispatched</th>
                </tr>
              </thead>
              <tbody>
                {jobHistory.data?.map((j: AgentJobSummary) => (
                  <tr key={j.jobId}>
                    <td style={{ fontFamily: "monospace", fontSize: 11.5, color: "var(--text-muted)" }}>
                      {j.jobId.slice(0, 8)}…
                    </td>
                    <td><span className="tag">{j.pluginId}</span></td>
                    <td style={{ fontSize: 12.5 }}>{j.databaseName ?? "—"}</td>
                    <td><span className={`badge ${JOB_BADGE[j.status] ?? "badge-gray"}`}>{j.status}</span></td>
                    <td style={{ fontSize: 12.5, color: "var(--text-muted)" }}>
                      {duration(j.startedAt, j.completedAt)}
                    </td>
                    <td style={{ fontSize: 12.5 }}>
                      {j.resultCount > 0
                        ? <span className="badge badge-green">{j.resultCount} findings</span>
                        : <span style={{ color: "var(--text-muted)" }}>—</span>}
                    </td>
                    <td style={{ fontSize: 12.5, color: "var(--text-muted)" }}>
                      {new Date(j.createdAt).toLocaleString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* ── Dispatch Job modal ────────────────────────────────── */}
      {dispatchTarget && (
        <div className="modal-overlay" onClick={() => setDispatchTarget(null)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: 520 }}>
            <div className="modal-title">▶ Dispatch Job</div>
            <div className="modal-sub">Agent: <strong>{dispatchTarget.name}</strong></div>

            {dispatchMutation.isError && (
              <div className="error-msg">Failed to dispatch job. Check the form and try again.</div>
            )}

            <div className="form-row">
              <label>Plugin *</label>
              <select
                value={jobForm.pluginId}
                onChange={e => setJobForm(f => ({
                  ...f, pluginId: e.target.value,
                  port: DEFAULT_PORTS[e.target.value] ?? f.port,
                }))}
              >
                {dispatchTarget.allowedPlugins.map(p => (
                  <option key={p} value={p}>{p}</option>
                ))}
              </select>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "1fr auto", gap: 12 }}>
              <div className="form-row">
                <label>Host *</label>
                <input
                  value={jobForm.host}
                  onChange={e => setJobForm(f => ({ ...f, host: e.target.value }))}
                  placeholder="e.g. 10.0.1.50 or db.internal"
                />
              </div>
              <div className="form-row" style={{ width: 90 }}>
                <label>Port *</label>
                <input
                  type="number"
                  value={jobForm.port}
                  onChange={e => setJobForm(f => ({ ...f, port: Number(e.target.value) }))}
                />
              </div>
            </div>

            <div className="form-row">
              <label>Database / Service Name *</label>
              <input
                value={jobForm.database}
                onChange={e => setJobForm(f => ({ ...f, database: e.target.value }))}
                placeholder={jobForm.pluginId === "oracle" ? "e.g. ORCL or ORCLPDB1" : "e.g. postgres"}
              />
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
              <div className="form-row">
                <label>Username *</label>
                <input
                  value={jobForm.username}
                  onChange={e => setJobForm(f => ({ ...f, username: e.target.value }))}
                  placeholder="Read-only assessment user"
                  autoComplete="off"
                />
              </div>
              <div className="form-row">
                <label>Password *</label>
                <input
                  type="password"
                  value={jobForm.password}
                  onChange={e => setJobForm(f => ({ ...f, password: e.target.value }))}
                  autoComplete="new-password"
                />
              </div>
            </div>

            <div className="warn-msg" style={{ marginTop: 4, fontSize: 12 }}>
              ⚠️ Credentials are encrypted in transit (TLS) and stored only in the job payload (JSONB). Use a dedicated read-only assessment account.
            </div>

            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setDispatchTarget(null)}>Cancel</button>
              <button
                className="btn btn-primary"
                disabled={dispatchMutation.isPending || !jobForm.host || !jobForm.database || !jobForm.username}
                onClick={() => dispatchMutation.mutate({ agent: dispatchTarget, form: jobForm })}
              >
                {dispatchMutation.isPending ? "Dispatching…" : "▶ Dispatch"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Bootstrap result modal ───────────────────────────── */}
      {bootstrapResult && (
        <div className="modal-overlay" onClick={() => setBootstrapResult(null)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-title" style={{ color: "var(--green-text)" }}>✅ Agent Registered</div>
            <div className="warn-msg" style={{ marginBottom: 12 }}>⚠️ {bootstrapResult.warning}</div>
            <div style={{ fontSize: 13, marginBottom: 10, color: "var(--text-secondary)" }}>
              Save the bootstrap package before closing — the PSK will not be shown again.
            </div>
            <pre style={{
              background: "var(--sidebar-bg)", color: "#818cf8",
              borderRadius: "var(--radius)", padding: 16, fontSize: 11.5,
              overflow: "auto", maxHeight: 260, border: "1px solid var(--sidebar-border)"
            }}>
              {JSON.stringify(bootstrapResult.bootstrapPackage, null, 2)}
            </pre>
            <div className="modal-actions">
              <button className="btn btn-secondary"
                onClick={() => navigator.clipboard.writeText(JSON.stringify(bootstrapResult.bootstrapPackage, null, 2))}>
                Copy JSON
              </button>
              <button className="btn btn-primary" onClick={() => setBootstrapResult(null)}>I have saved it</button>
            </div>
          </div>
        </div>
      )}

      {/* ── Register agent modal ─────────────────────────────── */}
      {showRegister && (
        <div className="modal-overlay" onClick={() => setShowRegister(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-title">Register Agent</div>
            <div className="modal-sub">A bootstrap package will be generated for deployment.</div>
            {registerMutation.isError && <div className="error-msg">Registration failed. Check the form and try again.</div>}

            <div className="form-row">
              <label>Agent Name *</label>
              <input value={regForm.name} onChange={e => setRegForm(f => ({ ...f, name: e.target.value }))}
                placeholder="e.g. Prod-Oracle-Agent-1" />
            </div>

            <div className="form-row">
              <label>Allowed Plugins</label>
              <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginTop: 4 }}>
                {ALL_PLUGINS.map(p => (
                  <label key={p} style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 13, cursor: "pointer" }}>
                    <input type="checkbox" checked={regForm.allowedPlugins.includes(p)} onChange={() => togglePlugin(p)} />
                    {p}
                  </label>
                ))}
              </div>
            </div>

            <div className="form-row">
              <label>PSK Mode</label>
              <select value={regForm.pskMode} onChange={e => setRegForm(f => ({ ...f, pskMode: e.target.value as PskMode }))}>
                <option value="SystemGenerated">System generated (recommended)</option>
                <option value="UserSupplied">User supplied</option>
              </select>
            </div>

            {regForm.pskMode === "UserSupplied" && (
              <div className="form-row">
                <label>Your PSK (min 32 bytes)</label>
                <input type="password" value={regForm.userPsk}
                  onChange={e => setRegForm(f => ({ ...f, userPsk: e.target.value }))}
                  placeholder="Enter your pre-shared key" />
              </div>
            )}

            <div className="form-row">
              <label>Registered By</label>
              <input value={regForm.createdBy} onChange={e => setRegForm(f => ({ ...f, createdBy: e.target.value }))} />
            </div>

            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setShowRegister(false)}>Cancel</button>
              <button className="btn btn-primary" disabled={registerMutation.isPending}
                onClick={() => registerMutation.mutate({
                  projectId: selectedProject,
                  name: regForm.name,
                  allowedPlugins: regForm.allowedPlugins,
                  pskMode: regForm.pskMode,
                  userPsk: regForm.pskMode === "UserSupplied" ? regForm.userPsk : undefined,
                  createdBy: regForm.createdBy,
                })}>
                {registerMutation.isPending ? "Registering…" : "Register Agent"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
