import { useState } from 'react';
import { useQueries, useQuery, useQueryClient } from '@tanstack/react-query';
import { generateReport, getAiStatus, getDatabases, getGeneratedReports, getProjects, transitionGeneratedReport } from '../lib/api';
import { parseReportContent } from '../lib/reportContent';
import type { ReportContent } from '../lib/reportContent';
import type { GeneratedReport, ReportState } from '../types';

// ── Types ────────────────────────────────────────────────────────────────────

interface ViewReport extends GeneratedReport {
  projectName: string;
  parsedContent: ReportContent | null;
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

const EVIDENCE_BADGE: Record<string, string> = {
  Confirmed: 'badge-green', Assumption: 'badge-yellow', Gap: 'badge-red',
};

const RECOMMENDATION_BADGE: Record<string, string> = {
  Preferred: 'badge-green', Candidate: 'badge-blue', 'Not Recommended': 'badge-gray',
};

// ── Component ────────────────────────────────────────────────────────────────

export default function Reports() {
  const [showGenModal, setShowGenModal] = useState(false);
  const [genProjectId, setGenProjectId] = useState('');
  const [genDatabaseId, setGenDatabaseId] = useState('');
  const [generating, setGenerating] = useState(false);
  const [genError, setGenError] = useState<string | null>(null);
  const [viewReport, setViewReport] = useState<ViewReport | null>(null);
  const queryClient = useQueryClient();

  const projects = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const generationDatabases = useQuery({
    queryKey: ['databases', genProjectId],
    queryFn: () => getDatabases(genProjectId),
    enabled: Boolean(genProjectId),
  });
  const aiStatus = useQuery({ queryKey: ['aiStatus'], queryFn: getAiStatus });
  const reportQueries = useQueries({
    queries: (projects.data ?? []).map(project => ({
      queryKey: ['reports', project.projectId],
      queryFn: () => getGeneratedReports(project.projectId),
    })),
  });
  const reports: ViewReport[] = reportQueries.flatMap((query, index) =>
    (query.data ?? []).map(report => ({
      ...report,
      projectName: projects.data?.[index]?.name ?? 'Unknown project',
      parsedContent: parseReportContent(report.reportJson),
    }))
  ).sort((left, right) => right.generatedAt.localeCompare(left.generatedAt));

  // ── Generate ──────────────────────────────────────────────────────────────

  const handleGenerate = async () => {
    if (!genProjectId || !aiStatus.data?.readyForReporting) return;
    const project = projects.data?.find(p => p.projectId === genProjectId);
    if (!project) return;

    setGenError(null);
    setGenerating(true);

    try {
      await generateReport(genProjectId, genDatabaseId || undefined);
      await queryClient.invalidateQueries({ queryKey: ['reports', genProjectId] });
      setShowGenModal(false);
      setGenProjectId('');
      setGenDatabaseId('');
    } catch (err: unknown) {
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

  const advanceState = async (report: ViewReport, next: ReportState) => {
    const updated = await transitionGeneratedReport(report.generatedReportId, next);
    await queryClient.invalidateQueries({ queryKey: ['reports', report.projectId] });
    setViewReport(prev => prev?.generatedReportId === report.generatedReportId
      ? { ...prev, ...updated }
      : prev);
  };

  const exportReport = async (report: ViewReport) => {
    const blob = new Blob([JSON.stringify({ ...report, parsedContent: report.parsedContent }, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url;
    a.download = `report-${report.projectName.replace(/\s+/g, '-')}-${report.generatedAt.slice(0, 10)}.json`;
    a.click(); URL.revokeObjectURL(url);
    await advanceState(report, 'Exported');
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
                <th>Project</th><th>Scope</th><th>State</th><th>Readiness</th>
                <th>Effort</th><th>Generated</th><th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {reports.map(r => (
                <tr key={r.generatedReportId}>
                  <td><strong>{r.projectName}</strong></td>
                  <td>{r.databaseId ? r.databaseName ?? 'Selected database' : 'Entire project'}</td>
                  <td><span className={`badge ${STATE_BADGE[r.state]}`}>{r.state}</span></td>
                  <td>
                    {r.parsedContent ? (
                      <span className={`badge ${READINESS_BADGE[r.parsedContent.migrationReadiness] ?? 'badge-gray'}`}>
                        {r.parsedContent.migrationReadiness}
                      </span>
                    ) : <span className="badge badge-red">Unavailable</span>}
                  </td>
                  <td>
                    {r.parsedContent ? (
                      <span className={`badge ${EFFORT_BADGE[r.parsedContent.estimatedEffort] ?? 'badge-gray'}`}>
                        {r.parsedContent.estimatedEffort}
                      </span>
                    ) : <span style={{ color: 'var(--text-muted)', fontSize: 12 }}>Invalid data</span>}
                  </td>
                  <td style={{ color: 'var(--text-muted)', fontSize: 12 }}>
                    {new Date(r.generatedAt).toLocaleString()}
                  </td>
                  <td>
                    <div style={{ display: 'flex', gap: 6 }}>
                      {r.parsedContent && (
                        <button className="btn btn-secondary btn-sm" onClick={() => setViewReport(r)}>View</button>
                      )}
                      {!r.parsedContent && (
                        <span style={{ color: 'var(--text-muted)', fontSize: 12 }}>Report unavailable</span>
                      )}
                      {r.parsedContent && r.state === 'DraftReady' && (
                        <button className="btn btn-secondary btn-sm" onClick={() => void advanceState(r, 'InReview')}>
                          Send for Review
                        </button>
                      )}
                      {r.parsedContent && r.state === 'InReview' && (
                        <button className="btn btn-primary btn-sm" onClick={() => void advanceState(r, 'Approved')}>
                          Approve
                        </button>
                      )}
                      {r.parsedContent && r.state === 'Approved' && (
                        <button className="btn btn-secondary btn-sm" onClick={() => void exportReport(r)}>
                          Export JSON
                        </button>
                      )}
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
              <select value={genProjectId} onChange={e => { setGenProjectId(e.target.value); setGenDatabaseId(''); }} disabled={generating}>
                <option value="">— select a project —</option>
                {(projects.data ?? []).map(p => (
                  <option key={p.projectId} value={p.projectId}>{p.name}</option>
                ))}
              </select>
            </div>

            <div className="form-row">
              <label>Report scope</label>
              <select
                value={genDatabaseId}
                onChange={e => setGenDatabaseId(e.target.value)}
                disabled={generating || !genProjectId || generationDatabases.isLoading}
              >
                <option value="">Entire project</option>
                {(generationDatabases.data ?? []).map(database => (
                  <option key={database.databaseId} value={database.databaseId}>
                    {database.name} ({database.engine}{database.version ? ` ${database.version}` : ''})
                  </option>
                ))}
              </select>
              <span className="form-hint">
                A database report includes database-tagged and project-wide evidence. Questionnaires remain shared project context.
              </span>
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

function ReportViewer({ report, onClose }: { report: ViewReport; onClose: () => void }) {
  const c = report.parsedContent;
  if (!c) return <p>No parsed content available.</p>;

  return (
    <div>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
        <div>
          <h2 style={{ fontSize: 20, fontWeight: 800, color: 'var(--text-primary)', marginBottom: 4 }}>
            {report.projectName}{report.databaseId ? ` — ${report.databaseName ?? 'Database'}` : ''}
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

      {/* Migration Requirements */}
      {(c.migrationRequirements?.length ?? 0) > 0 && (
        <section style={{ marginBottom: 24 }}>
          <h3 style={sectionHead}>Migration Requirements</h3>
          <table className="data-table">
            <thead>
              <tr><th>Category</th><th>Requirement</th><th>Evidence</th><th>Details</th></tr>
            </thead>
            <tbody>
              {c.migrationRequirements!.map((item, i) => (
                <tr key={i}>
                  <td><strong>{item.category}</strong></td>
                  <td>{item.requirement}</td>
                  <td><span className={`badge ${EVIDENCE_BADGE[item.evidenceStatus] ?? 'badge-gray'}`}>{item.evidenceStatus}</span></td>
                  <td style={{ color: 'var(--text-secondary)', fontSize: 13 }}>{item.details}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {/* Source Environment Details */}
      {c.sourceEnvironment && (
        <section style={{ marginBottom: 24 }}>
          <h3 style={sectionHead}>Source Environment Details</h3>
          <p style={bodyCopy}>{c.sourceEnvironment.summary}</p>

          {(c.sourceEnvironment.environments?.length ?? 0) > 0 && (
            <table className="data-table" style={{ marginTop: 12 }}>
              <thead>
                <tr><th>Environment</th><th>Type</th><th>Location</th><th>Connectivity</th><th>Databases</th></tr>
              </thead>
              <tbody>
                {c.sourceEnvironment.environments.map((environment, i) => (
                  <tr key={i}>
                    <td><strong>{environment.name}</strong></td>
                    <td>{environment.type || 'Not provided'}</td>
                    <td>{environment.location || 'Not provided'}</td>
                    <td>{environment.connectivity || 'Not provided'}</td>
                    <td>{environment.databaseCount}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          {(c.sourceEnvironment.databaseEstate?.length ?? 0) > 0 && (
            <table className="data-table" style={{ marginTop: 12 }}>
              <thead>
                <tr><th>Database</th><th>Engine / Version</th><th>Host</th><th>Criticality</th><th>Environment</th></tr>
              </thead>
              <tbody>
                {c.sourceEnvironment.databaseEstate.map((database, i) => (
                  <tr key={i}>
                    <td><strong>{database.name}</strong></td>
                    <td>{database.engine}{database.version ? ` ${database.version}` : ''}</td>
                    <td>{database.host || 'Not provided'}</td>
                    <td>{database.criticality}</td>
                    <td>{database.environment || 'Not assigned'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: 12, marginTop: 12 }}>
            <DetailList title="Known Dependencies" items={c.sourceEnvironment.dependencies ?? []} emptyText="No dependencies confirmed in the evidence." />
            <DetailList title="Information Gaps" items={c.sourceEnvironment.informationGaps ?? []} emptyText="No information gaps reported." warning />
          </div>
        </section>
      )}

      {/* Possible Migrations */}
      {(c.possibleMigrations?.length ?? 0) > 0 && (
        <section style={{ marginBottom: 24 }}>
          <h3 style={sectionHead}>Possible Migrations</h3>
          <table className="data-table">
            <thead>
              <tr><th>Source</th><th>Azure Target</th><th>Type</th><th>Position</th><th>Rationale and Considerations</th></tr>
            </thead>
            <tbody>
              {c.possibleMigrations!.map((option, i) => (
                <tr key={i}>
                  <td><strong>{option.sourcePlatform}</strong></td>
                  <td>{option.targetAzureService}</td>
                  <td>{option.migrationType}</td>
                  <td><span className={`badge ${RECOMMENDATION_BADGE[option.recommendation] ?? 'badge-gray'}`}>{option.recommendation}</span></td>
                  <td style={{ color: 'var(--text-secondary)', fontSize: 13 }}>
                    {option.rationale}
                    {(option.considerations?.length ?? 0) > 0 && (
                      <ul style={{ margin: '6px 0 0', paddingLeft: 18 }}>
                        {option.considerations.map((item, index) => <li key={index}>{item}</li>)}
                      </ul>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {/* Migration Tooling */}
      {(c.migrationTooling?.length ?? 0) > 0 && (
        <section style={{ marginBottom: 24 }}>
          <h3 style={sectionHead}>Migration Tooling</h3>
          <table className="data-table">
            <thead>
              <tr><th>Phase</th><th>Tools</th><th>Purpose</th><th>Prerequisites</th></tr>
            </thead>
            <tbody>
              {c.migrationTooling!.map((item, i) => (
                <tr key={i}>
                  <td><strong>{item.phase}</strong></td>
                  <td>{(item.tools ?? []).join(', ')}</td>
                  <td style={{ color: 'var(--text-secondary)', fontSize: 13 }}>{item.purpose}</td>
                  <td style={{ color: 'var(--text-secondary)', fontSize: 13 }}>{(item.prerequisites ?? []).join('; ') || 'None stated'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {/* Azure SKU Environment Proposal */}
      {(c.azureSkuProposal?.length ?? 0) > 0 && (
        <section style={{ marginBottom: 24 }}>
          <h3 style={sectionHead}>SKU Environment Proposal for Azure</h3>
          <div className="warn-msg" style={{ marginBottom: 12 }}>
            Preliminary sizing only. Validate with measured utilization, performance benchmarks, availability requirements, region availability, and current Azure pricing before approval.
          </div>
          {c.azureSkuProposal!.map((proposal, i) => (
            <div key={i} style={{ ...detailCard, marginBottom: 12 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap', marginBottom: 10 }}>
                <strong style={{ color: 'var(--text-primary)' }}>{proposal.environment}</strong>
                <span className="tag">{proposal.targetService} · {proposal.skuTier}</span>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))', gap: 10 }}>
                <ProposalField label="Compute" value={proposal.compute} />
                <ProposalField label="Storage" value={proposal.storage} />
                <ProposalField label="Availability" value={proposal.availability} />
                <ProposalField label="Networking" value={proposal.networking} />
              </div>
              <p style={{ ...bodyCopy, marginTop: 12 }}><strong>Rationale:</strong> {proposal.rationale}</p>
              <p style={{ ...bodyCopy, marginTop: 6 }}><strong>Sizing basis:</strong> {proposal.sizingBasis}</p>
              {(proposal.assumptions?.length ?? 0) > 0 && (
                <DetailList title="Sizing Assumptions" items={proposal.assumptions} emptyText="No assumptions stated." warning />
              )}
            </div>
          ))}
        </section>
      )}

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

const bodyCopy: React.CSSProperties = {
  fontSize: 14, lineHeight: 1.65, color: 'var(--text-secondary)', margin: 0,
};

const detailCard: React.CSSProperties = {
  background: 'var(--surface-2)', border: '1px solid var(--border)',
  borderRadius: 'var(--radius)', padding: '14px 16px',
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

function DetailList({ title, items, emptyText, warning = false }: {
  title: string;
  items: string[];
  emptyText: string;
  warning?: boolean;
}) {
  return (
    <div style={{ ...detailCard, borderColor: warning && items.length > 0 ? '#fde68a' : 'var(--border)' }}>
      <div style={metricLabel}>{title}</div>
      {items.length > 0 ? (
        <ul style={{ margin: '8px 0 0', paddingLeft: 18, color: 'var(--text-secondary)', fontSize: 13, lineHeight: 1.6 }}>
          {items.map((item, index) => <li key={index}>{item}</li>)}
        </ul>
      ) : (
        <p style={{ ...bodyCopy, fontSize: 13, marginTop: 8 }}>{emptyText}</p>
      )}
    </div>
  );
}

function ProposalField({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div style={metricLabel}>{label}</div>
      <div style={{ color: 'var(--text-secondary)', fontSize: 13, lineHeight: 1.5, marginTop: 4 }}>
        {value || 'Not specified'}
      </div>
    </div>
  );
}

