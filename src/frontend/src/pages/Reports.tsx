import { useState, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { generateReport, getAiStatus, getProjects } from '../lib/api';
import type { ReportState } from '../types';

// ── Types ────────────────────────────────────────────────────────────────────

interface RiskItem {
  title: string;
  severity: 'High' | 'Medium' | 'Low';
  description: string;
}

interface ReportContent {
  executiveSummary: string;
  scopeSummary: { databaseCount: number; enginesFound: string[]; criticalCount: number };
  migrationReadiness: 'Ready' | 'NeedsWork' | 'NotReady';
  keyRisks: RiskItem[];
  recommendedWave: string;
  nextSteps: string[];
  estimatedEffort: string;
}

interface StoredReport {
  id: string;
  projectId: string;
  projectName: string;
  reportJson: string;
  parsedContent: ReportContent | null;
  generatedAt: string;
  state: ReportState;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

const LS_KEY = 'dbmr_reports';

function loadReports(): StoredReport[] {
  try { return JSON.parse(localStorage.getItem(LS_KEY) ?? '[]'); }
  catch { return []; }
}

function saveReports(reports: StoredReport[]) {
  localStorage.setItem(LS_KEY, JSON.stringify(reports));
}

/** Extract JSON from an AI response that may wrap it in markdown fences. */
function extractJson(raw: string): ReportContent | null {
  try {
    const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
    return JSON.parse(cleaned);
  } catch {
    try { return JSON.parse(raw); } catch { return null; }
  }
}

// ── Constants ────────────────────────────────────────────────────────────────

const REPORT_STATES: { state: ReportState; label: string; desc: string }[] = [
  { state: 'Pending',             label: 'Pending',              desc: 'Not yet generated.' },
  { state: 'AiGenerating',        label: 'Generating',           desc: 'AI processing.' },
  { state: 'DraftReady',          label: 'Draft Ready',          desc: 'Available for review.' },
  { state: 'InReview',            label: 'In Review',            desc: 'Active review.' },
  { state: 'Approved',            label: 'Approved',             desc: 'Sections signed off.' },
  { state: 'Exported',            label: 'Exported',             desc: 'Delivered.' },
];

const STATE_BADGE: Record<ReportState, string> = {
  Pending: 'badge-gray', QuestionnaireActive: 'badge-blue', BundleReady: 'badge-blue',
  AiGenerating: 'badge-purple', DraftReady: 'badge-yellow', InReview: 'badge-yellow',
  Approved: 'badge-green', Exported: 'badge-green',
};

const READINESS_BADGE: Record<string, string> = {
  Ready: 'badge-green', NeedsWork: 'badge-yellow', NotReady: 'badge-red',
};

const EFFORT_BADGE: Record<string, string> = {
  Low: 'badge-green', Medium: 'badge-blue', High: 'badge-yellow', 'Very High': 'badge-red',
};

const RISK_BADGE: Record<string, string> = {
  High: 'badge-red', Medium: 'badge-yellow', Low: 'badge-green',
};

// ── Component ────────────────────────────────────────────────────────────────

export default function Reports() {
  const [reports, setReports] = useState<StoredReport[]>(loadReports);
  const [showGenModal, setShowGenModal] = useState(false);
  const [genProjectId, setGenProjectId] = useState('');
  const [generating, setGenerating] = useState(false);
  const [genError, setGenError] = useState<string | null>(null);
  const [viewReport, setViewReport] = useState<StoredReport | null>(null);

  const projects = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const aiStatus = useQuery({ queryKey: ['aiStatus'], queryFn: getAiStatus });

  const mutateReports = useCallback((updater: (prev: StoredReport[]) => StoredReport[]) => {
    setReports(prev => {
      const next = updater(prev);
      saveReports(next);
      return next;
    });
  }, []);

  // ── Generate ──────────────────────────────────────────────────────────────

  const handleGenerate = async () => {
    if (!genProjectId || !aiStatus.data?.readyForReporting) return;
    const project = projects.data?.find(p => p.projectId === genProjectId);
    if (!project) return;

    setGenError(null);
    setGenerating(true);

    // Optimistically add a "generating" row
    const tempId = crypto.randomUUID();
    const tempReport: StoredReport = {
      id: tempId, projectId: genProjectId, projectName: project.name,
      reportJson: '', parsedContent: null,
      generatedAt: new Date().toISOString(), state: 'AiGenerating',
    };
    mutateReports(prev => [tempReport, ...prev]);

    try {
      const result = await generateReport(genProjectId);
      const parsed = extractJson(result.reportJson);

      mutateReports(prev => prev.map(r =>
        r.id === tempId
          ? { ...r, reportJson: result.reportJson, parsedContent: parsed, generatedAt: result.generatedAt, state: 'DraftReady' }
          : r
      ));
      setShowGenModal(false);
      setGenProjectId('');
    } catch (err: unknown) {
      mutateReports(prev => prev.filter(r => r.id !== tempId));
      const msg = (err as { response?: { data?: { error?: string } }; message?: string })
        ?.response?.data?.error
        ?? (err as { message?: string })?.message
        ?? 'Report generation failed.';
      setGenError(msg);
    } finally {
      setGenerating(false);
    }
  };

  // ── State transitions ─────────────────────────────────────────────────────

  const advanceState = (id: string, next: ReportState) => {
    mutateReports(prev => prev.map(r => r.id === id ? { ...r, state: next } : r));
    setViewReport(prev => prev?.id === id ? { ...prev, state: next } : prev);
  };

  const deleteReport = (id: string) => {
    mutateReports(prev => prev.filter(r => r.id !== id));
    if (viewReport?.id === id) setViewReport(null);
  };

  const exportReport = (report: StoredReport) => {
    const blob = new Blob([JSON.stringify({ ...report, parsedContent: report.parsedContent }, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url;
    a.download = `report-${report.projectName.replace(/\s+/g, '-')}-${report.generatedAt.slice(0, 10)}.json`;
    a.click(); URL.revokeObjectURL(url);
    advanceState(report.id, 'Exported');
  };

  // ── Render ────────────────────────────────────────────────────────────────

  const aiAvailable = aiStatus.data?.available ?? false;
  const readyForReporting = aiStatus.data?.readyForReporting ?? false;

  return (
    <div>
      <div className="page-header">
        <h2>Reports</h2>
        <button className="btn btn-primary" onClick={() => { setShowGenModal(true); setGenError(null); }}>
          + Generate Report
        </button>
      </div>

      {/* AI reporting prerequisite */}
      {aiStatus.isSuccess && !readyForReporting && (
        <div className="warn-msg" style={{ marginBottom: 20 }}>
          {aiAvailable
            ? <>Microsoft Foundry must pass a connection test before reports can be generated. Open <a href="/ai-settings">AI Settings</a> to test it.</>
            : <>Microsoft Foundry is required for report generation. Configure it in <a href="/ai-settings">AI Settings</a>.</>}
        </div>
      )}

      {/* State machine bar */}
      <div className="card" style={{ marginBottom: 20 }}>
        <div className="card-title">Report Workflow</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 0, overflowX: 'auto', paddingBottom: 4 }}>
          {REPORT_STATES.map((s, i) => {
            const active = viewReport?.state === s.state;
            return (
              <div key={s.state} style={{ display: 'flex', alignItems: 'center' }}>
                <div style={{
                  textAlign: 'center', minWidth: 110, padding: '6px 8px',
                  borderRadius: 'var(--radius)',
                  background: active ? 'var(--accent-50)' : 'transparent',
                  border: active ? '1px solid var(--accent-100)' : '1px solid transparent',
                }}>
                  <div style={{ fontSize: 11, fontWeight: 700, color: active ? 'var(--accent-600)' : 'var(--text-muted)', marginBottom: 3 }}>{s.label}</div>
                  <div style={{ fontSize: 10, color: 'var(--text-muted)', lineHeight: 1.3 }}>{s.desc}</div>
                </div>
                {i < REPORT_STATES.length - 1 && (
                  <div style={{ color: 'var(--border)', fontSize: 18, flexShrink: 0, padding: '0 2px' }}>›</div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Reports table */}
      <div className="card">
        {reports.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">📋</div>
            <p>No reports yet.<br />Select a project and click <strong>Generate Report</strong> to create one.</p>
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>Project</th><th>State</th><th>Readiness</th>
                <th>Effort</th><th>Generated</th><th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {reports.map(r => (
                <tr key={r.id}>
                  <td><strong>{r.projectName}</strong></td>
                  <td><span className={`badge ${STATE_BADGE[r.state]}`}>{r.state}</span></td>
                  <td>
                    {r.parsedContent ? (
                      <span className={`badge ${READINESS_BADGE[r.parsedContent.migrationReadiness] ?? 'badge-gray'}`}>
                        {r.parsedContent.migrationReadiness}
                      </span>
                    ) : '—'}
                  </td>
                  <td>
                    {r.parsedContent ? (
                      <span className={`badge ${EFFORT_BADGE[r.parsedContent.estimatedEffort] ?? 'badge-gray'}`}>
                        {r.parsedContent.estimatedEffort}
                      </span>
                    ) : '—'}
                  </td>
                  <td style={{ color: 'var(--text-muted)', fontSize: 12 }}>
                    {new Date(r.generatedAt).toLocaleString()}
                  </td>
                  <td>
                    <div style={{ display: 'flex', gap: 6 }}>
                      {r.parsedContent && (
                        <button className="btn btn-secondary btn-sm" onClick={() => setViewReport(r)}>View</button>
                      )}
                      {r.state === 'DraftReady' && (
                        <button className="btn btn-secondary btn-sm" onClick={() => advanceState(r.id, 'InReview')}>
                          Send for Review
                        </button>
                      )}
                      {r.state === 'InReview' && (
                        <button className="btn btn-primary btn-sm" onClick={() => advanceState(r.id, 'Approved')}>
                          Approve
                        </button>
                      )}
                      {r.state === 'Approved' && (
                        <button className="btn btn-secondary btn-sm" onClick={() => exportReport(r)}>
                          Export JSON
                        </button>
                      )}
                      <button className="btn btn-danger btn-sm" onClick={() => deleteReport(r.id)}>✕</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* ── Generate modal ─────────────────────────────────────────────────── */}
      {showGenModal && (
        <div className="modal-overlay" onClick={() => !generating && setShowGenModal(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <p className="modal-title">Generate Assessment Report</p>
            <p className="modal-sub">AI will synthesise discovery agent results, evidence files, and database inventory into a migration readiness report.</p>

            {genError && <div className="error-msg">{genError}</div>}

            <div className="form-row">
              <label>Project</label>
              <select value={genProjectId} onChange={e => setGenProjectId(e.target.value)} disabled={generating}>
                <option value="">— select a project —</option>
                {(projects.data ?? []).map(p => (
                  <option key={p.projectId} value={p.projectId}>{p.name}</option>
                ))}
              </select>
            </div>

            {!readyForReporting && (
              <div className="warn-msg" style={{ marginTop: 8 }}>
                {aiAvailable
                  ? <>Microsoft Foundry must pass a connection test. Test it in <a href="/ai-settings">AI Settings</a> first.</>
                  : <>Microsoft Foundry is required. Configure it in <a href="/ai-settings">AI Settings</a> first.</>}
              </div>
            )}

            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setShowGenModal(false)} disabled={generating}>Cancel</button>
              <button
                className="btn btn-primary"
                onClick={handleGenerate}
                disabled={!genProjectId || generating || !readyForReporting}
              >
                {generating ? 'Generating…' : 'Generate'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Report viewer ──────────────────────────────────────────────────── */}
      {viewReport && (
        <div className="modal-overlay" onClick={() => setViewReport(null)}>
          <div
            style={{
              width: '92vw', maxWidth: 860, maxHeight: '90vh', overflowY: 'auto',
              background: 'var(--surface)', borderRadius: 'var(--radius-xl)',
              padding: '36px 40px', boxShadow: 'var(--shadow-lg)', border: '1px solid var(--border)',
            }}
            onClick={e => e.stopPropagation()}
          >
            <ReportViewer report={viewReport} onClose={() => setViewReport(null)} />
          </div>
        </div>
      )}
    </div>
  );
}

// ── Report Viewer ─────────────────────────────────────────────────────────────

function ReportViewer({ report, onClose }: { report: StoredReport; onClose: () => void }) {
  const c = report.parsedContent;
  if (!c) return <p>No parsed content available.</p>;

  return (
    <div>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
        <div>
          <h2 style={{ fontSize: 20, fontWeight: 800, color: 'var(--text-primary)', marginBottom: 4 }}>
            {report.projectName}
          </h2>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
            <span className={`badge ${READINESS_BADGE[c.migrationReadiness] ?? 'badge-gray'}`}>
              {c.migrationReadiness}
            </span>
            <span className={`badge ${EFFORT_BADGE[c.estimatedEffort] ?? 'badge-gray'}`}>
              Effort: {c.estimatedEffort}
            </span>
            <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              Generated {new Date(report.generatedAt).toLocaleString()}
            </span>
          </div>
        </div>
        <button className="btn btn-ghost btn-sm" onClick={onClose} style={{ fontSize: 18, padding: '4px 10px' }}>✕</button>
      </div>

      <hr className="divider" />

      {/* Executive Summary */}
      <section style={{ marginBottom: 24 }}>
        <h3 style={sectionHead}>Executive Summary</h3>
        <p style={{ fontSize: 14, lineHeight: 1.75, color: 'var(--text-secondary)', whiteSpace: 'pre-wrap' }}>
          {c.executiveSummary}
        </p>
      </section>

      {/* Scope */}
      <section style={{ marginBottom: 24 }}>
        <h3 style={sectionHead}>Scope</h3>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
          <Metric label="Databases" value={String(c.scopeSummary?.databaseCount ?? '—')} />
          <Metric label="Critical" value={String(c.scopeSummary?.criticalCount ?? '—')} />
          <div style={metricCard}>
            <div style={metricLabel}>Engines</div>
            <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap', marginTop: 6 }}>
              {(c.scopeSummary?.enginesFound ?? []).map(e => (
                <span key={e} className="tag">{e}</span>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Key Risks */}
      {c.keyRisks?.length > 0 && (
        <section style={{ marginBottom: 24 }}>
          <h3 style={sectionHead}>Key Risks</h3>
          <table className="data-table">
            <thead>
              <tr><th>Risk</th><th>Severity</th><th>Description</th></tr>
            </thead>
            <tbody>
              {c.keyRisks.map((r, i) => (
                <tr key={i}>
                  <td><strong>{r.title}</strong></td>
                  <td><span className={`badge ${RISK_BADGE[r.severity] ?? 'badge-gray'}`}>{r.severity}</span></td>
                  <td style={{ color: 'var(--text-secondary)', fontSize: 13 }}>{r.description}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {/* Recommended Wave */}
      {c.recommendedWave && (
        <section style={{ marginBottom: 24 }}>
          <h3 style={sectionHead}>Recommended Migration Wave</h3>
          <p style={{ fontSize: 14, lineHeight: 1.75, color: 'var(--text-secondary)', whiteSpace: 'pre-wrap' }}>
            {c.recommendedWave}
          </p>
        </section>
      )}

      {/* Next Steps */}
      {c.nextSteps?.length > 0 && (
        <section style={{ marginBottom: 8 }}>
          <h3 style={sectionHead}>Next Steps</h3>
          <ol style={{ paddingLeft: 20, display: 'flex', flexDirection: 'column', gap: 6 }}>
            {c.nextSteps.map((s, i) => (
              <li key={i} style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>{s}</li>
            ))}
          </ol>
        </section>
      )}
    </div>
  );
}

// ── Small UI pieces ───────────────────────────────────────────────────────────

const sectionHead: React.CSSProperties = {
  fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.8px',
  color: 'var(--text-muted)', marginBottom: 12,
};

const metricCard: React.CSSProperties = {
  background: 'var(--surface-2)', border: '1px solid var(--border)',
  borderRadius: 'var(--radius)', padding: '12px 16px', minWidth: 120,
};

const metricLabel: React.CSSProperties = {
  fontSize: 11, fontWeight: 700, textTransform: 'uppercase',
  letterSpacing: '.6px', color: 'var(--text-muted)',
};

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div style={metricCard}>
      <div style={metricLabel}>{label}</div>
      <div style={{ fontSize: 26, fontWeight: 800, color: 'var(--text-primary)', marginTop: 4 }}>{value}</div>
    </div>
  );
}

