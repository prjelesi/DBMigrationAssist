export interface RiskItem {
  title: string;
  severity: 'High' | 'Medium' | 'Low';
  description: string;
}

export interface MigrationRequirement {
  category: string;
  requirement: string;
  evidenceStatus: 'Confirmed' | 'Assumption' | 'Gap';
  details: string;
}

export interface SourceEnvironment {
  summary: string;
  environments: Array<{ name: string; type: string; location: string; connectivity: string; databaseCount: number }>;
  databaseEstate: Array<{ name: string; engine: string; version: string; host: string; criticality: string; environment: string }>;
  dependencies: string[];
  informationGaps: string[];
}

export interface MigrationOption {
  sourcePlatform: string;
  targetAzureService: string;
  migrationType: string;
  recommendation: 'Preferred' | 'Candidate' | 'Not Recommended';
  rationale: string;
  considerations: string[];
}

export interface MigrationToolingItem {
  phase: string;
  tools: string[];
  purpose: string;
  prerequisites: string[];
}

export interface AzureSkuProposal {
  environment: string;
  targetService: string;
  skuTier: string;
  compute: string;
  storage: string;
  availability: string;
  networking: string;
  rationale: string;
  sizingBasis: string;
  assumptions: string[];
}

export interface ReportContent {
  executiveSummary: string;
  scopeSummary: { databaseCount: number; enginesFound: string[]; criticalCount: number };
  migrationReadiness: 'Ready' | 'NeedsWork' | 'NotReady';
  migrationRequirements?: MigrationRequirement[];
  sourceEnvironment?: SourceEnvironment;
  possibleMigrations?: MigrationOption[];
  migrationTooling?: MigrationToolingItem[];
  azureSkuProposal?: AzureSkuProposal[];
  keyRisks: RiskItem[];
  recommendedWave: string;
  nextSteps: string[];
  estimatedEffort: 'Low' | 'Medium' | 'High' | 'Very High';
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isString = (value: unknown): value is string => typeof value === 'string';
const isNumber = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);
const isStringArray = (value: unknown): value is string[] => Array.isArray(value) && value.every(isString);
const isOneOf = <T extends string>(value: unknown, allowed: readonly T[]): value is T =>
  isString(value) && allowed.includes(value as T);

function isObjectArray(value: unknown, validate: (item: Record<string, unknown>) => boolean): boolean {
  return Array.isArray(value) && value.every(item => isRecord(item) && validate(item));
}

function isOptionalObjectArray(
  value: unknown,
  validate: (item: Record<string, unknown>) => boolean,
): boolean {
  return value === undefined || isObjectArray(value, validate);
}

function isSourceEnvironment(value: unknown): value is SourceEnvironment {
  if (!isRecord(value)) return false;

  return isString(value.summary)
    && isObjectArray(value.environments, item =>
      isString(item.name) && isString(item.type) && isString(item.location)
      && isString(item.connectivity) && isNumber(item.databaseCount))
    && isObjectArray(value.databaseEstate, item =>
      isString(item.name) && isString(item.engine) && isString(item.version)
      && isString(item.host) && isString(item.criticality) && isString(item.environment))
    && isStringArray(value.dependencies)
    && isStringArray(value.informationGaps);
}

export function isReportContent(value: unknown): value is ReportContent {
  if (!isRecord(value) || !isRecord(value.scopeSummary)) return false;

  return isString(value.executiveSummary)
    && isNumber(value.scopeSummary.databaseCount)
    && isStringArray(value.scopeSummary.enginesFound)
    && isNumber(value.scopeSummary.criticalCount)
    && isOneOf(value.migrationReadiness, ['Ready', 'NeedsWork', 'NotReady'])
    && isOptionalObjectArray(value.migrationRequirements, item =>
      isString(item.category) && isString(item.requirement)
      && isOneOf(item.evidenceStatus, ['Confirmed', 'Assumption', 'Gap']) && isString(item.details))
    && (value.sourceEnvironment === undefined || isSourceEnvironment(value.sourceEnvironment))
    && isOptionalObjectArray(value.possibleMigrations, item =>
      isString(item.sourcePlatform) && isString(item.targetAzureService) && isString(item.migrationType)
      && isOneOf(item.recommendation, ['Preferred', 'Candidate', 'Not Recommended'])
      && isString(item.rationale) && isStringArray(item.considerations))
    && isOptionalObjectArray(value.migrationTooling, item =>
      isString(item.phase) && isStringArray(item.tools) && isString(item.purpose) && isStringArray(item.prerequisites))
    && isOptionalObjectArray(value.azureSkuProposal, item =>
      isString(item.environment) && isString(item.targetService) && isString(item.skuTier)
      && isString(item.compute) && isString(item.storage) && isString(item.availability)
      && isString(item.networking) && isString(item.rationale) && isString(item.sizingBasis)
      && isStringArray(item.assumptions))
    && isObjectArray(value.keyRisks, item =>
      isString(item.title) && isOneOf(item.severity, ['High', 'Medium', 'Low']) && isString(item.description))
    && isString(value.recommendedWave)
    && isStringArray(value.nextSteps)
    && isOneOf(value.estimatedEffort, ['Low', 'Medium', 'High', 'Very High']);
}

export function parseReportContent(raw: string): ReportContent | null {
  try {
    const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
    const parsed: unknown = JSON.parse(cleaned);
    return isReportContent(parsed) ? parsed : null;
  } catch {
    return null;
  }
}
