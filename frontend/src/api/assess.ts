import client from './client';

export interface DatabaseEntry {
  DatabaseName: string;
  SourceType: string;
  SourceVersion: string;
  SourceEnvironment: string;
  TargetType?: string;
  MaxDowntime: 'zero' | 'hours' | 'days';
  Connectivity: 'expressroute' | 'vpn' | 'internet' | 'none';
  LandingZone: 'yes' | 'partial' | 'no';
  DataSize: 'small' | 'medium' | 'large';
  StoredProcs?: 'none' | 'few' | 'many' | 'extensive';
  Dependencies?: string;
  SpecialFeatures?: string;
  TeamSkill: 'expert' | 'moderate' | 'beginner';
  RollbackPlan: 'yes_tested' | 'yes_untested' | 'partial' | 'no';
  DatabaseCount?: number;
}

export interface AssessmentRequest {
  customerName: string;
  requestedBy: string;
  databases: DatabaseEntry[];
  runInfoGather?: boolean;
}

export interface AssessmentResponse {
  jobId: string;
  status: string;
  message: string;
  statusUrl: string;
}

export interface JobStatus {
  jobId: string;
  status: string;
  createdAt: string;
  completedAt?: string;
  customerName: string;
  dbCount: number;
  reportUrl?: string;
  dataverseRecordId?: string;
  error?: string;
}

export const startAssessment = (req: AssessmentRequest): Promise<AssessmentResponse> =>
  client.post('/assess', req).then(r => r.data);

export const getAssessmentStatus = (jobId: string): Promise<JobStatus> =>
  client.get(`/status/${jobId}`).then(r => r.data);

export const getReport = (jobId: string): Promise<unknown[]> =>
  client.get(`/report/${jobId}`).then(r => r.data);

export const listJobs = (): Promise<JobStatus[]> =>
  client.get('/status').then(r => r.data).catch(() => []);
