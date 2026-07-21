import { useQuery } from '@tanstack/react-query';
import { listCollectionJobs, type CollectionJob } from '../api/collect';
import { useState } from 'react';

const STATUS_OPTIONS = ['All', 'pending', 'running', 'completed', 'failed'];

export default function CollectJobs() {
  const [statusFilter, setStatusFilter] = useState('All');
  const { data: jobs = [], isLoading, dataUpdatedAt } = useQuery({
    queryKey: ['collectJobs'],
    queryFn: () => listCollectionJobs(),
    refetchInterval: 15_000,
  });

  const visible = statusFilter === 'All'
    ? jobs
    : jobs.filter(j => j.status === statusFilter);

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-800">Collection Jobs</h1>
        <span className="text-xs text-gray-400">
          {dataUpdatedAt ? `Updated ${new Date(dataUpdatedAt).toLocaleTimeString()}` : ''}
          {' — auto-refreshes every 15s'}
        </span>
      </div>

      {/* Status filter chips */}
      <div className="flex flex-wrap gap-2 mb-6">
        {STATUS_OPTIONS.map(s => (
          <button
            key={s}
            onClick={() => setStatusFilter(s)}
            className={`px-3 py-1 rounded-full text-xs font-medium border transition-colors ${statusFilter === s ? 'bg-blue-600 text-white border-blue-600' : 'bg-white text-gray-600 border-gray-300 hover:border-blue-400'}`}
          >
            {s}
          </button>
        ))}
      </div>

      {isLoading && <p className="text-gray-400">Loading jobs…</p>}

      {!isLoading && visible.length === 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-8 text-center">
          <p className="text-gray-400">No collection jobs found.</p>
        </div>
      )}

      <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
        {visible.length > 0 && (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-gray-500 uppercase text-xs">
              <tr>
                <th className="px-5 py-3 text-left">Database</th>
                <th className="px-5 py-3 text-left">Type</th>
                <th className="px-5 py-3 text-left">Host</th>
                <th className="px-5 py-3 text-left">Status</th>
                <th className="px-5 py-3 text-left">Agent</th>
                <th className="px-5 py-3 text-left">Created</th>
              </tr>
            </thead>
            <tbody>
              {visible.map(j => <JobRow key={j.jobId} job={j} />)}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function JobRow({ job }: { job: CollectionJob }) {
  const statusStyles: Record<string, string> = {
    completed: 'bg-green-100 text-green-700',
    running: 'bg-blue-100 text-blue-700',
    pending: 'bg-yellow-100 text-yellow-700',
    failed: 'bg-red-100 text-red-700',
  };

  return (
    <tr className="border-t border-gray-50 hover:bg-gray-50">
      <td className="px-5 py-3 font-medium text-gray-800">{job.databaseName}</td>
      <td className="px-5 py-3">
        <span className="bg-indigo-50 text-indigo-700 text-xs px-2 py-0.5 rounded-full">{job.role}</span>
      </td>
      <td className="px-5 py-3 text-gray-500 font-mono text-xs">{job.host}{job.port ? `:${job.port}` : ''}</td>
      <td className="px-5 py-3">
        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusStyles[job.status] ?? 'bg-gray-100 text-gray-600'}`}>
          {job.status}
        </span>
        {job.error && <p className="text-red-400 text-xs mt-1 truncate max-w-xs" title={job.error}>{job.error}</p>}
      </td>
      <td className="px-5 py-3 text-gray-400 text-xs font-mono">{job.assignedAgentId ? job.assignedAgentId.slice(0, 8) + '…' : '—'}</td>
      <td className="px-5 py-3 text-gray-400">{new Date(job.createdAt).toLocaleString()}</td>
    </tr>
  );
}
