namespace AssessmentToolkit.Shared.Models;

/// <summary>
/// Delivered out-of-band to the agent at deployment time.
/// Contains everything the agent needs to authenticate and receive jobs.
/// </summary>
public class AgentBootstrapPackage
{
    public Guid AgentId { get; set; }
    public string BackendUrl { get; set; } = string.Empty;
    /// <summary>
    /// Raw PSK value — shown once, never stored in recoverable form on the server.
    /// </summary>
    public string Psk { get; set; } = string.Empty;
    public List<string> AllowedPlugins { get; set; } = [];
    public DateTimeOffset IssuedAt { get; set; } = DateTimeOffset.UtcNow;
}
