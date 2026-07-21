import { useQuery } from '@tanstack/react-query';
import { listJobs, getReport, type JobStatus } from '../api/assess';
import { useSearchParams } from 'react-router-dom';
import { useState } from 'react';

export default function Reports() {
  const [searchParams, setSearchParams] = useSearchParams();
  const initialJob = searchParams.get('job') ?? '';
  const [selectedJobId, setSelectedJobId] = useState(initialJob);

  const { data: jobs = [], isLoading } = useQuery({ queryKey: ['jobs'], queryFn: listJobs, refetchInterval: 15_000 });

  const { data: report } = useQuery({
    queryKey: ['report', selectedJobId],
    queryFn: () => getReport(selectedJobId),
    enabled: !!selectedJobId,
  });

  const selectJob = (id: string) => {
    setSelectedJobId(id);
    setSearchParams(id ? { job: id } : {});
  };

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-800 mb-6">Assessment Reports</h1>

      <div className="flex gap-6">
        {/* Left panel — job list */}
        <div className="w-72 shrink-0">
          <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
            <div className="px-4 py-3 bg-gray-50 border-b border-gray-100">
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Assessments</p>
            </div>
            {isLoading && <p className="text-gray-400 text-sm p-4">Loading…</p>}
            {!isLoading && jobs.length === 0 && <p className="text-gray-400 text-sm p-4">No assessments yet.</p>}
            <ul>
              {jobs.map((j: JobStatus) => (
                <li key={j.jobId}>
                  <button
                    onClick={() => selectJob(j.jobId)}
                    className={`w-full text-left px-4 py-3 hover:bg-blue-50 transition-colors border-b border-gray-50 ${selectedJobId === j.jobId ? 'bg-blue-50 border-l-2 border-l-blue-500' : ''}`}
                  >
                    <p className="text-sm font-medium text-gray-800 truncate">{j.customerName}</p>
                    <p className="text-xs text-gray-400 mt-0.5">{new Date(j.createdAt).toLocaleDateString()} · {j.dbCount} DB</p>
                    <span className={`text-xs px-1.5 py-0.5 rounded-full font-medium mt-1 inline-block ${j.status === 'completed' ? 'bg-green-100 text-green-700' : j.status === 'failed' ? 'bg-red-100 text-red-700' : 'bg-yellow-100 text-yellow-700'}`}>
                      {j.status}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* Right panel — report detail */}
        <div className="flex-1">
          {!selectedJobId && (
            <div className="bg-white rounded-xl border border-gray-200 p-10 text-center text-gray-400">
              Select an assessment to view the report
            </div>
          )}
          {selectedJobId && !report && (
            <div className="bg-white rounded-xl border border-gray-200 p-10 text-center text-gray-400">
              Loading report…
            </div>
          )}
          {report && (report as unknown[]).length > 0 && (
            <div className="space-y-4">
              {(report as Record<string, unknown>[]).map((db, i) => (
                <DbReportCard key={i} db={db} />
              ))}
            </div>
          )}
          {report && (report as unknown[]).length === 0 && (
            <div className="bg-white rounded-xl border border-gray-200 p-10 text-center text-gray-400">
              Report is not ready yet. Assessment may still be running.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function DbReportCard({ db }: { db: Record<string, unknown> }) {
  const score = typeof db.ReadinessScore === 'number' ? db.ReadinessScore : null;
  const tier = typeof db.ReadinessTier === 'string' ? db.ReadinessTier : undefined;
  const target = typeof db.RecommendedTarget === 'string' ? db.RecommendedTarget : undefined;
  const dbName = typeof db.DatabaseName === 'string' ? db.DatabaseName : '';
  const sourceType = typeof db.SourceType === 'string' ? db.SourceType : '';
  const sourceVersion = typeof db.SourceVersion === 'string' ? db.SourceVersion : '';
  const migrationPath = typeof db.MigrationPath === 'string' ? db.MigrationPath : null;

  const tierColors: Record<string, string> = {
    Green: 'bg-green-100 text-green-700 border-green-200',
    Yellow: 'bg-yellow-100 text-yellow-700 border-yellow-200',
    Red: 'bg-red-100 text-red-700 border-red-200',
  };

  return (
    <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-5">
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="font-semibold text-gray-800 text-lg">{dbName}</h3>
          <p className="text-sm text-gray-400">{sourceType} {sourceVersion} → {target ?? 'TBD'}</p>
        </div>
        <div className="text-right">
          {score !== null && (
            <div className="flex flex-col items-end gap-1">
              <ScoreGauge score={score} />
              {tier && (
                <span className={`px-2 py-0.5 rounded-full text-xs font-semibold border ${tierColors[tier] ?? 'bg-gray-100 text-gray-600 border-gray-200'}`}>
                  {tier}
                </span>
              )}
            </div>
          )}
        </div>
      </div>

      {migrationPath && (
        <div className="bg-gray-50 rounded-lg p-3 text-sm text-gray-600 mb-3">
          <span className="font-medium">Migration Path: </span>{migrationPath}
        </div>
      )}

      {/* Blockers */}
      {Array.isArray(db.Blockers) && (db.Blockers as string[]).length > 0 && (
        <div className="mb-3">
          <p className="text-xs font-semibold text-red-500 mb-1">Blockers</p>
          <ul className="space-y-1">
            {(db.Blockers as string[]).map((b, i) => (
              <li key={i} className="text-xs text-red-600 bg-red-50 rounded px-2 py-1">⚠ {b}</li>
            ))}
          </ul>
        </div>
      )}

      {/* Recommendations */}
      {Array.isArray(db.Recommendations) && (db.Recommendations as string[]).length > 0 && (
        <div>
          <p className="text-xs font-semibold text-gray-500 mb-1">Recommendations</p>
          <ul className="space-y-1">
            {(db.Recommendations as string[]).map((r, i) => (
              <li key={i} className="text-xs text-gray-600 bg-blue-50 rounded px-2 py-1">→ {r}</li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function ScoreGauge({ score }: { score: number }) {
  const color = score >= 70 ? '#16a34a' : score >= 40 ? '#d97706' : '#dc2626';
  return (
    <div className="flex items-center gap-2">
      <svg width="48" height="48" viewBox="0 0 48 48">
        <circle cx="24" cy="24" r="20" fill="none" stroke="#e5e7eb" strokeWidth="5" />
        <circle
          cx="24" cy="24" r="20"
          fill="none"
          stroke={color}
          strokeWidth="5"
          strokeDasharray={`${(score / 100) * 125.6} 125.6`}
          strokeLinecap="round"
          transform="rotate(-90 24 24)"
        />
        <text x="24" y="28" textAnchor="middle" fontSize="11" fontWeight="bold" fill={color}>{score}</text>
      </svg>
    </div>
  );
}
