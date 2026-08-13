import { useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ArrowDownload20Regular, Attach20Regular, Delete20Regular } from '@fluentui/react-icons';
import {
  deleteEvidence, downloadEvidence, getQuestionnaireAttachments,
  getProjects, getTemplates, getResponses, startResponse,
  getResponse, saveAnswers, submitResponse, seedTemplates, uploadQuestionnaireAttachment,
} from '../lib/api';
import type { Answer, Question, QuestionnaireAttachment, QuestionnaireResponse, ResponseStatus } from '../types';

const CUSTOM_PREFIX = 'Custom: ';
const CUSTOM_VALUE = '__custom__';

const decodeCustomAnswer = (value: string) => {
  const encoded = value.slice(CUSTOM_PREFIX.length);
  try {
    return decodeURIComponent(encoded);
  } catch {
    return encoded;
  }
};

const formatBytes = (bytes: number) =>
  bytes < 1024 ? `${bytes} B` : bytes < 1_048_576 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1_048_576).toFixed(1)} MB`;

const hasMeaningfulAnswer = (question: Question, value: string | undefined) => {
  if (!value?.trim()) return false;
  const values = question.type === 'MultiSelect' ? value.split('|') : [value];
  return values.some(item => item.startsWith(CUSTOM_PREFIX)
    ? decodeCustomAnswer(item).trim().length > 0
    : item.trim().length > 0);
};

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
  const [syncMsg, setSyncMsg] = useState('');
  const [missingRequired, setMissingRequired] = useState<Set<string>>(new Set());

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
  const attachments = useQuery({
    queryKey: ['questionnaireAttachments', activeResponseId],
    queryFn: () => getQuestionnaireAttachments(activeResponseId!),
    enabled: !!activeResponseId,
  });

  const seedMutation = useMutation({
    mutationFn: seedTemplates,
    onSuccess: (result) => {
      qc.invalidateQueries({ queryKey: ['templates'] });
      const count = result.imported?.length ?? 0;
      setSyncMsg(count > 0 ? `${count} template version${count === 1 ? '' : 's'} imported.` : 'Templates are up to date.');
    },
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

  const uploadAttachmentMutation = useMutation({
    mutationFn: ({ questionId, file }: { questionId: string; file: File }) => {
      const response = activeResponse.data!;
      return uploadQuestionnaireAttachment(
        response.projectId,
        response.responseId,
        questionId,
        response.assignedTo ?? 'Questionnaire respondent',
        file,
      );
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['questionnaireAttachments', activeResponseId] });
      qc.invalidateQueries({ queryKey: ['evidence', selectedProject] });
    },
  });

  const deleteAttachmentMutation = useMutation({
    mutationFn: deleteEvidence,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['questionnaireAttachments', activeResponseId] });
      qc.invalidateQueries({ queryKey: ['evidence', selectedProject] });
    },
  });

  const loadDraft = (answers: Answer[] = []) => {
    const d: Record<string, string> = {};
    answers.forEach(a => { d[a.questionId] = a.value ?? ''; });
    setDraft(d);
  };

  useEffect(() => {
    if (activeResponse.data)
      loadDraft(activeResponse.data.answers);
  }, [activeResponse.data]);

  const handleSave = () => {
    if (!activeResponseId) return;
    saveMutation.mutate({
      id: activeResponseId,
      answers: Object.entries(draft).map(([questionId, value]) => ({ questionId, value })),
    });
  };

  const handleSubmit = async () => {
    if (!activeResponseId || !activeResponse.data?.template) return;

    const attachedQuestionIds = new Set(attachments.data?.map(attachment => attachment.questionId) ?? []);
    const missing = activeResponse.data.template.sections
      .flatMap(section => section.questions)
      .filter(question => question.isRequired &&
        !hasMeaningfulAnswer(question, draft[question.questionId]) &&
        !(question.allowAttachments && attachedQuestionIds.has(question.questionId)))
      .map(question => question.questionId);

    if (missing.length > 0) {
      setMissingRequired(new Set(missing));
      document.getElementById(`question-${missing[0]}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      return;
    }

    setMissingRequired(new Set());
    await saveMutation.mutateAsync({
      id: activeResponseId,
      answers: Object.entries(draft).map(([questionId, value]) => ({ questionId, value })),
    });
    submitMutation.mutate(activeResponseId);
  };

  const getAnsweredCount = (template: typeof activeResponse.data) => {
    if (!template) return { answered: 0, required: 0, total: 0 };
    const allQuestions = template.template?.sections.flatMap(s => s.questions) ?? [];
    const attachedQuestionIds = new Set(attachments.data?.map(attachment => attachment.questionId) ?? []);
    const answered = allQuestions.filter(question =>
      hasMeaningfulAnswer(question, draft[question.questionId]) ||
      (question.allowAttachments && attachedQuestionIds.has(question.questionId))).length;
    const required = allQuestions.filter(q => q.isRequired).length;
    return { answered, required, total: allQuestions.length };
  };

  const progress = getAnsweredCount(activeResponse.data);
  const pct = progress.total > 0 ? Math.round((progress.answered / progress.total) * 100) : 0;
  const isSubmitted = activeResponse.data?.status === 'Submitted';

  const renderInput = (q: Question) => {
    const val = draft[q.questionId] ?? '';
    const set = (v: string) => {
      setDraft(d => ({ ...d, [q.questionId]: v }));
      if (v.trim())
        setMissingRequired(current => {
          if (!current.has(q.questionId)) return current;
          const next = new Set(current);
          next.delete(q.questionId);
          return next;
        });
    };
    const opts = q.optionsJson ? (JSON.parse(q.optionsJson) as string[]) : [];
    const disabled = isSubmitted;

    switch (q.type) {
      case 'Textarea':
        return <textarea rows={3} value={val} onChange={e => set(e.target.value)} disabled={disabled}
          style={{ width: '100%', resize: 'vertical' }} />;
      case 'Select':
        const customSelected = val.startsWith(CUSTOM_PREFIX);
        return (
          <div style={{ width: '100%' }}>
            <select value={customSelected ? CUSTOM_VALUE : val} onChange={e => set(e.target.value === CUSTOM_VALUE ? CUSTOM_PREFIX : e.target.value)} disabled={disabled} style={{ width: '100%' }}>
              <option value="">Select an option…</option>
              {opts.map(o => <option key={o} value={o}>{o}</option>)}
              {q.allowCustomAnswer && <option value={CUSTOM_VALUE}>Other / custom answer</option>}
            </select>
            {customSelected && (
              <textarea rows={2} value={val.slice(CUSTOM_PREFIX.length)}
                aria-label="Custom answer" placeholder="Enter the customer's answer"
                onChange={e => set(`${CUSTOM_PREFIX}${e.target.value}`)} disabled={disabled}
                style={{ width: '100%', resize: 'vertical', marginTop: 8 }} />
            )}
          </div>
        );
      case 'MultiSelect': {
        const selected = val ? val.split('|') : [];
        const customAnswer = selected.find(item => item.startsWith(CUSTOM_PREFIX));
        return (
          <div style={{ width: '100%' }}>
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
              {q.allowCustomAnswer && (
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, cursor: 'pointer' }}>
                  <input type="checkbox" disabled={disabled} checked={customAnswer !== undefined}
                    onChange={e => {
                      const withoutCustom = selected.filter(item => !item.startsWith(CUSTOM_PREFIX));
                      set((e.target.checked ? [...withoutCustom, CUSTOM_PREFIX] : withoutCustom).join('|'));
                    }} />
                  Other / custom answer
                </label>
              )}
            </div>
            {customAnswer !== undefined && (
              <textarea rows={2} value={decodeCustomAnswer(customAnswer)}
                aria-label="Custom answer" placeholder="Enter the customer's answer"
                onChange={e => {
                  const next = selected.filter(item => !item.startsWith(CUSTOM_PREFIX));
                  set([...next, `${CUSTOM_PREFIX}${encodeURIComponent(e.target.value)}`].join('|'));
                }} disabled={disabled}
                style={{ width: '100%', resize: 'vertical', marginTop: 8 }} />
            )}
          </div>
        );
      }
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

  const downloadAttachment = async (attachment: QuestionnaireAttachment) => {
    const blob = await downloadEvidence(attachment.reportId);
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = attachment.fileName;
    link.click();
    URL.revokeObjectURL(url);
  };

  const renderAttachments = (question: Question) => {
    if (!question.allowAttachments) return null;
    const questionAttachments = attachments.data?.filter(attachment => attachment.questionId === question.questionId) ?? [];
    const isUploading = uploadAttachmentMutation.isPending && uploadAttachmentMutation.variables?.questionId === question.questionId;

    return (
      <div style={{ marginTop: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          {!isSubmitted && (
            <label className="btn btn-secondary btn-sm" style={{ display: 'inline-flex', alignItems: 'center', gap: 6, cursor: isUploading ? 'wait' : 'pointer' }}>
              <Attach20Regular /> {isUploading ? 'Uploading…' : 'Attach document'}
              <input type="file" hidden disabled={isUploading}
                accept=".pdf,.doc,.docx,.xls,.xlsx,.csv,.txt,.json,.xml,.html,.png,.jpg,.jpeg"
                onChange={event => {
                  const file = event.target.files?.[0];
                  if (file) uploadAttachmentMutation.mutate({ questionId: question.questionId, file });
                  event.target.value = '';
                }} />
            </label>
          )}
          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>Supporting documents, max 50 MB each</span>
        </div>

        {uploadAttachmentMutation.isError && uploadAttachmentMutation.variables?.questionId === question.questionId && (
          <div className="error-msg" style={{ marginTop: 8 }}>Document upload failed. Check the file and try again.</div>
        )}

        {questionAttachments.length > 0 && (
          <div style={{ display: 'grid', gap: 6, marginTop: 8 }}>
            {questionAttachments.map(attachment => (
              <div key={attachment.reportId} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 9px', border: '1px solid var(--border-light)', borderRadius: 4, background: 'var(--surface)' }}>
                <span style={{ flex: 1, minWidth: 0, fontSize: 12.5, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{attachment.fileName}</span>
                <span style={{ fontSize: 11.5, color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>{formatBytes(attachment.fileSizeBytes)}</span>
                <button type="button" className="btn btn-ghost btn-sm" title="Download document" aria-label={`Download ${attachment.fileName}`}
                  onClick={() => downloadAttachment(attachment)}><ArrowDownload20Regular /></button>
                {!isSubmitted && (
                  <button type="button" className="btn btn-ghost btn-sm" title="Remove document" aria-label={`Remove ${attachment.fileName}`}
                    disabled={deleteAttachmentMutation.isPending}
                    onClick={() => deleteAttachmentMutation.mutate(attachment.reportId)}><Delete20Regular /></button>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    );
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
                            setDraft({});
                            setMissingRequired(new Set());
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
              <button className="btn btn-secondary btn-sm" disabled={seedMutation.isPending}
                onClick={() => { setSyncMsg(''); seedMutation.mutate(); }}>
                {seedMutation.isPending ? 'Syncing…' : 'Sync JSON templates'}
              </button>
            </div>
            {syncMsg && <div className="success-msg" style={{ marginBottom: 12 }}>{syncMsg}</div>}
            {seedMutation.isError && <div className="error-msg" style={{ marginBottom: 12 }}>Template sync failed.</div>}
            {templates.isLoading && <div className="loading" />}
            {(templates.data?.length ?? 0) === 0 && !templates.isLoading && (
              <div className="empty-state">
                <div className="empty-state-icon">📄</div>
                <p>No templates loaded.<br />Sync the JSON files to make questionnaires available.</p>
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
                            {saveMutation.isPending || submitMutation.isPending ? 'Submitting…' : 'Submit'}
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

                {missingRequired.size > 0 && (
                  <div className="error-msg" role="alert" style={{ marginBottom: 16 }}>
                    Complete {missingRequired.size} required field{missingRequired.size === 1 ? '' : 's'} before submitting.
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
                      <div id={`question-${q.questionId}`} key={q.questionId} style={{
                        marginBottom: 20,
                        padding: missingRequired.has(q.questionId) ? '12px' : '0 0 20px',
                        border: missingRequired.has(q.questionId) ? '1px solid var(--red-text)' : 'none',
                        borderBottom: `1px solid ${missingRequired.has(q.questionId) ? 'var(--red-text)' : 'var(--border-light)'}`,
                        borderRadius: missingRequired.has(q.questionId) ? 4 : 0,
                        background: missingRequired.has(q.questionId) ? 'var(--red-bg)' : undefined,
                      }}>
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
                        {renderAttachments(q)}
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
