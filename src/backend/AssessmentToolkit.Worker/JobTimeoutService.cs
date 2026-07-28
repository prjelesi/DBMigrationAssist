using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Worker;

/// <summary>
/// Detects assessment jobs that are stuck in Assigned or Running state
/// beyond the configured timeout and marks them as Failed.
/// </summary>
public sealed class JobTimeoutService(
    IDbContextFactory<AssessmentDbContext> dbFactory,
    IConfiguration config,
    ILogger<JobTimeoutService> log) : BackgroundService
{
    private readonly TimeSpan _interval = TimeSpan.FromSeconds(
        config.GetValue<int>("Worker:JobTimeoutIntervalSeconds", 120));
    private readonly TimeSpan _jobTimeout = TimeSpan.FromMinutes(
        config.GetValue<int>("Worker:JobTimeoutMinutes", 30));

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        log.LogInformation(
            "JobTimeoutService started — interval {Interval}s, job timeout {Timeout}min.",
            _interval.TotalSeconds, _jobTimeout.TotalMinutes);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CheckJobTimeoutsAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                log.LogError(ex, "Error during job timeout check.");
            }

            await Task.Delay(_interval, stoppingToken);
        }
    }

    private async Task CheckJobTimeoutsAsync(CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var cutoff = DateTimeOffset.UtcNow - _jobTimeout;

        var timedOutJobs = await db.Jobs
            .Where(j => (j.Status == JobStatus.Assigned || j.Status == JobStatus.Running)
                     && j.StartedAt != null && j.StartedAt < cutoff)
            .ToListAsync(ct);

        if (timedOutJobs.Count > 0)
        {
            foreach (var job in timedOutJobs)
            {
                job.Status      = JobStatus.Failed;
                job.CompletedAt = DateTimeOffset.UtcNow;
                job.UpdatedAt   = DateTimeOffset.UtcNow;
                log.LogWarning(
                    "Job {JobId} (Plugin: {PluginId}) timed out after >{Timeout}min — marked Failed. Started: {StartedAt:u}.",
                    job.JobId, job.PluginId, (int)_jobTimeout.TotalMinutes, job.StartedAt);
            }

            await db.SaveChangesAsync(ct);
            log.LogInformation("Timed out {Count} stuck job(s).", timedOutJobs.Count);
        }
    }
}
