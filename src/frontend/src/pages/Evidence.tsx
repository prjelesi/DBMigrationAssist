import { useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { deleteEvidence, getEvidence, getEvidenceDetail, getProjects, reparseEvidence, uploadEvidence } from '../lib/api';
import type { EvidenceReport, ParseStatus, ReportSourceType } from '../types';

const PARSE_BADGE: Record<ParseStatus, string> = {
  Pending: 'badge-gray', Parsing: 'badge-blue', Parsed: 'badge-green',
  Failed: 'badge-red', ReviewRequired: 'badge-yellow',
};

const CONF_BADGE: Record<string, string> = {
  High: 'badge-green', Medium: 'badge-blue', Low: 'badge-yellow', Unverified: 'badge-gray',
};

const SOURCE_LABELS: Record<ReportSourceType, string> = {
  DmaJson: 'DMA Report', Awr: 'Oracle AWR', Statspack: 'Oracle Statspack',
  AzureMigrate: 'Azure Migrate', CsvGeneric: 'CSV', JsonGeneric: 'JSON', Other: 'Other',
};

const SOURCE_TYPES: ReportSourceType[] = ['DmaJson', 'Awr', 'Statspack', 'AzureMigrate', 'CsvGeneric', 'JsonGeneric', 'Other'];

const formatBytes = (b: number) =>
  b < 1024 ? `${b} B` : b < 1_048_576 ? `${(b / 1024).toFixed(1)} KB` : `${(b / 1_048_576).toFixed(1)} MB`;

export default function Evidence() {
  const qc = useQueryClient();
  const fileRef = useRef<HTMLInputElement>(null);
  const [selectedProject, setSelectedProject] = useState('');
  const [dragOver, setDragOver] = useState(false);
  const [detailId, setDetailId] = useState<string | null>(null);
  const [uploadForm, setUploadForm] = useState({ uploadedBy: 'admin', sourceType: 'Other' as ReportSourceType });

  const projects = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const reports = useQuery({
    queryKey: ['evidence', selectedProject],
    queryFn: () => getEvidence(selectedProject),
    enabled: !!selectedProject,
  });
  const detail = useQuery({
    queryKey: ['evidenceDetail', detailId],
    queryFn: () => getEvidenceDetail(detailId!),
    enabled: !!detailId,
  });

  const uploadMutation = useMutation({
    mutationFn: (file: File) => uploadEvidence(selectedProject, uploadForm.uploadedBy, uploadForm.sourceType, file),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['evidence', selectedProject] }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteEvidence,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['evidence', selectedProject] });
      if (detailId) setDetailId(null);
    },
  });

  const reparseMutation = useMutation({
    mutationFn: reparseEvidence,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['evidence', selectedProject] });
      if (detailId) qc.invalidateQueries({ queryKey: ['evidenceDetail', detailId] });
    },
  });

  const handleFiles = (files: FileList | null) => {
    if (!files || !selectedProject) return;
    Array.from(files).forEach(f => uploadMutation.mutate(f));
  };

  return (
    <div>
      <div className="page-header"><h2>Evidence Library</h2></div>

      {/* Project + upload config */}
      <div className="filter-bar" style={{ flexDirection: 'column', gap: 12, alignItems: 'stretch' }}>
        <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
          <div className="form-row" style={{ marginBottom: 0, minWidth: 260 }}>
            <label>Project</label>
            <select value={selectedProject} onChange={e => { setSelectedProject(e.target.value); setDetailId(null); }}>
              <option value="">Choose a project…</option>
              {projects.data?.map(p => <option key={p.projectId} value={p.projectId}>{p.name}</option>)}
            </select>
          </div>
          <div className="form-row" style={{ marginBottom: 0, minWidth: 180 }}>
            <label>Source Type (hint)</label>
            <select value={uploadForm.sourceType}
              onChange={e => setUploadForm(f => ({ ...f, sourceType: e.target.value as ReportSourceType }))}>
              {SOURCE_TYPES.map(t => <option key={t} value={t}>{SOURCE_LABELS[t]}</option>)}
            </select>
          </div>
          <div className="form-row" style={{ marginBottom: 0, minWidth: 180 }}>
            <label>Uploaded By</label>
            <input value={uploadForm.uploadedBy}
              onChange={e => setUploadForm(f => ({ ...f, uploadedBy: e.target.value }))} />
          </div>
        </div>
      </div>

      {/* Drop zone */}
      <div
        onClick={() => selectedProject && fileRef.current?.click()}
        onDragOver={e => { e.preventDefault(); setDragOver(true); }}
        onDragLeave={() => setDragOver(false)}
        onDrop={e => { e.preventDefault(); setDragOver(false); handleFiles(e.dataTransfer.files); }}
        style={{
          border: `2px dashed ${dragOver ? 'var(--accent-500)' : 'var(--border)'}`,
          borderRadius: 'var(--radius-lg)',
          padding: '32px 24px',
          textAlign: 'center',
          background: dragOver ? 'var(--accent-50)' : 'var(--surface)',
          cursor: selectedProject ? 'pointer' : 'not-allowed',
          opacity: selectedProject ? 1 : 0.5,
          marginBottom: 20,
          transition: 'all .15s',
        }}
      >
        <div style={{ fontSize: 32, marginBottom: 10 }}>📂</div>
        <div style={{ fontWeight: 600, fontSize: 14, marginBottom: 4 }}>
          {uploadMutation.isPending ? 'Uploading and parsing…' : 'Drop files here or click to browse'}
        </div>
        <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
          Supports: DMA JSON, AWR HTML/TXT, Statspack TXT, Azure Migrate JSON, CSV, JSON — max 50 MB
        </div>
        {!selectedProject && <div style={{ fontSize: 12, color: 'var(--amber-text)', marginTop: 8 }}>Select a project first</div>}
      </div>
      <input ref={fileRef} type="file" multiple style={{ display: 'none' }}
        accept=".json,.csv,.txt,.html,.xlsx"
        onChange={e => handleFiles(e.target.files)} />

      {uploadMutation.isError && (
        <div className="error-msg">Upload failed. Check the file and try again.</div>
      )}

      {/* Evidence list + detail panel */}
      <div style={{ display: 'grid', gridTemplateColumns: detailId ? '1fr 380px' : '1fr', gap: 20 }}>
        <div className="card">
          <div className="card-header">
            <span className="card-title">Uploaded Reports</span>
            <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>{reports.data?.length ?? 0} files</span>
          </div>
          {reports.isLoading && <div className="loading" />}
          {!selectedProject && <div className="empty-state"><p>Select a project to view evidence.</p></div>}
          {selectedProject && !reports.isLoading && (reports.data?.length ?? 0) === 0 && (
            <div className="empty-state">
              <div className="empty-state-icon">📂</div>
              <p>No evidence uploaded yet.<br />Drop files in the zone above.</p>
            </div>
          )}
          {(reports.data?.length ?? 0) > 0 && (
            <table className="data-table">
              <thead>
                <tr><th>File</th><th>Source</th><th>Size</th><th>Parse</th><th>Confidence</th><th>Uploaded</th><th></th></tr>
              </thead>
              <tbody>
                {reports.data?.map((r: EvidenceReport) => (
                  <tr key={r.reportId} style={{ background: detailId === r.reportId ? 'var(--accent-50)' : undefined }}>
                    <td>
                      <button className="btn btn-ghost" style={{ padding: '2px 0', fontWeight: 600, fontSize: 13 }}
                        onClick={() => setDetailId(detailId === r.reportId ? null : r.reportId)}>
                        {r.fileName}
                      </button>
                    </td>
                    <td><span className="badge badge-indigo">{SOURCE_LABELS[r.sourceType] ?? r.sourceType}</span></td>
                    <td style={{ color: 'var(--text-muted)', fontSize: 12.5 }}>{formatBytes(r.fileSizeBytes)}</td>
                    <td><span className={`badge ${PARSE_BADGE[r.parseStatus]}`}>{r.parseStatus}</span></td>
                    <td><span className={`badge ${CONF_BADGE[r.parseConfidence] ?? 'badge-gray'}`}>{r.parseConfidence}</span></td>
                    <td style={{ color: 'var(--text-muted)', fontSize: 12 }}>{new Date(r.uploadedAt).toLocaleDateString()}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 6 }}>
                        {(r.parseStatus === 'Failed' || r.parseStatus === 'ReviewRequired') && (
                          <button className="btn btn-secondary btn-sm"
                            disabled={reparseMutation.isPending}
                            onClick={() => reparseMutation.mutate(r.reportId)}>
                            ↻
                          </button>
                        )}
                        <button className="btn btn-danger btn-sm"
                          disabled={deleteMutation.isPending}
                          onClick={() => {
                            if (confirm(`Delete "${r.fileName}"?`)) deleteMutation.mutate(r.reportId);
                          }}>
                          ✕
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* Detail panel */}
        {detailId && (
          <div className="card" style={{ alignSelf: 'start' }}>
            <div className="card-header">
              <span className="card-title">Parse Summary</span>
              <button className="btn btn-ghost btn-sm" onClick={() => setDetailId(null)}>✕</button>
            </div>
            {detail.isLoading && <div className="loading" />}
            {detail.data && (() => {
              const r = detail.data;
              const summary = r.parseSummaryJson
                ? JSON.parse(r.parseSummaryJson) as Record<string, unknown>
                : null;
              return (
                <>
                  <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 12, wordBreak: 'break-all' }}>{r.fileName}</div>

                  {r.parseErrorMessage && (
                    <div className="error-msg" style={{ marginBottom: 12 }}>{r.parseErrorMessage}</div>
                  )}

                  {summary && (
                    <table style={{ width: '100%', fontSize: 12.5, borderCollapse: 'collapse' }}>
                      <tbody>
                        {Object.entries(summary).map(([k, v]) => (
                          <tr key={k} style={{ borderBottom: '1px solid var(--border-light)' }}>
                            <td style={{ padding: '7px 4px', fontWeight: 600, color: 'var(--text-muted)', whiteSpace: 'nowrap', paddingRight: 12 }}>
                              {k.replace(/([A-Z])/g, ' $1').trim()}
                            </td>
                            <td style={{ padding: '7px 4px', color: 'var(--text-primary)', wordBreak: 'break-all' }}>
                              {Array.isArray(v) ? (v as string[]).join(', ') || '—' : String(v)}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}

                  <div className="divider" />
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                    <div>Hash: <span style={{ fontFamily: 'monospace' }}>{r.fileHash?.slice(0, 16)}…</span></div>
                    <div>By: {r.uploadedBy} · {new Date(r.uploadedAt).toLocaleString()}</div>
                  </div>
                </>
              );
            })()}
          </div>
        )}
      </div>
    </div>
  );
}
