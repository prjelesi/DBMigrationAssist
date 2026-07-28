import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  getProjects, getTemplates, getResponses, startResponse,
  getResponse, saveAnswers, submitResponse, seedTemplates,
} from '../lib/api';
import type { Answer, Question, QuestionnaireResponse, ResponseStatus } from '../types';

const STATUS_BADGE: Record<ResponseStatus, string> = {
  NotStarted: 'badge-gray', InProgress: 'badge-blue',
  Completed: 'badge-green', Submitted: 'badge-green',
};

const PHASE_BADGE: Record<string, string> = {
  Baseline: 'badge-indigo', Supplemental: 'badge-purple',
};

export default function Questionnaire() {
  const qc = useQueryClient();
  const [selectedProject, setSelectedProject] = useState('');
  const [activeResponseId, setActiveResponseId] = useState<string | null>(null);
  // Local draft answers: questionId → value
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [saveMsg, setSaveMsg] = useState('');

  const projects = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const templates = useQuery({ queryKey: ['templates'], queryFn: getTemplates });
  const responses = useQuery({
    queryKey: ['responses', selectedProject],
    queryFn: () => getResponses(selectedProject),
    enabled: !!selectedProject,
  });
  const activeResponse = useQuery({
    queryKey: ['response', activeResponseId],
    queryFn: () => getResponse(activeResponseId!),
    enabled: !!activeResponseId,
  });

  const seedMutation = useMutation({
    mutationFn: seedTemplates,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['templates'] }),
  });

  const startMutation = useMutation({
    mutationFn: startResponse,
    onSuccess: (data: QuestionnaireResponse) => {
      qc.invalidateQueries({ queryKey: ['responses', selectedProject] });
      setActiveResponseId(data.responseId);
      setDraft({});
    },
  });

  const saveMutation = useMutation({
    mutationFn: ({ id, answers }: { id: string; answers: { questionId: string; value: string | null }[] }) =>
      saveAnswers(id, answers),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['response', activeResponseId] });
      setSaveMsg('Draft saved ✓');
      setTimeout(() => setSaveMsg(''), 2500);
    },
  });

  const submitMutation = useMutation({
    mutationFn: submitResponse,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['responses', selectedProject] });
      qc.invalidateQueries({ queryKey: ['response', activeResponseId] });
    },
  });

  // Initialise draft from loaded response answers
  const loadDraft = (answers: Answer[]) => {
    const d: Record<string, string> = {};
    answers.forEach(a => { if (a.value) d[a.questionId] = a.value; });
    setDraft(d);
  };

  const handleSave = () => {
    if (!activeResponseId) return;
    saveMutation.mutate({
      id: activeResponseId,
      answers: Object.entries(draft).map(([questionId, value]) => ({ questionId, value })),
    });
  };

  const handleSubmit = () => {
    if (!activeResponseId) return;
    handleSave();
    setTimeout(() => submitMutation.mutate(activeResponseId!), 300);
  };

  const getAnsweredCount = (template: typeof activeResponse.data) => {
    if (!template) return { answered: 0, required: 0, total: 0 };
    const allQuestions = template.template?.sections.flatMap(s => s.questions) ?? [];
    const answered = allQuestions.filter(q => !!draft[q.questionId]).length;
    const required = allQuestions.filter(q => q.isRequired).length;
    return { answered, required, total: allQuestions.length };
  };

  const progress = getAnsweredCount(activeResponse.data);
  const pct = progress.total > 0 ? Math.round((progress.answered / progress.total) * 100) : 0;
  const isSubmitted = activeResponse.data?.status === 'Submitted';

  const renderInput = (q: Question) => {
    const val = draft[q.questionId] ?? '';
    const set = (v: string) => setDraft(d => ({ ...d, [q.questionId]: v }));
    const opts = q.optionsJson ? (JSON.parse(q.optionsJson) as string[]) : [];
    const disabled = isSubmitted;

    switch (q.type) {
      case 'Textarea':
        return <textarea rows={3} value={val} onChange={e => set(e.target.value)} disabled={disabled}
          style={{ width: '100%', resize: 'vertical' }} />;
      case 'Select':
        return (
          <select value={val} onChange={e => set(e.target.value)} disabled={disabled} style={{ width: '100%' }}>
            <option value="">Select an option…</option>
            {opts.map(o => <option key={o} value={o}>{o}</option>)}
          </select>
        );
      case 'MultiSelect':
        const selected = val ? val.split('|') : [];
        return (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 4 }}>
            {opts.map(o => (
              <label key={o} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, cursor: 'pointer' }}>
                <input type="checkbox" disabled={disabled}
                  checked={selected.includes(o)}
                  onChange={e => {
                    const next = e.target.checked ? [...selected, o] : selected.filter(x => x !== o);
                    set(next.join('|'));
                  }} />
                {o}
              </label>
            ))}
          </div>
        );
      case 'Boolean':
        return (
          <div style={{ display: 'flex', gap: 20, marginTop: 4 }}>
            {['Yes', 'No'].map(opt => (
              <label key={opt} style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 13.5, cursor: 'pointer' }}>
                <input type="radio" name={q.questionId} value={opt} checked={val === opt}
                  onChange={() => set(opt)} disabled={disabled} />
                {opt}
              </label>
            ))}
          </div>
        );
      case 'Number':
        return <input type="number" value={val} onChange={e => set(e.target.value)} disabled={disabled}
          style={{ width: 160 }} />;
      default:
        return <input type="text" value={val} onChange={e => set(e.target.value)} disabled={disabled}
          style={{ width: '100%' }} />;
    }
  };

  return (
    <div>
      <div className="page-header"><h2>Questionnaires</h2></div>

      {/* Project selector */}
      <div className="filter-bar">
        <div className="form-row" style={{ marginBottom: 0, minWidth: 300 }}>
          <label>Project</label>
          <select value={selectedProject} onChange={e => { setSelectedProject(e.target.value); setActiveResponseId(null); setDraft({}); }}>
            <option value="">Choose a project…</option>
            {projects.data?.map(p => <option key={p.projectId} value={p.projectId}>{p.name}</option>)}
          </select>
        </div>
      </div>

      {!activeResponseId ? (
        // ── Response list + template picker ──────────────────────────────
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
          {/* Active responses */}
          <div className="card">
            <div className="card-header">
              <span className="card-title">Responses for this Project</span>
            </div>
            {!selectedProject && <div className="empty-state"><p>Select a project above.</p></div>}
            {selectedProject && responses.isLoading && <div className="loading" />}
            {selectedProject && !responses.isLoading && (responses.data?.length ?? 0) === 0 && (
              <div className="empty-state">
                <div className="empty-state-icon">📋</div>
                <p>No questionnaires started.<br />Select a template on the right to begin.</p>
              </div>
            )}
            {(responses.data?.length ?? 0) > 0 && (
              <table className="data-table">
                <thead><tr><th>Template</th><th>Phase</th><th>Status</th><th></th></tr></thead>
                <tbody>
                  {responses.data?.map((r: QuestionnaireResponse) => (
                    <tr key={r.responseId}>
                      <td style={{ fontWeight: 600 }}>{r.template?.name ?? 'Unknown'}</td>
                      <td><span className={`badge ${PHASE_BADGE[r.template?.phase ?? ''] ?? 'badge-gray'}`}>{r.template?.phase}</span></td>
                      <td><span className={`badge ${STATUS_BADGE[r.status]}`}>{r.status}</span></td>
                      <td>
                        <button className="btn btn-secondary btn-sm"
                          onClick={() => {
                            setActiveResponseId(r.responseId);
                            // Pre-fill draft from existing answers
                            if (r.answers) loadDraft(r.answers);
                          }}>
                          {r.status === 'Submitted' ? 'View' : 'Continue →'}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          {/* Template picker */}
          <div className="card">
            <div className="card-header">
              <span className="card-title">Available Templates</span>
              {(templates.data?.length ?? 0) === 0 && (
                <button className="btn btn-secondary btn-sm" disabled={seedMutation.isPending}
                  onClick={() => seedMutation.mutate()}>
                  {seedMutation.isPending ? 'Seeding…' : 'Load defaults'}
                </button>
              )}
            </div>
            {templates.isLoading && <div className="loading" />}
            {(templates.data?.length ?? 0) === 0 && !templates.isLoading && (
              <div className="empty-state">
                <div className="empty-state-icon">📄</div>
                <p>No templates loaded.<br />Click <strong>Load defaults</strong> to add the baseline template.</p>
              </div>
            )}
            {templates.data?.map((t, idx) => (
              <div key={t.templateId} style={{ borderBottom: idx < (templates.data?.length ?? 0) - 1 ? '1px solid var(--border-light)' : 'none', padding: '14px 0' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
                  <div>
                    <div style={{ fontWeight: 600, marginBottom: 4 }}>{t.name}</div>
                    <div style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 6 }}>{t.description}</div>
                    <span className={`badge ${PHASE_BADGE[t.phase] ?? 'badge-gray'}`}>{t.phase}</span>
                    <span className="badge badge-gray" style={{ marginLeft: 6 }}>{t.sections?.length ?? 0} sections</span>
                  </div>
                  <button className="btn btn-primary btn-sm"
                    disabled={!selectedProject || startMutation.isPending}
                    onClick={() => startMutation.mutate({ projectId: selectedProject, templateId: t.templateId })}>
                    Start →
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      ) : (
        // ── Active questionnaire ──────────────────────────────────────────
        <div>
          {activeResponse.isLoading && <div className="loading" />}
          {activeResponse.data && (() => {
            const resp = activeResponse.data;
            const sections = resp.template?.sections ?? [];

            return (
              <>
                {/* Header bar */}
                <div className="card" style={{ marginBottom: 16 }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 12 }}>
                    <div>
                      <div style={{ fontWeight: 700, fontSize: 16 }}>{resp.template?.name}</div>
                      <div style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 3 }}>
                        <span className={`badge ${STATUS_BADGE[resp.status]}`} style={{ marginRight: 8 }}>{resp.status}</span>
                        {progress.answered}/{progress.total} answered · {progress.required} required
                      </div>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      {saveMsg && <span style={{ fontSize: 12.5, color: 'var(--green-text)' }}>{saveMsg}</span>}
                      <button className="btn btn-secondary btn-sm" onClick={() => { setActiveResponseId(null); setDraft({}); }}>← Back</button>
                      {!isSubmitted && (
                        <>
                          <button className="btn btn-secondary" disabled={saveMutation.isPending} onClick={handleSave}>
                            {saveMutation.isPending ? 'Saving…' : 'Save Draft'}
                          </button>
                          <button className="btn btn-primary" disabled={submitMutation.isPending} onClick={handleSubmit}>
                            {submitMutation.isPending ? 'Submitting…' : 'Submit'}
                          </button>
                        </>
                      )}
                    </div>
                  </div>
                  {/* Progress bar */}
                  <div style={{ marginTop: 14, background: 'var(--border)', borderRadius: 6, height: 6 }}>
                    <div style={{ width: `${pct}%`, background: 'var(--accent-500)', borderRadius: 6, height: 6, transition: 'width .3s' }} />
                  </div>
                </div>

                {isSubmitted && (
                  <div className="warn-msg" style={{ background: 'var(--green-bg)', color: 'var(--green-text)', borderColor: '#bbf7d0', marginBottom: 16 }}>
                    ✅ This questionnaire was submitted on {new Date(resp.submittedAt!).toLocaleString()} and is read-only.
                  </div>
                )}

                {/* Sections */}
                {sections.map(section => (
                  <div className="card" key={section.sectionId} style={{ marginBottom: 16 }}>
                    <div style={{ marginBottom: 16 }}>
                      <div style={{ fontWeight: 700, fontSize: 15 }}>{section.title}</div>
                      {section.description && <div style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 3 }}>{section.description}</div>}
                    </div>

                    {section.questions.map((q: Question) => (
                      <div key={q.questionId} style={{ marginBottom: 20, paddingBottom: 20, borderBottom: '1px solid var(--border-light)' }}>
                        <div style={{ marginBottom: 8 }}>
                          <span style={{ fontWeight: 600, fontSize: 13.5 }}>{q.text}</span>
                          {q.isRequired && <span style={{ color: 'var(--red-text)', marginLeft: 4 }}>*</span>}
                        </div>
                        {q.helpText && (
                          <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8, fontStyle: 'italic' }}>
                            💡 {q.helpText}
                          </div>
                        )}
                        <div className="form-row" style={{ marginBottom: 0 }}>
                          {renderInput(q)}
                        </div>
                      </div>
                    ))}
                  </div>
                ))}
              </>
            );
          })()}
        </div>
      )}
    </div>
  );
}
