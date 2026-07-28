import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  createEnvironment, deleteEnvironment, getEnvironments,
  getProjects, updateEnvironment,
} from '../lib/api';
import type { ProjectEnvironment } from '../types';

const ENV_TYPES = ['Production', 'UAT', 'DR', 'Dev', 'Custom'];

const TYPE_BADGE: Record<string, string> = {
  Production: 'badge-red', UAT: 'badge-blue', DR: 'badge-yellow',
  Dev: 'badge-green', Custom: 'badge-gray',
};

type FormState = {
  name: string; type: string; location: string; connectivityZone: string;
};

const EMPTY_FORM: FormState = { name: '', type: 'Production', location: '', connectivityZone: '' };

export default function Environments() {
  const qc = useQueryClient();
  const [selectedProject, setSelectedProject] = useState('');
  const [modal, setModal] = useState<'create' | { env: ProjectEnvironment } | null>(null);
  const [form, setForm] = useState<FormState>(EMPTY_FORM);
  const [formError, setFormError] = useState<string | null>(null);

  const projects     = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const environments = useQuery({
    queryKey: ['environments', selectedProject],
    queryFn: () => getEnvironments(selectedProject),
    enabled: !!selectedProject,
  });

  const invalidate = () => qc.invalidateQueries({ queryKey: ['environments', selectedProject] });

  const createMutation = useMutation({
    mutationFn: (f: FormState) => createEnvironment({
      projectId: selectedProject,
      name: f.name.trim(), type: f.type,
      location: f.location.trim() || undefined,
      connectivityZone: f.connectivityZone.trim() || undefined,
    }),
    onSuccess: () => { invalidate(); closeModal(); },
    onError: () => setFormError('Failed to create environment.'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, f }: { id: string; f: FormState }) => updateEnvironment(id, {
      name: f.name.trim(), type: f.type,
      location: f.location.trim() || undefined,
      connectivityZone: f.connectivityZone.trim() || undefined,
    }),
    onSuccess: () => { invalidate(); closeModal(); },
    onError: () => setFormError('Failed to update environment.'),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteEnvironment,
    onSuccess: invalidate,
  });

  const openCreate = () => { setForm(EMPTY_FORM); setFormError(null); setModal('create'); };
  const openEdit   = (env: ProjectEnvironment) => {
    setForm({
      name: env.name, type: env.type,
      location: env.location ?? '', connectivityZone: env.connectivityZone ?? '',
    });
    setFormError(null);
    setModal({ env });
  };
  const closeModal = () => setModal(null);

  const handleSubmit = () => {
    if (!form.name.trim()) { setFormError('Name is required.'); return; }
    if (modal === 'create') {
      createMutation.mutate(form);
    } else if (modal && typeof modal === 'object') {
      updateMutation.mutate({ id: modal.env.environmentId, f: form });
    }
  };

  const isPending = createMutation.isPending || updateMutation.isPending;
  const isEditing = modal !== null && modal !== 'create';

  return (
    <div>
      <div className="page-header">
        <h2>Environments</h2>
        <button
          className="btn btn-primary"
          disabled={!selectedProject}
          onClick={openCreate}
        >
          + Add Environment
        </button>
      </div>

      {/* Project selector */}
      <div className="card" style={{ padding: '14px 20px', marginBottom: 20 }}>
        <div className="form-row" style={{ marginBottom: 0, maxWidth: 320 }}>
          <label>Project</label>
          <select value={selectedProject} onChange={e => setSelectedProject(e.target.value)}>
            <option value="">Choose a project…</option>
            {projects.data?.map(p => (
              <option key={p.projectId} value={p.projectId}>{p.name}</option>
            ))}
          </select>
        </div>
      </div>

      {!selectedProject && (
        <div className="card">
          <div className="empty-state">
            <div className="empty-state-icon">🏗️</div>
            <p>Select a project to manage its environments.</p>
          </div>
        </div>
      )}

      {environments.isLoading && <div className="loading">Loading…</div>}

      {selectedProject && environments.isSuccess && (
        <div className="card">
          {environments.data.length === 0 ? (
            <div className="empty-state">
              <div className="empty-state-icon">🏗️</div>
              <p>No environments yet.<br />Click <strong>+ Add Environment</strong> to create one.</p>
            </div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Name</th><th>Type</th><th>Location</th>
                  <th>Connectivity Zone</th><th>Created</th><th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {environments.data.map(env => (
                  <tr key={env.environmentId}>
                    <td><strong>{env.name}</strong></td>
                    <td>
                      <span className={`badge ${TYPE_BADGE[env.type] ?? 'badge-gray'}`}>
                        {env.type}
                      </span>
                    </td>
                    <td>{env.location ?? <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                    <td>{env.connectivityZone ?? <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                    <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                      {new Date(env.createdAt).toLocaleDateString()}
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: 6 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => openEdit(env)}>
                          Edit
                        </button>
                        <button
                          className="btn btn-danger btn-sm"
                          onClick={() => deleteMutation.mutate(env.environmentId)}
                        >
                          Delete
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

      {/* Create / Edit modal */}
      {modal !== null && (
        <div className="modal-overlay" onClick={closeModal}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <p className="modal-title">{isEditing ? 'Edit Environment' : 'Add Environment'}</p>
            <p className="modal-sub">
              {isEditing
                ? 'Update the environment details.'
                : 'Add a new deployment environment to this project.'}
            </p>

            {formError && <div className="error-msg">{formError}</div>}

            <div className="form-row">
              <label>Name *</label>
              <input
                value={form.name}
                onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                placeholder="e.g. Production EU-West"
                autoFocus
              />
            </div>

            <div className="form-row">
              <label>Type</label>
              <select value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value }))}>
                {ENV_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
              </select>
            </div>

            <div className="form-row">
              <label>Location</label>
              <input
                value={form.location}
                onChange={e => setForm(f => ({ ...f, location: e.target.value }))}
                placeholder="e.g. Azure West Europe"
              />
            </div>

            <div className="form-row">
              <label>Connectivity Zone</label>
              <input
                value={form.connectivityZone}
                onChange={e => setForm(f => ({ ...f, connectivityZone: e.target.value }))}
                placeholder="e.g. On-prem, DMZ, Cloud VNet"
              />
            </div>

            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={closeModal} disabled={isPending}>
                Cancel
              </button>
              <button
                className="btn btn-primary"
                onClick={handleSubmit}
                disabled={isPending}
              >
                {isPending ? 'Saving…' : isEditing ? 'Save Changes' : 'Create'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
