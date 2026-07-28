import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import api from '../lib/api';

type ProviderType = 'AzureOpenAi' | 'AiFoundry' | 'OpenAi' | 'LocalEndpoint';
type ProviderStatus = 'Active' | 'Disabled' | 'Error';

interface AiProvider {
  providerId: string;
  name: string;
  providerType: ProviderType;
  status: ProviderStatus;
  endpoint: string;
  deploymentName: string;
  apiVersion?: string;
  apiKeyEnvVar: string;
  isDefault: boolean;
  notes?: string;
  lastTestedAt?: string;
  lastTestResult?: string;
}

interface AiStatus { available: boolean; message: string; configuredVia: string; }

const PROVIDER_TYPES: ProviderType[] = ['AzureOpenAi', 'AiFoundry', 'OpenAi', 'LocalEndpoint'];
const STATUS_BADGE: Record<ProviderStatus, string> = {
  Active: 'badge-green', Disabled: 'badge-gray', Error: 'badge-red',
};

const getProviders    = () => api.get<AiProvider[]>('/api/ai/providers').then(r => r.data);
const getAiStatus     = () => api.get<AiStatus>('/api/ai/status').then(r => r.data);
const testConnection  = () => api.post('/api/ai/test').then(r => r.data);
const registerProvider = (data: object) => api.post('/api/ai/providers', data).then(r => r.data);
const deleteProvider   = (id: string) => api.delete(`/api/ai/providers/${id}`).then(r => r.data);

