import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Delete20Regular } from '@fluentui/react-icons';
import { isAxiosError } from 'axios';
import { createCustomer, createProject, deleteProject, getCustomers, getProjects } from '../lib/api';
import type { DeploymentMode } from '../types';

export default function Projects() {
  const qc = useQueryClient();
  const [showProject, setShowProject] = useState(false);
  const [showCustomer, setShowCustomer] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const projects = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const customers = useQuery({ queryKey: ['customers'], queryFn: getCustomers });

  const [projForm, setProjForm] = useState({
    customerId: '', name: '', description: '',
    deploymentMode: 'Connected' as DeploymentMode, createdBy: 'admin',
  });

  const [custForm, setCustForm] = useState({ name: '', industry: '', region: '' });

  const addProject = useMutation({
    mutationFn: createProject,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['projects'] }); setShowProject(false); },
  });

  const addCustomer = useMutation({
    mutationFn: createCustomer,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['customers'] }); setShowCustomer(false); },
  });

  const removeProject = useMutation({
    mutationFn: deleteProject,
    onMutate: () => setDeleteError(null),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['projects'] }),
    onError: error => setDeleteError(
      isAxiosError(error) && error.response?.status === 403
        ? 'Only project owners and administrators can delete projects.'
        : 'Could not delete the project. Refresh the page and try again.'),
  });

  const MODE_BADGE: Record<string, string> = {
    Connected: 'badge-blue', Standalone: 'badge-gray', AirGapped: 'badge-yellow',
  };

  return (
    <div>
      <div className="page-header">
        <h2>Projects</h2>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={() => setShowCustomer(true)}>+ Customer</button>
          <button className="btn btn-primary" onClick={() => setShowProject(true)}>+ New Project</button>
        </div>
      </div>

      {projects.isLoading && <div className="loading">Loading…</div>}
      {deleteError && <div className="error-msg">{deleteError}</div>}

      <div className="card">
        {(projects.data?.length ?? 0) === 0 && !projects.isLoading ? (
          <div className="empty-state">
            <div className="empty-state-icon">📁</div>
            <p>No projects yet. Create your first project above.</p>
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr><th>Project</th><th>Customer</th><th>Deployment Mode</th><th>Status</th><th>Created</th><th>Actions</th></tr>
            </thead>
            <tbody>
              {projects.data?.map(p => (
                <tr key={p.projectId}>
                  <td><strong>{p.name}</strong>{p.description && <div style={{ fontSize: 12, color: '#94a3b8', marginTop: 2 }}>{p.description}</div>}</td>
                  <td>{p.customer?.name ?? '—'}</td>
                  <td><span className={`badge ${MODE_BADGE[p.deploymentMode] ?? 'badge-gray'}`}>{p.deploymentMode}</span></td>
                  <td><span className="badge badge-green">{p.status}</span></td>
                  <td>{new Date(p.createdAt).toLocaleDateString()}</td>
                  <td>
                    <button type="button" className="btn btn-ghost btn-sm" title="Delete project"
                      aria-label={`Delete project ${p.name}`} disabled={removeProject.isPending}
                      onClick={() => {
                        if (window.confirm(`Permanently delete “${p.name}” and all of its databases, assessments, questionnaires, evidence, and reports? This cannot be undone.`))
                          removeProject.mutate(p.projectId);
                      }}>
                      <Delete20Regular />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* New Project Modal */}
      {showProject && (
        <div className="modal-overlay" onClick={() => setShowProject(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-title">New Project</div>
            {addProject.isError && <div className="error-msg">Failed to create project. Check required fields.</div>}
            <div className="form-row">
              <label>Customer *</label>
              <select value={projForm.customerId} onChange={e => setProjForm(f => ({ ...f, customerId: e.target.value }))}>
                <option value="">Select customer…</option>
                {customers.data?.map(c => <option key={c.customerId} value={c.customerId}>{c.name}</option>)}
              </select>
            </div>
            <div className="form-row">
              <label>Project Name *</label>
              <input value={projForm.name} onChange={e => setProjForm(f => ({ ...f, name: e.target.value }))} placeholder="e.g. ACME Oracle Migration 2025" />
            </div>
            <div className="form-row">
              <label>Description</label>
              <textarea value={projForm.description} onChange={e => setProjForm(f => ({ ...f, description: e.target.value }))} rows={2} placeholder="Optional project description" />
            </div>
            <div className="form-row">
              <label>Deployment Mode</label>
              <select value={projForm.deploymentMode} onChange={e => setProjForm(f => ({ ...f, deploymentMode: e.target.value as DeploymentMode }))}>
                <option value="Connected">Connected</option>
                <option value="Standalone">Standalone</option>
                <option value="AirGapped">Air-Gapped</option>
              </select>
            </div>
            <div className="form-row">
              <label>Created By</label>
              <input value={projForm.createdBy} onChange={e => setProjForm(f => ({ ...f, createdBy: e.target.value }))} />
            </div>
            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setShowProject(false)}>Cancel</button>
              <button className="btn btn-primary" disabled={addProject.isPending}
                onClick={() => addProject.mutate(projForm)}>
                {addProject.isPending ? 'Creating…' : 'Create Project'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* New Customer Modal */}
      {showCustomer && (
        <div className="modal-overlay" onClick={() => setShowCustomer(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-title">New Customer</div>
            <div className="form-row">
              <label>Customer Name *</label>
              <input value={custForm.name} onChange={e => setCustForm(f => ({ ...f, name: e.target.value }))} placeholder="e.g. Acme Corporation" />
            </div>
            <div className="form-row">
              <label>Industry</label>
              <input value={custForm.industry} onChange={e => setCustForm(f => ({ ...f, industry: e.target.value }))} placeholder="e.g. Financial Services" />
            </div>
            <div className="form-row">
              <label>Region</label>
              <input value={custForm.region} onChange={e => setCustForm(f => ({ ...f, region: e.target.value }))} placeholder="e.g. West Europe" />
            </div>
            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => setShowCustomer(false)}>Cancel</button>
              <button className="btn btn-primary" disabled={addCustomer.isPending}
                onClick={() => addCustomer.mutate(custForm)}>
                {addCustomer.isPending ? 'Saving…' : 'Save Customer'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
