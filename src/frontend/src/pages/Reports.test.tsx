import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import Reports from './Reports';

describe('Reports', () => {
  it('renders an explicit unavailable state for a malformed stored report', () => {
    const queryClient = new QueryClient({
      defaultOptions: { queries: { staleTime: Infinity } },
    });
    const projectId = '75dd0324-446d-4988-95dc-2e2c8f8215e3';
    queryClient.setQueryData(['projects'], [{ projectId, name: 'Migration project' }]);
    queryClient.setQueryData(['aiStatus'], { available: true, readyForReporting: true });
    queryClient.setQueryData(['reports', projectId], [{
      generatedReportId: 'f5cbb0fe-6686-4c32-9af5-8b0d7e90446c',
      projectId,
      databaseId: null,
      databaseName: null,
      evidenceBundleId: 'e3e50896-a411-4302-a91f-96cedad42289',
      reportJson: '{}',
      state: 'DraftReady',
      generatedBy: 'test-user',
      generatedAt: '2026-09-07T12:00:00Z',
      reviewedBy: null,
      reviewedAt: null,
      approvedBy: null,
      approvedAt: null,
      exportedAt: null,
    }]);

    const markup = renderToStaticMarkup(
      <QueryClientProvider client={queryClient}>
        <Reports />
      </QueryClientProvider>,
    );

    expect(markup).toContain('Unavailable');
    expect(markup).toContain('Invalid data');
    expect(markup).toContain('Report unavailable');
  });
});
