import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { deletePortfolio, getDatabases, getPortfolios, getProjects, savePortfolio } from '../lib/api';
import type { PortfolioDto } from '../lib/api';
import type { DatabaseInstance } from '../types';

type GroupingRule = 'Environment' | 'Engine' | 'Criticality';

const ENGINE_BADGE: Record<string, string> = {
  Oracle: 'badge-red', PostgreSQL: 'badge-blue', SqlServer: 'badge-purple',
  MySQL: 'badge-green', MongoDB: 'badge-yellow', Unknown: 'badge-gray',
};

export default function Portfolio() {
  const qc = useQueryClient();
  const [selectedProject, setSelectedProject] = useState('');
  const [groupBy, setGroupBy] = useState<GroupingRule>('Environment');
  const [saveModal, setSaveModal] = useState<{
    groupKey: string; dbs: DatabaseInstance[];
  } | null>(null);
  const [portfolioName, setPortfolioName] = useState('');
  const [portfolioNotes, setPortfolioNotes] = useState('');

  const projects  = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const databases = useQuery({
    queryKey: ['databases', selectedProject],
    queryFn: () => getDatabases(selectedProject),
    enabled: !!selectedProject,
  });
  const portfolios = useQuery({
    queryKey: ['portfolios', selectedProject],
    queryFn: () => getPortfolios(selectedProject),
    enabled: !!selectedProject,
  });

  const saveMutation = useMutation({
    mutationFn: (req: Parameters<typeof savePortfolio>[0]) => savePortfolio(req),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['portfolios', selectedProject] });
      setSaveModal(null);
      setPortfolioName('');
      setPortfolioNotes('');
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deletePortfolio,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['portfolios', selectedProject] }),
  });

  const grouped = (databases.data ?? []).reduce<Record<string, DatabaseInstance[]>>((acc, db) => {
    const key = groupBy === 'Engine'      ? db.engine
              : groupBy === 'Criticality' ? db.criticality
              : db.environment?.name ?? 'Unassigned';
    (acc[key] = acc[key] ?? []).push(db);
    return acc;
  }, {});

  const openSaveModal = (groupKey: string, dbs: DatabaseInstance[]) => {
    setPortfolioName(groupKey);
    setPortfolioNotes('');
    setSaveModal({ groupKey, dbs });
  };

  const handleSave = () => {
    if (!saveModal || !portfolioName.trim()) return;
    saveMutation.mutate({
      projectId:    selectedProject,
      name:         portfolioName.trim(),
      groupingRule: groupBy,
      groupKey:     saveModal.groupKey,
      databaseIds:  saveModal.dbs.map(d => d.databaseId),
      notes:        portfolioNotes || undefined,
    });
  };

  // Check if a group is already saved as a portfolio
  const savedKeys = new Set(
    (portfolios.data ?? [])
      .filter(p => p.groupingRule === groupBy)
      .map(p => p.groupKey)
  );

  return (
    <div>
      <div className="page-header"><h2>Portfolio Grouping</h2></div>

      {/* Controls */}
      <div className="card" style={{ padding: '14px 20px', marginBottom: 20 }}>
        <div style={{ display: 'flex', gap: 14 }}>
          <div className="form-row" style={{ marginBottom: 0, minWidth: 240 }}>
            <label>Project</label>
            <select value={selectedProject} onChange={e => setSelectedProject(e.target.value)}>
              <option value="">Choose a project…</option>
              {projects.data?.map(p => <option key={p.projectId} value={p.projectId}>{p.name}</option>)}
            </select>
          </div>
          <div className="form-row" style={{ marginBottom: 0 }}>
            <label>Group By</label>
            <select value={groupBy} onChange={e => setGroupBy(e.target.value as GroupingRule)}>
              <option value="Environment">Environment</option>
              <option value="Engine">Engine Type</option>
              <option value="Criticality">Criticality</option>
            </select>
          </div>
        </div>
      </div>

      {!selectedProject && (
        <div className="card"><div className="empty-state"><p>Select a project to build portfolios.</p></div></div>
      )}
      {databases.isLoading && <div className="loading">Loading…</div>}

      {/* Groups */}
      {Object.entries(grouped).map(([group, dbs]) => {
        const alreadySaved = savedKeys.has(group);
        return (
          <div className="card" key={group}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ fontSize: 18 }}>📦</span>
                <strong style={{ fontSize: 15 }}>{group}</strong>
                <span className="badge badge-gray">{dbs.length} databases</span>
                {alreadySaved && <span className="badge badge-green">Saved</span>}
              </div>
              <button
                className={`btn btn-sm ${alreadySaved ? 'btn-secondary' : 'btn-primary'}`}
                onClick={() => openSaveModal(group, dbs)}
              >
                {alreadySaved ? 'Update Portfolio' : 'Save as Portfolio'}
              </button>
            </div>
            <table className="data-table">
              <thead>
                <tr><th>Database</th><th>Engine</th><th>Criticality</th><th>Host</th></tr>
              </thead>
              <tbody>
                {dbs.map(db => (
                  <tr key={db.databaseId}>
                    <td><strong>{db.name}</strong></td>
                    <td><span className={`badge ${ENGINE_BADGE[db.engine] ?? 'badge-gray'}`}>{db.engine}</span></td>
                    <td>{db.criticality}</td>
                    <td>{db.hostName ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      })}

      {/* Saved Portfolios */}
      {(portfolios.data?.length ?? 0) > 0 && (
        <div className="card">
          <div className="card-header">
            <div className="card-title">Saved Portfolios</div>
          </div>
          <table className="data-table">
            <thead>
              <tr><th>Name</th><th>Rule</th><th>Group</th><th>Databases</th><th>Saved</th><th></th></tr>
            </thead>
            <tbody>
              {portfolios.data!.map(p => (
                <SavedPortfolioRow
                  key={p.portfolioId}
                  portfolio={p}
                  onDelete={() => deleteMutation.mutate(p.portfolioId)}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Save modal */}
      {saveModal && (
        <div className="modal-overlay" onClick={() => setSaveModal(null)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <p className="modal-title">Save Portfolio</p>
            <p className="modal-sub">
              Group: <strong>{saveModal.groupKey}</strong> · {saveModal.dbs.length} databases
            </p>
            {saveMutation.isError && (
              <div className="error-msg">Save failed. Please try again.</div>
            )}
            <div className="form-row">
              <label>Portfolio Name</label>
              <input
                value={portfolioName}
                onChange={e => setPortfolioName(e.target.value)}
                placeholder="e.g. Oracle Production Databases"
                autoFocus
              />
            </div>
            <div className="form-row">
              <label>Notes (optional)</label>
              <input
                value={portfolioNotes}
                onChange={e => setPortfolioNotes(e.target.value)}
                placeholder="Any additional context…"
              />
            </div>
            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setSaveModal(null)}>Cancel</button>
              <button
                className="btn btn-primary"
                onClick={handleSave}
                disabled={!portfolioName.trim() || saveMutation.isPending}
              >
                {saveMutation.isPending ? 'Saving…' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function SavedPortfolioRow({
  portfolio, onDelete,
}: { portfolio: PortfolioDto; onDelete: () => void }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <tr>
      <td>
        <button
          className="btn btn-ghost btn-sm"
          style={{ padding: '2px 6px', fontWeight: 600 }}
          onClick={() => setExpanded(e => !e)}
        >
          {expanded ? '▾' : '▸'} {portfolio.name}
        </button>
        {expanded && (
          <div style={{ marginTop: 6, paddingLeft: 8 }}>
            {portfolio.notes && (
              <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 4 }}>{portfolio.notes}</div>
            )}
            <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
              IDs: {portfolio.databaseIds.slice(0, 3).map(id => id.slice(0, 8)).join(', ')}{portfolio.databaseIds.length > 3 ? '…' : ''}
            </div>
          </div>
        )}
      </td>
      <td>{portfolio.groupingRule}</td>
      <td><span className="tag">{portfolio.groupKey}</span></td>
      <td><strong>{portfolio.databaseIds.length}</strong></td>
      <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>
        {new Date(portfolio.createdAt).toLocaleDateString()}
      </td>
      <td>
        <button className="btn btn-danger btn-sm" onClick={onDelete}>Delete</button>
      </td>
    </tr>
  );
}

