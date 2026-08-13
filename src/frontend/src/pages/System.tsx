import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import api, { getSystemStatus } from '../lib/api';

// ── Types ─────────────────────────────────────────────────────────────────

interface ConfigEntry {
  key: string; value?: string; description?: string;
  isSensitive: boolean; updatedAt?: string; updatedBy?: string;
}
interface AgentRow {
  agentId: string; name: string; status: string; allowedPlugins: string[];
  lastHeartbeatAt?: string; projectName: string; customerName?: string;
}

// ── API calls ─────────────────────────────────────────────────────────────

const getConfig    = () => api.get<ConfigEntry[]>('/api/system/config').then(r => r.data);
const setConfig    = (data: object) => api.put('/api/system/config', data).then(r => r.data);
const deleteConfig = (key: string) => api.delete(`/api/system/config/${encodeURIComponent(key)}`).then(r => r.data);
const getAllAgents  = () => api.get<AgentRow[]>('/api/system/agents').then(r => r.data);
const testAi       = () => api.post('/api/ai/test').then(r => r.data);

// ── Helpers ───────────────────────────────────────────────────────────────

const STATUS_INDICATOR: Record<string, { color: string; glow: string; label: string }> = {
  Healthy:        { color: '#22c55e', glow: '#dcfce7', label: 'Healthy' },
  Connected:      { color: '#22c55e', glow: '#dcfce7', label: 'Connected' },
  Running:        { color: '#22c55e', glow: '#dcfce7', label: 'Running' },
  'Not Configured': { color: '#f59e0b', glow: '#fef3c7', label: 'Not Configured' },
  Error:          { color: '#ef4444', glow: '#fee2e2', label: 'Error' },
};

const AGENT_BADGE: Record<string, string> = {
  Active: 'badge-green', Registered: 'badge-blue', Offline: 'badge-yellow', Revoked: 'badge-red',
};

const hbAge = (ts?: string) => {
  if (!ts) return '—';
  const d = Date.now() - new Date(ts).getTime();
  if (d < 60_000) return 'Just now';
  if (d < 3_600_000) return `${Math.floor(d / 60_000)}m ago`;
  return `${Math.floor(d / 3_600_000)}h ago`;
};

// ── Predefined config keys ────────────────────────────────────────────────

const AI_CONFIG_KEYS = [
  { key: 'AiFoundry:Endpoint',   label: 'Endpoint URL',      placeholder: 'https://<resource>.openai.azure.com/', sensitive: false },
  { key: 'AiFoundry:Deployment', label: 'Deployment Name',   placeholder: 'gpt-4o',                               sensitive: false },
];

