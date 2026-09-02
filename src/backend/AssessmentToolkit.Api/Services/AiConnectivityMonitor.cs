namespace AssessmentToolkit.Api.Services;

public sealed class AiConnectivityMonitor(
    IAiAdapterService ai,
    IConfiguration configuration,
    ILogger<AiConnectivityMonitor> logger) : BackgroundService
{
    private readonly TimeSpan _startupDelay = TimeSpan.FromSeconds(
        Math.Max(0, configuration.GetValue("AiFoundry:ConnectivityCheckStartupDelaySeconds", 5)));
    private readonly TimeSpan _checkInterval = TimeSpan.FromMinutes(
        Math.Max(1, configuration.GetValue("AiFoundry:ConnectivityCheckIntervalMinutes", 15)));

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (_startupDelay > TimeSpan.Zero)
            await Task.Delay(_startupDelay, stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            if (ai.IsAvailable)
            {
                var result = await ai.TestConnectionAsync(stoppingToken);
                if (result.Succeeded)
                    logger.LogInformation("Periodic AI Foundry connectivity check succeeded at {TestedAt}.", result.TestedAt);
                else
                    logger.LogWarning("Periodic AI Foundry connectivity check failed at {TestedAt}: {Message}", result.TestedAt, result.Message);
            }
            else
            {
                logger.LogDebug("Skipping periodic AI Foundry connectivity check because it is not configured.");
            }

            await Task.Delay(_checkInterval, stoppingToken);
        }
    }
}