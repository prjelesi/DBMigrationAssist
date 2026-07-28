using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Worker;

/// <summary>
/// Periodically checks agent heartbeats and marks agents as Offline
/// when no heartbeat has been received within the configured threshold.
/// </summary>
public sealed class AgentHealthService(
    IDbContextFactory<AssessmentDbContext> dbFactory,
    IConfiguration config,
    ILogger<AgentHealthService> log) : BackgroundService
{
    private readonly TimeSpan _interval = TimeSpan.FromSeconds(
        config.GetValue<int>("Worker:AgentHealthIntervalSeconds", 60));
    private readonly TimeSpan _offlineThreshold = TimeSpan.FromMinutes(
        config.GetValue<int>("Worker:AgentOfflineThresholdMinutes", 5));

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        log.LogInformation(
            "AgentHealthService started — interval {Interval}s, offline threshold {Threshold}min.",
            _interval.TotalSeconds, _offlineThreshold.TotalMinutes);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CheckAgentHealthAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                log.LogError(ex, "Error during agent health check.");
            }

            await Task.Delay(_interval, stoppingToken);
        }
    }

    private async Task CheckAgentHealthAsync(CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var cutoff = DateTimeOffset.UtcNow - _offlineThreshold;

        // Agents that have gone silent — mark Offline
        var staleAgents = await db.Agents
            .Where(a => (a.Status == AgentStatus.Registered || a.Status == AgentStatus.Active)
                     && (a.LastHeartbeatAt == null || a.LastHeartbeatAt < cutoff))
            .ToListAsync(ct);

        if (staleAgents.Count > 0)
        {
            foreach (var agent in staleAgents)
            {
                agent.Status    = AgentStatus.Offline;
                agent.UpdatedAt = DateTimeOffset.UtcNow;
                log.LogWarning(
                    "Agent {AgentId} ({Name}) marked Offline — last heartbeat: {LastBeat:u}.",
                    agent.AgentId, agent.Name, agent.LastHeartbeatAt);
            }

            await db.SaveChangesAsync(ct);
            log.LogInformation("Marked {Count} agent(s) Offline.", staleAgents.Count);
        }
    }
}
