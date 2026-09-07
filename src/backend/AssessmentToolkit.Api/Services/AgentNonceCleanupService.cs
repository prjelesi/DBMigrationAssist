using AssessmentToolkit.Data;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Services;

public sealed class AgentNonceCleanupService(
    IServiceScopeFactory scopeFactory,
    ILogger<AgentNonceCleanupService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(5));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await using var scope = scopeFactory.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<AssessmentDbContext>();
                await db.AgentRequestNonces
                    .Where(nonce => nonce.ExpiresAt < DateTimeOffset.UtcNow)
                    .ExecuteDeleteAsync(stoppingToken);
            }
            catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
            {
                logger.LogWarning(ex, "Failed to remove expired agent request nonces.");
            }
        }
    }
}