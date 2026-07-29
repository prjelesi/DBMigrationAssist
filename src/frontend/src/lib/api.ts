import axios from 'axios';
import type {
  Agent, AgentJobSummary, AssessmentResult, Customer, DatabaseInstance,
  EvidenceReport, Project, ProjectEnvironment,
  QuestionnaireTemplate, QuestionnaireResponse,
} from '../types';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL ?? 'http://localhost:5000',
  headers: { 'Content-Type': 'application/json' },
});

// Projects
export const getProjects = () => api.get<Project[]>('/api/projects').then(r => r.data);
export const getProject = (id: string) => api.get<Project>(`/api/projects/${id}`).then(r => r.data);
export const createProject = (data: {
  customerId: string; name: string; description?: string;
  deploymentMode: string; createdBy: string;
}) => api.post<Project>('/api/projects', data).then(r => r.data);

// Agents
export const getAgents = (projectId: string) =>
  api.get<Agent[]>('/api/agents', { params: { projectId } }).then(r => r.data);

export const registerAgent = (data: {
  projectId: string; environmentId?: string; name: string;
  allowedPlugins: string[]; pskMode: string; userPsk?: string; createdBy: string;
}) => api.post('/api/agents', data).then(r => r.data);

export const getAgentJobs = (agentId: string) =>
  api.get<AgentJobSummary[]>(`/api/agents/${agentId}/jobs`).then(r => r.data);

export const getJobResults = (agentId: string, jobId: string) =>
  api.get<AssessmentResult[]>(`/api/agents/${agentId}/jobs/${jobId}/results`).then(r => r.data);

export const dispatchJob = (agentId: string, data: {
  databaseId?: string;
  pluginId: string;
  parametersJson: string; // JSON-encoded JobCredentials
}) => api.post(`/api/agents/${agentId}/jobs`, data).then(r => r.data);

// Databases
export const getDatabases = (projectId: string) =>
  api.get<DatabaseInstance[]>('/api/databases', { params: { projectId } }).then(r => r.data);

// Environments
export const getEnvironments = (projectId: string) =>
  api.get<ProjectEnvironment[]>('/api/environments', { params: { projectId } }).then(r => r.data);

// Customers
export const getCustomers = () => api.get<Customer[]>('/api/customers').then(r => r.data);
export const createCustomer = (data: { name: string; industry?: string; region?: string }) =>
  api.post<Customer>('/api/customers', data).then(r => r.data);

// Questionnaires
export const getTemplates = () =>
  api.get<QuestionnaireTemplate[]>('/api/questionnaires/templates').then(r => r.data);
export const getTemplate = (id: string) =>
  api.get<QuestionnaireTemplate>(`/api/questionnaires/templates/${id}`).then(r => r.data);
export const seedTemplates = () =>
  api.post('/api/questionnaires/templates/seed').then(r => r.data);
export const getResponses = (projectId: string) =>
  api.get<QuestionnaireResponse[]>('/api/questionnaires/responses', { params: { projectId } }).then(r => r.data);
export const startResponse = (data: { projectId: string; templateId: string; assignedTo?: string }) =>
  api.post<QuestionnaireResponse>('/api/questionnaires/responses', data).then(r => r.data);
export const getResponse = (id: string) =>
  api.get<QuestionnaireResponse>(`/api/questionnaires/responses/${id}`).then(r => r.data);
export const saveAnswers = (id: string, answers: { questionId: string; value: string | null }[]) =>
  api.put(`/api/questionnaires/responses/${id}/answers`, { answers }).then(r => r.data);
export const submitResponse = (id: string) =>
  api.post(`/api/questionnaires/responses/${id}/submit`).then(r => r.data);

// Evidence
export const getEvidence = (projectId: string) =>
  api.get<EvidenceReport[]>('/api/evidence', { params: { projectId } }).then(r => r.data);
export const getEvidenceDetail = (id: string) =>
  api.get<EvidenceReport>(`/api/evidence/${id}`).then(r => r.data);
export const deleteEvidence = (id: string) =>
  api.delete(`/api/evidence/${id}`).then(r => r.data);
export const reparseEvidence = (id: string) =>
  api.post(`/api/evidence/${id}/reparse`).then(r => r.data);
export const uploadEvidence = (projectId: string, uploadedBy: string, sourceType: string, file: File) => {
  const form = new FormData();
  form.append('projectId', projectId);
  form.append('uploadedBy', uploadedBy);
  form.append('sourceType', sourceType);
  form.append('file', file);
  return api.post('/api/evidence/upload', form, {
    headers: { 'Content-Type': 'multipart/form-data' },
    onUploadProgress: undefined,
  }).then(r => r.data);
};

// Environments (extra mutations — getEnvironments already exists above)
export const createEnvironment = (data: {
  projectId: string; name: string; type: string;
  location?: string; connectivityZone?: string;
}) => api.post<ProjectEnvironment>('/api/environments', data).then(r => r.data);

export const updateEnvironment = (id: string, data: {
  name?: string; type?: string; location?: string; connectivityZone?: string;
}) => api.patch<ProjectEnvironment>(`/api/environments/${id}`, data).then(r => r.data);

export const deleteEnvironment = (id: string) =>
  api.delete(`/api/environments/${id}`).then(r => r.data);

// Portfolios
export interface PortfolioDto {
  portfolioId: string;
  projectId: string;
  name: string;
  groupingRule: string;
  groupKey: string;
  databaseIds: string[];
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export const getPortfolios = (projectId: string) =>
  api.get<PortfolioDto[]>('/api/portfolios', { params: { projectId } }).then(r => r.data);

export const savePortfolio = (data: {
  projectId: string; name: string; groupingRule: string;
  groupKey: string; databaseIds: string[]; notes?: string;
}) => api.post<PortfolioDto>('/api/portfolios', data).then(r => r.data);

export const deletePortfolio = (id: string) =>
  api.delete(`/api/portfolios/${id}`).then(r => r.data);

// Graph
export interface GraphEdgeDto {
  edgeId: string;
  projectId: string;
  sourceDatabaseId: string;
  targetDatabaseId: string;
  relationType: string;
  protocol: string;
  direction: string;
  confidence: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export const getGraphEdges = (projectId: string) =>
  api.get<GraphEdgeDto[]>('/api/graph/edges', { params: { projectId } }).then(r => r.data);

export const saveGraphEdges = (projectId: string, edges: {
  edgeId: string; sourceDatabaseId: string; targetDatabaseId: string;
  relationType?: string; protocol?: string; direction?: string; confidence?: string; notes?: string;
}[]) =>
  api.post<{ saved: number; deleted: number }>('/api/graph/edges/batch', { projectId, edges }).then(r => r.data);

export const deleteGraphEdge = (edgeId: string) =>
  api.delete(`/api/graph/edges/${edgeId}`).then(r => r.data);

// AI / Reports
export const generateReport = (projectId: string) =>
  api.post<{ projectId: string; reportJson: string; generatedAt: string }>(
    '/api/ai/generate-report', { projectId }
  ).then(r => r.data);

export const getAiStatus = () =>
  api.get<{ available: boolean; message: string }>('/api/ai/status').then(r => r.data);

export default api;
