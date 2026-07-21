import { useQuery } from '@tanstack/react-query';
import { fetchAgents } from '../api/agents';
import { listJobs } from '../api/assess';
import { listCollectionJobs } from '../api/collect';
import { Link } from 'react-router-dom';

export default function Dashboard() {
  const { data: agents = [] } = useQuery({ queryKey: ['agents'], queryFn: () => fetchAgents(), refetchInterval: 30_000 });
  const { data: jobs = [] } = useQuery({ queryKey: ['jobs'], queryFn: listJobs, refetchInterval: 30_000 });
  const { data: collectJobs = [] } = useQuery({ queryKey: ['collectJobs'], queryFn: () => listCollectionJobs(), refetchInterval: 15_000 });

  const onlineAgents = agents.filter(a => a.status === 'online').length;
  const completedJobs = jobs.filter((j: { status: string }) => j.status === 'completed').length;
  const pendingCollect = collectJobs.filter(j => j.status === 'pending' || j.status === 'running').length;

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-800 mb-6">DB Migration Readiness Hub</h1>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        <StatCard label="Online Agents" value={onlineAgents} color="green" />
        <StatCard label="Total Assessments" value={jobs.length} color="blue" />
        <StatCard label="Completed" value={completedJobs} color="indigo" />
        <StatCard label="Active Collections" value={pendingCollect} color="amber" />
      </div>

      {/* Quick actions */}
      <div className="flex gap-3 mb-8">
        <Link to="/new-assessment" className="bg-blue-600 hover:bg-blue-700 text-white px-5 py-2 rounded-lg font-medium transition-colors">
          + New Assessment
        </Link>
        <Link to="/agents" className="bg-white hover:bg-gray-50 text-gray-700 border border-gray-300 px-5 py-2 rounded-lg font-medium transition-colors">
          View Agents
        </Link>
        <Link to="/reports" className="bg-white hover:bg-gray-50 text-gray-700 border border-gray-300 px-5 py-2 rounded-lg font-medium transition-colors">
          Reports
        </Link>
      </div>

      {/* Recent assessments */}
      <div className="bg-white rounded-xl border border-gray-200 shadow-sm">
        <div className="px-5 py-4 border-b border-gray-100">
          <h2 className="font-semibold text-gray-700">Recent Assessments</h2>
        </div>
        {jobs.length === 0 ? (
          <p className="text-gray-400 text-sm p-5">No assessments yet. <Link to="/new-assessment" className="text-blue-600 hover:underline">Start one</Link>.</p>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-gray-500 uppercase text-xs">
              <tr>
                <th className="px-5 py-3 text-left">Customer</th>
                <th className="px-5 py-3 text-left">DBs</th>
                <th className="px-5 py-3 text-left">Status</th>
                <th className="px-5 py-3 text-left">Created</th>
                <th className="px-5 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {jobs.slice(0, 10).map((j: { jobId: string; customerName: string; dbCount: number; status: string; createdAt: string }) => (
                <tr key={j.jobId} className="border-t border-gray-50 hover:bg-gray-50">
                  <td className="px-5 py-3 font-medium text-gray-800">{j.customerName}</td>
                  <td className="px-5 py-3 text-gray-500">{j.dbCount}</td>
                  <td className="px-5 py-3"><StatusBadge status={j.status} /></td>
                  <td className="px-5 py-3 text-gray-400">{new Date(j.createdAt).toLocaleString()}</td>
                  <td className="px-5 py-3 text-right">
                    <Link to={`/reports?job=${j.jobId}`} className="text-blue-600 hover:underline text-xs">View</Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function StatCard({ label, value, color }: { label: string; value: number; color: string }) {
  const colors: Record<string, string> = {
    green: 'bg-green-50 text-green-700 border-green-200',
    blue: 'bg-blue-50 text-blue-700 border-blue-200',
    indigo: 'bg-indigo-50 text-indigo-700 border-indigo-200',
    amber: 'bg-amber-50 text-amber-700 border-amber-200',
  };
  return (
    <div className={`rounded-xl border p-4 ${colors[color]}`}>
      <p className="text-xs font-medium uppercase tracking-wide opacity-70">{label}</p>
      <p className="text-3xl font-bold mt-1">{value}</p>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const map: Record<string, string> = {
    completed: 'bg-green-100 text-green-700',
    running: 'bg-blue-100 text-blue-700',
    pending: 'bg-yellow-100 text-yellow-700',
    failed: 'bg-red-100 text-red-700',
  };
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${map[status] ?? 'bg-gray-100 text-gray-600'}`}>
      {status}
    </span>
  );
}
