namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Contract for all database assessment plugins.
/// Each plugin targets one engine type.
/// </summary>
public interface IAssessmentPlugin
{
    string PluginId { get; }
    string PluginVersion { get; }
    string TargetEngine { get; }

    Task<PluginResult> RunAsync(PluginContext context, CancellationToken ct);
}

public record PluginContext(
    Guid JobId,
    Guid DatabaseId,
    string Host,
    int Port,
    string Database,
    string Username,
    string Password,
    string? AdditionalParams);

public record PluginResult(
    bool Success,
    string FindingJson,
    string RawSummaryJson,
    string? ErrorMessage = null);
