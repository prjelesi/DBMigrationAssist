import { describe, expect, it } from 'vitest';
import { parseReportContent } from './reportContent';

const validReport = JSON.stringify({
  executiveSummary: 'Assessment summary',
  scopeSummary: { databaseCount: 1, enginesFound: ['Oracle'], criticalCount: 0 },
  migrationReadiness: 'NeedsWork',
  migrationRequirements: [],
  sourceEnvironment: {
    summary: 'One database',
    environments: [],
    databaseEstate: [],
    dependencies: [],
    informationGaps: [],
  },
  possibleMigrations: [],
  migrationTooling: [],
  azureSkuProposal: [],
  keyRisks: [{ title: 'Compatibility', severity: 'High', description: 'Requires remediation' }],
  recommendedWave: 'Validate in non-production first',
  nextSteps: ['Complete compatibility testing'],
  estimatedEffort: 'High',
});

describe('parseReportContent', () => {
  it('parses a valid report', () => {
    expect(parseReportContent(validReport)?.scopeSummary.databaseCount).toBe(1);
  });

  it('parses a markdown-fenced valid report', () => {
    expect(parseReportContent(`\`\`\`json\n${validReport}\n\`\`\``)?.migrationReadiness).toBe('NeedsWork');
  });

  it.each([
    '{}',
    '[]',
    'null',
    '{"executiveSummary":',
  ])('rejects invalid or incomplete output: %s', output => {
    expect(parseReportContent(output)).toBeNull();
  });

  it('rejects wrong collection types', () => {
    const report = JSON.parse(validReport) as Record<string, unknown>;
    report.keyRisks = {};

    expect(parseReportContent(JSON.stringify(report))).toBeNull();
  });

  it('rejects invalid enum values', () => {
    const report = JSON.parse(validReport) as Record<string, unknown>;
    report.migrationReadiness = 'Unknown';

    expect(parseReportContent(JSON.stringify(report))).toBeNull();
  });
});
