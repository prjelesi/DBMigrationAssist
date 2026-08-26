import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { AxiosError } from 'axios';
import { ArrowDownload20Regular, ArrowUpload20Regular, Delete20Regular } from '@fluentui/react-icons';
import {
  createDatabase, deleteDatabase, downloadDatabaseImportTemplate, downloadOfflineAssessmentScript,
  getDatabases, getEnvironments, getProjects, importDatabases, uploadOfflineAssessmentResult,
} from '../lib/api';
import type { DatabaseImportErrorResponse } from '../lib/api';
import type { Criticality, DatabaseInstance, EngineType } from '../types';

const ENGINES: EngineType[] = ['Oracle', 'PostgreSQL', 'SqlServer', 'MySQL', 'MongoDB', 'Cassandra', 'Sybase'];
const DEFAULT_PORTS: Partial<Record<EngineType, number>> = {
  Oracle: 1521, PostgreSQL: 5432, SqlServer: 1433, MySQL: 3306,
  MongoDB: 27017, Cassandra: 9042, Sybase: 5000,
};

type FormState = {
  name: string; environmentId: string; engine: EngineType; version: string;
  hostName: string; port: string; criticality: Criticality; ownerName: string;
};

const EMPTY_FORM: FormState = {
  name: '', environmentId: '', engine: 'PostgreSQL', version: '',
  hostName: '', port: '5432', criticality: 'Medium', ownerName: '',
};

const ENGINE_BADGE: Record<string, string> = {
  Oracle: 'badge-red', PostgreSQL: 'badge-blue', SqlServer: 'badge-purple',
  MySQL: 'badge-green', MongoDB: 'badge-yellow', Cassandra: 'badge-gray', Sybase: 'badge-gray', Unknown: 'badge-gray',
};

const CRIT_BADGE: Record<string, string> = {
  Critical: 'badge-red', High: 'badge-yellow', Medium: 'badge-blue', Low: 'badge-gray',
};