export default function AiSettings() {
  const qc = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);
  const [testResult, setTestResult] = useState<{ ok: boolean; message: string } | null>(null);

  const [form, setForm] = useState({
    name: '', providerType: 'AzureOpenAi' as ProviderType,
    endpoint: '', deploymentName: 'gpt-4o',
    apiVersion: '2024-02-01', apiKeyEnvVar: 'AI_FOUNDRY_API_KEY',
    isDefault: true, notes: '',
  });

  const status    = useQuery({ queryKey: ['aiStatus'],    queryFn: getAiStatus,    refetchInterval: 30_000 });
  const providers = useQuery({ queryKey: ['aiProviders'], queryFn: getProviders });

  const addMutation = useMutation({
    mutationFn: registerProvider,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['aiProviders'] }); setShowAdd(false); },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteProvider,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['aiProviders'] }),
  });

  const testMutation = useMutation({
    mutationFn: testConnection,
    onSuccess: (data) => setTestResult({ ok: true, message: data.raw ?? 'Connection successful.' }),
    onError: (e: unknown) => setTestResult({ ok: false, message: (e as Error).message }),
  });

  return (
    <div>
      <div className="page-header"><h2>AI Settings</h2></div>

      {/* Live status card */}
      <div className="card" style={{ marginBottom: 20 }}>
        <div className="card-header"><span className="card-title">AI Foundry Status</span></div>
        {status.isLoading && <div className="loading" />}
        {status.data && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <div style={{
                width: 12, height: 12, borderRadius: '50%',
                background: status.data.available ? '#22c55e' : '#f59e0b',
                boxShadow: status.data.available ? '0 0 0 3px #dcfce7' : '0 0 0 3px #fef3c7',
              }} />
              <div>
                <div style={{ fontWeight: 600, fontSize: 14 }}>
                  {status.data.available ? 'Connected' : 'Not configured'}
                </div>
                <div style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 2 }}>{status.data.message}</div>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 10 }}>
              {status.data.available && (
                <button className="btn btn-secondary btn-sm"
                  disabled={testMutation.isPending}
                  onClick={() => { setTestResult(null); testMutation.mutate(); }}>
                  {testMutation.isPending ? 'Testing…' : '🔗 Test Connection'}
                </button>
              )}
              <button className="btn btn-primary btn-sm" onClick={() => setShowAdd(true)}>
                + Register Provider
              </button>
            </div>
          </div>
        )}
        {testResult && (
          <div className={testResult.ok ? 'warn-msg' : 'error-msg'}
            style={{ marginTop: 12, background: testResult.ok ? 'var(--green-bg)' : undefined, color: testResult.ok ? 'var(--green-text)' : undefined }}>
            {testResult.ok ? '✅' : '❌'} {testResult.message}
          </div>
        )}
      </div>

      {/* Where AI is used */}
      <div className="card" style={{ marginBottom: 20 }}>
        <div className="card-header"><span className="card-title">Where AI Foundry is Used</span></div>
        <table className="data-table">
          <thead><tr><th>Feature</th><th>Status</th><th>Description</th></tr></thead>
          <tbody>
            {[
              { feature: 'Evidence Parsing', active: status.data?.available,
                desc: 'Extracts structured findings from AWR, Statspack and unsupported report formats.' },
              { feature: 'Finding Enrichment', active: status.data?.available,
                desc: 'Adds migration path, risk level and remediation steps to raw agent assessment results.' },
              { feature: 'Report Generation', active: status.data?.available,
                desc: 'Generates executive summary, risk register, wave recommendation and next steps.' },
              { feature: 'Rules-based Fallback', active: true,
                desc: 'Always available — deterministic classification when AI is not configured.' },
            ].map(row => (
              <tr key={row.feature}>
                <td style={{ fontWeight: 600 }}>{row.feature}</td>
                <td>
                  <span className={`badge ${row.active ? 'badge-green' : 'badge-yellow'}`}>
                    {row.active ? 'Active' : 'Fallback only'}
                  </span>
                </td>
                <td style={{ color: 'var(--text-muted)', fontSize: 12.5 }}>{row.desc}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* How to configure (env vars guide) */}
      {!status.data?.available && (
        <div className="card" style={{ marginBottom: 20 }}>
          <div className="card-header"><span className="card-title">How to Configure</span></div>
          <div style={{ fontSize: 13.5, color: 'var(--text-secondary)', marginBottom: 12 }}>
            Set the following environment variables on the API container to enable AI features:
          </div>
          <pre style={{
            background: 'var(--sidebar-bg)', color: '#818cf8',
            borderRadius: 'var(--radius)', padding: '16px 20px', fontSize: 12.5,
            border: '1px solid var(--sidebar-border)', overflowX: 'auto',
          }}>{`# Azure OpenAI / AI Foundry
AiFoundry__Endpoint=https://<your-resource>.openai.azure.com/
AiFoundry__ApiKey=<your-api-key>
AiFoundry__Deployment=gpt-4o

# Or use environment variable names (docker-compose / K8s secrets)
AZURE_OPENAI_ENDPOINT=https://<your-resource>.openai.azure.com/
AZURE_OPENAI_API_KEY=<your-api-key>
AZURE_OPENAI_DEPLOYMENT=gpt-4o`}</pre>
          <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 10 }}>
            The API key is read from environment variables only — it is never stored in the database.
          </div>
        </div>
      )}

      {/* Registered providers */}
      <div className="card">
        <div className="card-header">
          <span className="card-title">Registered Providers</span>
          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>{providers.data?.length ?? 0} configured</span>
        </div>
        {providers.isLoading && <div className="loading" />}
        {(providers.data?.length ?? 0) === 0 && !providers.isLoading && (
          <div className="empty-state">
            <div className="empty-state-icon">🤖</div>
            <p>No providers registered yet.<br />Register one above to track your AI endpoint configuration.</p>
          </div>
        )}
        {(providers.data?.length ?? 0) > 0 && (
          <table className="data-table">
            <thead><tr><th>Name</th><th>Type</th><th>Endpoint</th><th>Deployment</th><th>Key Env Var</th><th>Status</th><th></th></tr></thead>
            <tbody>
              {providers.data?.map((p: AiProvider) => (
                <tr key={p.providerId}>
                  <td>
                    <div style={{ fontWeight: 600 }}>{p.name}</div>
                    {p.isDefault && <span className="badge badge-indigo" style={{ fontSize: 10, marginTop: 2 }}>Default</span>}
                  </td>
                  <td><span className="badge badge-gray">{p.providerType}</span></td>
                  <td style={{ fontSize: 12, color: 'var(--text-muted)', maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{p.endpoint}</td>
                  <td><span className="tag">{p.deploymentName}</span></td>
                  <td style={{ fontFamily: 'monospace', fontSize: 12 }}>{p.apiKeyEnvVar}</td>
                  <td><span className={`badge ${STATUS_BADGE[p.status]}`}>{p.status}</span></td>
                  <td>
                    <button className="btn btn-danger btn-sm"
                      disabled={deleteMutation.isPending}
                      onClick={() => { if (confirm(`Delete "${p.name}"?`)) deleteMutation.mutate(p.providerId); }}>
                      ✕
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Register modal */}
      {showAdd && (
        <div className="modal-overlay" onClick={() => setShowAdd(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-title">Register AI Provider</div>
            <div className="modal-sub">The API key is read from an environment variable — never stored in the database.</div>
            {addMutation.isError && <div className="error-msg">Registration failed.</div>}

            <div className="form-row">
              <label>Name *</label>
              <input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="e.g. Production AI Foundry" />
            </div>
            <div className="form-row">
              <label>Provider Type</label>
              <select value={form.providerType} onChange={e => setForm(f => ({ ...f, providerType: e.target.value as ProviderType }))}>
                {PROVIDER_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
              </select>
            </div>
            <div className="form-row">
              <label>Endpoint *</label>
              <input value={form.endpoint} onChange={e => setForm(f => ({ ...f, endpoint: e.target.value }))}
                placeholder="https://<resource>.openai.azure.com/" />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <div className="form-row">
                <label>Deployment Name *</label>
                <input value={form.deploymentName} onChange={e => setForm(f => ({ ...f, deploymentName: e.target.value }))} />
              </div>
              <div className="form-row">
                <label>API Version</label>
                <input value={form.apiVersion} onChange={e => setForm(f => ({ ...f, apiVersion: e.target.value }))} />
              </div>
            </div>
            <div className="form-row">
              <label>API Key Environment Variable</label>
              <input value={form.apiKeyEnvVar} onChange={e => setForm(f => ({ ...f, apiKeyEnvVar: e.target.value }))}
                placeholder="AI_FOUNDRY_API_KEY" />
            </div>
            <div className="form-row">
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
                <input type="checkbox" checked={form.isDefault} onChange={e => setForm(f => ({ ...f, isDefault: e.target.checked }))} />
                Set as default provider
              </label>
            </div>
            <div className="form-row">
              <label>Notes</label>
              <textarea value={form.notes} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))} rows={2} />
            </div>
            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setShowAdd(false)}>Cancel</button>
              <button className="btn btn-primary" disabled={addMutation.isPending || !form.name || !form.endpoint}
                onClick={() => addMutation.mutate(form)}>
                {addMutation.isPending ? 'Saving…' : 'Register'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
