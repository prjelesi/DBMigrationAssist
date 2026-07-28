using AssessmentToolkit.Data;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Worker;

/// <summary>
/// Periodic DB connectivity check — confirms the worker can reach PostgreSQL
/// and logs a brief summary of pending work every 5 minutes.
/// </summary>
public sealed class WorkerStatusReporter(
    IDbContextFactory<AssessmentDbContext> dbFactory,
    ILogger<WorkerStatusReporter> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        log.LogInformation("AssessmentToolkit.Worker started.");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var db = await dbFactory.CreateDbContextAsync(stoppingToken);

                var pendingJobs  = await db.Jobs.CountAsync(j => j.Status == Core.Enums.JobStatus.Pending,  stoppingToken);
                var runningJobs  = await db.Jobs.CountAsync(j => j.Status == Core.Enums.JobStatus.Running || j.Status == Core.Enums.JobStatus.Assigned, stoppingToken);
                var activeAgents = await db.Agents.CountAsync(a => a.Status == Core.Enums.AgentStatus.Active, stoppingToken);

                log.LogInformation(
                    "[Status] Agents active: {Active} | Jobs pending: {Pending} | Jobs in-progress: {Running}",
                    activeAgents, pendingJobs, runningJobs);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                log.LogError(ex, "DB connectivity check failed.");
            }

            await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);
        }
    }
}