export default function Inventory() {
  const qc = useQueryClient();
  const [selectedProject, setSelectedProject] = useState('');
  const [engineFilter, setEngineFilter] = useState<EngineType | ''>('');
  const [critFilter, setCritFilter] = useState<Criticality | ''>('');
  const [search, setSearch] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [showImport, setShowImport] = useState(false);
  const [importFile, setImportFile] = useState<File | null>(null);
  const [uploadTarget, setUploadTarget] = useState<DatabaseInstance | null>(null);
  const [resultFile, setResultFile] = useState<File | null>(null);
  const [downloadError, setDownloadError] = useState<string | null>(null);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [form, setForm] = useState<FormState>(EMPTY_FORM);
  const [formError, setFormError] = useState<string | null>(null);

  const projects = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const databases = useQuery({
    queryKey: ['databases', selectedProject],
    queryFn: () => getDatabases(selectedProject),
    enabled: !!selectedProject,
  });
  const environments = useQuery({
    queryKey: ['environments', selectedProject],
    queryFn: () => getEnvironments(selectedProject),
    enabled: !!selectedProject,
  });

  const createMutation = useMutation({
    mutationFn: () => createDatabase({
      projectId: selectedProject,
      environmentId: form.environmentId || undefined,
      name: form.name.trim(),
      engine: form.engine,
      version: form.version.trim() || undefined,
      hostName: form.hostName.trim() || undefined,
      port: form.port ? Number(form.port) : undefined,
      criticality: form.criticality,
      ownerName: form.ownerName.trim() || undefined,
    }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['databases', selectedProject] });
      setShowCreate(false);
    },
    onError: () => setFormError('Failed to add the database. Check the values and try again.'),
  });

  const importMutation = useMutation({
    mutationFn: (file: File) => importDatabases(selectedProject, file),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['databases', selectedProject] }),
  });

  const uploadResultMutation = useMutation({
    mutationFn: ({ databaseId, file }: { databaseId: string; file: File }) =>
      uploadOfflineAssessmentResult(databaseId, file),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteDatabase,
    onMutate: () => setDeleteError(null),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['databases', selectedProject] }),
    onError: () => setDeleteError('Could not delete the database. Refresh the page and try again.'),
  });

  const openImport = () => {
    setImportFile(null);
    importMutation.reset();
    setShowImport(true);
  };

  const downloadTemplate = async () => {
    const blob = await downloadDatabaseImportTemplate();
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = 'database-inventory-import-template.xlsx';
    anchor.click();
    URL.revokeObjectURL(url);
  };

  const downloadAssessmentScript = async (database: DatabaseInstance) => {
    setDownloadError(null);
    try {
      const blob = await downloadOfflineAssessmentScript(database.databaseId);
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `collect-${database.name.replace(/[^a-z0-9._-]+/gi, '-')}-assessment.ps1`;
      anchor.click();
      URL.revokeObjectURL(url);
    } catch {
      setDownloadError(`Could not download the assessment script for ${database.name}.`);
    }
  };

  const openResultUpload = (database: DatabaseInstance) => {
    setUploadTarget(database);
    setResultFile(null);
    uploadResultMutation.reset();
  };

  const openCreate = () => {
    setForm(EMPTY_FORM);
    setFormError(null);
    setShowCreate(true);
  };

  const handleEngineChange = (engine: EngineType) => {
    setForm(current => ({ ...current, engine, port: String(DEFAULT_PORTS[engine] ?? '') }));
  };

  const handleCreate = () => {
    if (!form.name.trim()) { setFormError('Database name is required.'); return; }
    if (!form.hostName.trim()) { setFormError('Host name is required.'); return; }
    const port = Number(form.port);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      setFormError('Port must be a number between 1 and 65535.');
      return;
    }
    createMutation.mutate();
  };

  const filtered = (databases.data ?? []).filter(db => {
    if (engineFilter && db.engine !== engineFilter) return false;
    if (critFilter && db.criticality !== critFilter) return false;
    if (search && !db.name.toLowerCase().includes(search.toLowerCase()) &&
        !db.hostName?.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  return (
    <div>
      <div className="page-header">
        <h2>Database Inventory</h2>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="btn btn-secondary" disabled={!selectedProject} onClick={openImport}>
            Import Spreadsheet
          </button>
          <button className="btn btn-primary" disabled={!selectedProject} onClick={openCreate}>
            + Add Database
          </button>
        </div>
      </div>

      <div className="card" style={{ padding: '14px 20px', marginBottom: 20 }}>
        <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
          <div className="form-row" style={{ marginBottom: 0, minWidth: 220 }}>
            <label>Project</label>
            <select value={selectedProject} onChange={e => setSelectedProject(e.target.value)}>
              <option value="">Choose a project…</option>
              {projects.data?.map(p => <option key={p.projectId} value={p.projectId}>{p.name}</option>)}
            </select>
          </div>
          <div className="form-row" style={{ marginBottom: 0, minWidth: 160 }}>
            <label>Engine</label>
            <select value={engineFilter} onChange={e => setEngineFilter(e.target.value as EngineType | '')}>
              <option value="">All engines</option>
              {['Oracle','PostgreSQL','SqlServer','MySQL','MongoDB','Cassandra','Sybase'].map(e =>
                <option key={e} value={e}>{e}</option>)}
            </select>
          </div>
          <div className="form-row" style={{ marginBottom: 0, minWidth: 160 }}>
            <label>Criticality</label>
            <select value={critFilter} onChange={e => setCritFilter(e.target.value as Criticality | '')}>
              <option value="">All</option>
              {['Critical','High','Medium','Low'].map(c => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
          <div className="form-row" style={{ marginBottom: 0, flex: 1, minWidth: 200 }}>
            <label>Search</label>
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Name or host…" />
          </div>
        </div>
      </div>

      <div className="card">
        {downloadError && <div className="error-msg">{downloadError}</div>}
        {deleteError && <div className="error-msg">{deleteError}</div>}
        {databases.isLoading && <div className="loading">Loading…</div>}
        {!selectedProject && <div className="empty-state"><p>Select a project to view its inventory.</p></div>}
        {selectedProject && !databases.isLoading && filtered.length === 0 && (
          <div className="empty-state">
            <div className="empty-state-icon">🗄️</div>
            <p>No databases match your filters.<br />Click <strong>+ Add Database</strong> to create one.</p>
          </div>
        )}
        {filtered.length > 0 && (
          <table className="data-table">
            <thead>
              <tr><th>Name</th><th>Engine</th><th>Host</th><th>Port</th><th>Criticality</th><th>Owner</th><th>Actions</th></tr>
            </thead>
            <tbody>
              {filtered.map(db => (
                <tr key={db.databaseId}>
                  <td><strong>{db.name}</strong>{db.version && <span style={{ fontSize: 11, color: '#94a3b8', marginLeft: 6 }}>v{db.version}</span>}</td>
                  <td><span className={`badge ${ENGINE_BADGE[db.engine] ?? 'badge-gray'}`}>{db.engine}</span></td>
                  <td>{db.hostName ?? '—'}</td>
                  <td>{db.port ?? '—'}</td>
                  <td><span className={`badge ${CRIT_BADGE[db.criticality] ?? 'badge-gray'}`}>{db.criticality}</span></td>
                  <td>{db.ownerName ?? '—'}</td>
                  <td>
                    <div style={{ display: 'flex', gap: 6 }}>
                      <button type="button" className="btn btn-ghost btn-sm" title="Download offline assessment script"
                        aria-label={`Download assessment script for ${db.name}`} onClick={() => downloadAssessmentScript(db)}>
                        <ArrowDownload20Regular />
                      </button>
                      <button type="button" className="btn btn-ghost btn-sm" title="Upload offline assessment result"
                        aria-label={`Upload assessment result for ${db.name}`} onClick={() => openResultUpload(db)}>
                        <ArrowUpload20Regular />
                      </button>
                      <button type="button" className="btn btn-ghost btn-sm" title="Delete database from inventory"
                        aria-label={`Delete ${db.name} from inventory`} disabled={deleteMutation.isPending}
                        onClick={() => {
                          if (window.confirm(`Delete ${db.name} from this project's inventory? Assessment history will be preserved.`))
                            deleteMutation.mutate(db.databaseId);
                        }}>
                        <Delete20Regular />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showCreate && (
        <div className="modal-overlay" onClick={() => setShowCreate(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <p className="modal-title">Add Database</p>
            <p className="modal-sub">Register a source database in this project's inventory.</p>

            {formError && <div className="error-msg">{formError}</div>}

            <div className="form-row">
              <label>Database Name *</label>
              <input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                placeholder="e.g. commerce-orders-prod" autoFocus />
            </div>

            <div className="form-row">
              <label>Environment</label>
              <select value={form.environmentId} onChange={e => setForm(f => ({ ...f, environmentId: e.target.value }))}>
                <option value="">No environment</option>
                {environments.data?.map(env => <option key={env.environmentId} value={env.environmentId}>{env.name}</option>)}
              </select>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
              <div className="form-row">
                <label>Engine *</label>
                <select value={form.engine} onChange={e => handleEngineChange(e.target.value as EngineType)}>
                  {ENGINES.map(engine => <option key={engine} value={engine}>{engine}</option>)}
                </select>
              </div>
              <div className="form-row">
                <label>Version</label>
                <input value={form.version} onChange={e => setForm(f => ({ ...f, version: e.target.value }))}
                  placeholder="e.g. 16" />
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 14 }}>
              <div className="form-row">
                <label>Host Name *</label>
                <input value={form.hostName} onChange={e => setForm(f => ({ ...f, hostName: e.target.value }))}
                  placeholder="postgres or host.docker.internal" />
              </div>
              <div className="form-row">
                <label>Port *</label>
                <input type="number" min="1" max="65535" value={form.port}
                  onChange={e => setForm(f => ({ ...f, port: e.target.value }))} />
              </div>
            </div>

            <div className="form-row">
              <label>Criticality</label>
              <select value={form.criticality} onChange={e => setForm(f => ({ ...f, criticality: e.target.value as Criticality }))}>
                {['Critical', 'High', 'Medium', 'Low'].map(value => <option key={value} value={value}>{value}</option>)}
              </select>
            </div>

            <div className="form-row">
              <label>Owner</label>
              <input value={form.ownerName} onChange={e => setForm(f => ({ ...f, ownerName: e.target.value }))}
                placeholder="e.g. Digital Commerce Team" />
            </div>

            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setShowCreate(false)} disabled={createMutation.isPending}>Cancel</button>
              <button className="btn btn-primary" onClick={handleCreate} disabled={createMutation.isPending}>
                {createMutation.isPending ? 'Adding…' : 'Add Database'}
              </button>
            </div>
          </div>
        </div>
      )}

      {uploadTarget && (
        <div className="modal-overlay" onClick={() => setUploadTarget(null)}>
          <div className="modal" onClick={event => event.stopPropagation()}>
            <p className="modal-title">Upload Assessment Result</p>
            <p className="modal-sub">
              Attach the JSON returned by the offline collector to <strong>{uploadTarget.name}</strong>.
            </p>

            <div className="form-row">
              <label>Assessment result (.json) *</label>
              <input type="file" accept=".json,application/json" disabled={uploadResultMutation.isSuccess}
                onChange={event => {
                  setResultFile(event.target.files?.[0] ?? null);
                  uploadResultMutation.reset();
                }} />
            </div>

            {uploadResultMutation.isSuccess && (
              <div className="success-msg">
                Result uploaded and linked to {uploadTarget.name}.
              </div>
            )}

            {uploadResultMutation.isError && (
              <div className="error-msg">
                {(uploadResultMutation.error as AxiosError<{ message?: string }>).response?.data?.message ??
                  'The result could not be uploaded.'}
              </div>
            )}

            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setUploadTarget(null)} disabled={uploadResultMutation.isPending}>
                {uploadResultMutation.isSuccess ? 'Close' : 'Cancel'}
              </button>
              {!uploadResultMutation.isSuccess && (
                <button className="btn btn-primary" disabled={!resultFile || uploadResultMutation.isPending}
                  onClick={() => resultFile && uploadResultMutation.mutate({ databaseId: uploadTarget.databaseId, file: resultFile })}>
                  {uploadResultMutation.isPending ? 'Uploading…' : 'Upload Result'}
                </button>
              )}
            </div>
          </div>
        </div>
      )}

      {showImport && (
        <div className="modal-overlay" onClick={() => setShowImport(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <p className="modal-title">Import Database Inventory</p>
            <p className="modal-sub">Upload up to 1,000 databases from an Excel workbook. The import is cancelled if any row is invalid.</p>

            <button className="btn btn-secondary" onClick={downloadTemplate}>
              Download Excel Template
            </button>

            <div className="form-row" style={{ marginTop: 18 }}>
              <label>Completed Spreadsheet *</label>
              <input type="file" accept=".xlsx,.xls" onChange={e => {
                setImportFile(e.target.files?.[0] ?? null);
                importMutation.reset();
              }} />
            </div>

            {importMutation.isSuccess && (
              <div className="success-msg">Imported {importMutation.data.imported} database{importMutation.data.imported === 1 ? '' : 's'}.</div>
            )}

            {importMutation.isError && (() => {
              const response = (importMutation.error as AxiosError<DatabaseImportErrorResponse>).response?.data;
              return (
                <div className="error-msg">
                  <strong>{response?.message ?? 'Import failed.'}</strong>
                  {response?.errors?.map(error => <div key={`${error.row}-${error.message}`}>Row {error.row}: {error.message}</div>)}
                </div>
              );
            })()}

            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setShowImport(false)} disabled={importMutation.isPending}>
                {importMutation.isSuccess ? 'Close' : 'Cancel'}
              </button>
              {!importMutation.isSuccess && (
                <button className="btn btn-primary" disabled={!importFile || importMutation.isPending}
                  onClick={() => importFile && importMutation.mutate(importFile)}>
                  {importMutation.isPending ? 'Importing…' : 'Import Databases'}
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
