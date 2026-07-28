namespace AssessmentToolkit.Core.Entities;

/// <summary>
/// Key-value system configuration store.
/// Sensitive values (API keys) are stored masked after first save.
/// Raw values must be provided fresh if they need to be updated.
/// </summary>
public class SystemConfig
{
    public string Key { get; set; } = string.Empty;
    public string? Value { get; set; }
    /// <summary>If true, the value is a secret and will be returned masked via the API.</summary>
    public bool IsSensitive { get; set; } = false;
    /// <summary>Human-readable description of what this config key controls.</summary>
    public string? Description { get; set; }
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public string? UpdatedBy { get; set; }
}