// ═══════════════════════════════════════════════════════════════════════════
export default function System() {
  const qc = useQueryClient();
  const [aiTestResult, setAiTestResult] = useState<{ ok: boolean; msg: string } | null>(null);
  const [editKey, setEditKey] = useState<string | null>(null);
  const [editValue, setEditValue] = useState('');

  const status  = useQuery({ queryKey: ['systemStatus'],  queryFn: getSystemStatus, refetchInterval: 15_000 });
  const config  = useQuery({ queryKey: ['systemConfig'],  queryFn: getConfig });
  const agents  = useQuery({ queryKey: ['systemAgents'],  queryFn: getAllAgents, refetchInterval: 30_000 });

  const configMap = Object.fromEntries((config.data ?? []).map(c => [c.key, c]));

  const saveMutation = useMutation({
    mutationFn: setConfig,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['systemConfig'] });
      qc.invalidateQueries({ queryKey: ['systemStatus'] });
      setEditKey(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteConfig,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['systemConfig'] }),
  });

  const testMutation = useMutation({
    mutationFn: testAi,
    onSuccess: (d) => setAiTestResult({ ok: true, msg: d.raw ?? 'Connection successful.' }),
    onError:   (e: unknown) => setAiTestResult({ ok: false, msg: (e as Error).message }),
  });

  const startEdit = (key: string) => {
    setEditKey(key);
    setEditValue(configMap[key]?.value ?? '');
  };

  const saveEdit = (key: string, sensitive: boolean, description?: string) => {
    saveMutation.mutate({ key, value: editValue, description, isSensitive: sensitive, updatedBy: 'admin' });
  };

  return (
    <div>
      <div className="page-header"><h2>System</h2></div>

      {/* ── Component health grid ─────────────────────────────────────── */}
      <div className="stat-grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(220px,1fr))', marginBottom: 24 }}>
        {status.isLoading && [1,2,3,4].map(i => (
          <div key={i} className="stat-card" style={{ minHeight: 100 }} />
        ))}
        {status.data?.components.map(c => {
          const s = STATUS_INDICATOR[c.status] ?? STATUS_INDICATOR.Error;
          return (
            <div key={c.name} className="stat-card">
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
                <div style={{ width: 10, height: 10, borderRadius: '50%', background: s.color, boxShadow: `0 0 0 3px ${s.glow}`, flexShrink: 0 }} />
                <span style={{ fontWeight: 700, fontSize: 14 }}>{c.name}</span>
              </div>
              <div style={{ fontSize: 11.5, fontWeight: 600, color: s.color, marginBottom: 4 }}>{s.label}</div>
              <div style={{ fontSize: 12, color: 'var(--text-muted)', lineHeight: 1.4 }}>{c.detail}</div>
            </div>
          );
        })}
      </div>

      {/* Counts */}
      {status.data && (
        <div style={{ display: 'flex', gap: 20, marginBottom: 24 }}>
          {[
            { label: 'Projects',        value: status.data.counts.projectCount },
            { label: 'Discovery agents', value: status.data.counts.agentCount },
            { label: 'Evidence files',  value: status.data.counts.evidenceCount },
            { label: 'Last refreshed',  value: new Date(status.data.timestamp).toLocaleTimeString() },
          ].map(stat => (
            <div key={stat.label} style={{ background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '10px 18px', boxShadow: 'var(--shadow-sm)' }}>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.5px', fontWeight: 600 }}>{stat.label}</div>
              <div style={{ fontSize: 20, fontWeight: 700, marginTop: 2 }}>{stat.value}</div>
            </div>
          ))}
        </div>
      )}

      {/* ── AI Foundry configuration ───────────────────────────────────── */}
      <div className="card" style={{ marginBottom: 20 }}>
        <div className="card-header">
          <span className="card-title">AI Foundry Configuration</span>
          <div style={{ display: 'flex', gap: 8 }}>
            {status.data?.components.find(c => c.name === 'AI Foundry')?.status === 'Connected' && (
              <button className="btn btn-secondary btn-sm" disabled={testMutation.isPending}
                onClick={() => { setAiTestResult(null); testMutation.mutate(); }}>
                {testMutation.isPending ? 'Testing…' : '🔗 Test'}
              </button>
            )}
          </div>
        </div>

        <div style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 16 }}>
          Endpoint and deployment changes take effect immediately. Manage the encrypted API key and test model access in{' '}
          <a href="/ai-settings">AI Settings</a>.
        </div>

        {aiTestResult && (
          <div style={{
            background: aiTestResult.ok ? 'var(--green-bg)' : 'var(--red-bg)',
            color: aiTestResult.ok ? 'var(--green-text)' : 'var(--red-text)',
            borderRadius: 'var(--radius)', padding: '10px 14px', fontSize: 13, marginBottom: 14,
          }}>
            {aiTestResult.ok ? '✅' : '❌'} {aiTestResult.msg}
          </div>
        )}

        <table className="data-table">
          <thead><tr><th>Setting</th><th>Current Value</th><th>Action</th></tr></thead>
          <tbody>
            {AI_CONFIG_KEYS.map(({ key, label, placeholder, sensitive }) => {
              const current = configMap[key];
              const isEditing = editKey === key;
              return (
                <tr key={key}>
                  <td>
                    <div style={{ fontWeight: 600 }}>{label}</div>
                    <div style={{ fontSize: 11.5, color: 'var(--text-muted)', fontFamily: 'monospace' }}>{key}</div>
                  </td>
                  <td>
                    {isEditing ? (
                      <input value={editValue} onChange={e => setEditValue(e.target.value)}
                        placeholder={placeholder} style={{ width: '100%', maxWidth: 380 }} className="form-row"
                        autoFocus />
                    ) : (
                      <span style={{ fontFamily: 'monospace', fontSize: 13, color: current?.value ? 'var(--text-primary)' : 'var(--text-muted)' }}>
                        {current?.value ?? <em>not set</em>}
                      </span>
                    )}
                  </td>
                  <td>
                    <div style={{ display: 'flex', gap: 6 }}>
                      {isEditing ? (
                        <>
                          <button className="btn btn-primary btn-sm" disabled={saveMutation.isPending}
                            onClick={() => saveEdit(key, sensitive, label)}>
                            {saveMutation.isPending ? 'Saving…' : 'Save'}
                          </button>
                          <button className="btn btn-secondary btn-sm" onClick={() => setEditKey(null)}>Cancel</button>
                        </>
                      ) : (
                        <>
                          <button className="btn btn-secondary btn-sm" onClick={() => startEdit(key)}>Edit</button>
                          {current?.value && (
                            <button className="btn btn-danger btn-sm" onClick={() => deleteMutation.mutate(key)}>Clear</button>
                          )}
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
            {/* API key — managed through the dedicated write-only workflow */}
            <tr>
              <td>
                <div style={{ fontWeight: 600 }}>API Key</div>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Write-only encrypted credential</div>
              </td>
              <td>
                <span className="badge badge-gray">Managed in AI Settings</span>
              </td>
              <td>
                <a className="btn btn-secondary btn-sm" href="/ai-settings">Configure</a>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      {/* ── All discovery agents across all projects ─────────────────── */}
      <div className="card">
        <div className="card-header">
          <span className="card-title">All Discovery Agents</span>
          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
            {agents.data?.length ?? 0} registered · refreshes every 30s
          </span>
        </div>
        {agents.isLoading && <div className="loading" />}
        {!agents.isLoading && (agents.data?.length ?? 0) === 0 && (
          <div className="empty-state">
            <div className="empty-state-icon">🔌</div>
            <p>No discovery agents registered yet. Go to a project's <a href="/agents">Discovery Agents page</a> to register one.</p>
          </div>
        )}
        {(agents.data?.length ?? 0) > 0 && (
          <table className="data-table">
            <thead>
              <tr><th>Discovery Agent</th><th>Project / Customer</th><th>Status</th><th>Plugins</th><th>Heartbeat</th></tr>
            </thead>
            <tbody>
              {agents.data?.map((a: AgentRow) => (
                <tr key={a.agentId}>
                  <td>
                    <div style={{ fontWeight: 600 }}>{a.name}</div>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'monospace', marginTop: 2 }}>
                      {a.agentId.slice(0, 18)}…
                    </div>
                  </td>
                  <td>
                    <div style={{ fontWeight: 500 }}>{a.projectName}</div>
                    {a.customerName && <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{a.customerName}</div>}
                  </td>
                  <td><span className={`badge ${AGENT_BADGE[a.status] ?? 'badge-gray'}`}>{a.status}</span></td>
                  <td>{a.allowedPlugins.map(p => <span key={p} className="tag">{p}</span>)}</td>
                  <td style={{ color: 'var(--text-muted)', fontSize: 12.5 }}>{hbAge(a.lastHeartbeatAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* ── Raw system config ─────────────────────────────────────────── */}
      <div className="card">
        <div className="card-header">
          <span className="card-title">All Config Keys</span>
          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>{config.data?.length ?? 0} entries</span>
        </div>
        {config.isLoading && <div className="loading" />}
        {(config.data?.length ?? 0) === 0 && !config.isLoading && (
          <div className="empty-state"><p>No config keys set yet.</p></div>
        )}
        {(config.data?.length ?? 0) > 0 && (
          <table className="data-table">
            <thead><tr><th>Key</th><th>Value</th><th>Updated</th><th>By</th><th></th></tr></thead>
            <tbody>
              {config.data?.map((c: ConfigEntry) => (
                <tr key={c.key}>
                  <td style={{ fontFamily: 'monospace', fontSize: 12.5, fontWeight: 600 }}>{c.key}</td>
                  <td style={{ fontFamily: 'monospace', fontSize: 12.5, color: 'var(--text-muted)' }}>
                    {c.value ?? <em>empty</em>}
                  </td>
                  <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                    {c.updatedAt ? new Date(c.updatedAt).toLocaleString() : '—'}
                  </td>
                  <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{c.updatedBy ?? '—'}</td>
                  <td>
                    <button className="btn btn-danger btn-sm"
                      onClick={() => { if (confirm(`Delete "${c.key}"?`)) deleteMutation.mutate(c.key); }}>
                      ✕
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
