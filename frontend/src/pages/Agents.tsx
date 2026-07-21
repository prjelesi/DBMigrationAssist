import { useQuery } from '@tanstack/react-query';
import { fetchAgents, type AgentRecord } from '../api/agents';
import { useState } from 'react';

const ROLES = ['All', 'sqlserver', 'oracle', 'postgresql', 'mysql', 'mariadb', 'mongodb', 'cassandra'];

export default function Agents() {
  const [roleFilter, setRoleFilter] = useState('All');
  const { data: agents = [], isLoading, dataUpdatedAt } = useQuery({
    queryKey: ['agents'],
    queryFn: () => fetchAgents(),
    refetchInterval: 30_000,
  });

  const visible = roleFilter === 'All'
    ? agents
    : agents.filter(a => a.roles.includes(roleFilter));

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-800">Registered Agents</h1>
        <span className="text-xs text-gray-400">
          {dataUpdatedAt ? `Updated ${new Date(dataUpdatedAt).toLocaleTimeString()}` : ''}
          {' — auto-refreshes every 30s'}
        </span>
      </div>

      {/* Role filter chips */}
      <div className="flex flex-wrap gap-2 mb-6">
        {ROLES.map(r => (
          <button
            key={r}
            onClick={() => setRoleFilter(r)}
            className={`px-3 py-1 rounded-full text-xs font-medium border transition-colors ${roleFilter === r ? 'bg-blue-600 text-white border-blue-600' : 'bg-white text-gray-600 border-gray-300 hover:border-blue-400'}`}
          >
            {r}
          </button>
        ))}
      </div>

      {isLoading && <p className="text-gray-400">Loading agents…</p>}

      {!isLoading && visible.length === 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-8 text-center">
          <p className="text-gray-400">No agents registered. Start a collector agent with <code className="bg-gray-100 px-1 rounded">docker compose up agent-relational</code></p>
        </div>
      )}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {visible.map(a => <AgentCard key={a.agentId} agent={a} />)}
      </div>
    </div>
  );
}

function AgentCard({ agent }: { agent: AgentRecord }) {
  const statusStyles: Record<string, string> = {
    online: 'bg-green-100 text-green-700',
    offline: 'bg-gray-100 text-gray-500',
    busy: 'bg-amber-100 text-amber-700',
  };

  const lastSeen = agent.lastHeartbeat
    ? `${Math.round((Date.now() - new Date(agent.lastHeartbeat).getTime()) / 1000)}s ago`
    : 'never';

  return (
    <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-5">
      <div className="flex justify-between items-start mb-3">
        <div>
          <p className="font-semibold text-gray-800 text-sm">{agent.name}</p>
          <p className="text-xs text-gray-400">{agent.hostname}</p>
        </div>
        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusStyles[agent.status] ?? 'bg-gray-100 text-gray-500'}`}>
          {agent.status}
        </span>
      </div>

      <div className="flex flex-wrap gap-1 mb-3">
        {agent.roles.map(r => (
          <span key={r} className="bg-blue-50 text-blue-700 text-xs px-2 py-0.5 rounded-full">{r}</span>
        ))}
      </div>

      <div className="text-xs text-gray-400 space-y-1">
        <div className="flex justify-between"><span>Version</span><span>{agent.version}</span></div>
        <div className="flex justify-between"><span>Active Jobs</span><span>{agent.activeJobCount}</span></div>
        <div className="flex justify-between"><span>Last Seen</span><span>{lastSeen}</span></div>
      </div>
    </div>
  );
}
