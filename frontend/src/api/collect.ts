import client from './client';

export interface CollectionJob {
  jobId: string;
  assessmentJobId?: string;
  role: string;
  databaseName: string;
  host: string;
  port?: number;
  username?: string;
  status: string;
  assignedAgentId?: string;
  createdAt: string;
  startedAt?: string;
  completedAt?: string;
  error?: string;
}

export interface CreateCollectionJobRequest {
  role: string;
  databaseName: string;
  host: string;
  port?: number;
  username?: string;
  password?: string;
  additionalParams?: Record<string, unknown>;
  assessmentJobId?: string;
}

export const createCollectionJob = (req: CreateCollectionJobRequest): Promise<CollectionJob> =>
  client.post('/collect', req).then(r => r.data);

export const getCollectionJob = (jobId: string): Promise<CollectionJob> =>
  client.get(`/collect/${jobId}`).then(r => r.data);

export const listCollectionJobs = (status?: string, role?: string): Promise<CollectionJob[]> =>
  client.get('/collect', { params: { ...(status ? { status } : {}), ...(role ? { role } : {}) } })
    .then(r => r.data);
