import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getDatabases, getProjects } from '../lib/api';
import type { Criticality, EngineType } from '../types';

const ENGINE_BADGE: Record<string, string> = {
  Oracle: 'badge-red', PostgreSQL: 'badge-blue', SqlServer: 'badge-purple',
  MySQL: 'badge-green', MongoDB: 'badge-yellow', Cassandra: 'badge-gray', Sybase: 'badge-gray', Unknown: 'badge-gray',
};

const CRIT_BADGE: Record<string, string> = {
  Critical: 'badge-red', High: 'badge-yellow', Medium: 'badge-blue', Low: 'badge-gray',
};

export default function Inventory() {
  const [selectedProject, setSelectedProject] = useState('');
  const [engineFilter, setEngineFilter] = useState<EngineType | ''>('');
  const [critFilter, setCritFilter] = useState<Criticality | ''>('');
  const [search, setSearch] = useState('');

  const projects = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const databases = useQuery({
    queryKey: ['databases', selectedProject],
    queryFn: () => getDatabases(selectedProject),
    enabled: !!selectedProject,
  });

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
        {databases.isLoading && <div className="loading">Loading…</div>}
        {!selectedProject && <div className="empty-state"><p>Select a project to view its inventory.</p></div>}
        {selectedProject && !databases.isLoading && filtered.length === 0 && (
          <div className="empty-state">
            <div className="empty-state-icon">🗄️</div>
            <p>No databases match your filters.</p>
          </div>
        )}
        {filtered.length > 0 && (
          <table className="data-table">
            <thead>
              <tr><th>Name</th><th>Engine</th><th>Host</th><th>Port</th><th>Criticality</th><th>Owner</th></tr>
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
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
