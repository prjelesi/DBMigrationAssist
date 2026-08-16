using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Worker;

/// <summary>
/// Polls for completed assessment results that have not yet been AI-enriched
/// and triggers enrichment by calling the API's /api/ai/enrich/{resultId} endpoint.
///
/// Detection heuristic: a result whose FindingJson does not contain the key
/// "migrationPath" has not been through AI enrichment.
///
/// This is a best-effort service — if AI is not configured the API returns 400
/// and the result is silently skipped until AI becomes available.
/// </summary>
public sealed class ResultEnrichmentService(
    IDbContextFactory<AssessmentDbContext> dbFactory,
    IHttpClientFactory httpClientFactory,
    IConfiguration config,
    ILogger<ResultEnrichmentService> log) : BackgroundService
{
    private readonly TimeSpan _interval = TimeSpan.FromSeconds(
        config.GetValue<int>("Worker:EnrichmentIntervalSeconds", 30));

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        log.LogInformation(
            "ResultEnrichmentService started — polling every {Interval}s.",
            _interval.TotalSeconds);

        // Give the API container a moment to be fully ready before the first poll
        await Task.Delay(TimeSpan.FromSeconds(15), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await EnrichPendingResultsAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                log.LogError(ex, "Error during result enrichment poll.");
            }

            await Task.Delay(_interval, stoppingToken);
        }
    }

    private async Task EnrichPendingResultsAsync(CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);

        // Results from completed jobs that haven't been through AI enrichment yet.
        // "migrationPath" is the key injected by the API's EnrichFinding endpoint.
        var unenriched = await db.Results
            .Where(r => r.Job.Status == JobStatus.Completed
                     && !EF.Functions.JsonExists(r.FindingJson, "migrationPath"))
            .Select(r => r.ResultId)
            .Take(10) // process in small batches per cycle
            .ToListAsync(ct);

        if (unenriched.Count == 0) return;

        log.LogInformation("Found {Count} result(s) awaiting AI enrichment.", unenriched.Count);

        var http = httpClientFactory.CreateClient("api");
        foreach (var resultId in unenriched)
        {
            if (ct.IsCancellationRequested) break;
            try
            {
                var response = await http.PostAsync($"/api/ai/enrich/{resultId}", content: null, ct);

                if (response.IsSuccessStatusCode)
                {
                    log.LogInformation("Successfully enriched result {ResultId}.", resultId);
                }
                else if ((int)response.StatusCode == 400)
                {
                    // AI not configured — expected; stop spamming for this cycle
                    log.LogDebug("AI not configured — enrichment skipped for result {ResultId}.", resultId);
                    break;
                }
                else if ((int)response.StatusCode == 404)
                {
                    log.LogWarning("Result {ResultId} not found on API — skipping.", resultId);
                }
                else
                {
                    log.LogWarning(
                        "Enrichment call returned {StatusCode} for result {ResultId}.",
                        (int)response.StatusCode, resultId);
                }
            }
            catch (HttpRequestException ex)
            {
                log.LogWarning(ex, "Could not reach API to enrich result {ResultId} — will retry next cycle.", resultId);
                break; // don't hammer a down API
            }
        }
    }
}
