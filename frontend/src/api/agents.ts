export interface AgentRecord {
  agentId: string;
  name: string;
  roles: string[];
  status: 'online' | 'offline' | 'busy';
  hostname: string;
  version: string;
  registeredAt: string;
  lastHeartbeat: string;
  activeJobCount: number;
}

import client from './client';

export const fetchAgents = (role?: string): Promise<AgentRecord[]> =>
  client.get('/agents', { params: role ? { role } : {} }).then(r => r.data);
