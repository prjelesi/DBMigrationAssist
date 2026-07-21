import { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { startAssessment, type DatabaseEntry } from '../api/assess';

const SOURCE_TYPES = ['SQL Server', 'Oracle', 'PostgreSQL', 'MySQL', 'MariaDB', 'MongoDB', 'Cassandra', 'SybaseASE'];
const ENVIRONMENTS = ['OnPrem', 'AzureVM', 'AzureVM_Windows', 'AzureVM_Linux', 'AzureArc', 'AzurePaaS_SingleServer', 'ODAA', 'OracleCloud', 'AWS_EC2', 'AWS_RDS', 'AWS_Aurora', 'GCP_CloudSQL'];

const emptyDb = (): DatabaseEntry => ({
  DatabaseName: '',
  SourceType: 'SQL Server',
  SourceVersion: '',
  SourceEnvironment: 'OnPrem',
  MaxDowntime: 'hours',
  Connectivity: 'expressroute',
  LandingZone: 'yes',
  DataSize: 'medium',
  StoredProcs: 'none',
  TeamSkill: 'moderate',
  RollbackPlan: 'yes_untested',
  DatabaseCount: 1,
});

export default function NewAssessment() {
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [customerName, setCustomerName] = useState('');
  const [requestedBy, setRequestedBy] = useState('');
  const [databases, setDatabases] = useState<DatabaseEntry[]>([emptyDb()]);

  const mutation = useMutation({
    mutationFn: startAssessment,
    onSuccess: (res) => navigate(`/reports?job=${res.jobId}`),
  });

  const updateDb = (i: number, field: keyof DatabaseEntry, value: unknown) => {
    setDatabases(dbs => dbs.map((d, idx) => idx === i ? { ...d, [field]: value } : d));
  };

  const addDb = () => setDatabases(dbs => [...dbs, emptyDb()]);
  const removeDb = (i: number) => setDatabases(dbs => dbs.filter((_, idx) => idx !== i));

  const steps = ['Customer Info', 'Databases', 'Review & Submit'];

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-800 mb-6">New Assessment</h1>

      {/* Stepper */}
      <div className="flex items-center gap-2 mb-8">
        {steps.map((s, i) => (
          <div key={s} className="flex items-center gap-2">
            <button
              onClick={() => i < step && setStep(i)}
              className={`w-8 h-8 rounded-full text-sm font-bold flex items-center justify-center ${i <= step ? 'bg-blue-600 text-white' : 'bg-gray-200 text-gray-500'}`}
            >
              {i + 1}
            </button>
            <span className={`text-sm ${i === step ? 'font-semibold text-gray-800' : 'text-gray-400'}`}>{s}</span>
            {i < steps.length - 1 && <div className="w-8 h-px bg-gray-300 mx-1" />}
          </div>
        ))}
      </div>

      {/* Step 0 — Customer info */}
      {step === 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-6 space-y-4">
          <Field label="Customer Name" required>
            <input className="input" value={customerName} onChange={e => setCustomerName(e.target.value)} placeholder="Contoso Ltd." />
          </Field>
          <Field label="Requested By" required>
            <input className="input" value={requestedBy} onChange={e => setRequestedBy(e.target.value)} placeholder="Your name / email" />
          </Field>
          <div className="flex justify-end pt-2">
            <button
              disabled={!customerName || !requestedBy}
              onClick={() => setStep(1)}
              className="btn-primary"
            >
              Next →
            </button>
          </div>
        </div>
      )}

      {/* Step 1 — Databases */}
      {step === 1 && (
        <div className="space-y-4">
          {databases.map((db, i) => (
            <div key={i} className="bg-white rounded-xl border border-gray-200 p-5">
              <div className="flex justify-between items-center mb-4">
                <h3 className="font-semibold text-gray-700">Database #{i + 1}</h3>
                {databases.length > 1 && (
                  <button onClick={() => removeDb(i)} className="text-red-400 hover:text-red-600 text-sm">Remove</button>
                )}
              </div>
              <div className="grid grid-cols-2 gap-4">
                <Field label="Database Name" required>
                  <input className="input" value={db.DatabaseName} onChange={e => updateDb(i, 'DatabaseName', e.target.value)} />
                </Field>
                <Field label="Source Type">
                  <select className="input" value={db.SourceType} onChange={e => updateDb(i, 'SourceType', e.target.value)}>
                    {SOURCE_TYPES.map(t => <option key={t}>{t}</option>)}
                  </select>
                </Field>
                <Field label="Version">
                  <input className="input" value={db.SourceVersion} onChange={e => updateDb(i, 'SourceVersion', e.target.value)} placeholder="e.g. 2019, 19c" />
                </Field>
                <Field label="Environment">
                  <select className="input" value={db.SourceEnvironment} onChange={e => updateDb(i, 'SourceEnvironment', e.target.value)}>
                    {ENVIRONMENTS.map(t => <option key={t}>{t}</option>)}
                  </select>
                </Field>
                <Field label="Max Downtime">
                  <select className="input" value={db.MaxDowntime} onChange={e => updateDb(i, 'MaxDowntime', e.target.value as DatabaseEntry['MaxDowntime'])}>
                    <option value="zero">Zero (online migration)</option>
                    <option value="hours">Hours</option>
                    <option value="days">Days</option>
                  </select>
                </Field>
                <Field label="Data Size">
                  <select className="input" value={db.DataSize} onChange={e => updateDb(i, 'DataSize', e.target.value as DatabaseEntry['DataSize'])}>
                    <option value="small">Small (&lt;100 GB)</option>
                    <option value="medium">Medium (100 GB–1 TB)</option>
                    <option value="large">Large (&gt;1 TB)</option>
                  </select>
                </Field>
                <Field label="Connectivity">
                  <select className="input" value={db.Connectivity} onChange={e => updateDb(i, 'Connectivity', e.target.value as DatabaseEntry['Connectivity'])}>
                    <option value="expressroute">ExpressRoute</option>
                    <option value="vpn">VPN</option>
                    <option value="internet">Internet</option>
                    <option value="none">None</option>
                  </select>
                </Field>
                <Field label="Landing Zone Ready">
                  <select className="input" value={db.LandingZone} onChange={e => updateDb(i, 'LandingZone', e.target.value as DatabaseEntry['LandingZone'])}>
                    <option value="yes">Yes</option>
                    <option value="partial">Partial</option>
                    <option value="no">No</option>
                  </select>
                </Field>
                <Field label="Stored Procedures">
                  <select className="input" value={db.StoredProcs} onChange={e => updateDb(i, 'StoredProcs', e.target.value as DatabaseEntry['StoredProcs'])}>
                    <option value="none">None</option>
                    <option value="few">Few</option>
                    <option value="many">Many</option>
                    <option value="extensive">Extensive</option>
                  </select>
                </Field>
                <Field label="Team Skill">
                  <select className="input" value={db.TeamSkill} onChange={e => updateDb(i, 'TeamSkill', e.target.value as DatabaseEntry['TeamSkill'])}>
                    <option value="expert">Expert</option>
                    <option value="moderate">Moderate</option>
                    <option value="beginner">Beginner</option>
                  </select>
                </Field>
                <Field label="Rollback Plan">
                  <select className="input" value={db.RollbackPlan} onChange={e => updateDb(i, 'RollbackPlan', e.target.value as DatabaseEntry['RollbackPlan'])}>
                    <option value="yes_tested">Yes, tested</option>
                    <option value="yes_untested">Yes, untested</option>
                    <option value="partial">Partial</option>
                    <option value="no">No</option>
                  </select>
                </Field>
                <Field label="DB Count">
                  <input type="number" className="input" min={1} value={db.DatabaseCount} onChange={e => updateDb(i, 'DatabaseCount', parseInt(e.target.value) || 1)} />
                </Field>
              </div>
            </div>
          ))}
          <button onClick={addDb} className="w-full border-2 border-dashed border-gray-300 text-gray-500 hover:border-blue-400 hover:text-blue-600 rounded-xl py-3 text-sm font-medium transition-colors">
            + Add Another Database
          </button>
          <div className="flex justify-between pt-2">
            <button onClick={() => setStep(0)} className="btn-secondary">← Back</button>
            <button
              disabled={databases.some(d => !d.DatabaseName)}
              onClick={() => setStep(2)}
              className="btn-primary"
            >
              Next →
            </button>
          </div>
        </div>
      )}

      {/* Step 2 — Review */}
      {step === 2 && (
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h3 className="font-semibold text-gray-700 mb-4">Review</h3>
          <dl className="grid grid-cols-2 gap-3 text-sm mb-6">
            <dt className="text-gray-500">Customer</dt><dd className="font-medium">{customerName}</dd>
            <dt className="text-gray-500">Requested by</dt><dd className="font-medium">{requestedBy}</dd>
            <dt className="text-gray-500">Databases</dt><dd className="font-medium">{databases.length}</dd>
          </dl>
          <ul className="space-y-2 mb-6">
            {databases.map((d, i) => (
              <li key={i} className="flex items-center gap-3 text-sm bg-gray-50 rounded-lg px-4 py-2">
                <span className="font-medium text-gray-800">{d.DatabaseName}</span>
                <span className="text-gray-400">{d.SourceType} {d.SourceVersion}</span>
                <span className="text-gray-400">{d.SourceEnvironment}</span>
              </li>
            ))}
          </ul>
          {mutation.isError && (
            <p className="text-red-500 text-sm mb-4">Error submitting assessment. Please try again.</p>
          )}
          <div className="flex justify-between">
            <button onClick={() => setStep(1)} className="btn-secondary">← Back</button>
            <button
              onClick={() => mutation.mutate({ customerName, requestedBy, databases })}
              disabled={mutation.isPending}
              className="btn-primary"
            >
              {mutation.isPending ? 'Submitting…' : 'Submit Assessment'}
            </button>
          </div>
        </div>
      )}

      <style>{`
        .input { width: 100%; border: 1px solid #d1d5db; border-radius: 0.5rem; padding: 0.45rem 0.75rem; font-size: 0.875rem; outline: none; }
        .input:focus { border-color: #3b82f6; box-shadow: 0 0 0 2px rgba(59,130,246,0.2); }
        .btn-primary { background: #2563eb; color: white; padding: 0.5rem 1.25rem; border-radius: 0.5rem; font-weight: 600; font-size: 0.875rem; cursor: pointer; transition: background 0.15s; }
        .btn-primary:hover:not(:disabled) { background: #1d4ed8; }
        .btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
        .btn-secondary { background: white; color: #374151; border: 1px solid #d1d5db; padding: 0.5rem 1.25rem; border-radius: 0.5rem; font-weight: 600; font-size: 0.875rem; cursor: pointer; }
        .btn-secondary:hover { background: #f9fafb; }
      `}</style>
    </div>
  );
}

function Field({ label, required, children }: { label: string; required?: boolean; children: React.ReactNode }) {
  return (
    <div>
      <label className="block text-xs font-medium text-gray-600 mb-1">{label}{required && <span className="text-red-400 ml-0.5">*</span>}</label>
      {children}
    </div>
  );
}
