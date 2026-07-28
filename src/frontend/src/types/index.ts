// Domain types matching the backend entities

export type DeploymentMode = 'Standalone' | 'Connected' | 'AirGapped';
export type EngineType = 'Oracle' | 'PostgreSQL' | 'SqlServer' | 'MySQL' | 'MongoDB' | 'Cassandra' | 'Sybase' | 'Unknown';
export type AgentStatus = 'Registered' | 'Active' | 'Offline' | 'Revoked';
export type JobStatus = 'Pending' | 'Assigned' | 'Running' | 'Completed' | 'Failed' | 'Cancelled';
export type Criticality = 'Low' | 'Medium' | 'High' | 'Critical';
export type ConfidenceLevel = 'High' | 'Medium' | 'Low' | 'Unverified';
export type PskMode = 'SystemGenerated' | 'UserSupplied';
export type ReportState = 'Pending' | 'QuestionnaireActive' | 'BundleReady' | 'AiGenerating' | 'DraftReady' | 'InReview' | 'Approved' | 'Exported';

export interface Customer {
  customerId: string;
  name: string;
  industry?: string;
  region?: string;
  createdAt: string;
}

export interface Project {
  projectId: string;
  customerId: string;
  name: string;
  description?: string;
  deploymentMode: DeploymentMode;
  status: string;
  createdBy: string;
  createdAt: string;
  customer?: Customer;
  environments?: ProjectEnvironment[];
}

export interface ProjectEnvironment {
  environmentId: string;
  projectId: string;
  name: string;
  type: string;
  location?: string;
  connectivityZone?: string;
  createdAt: string;
}

export interface DatabaseInstance {
  databaseId: string;
  projectId: string;
  environmentId?: string;
  name: string;
  engine: EngineType;
  version?: string;
  hostName?: string;
  port?: number;
  criticality: Criticality;
  ownerName?: string;
  createdAt: string;
  environment?: ProjectEnvironment;
}

export interface Agent {
  agentId: string;
  projectId: string;
  environmentId?: string;
  name: string;
  status: AgentStatus;
  pskMode: PskMode;
  allowedPlugins: string[];
  lastHeartbeatAt?: string;
  pskIssuedAt?: string;
  createdBy: string;
  createdAt: string;
}

export interface AgentBootstrapPackage {
  agentId: string;
  backendUrl: string;
  psk: string;
  allowedPlugins: string[];
  issuedAt: string;
}

export interface RegisterAgentResponse {
  agentId: string;
  name: string;
  status: AgentStatus;
  bootstrapPackage: AgentBootstrapPackage;
  warning: string;
}

export interface AgentJobSummary {
  jobId: string;
  pluginId: string;
  status: JobStatus;
  startedAt?: string;
  completedAt?: string;
  createdAt: string;
  databaseName?: string;
  resultCount: number;
}

// ── Questionnaire ───────────────────────────────────────────────────────

export type QuestionType = 'Text' | 'Textarea' | 'Select' | 'MultiSelect' | 'Boolean' | 'Number';
export type QuestionnairePhase = 'Baseline' | 'Supplemental';
export type ResponseStatus = 'NotStarted' | 'InProgress' | 'Completed' | 'Submitted';

export interface Question {
  questionId: string;
  sectionId: string;
  text: string;
  helpText?: string;
  type: QuestionType;
  isRequired: boolean;
  order: number;
  optionsJson?: string;
}

export interface QuestionnaireSection {
  sectionId: string;
  templateId: string;
  title: string;
  description?: string;
  order: number;
  questions: Question[];
}

export interface QuestionnaireTemplate {
  templateId: string;
  name: string;
  description?: string;
  phase: QuestionnairePhase;
  version: number;
  sections: QuestionnaireSection[];
}

export interface Answer {
  answerId: string;
  responseId: string;
  questionId: string;
  value?: string;
}

export interface QuestionnaireResponse {
  responseId: string;
  projectId: string;
  templateId: string;
  status: ResponseStatus;
  assignedTo?: string;
  createdAt: string;
  updatedAt: string;
  submittedAt?: string;
  template?: QuestionnaireTemplate;
  answers?: Answer[];
}

// ── Evidence ────────────────────────────────────────────────────────────

export type ParseStatus = 'Pending' | 'Parsing' | 'Parsed' | 'Failed' | 'ReviewRequired';
export type ReportSourceType = 'DmaJson' | 'Awr' | 'Statspack' | 'AzureMigrate' | 'CsvGeneric' | 'JsonGeneric' | 'Other';

export interface EvidenceReport {
  reportId: string;
  projectId: string;
  fileName: string;
  sourceType: ReportSourceType;
  fileSizeBytes: number;
  fileHash?: string;
  parseStatus: ParseStatus;
  parseConfidence: ConfidenceLevel;
  parseSummaryJson?: string;
  parseErrorMessage?: string;
  uploadedBy: string;
  uploadedAt: string;
  hasSummary?: boolean;
}
