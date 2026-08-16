using AssessmentToolkit.Shared.Models;
using System.Text.Json;

namespace AssessmentToolkit.Agent;

public static class AgentBootstrapLoader
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    public static async Task<AgentBootstrapPackage> LoadAsync(CancellationToken cancellationToken = default)
    {
        var bootstrapPath = Environment.GetEnvironmentVariable("AGENT_BOOTSTRAP_PATH") ?? "bootstrap.json";
        if (File.Exists(bootstrapPath))
        {
            var json = await File.ReadAllTextAsync(bootstrapPath, cancellationToken);
            return JsonSerializer.Deserialize<AgentBootstrapPackage>(json, JsonOptions)
                ?? throw new InvalidOperationException("Invalid bootstrap package.");
        }

        if (string.Equals(Environment.GetEnvironmentVariable("AGENT_AUTO_REGISTER"), "true", StringComparison.OrdinalIgnoreCase))
            return await WaitForProvisionedBootstrapAsync(bootstrapPath, cancellationToken);

        return new AgentBootstrapPackage
        {
            AgentId = Guid.Parse(RequiredEnvironmentVariable("AGENT_ID")),
            BackendUrl = RequiredEnvironmentVariable("AGENT_BACKEND_URL"),
            Psk = RequiredEnvironmentVariable("AGENT_PSK"),
            AllowedPlugins = GetAllowedPlugins()
        };
    }

    private static async Task<AgentBootstrapPackage> WaitForProvisionedBootstrapAsync(
        string bootstrapPath,
        CancellationToken cancellationToken)
    {
        var timeoutAt = DateTimeOffset.UtcNow.AddMinutes(2);
        while (!File.Exists(bootstrapPath) && DateTimeOffset.UtcNow < timeoutAt)
        {
            await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
        }

        if (!File.Exists(bootstrapPath))
            throw new InvalidOperationException($"The platform did not provision {bootstrapPath} within two minutes.");

        var json = await File.ReadAllTextAsync(bootstrapPath, cancellationToken);
        return JsonSerializer.Deserialize<AgentBootstrapPackage>(json, JsonOptions)
            ?? throw new InvalidOperationException("Invalid provisioned bootstrap package.");
    }

    private static List<string> GetAllowedPlugins() =>
        (Environment.GetEnvironmentVariable("AGENT_PLUGINS") ?? "postgresql,oracle")
        .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .ToList();

    private static string RequiredEnvironmentVariable(string name) =>
        Environment.GetEnvironmentVariable(name)
        ?? throw new InvalidOperationException($"{name} environment variable is required.");
}