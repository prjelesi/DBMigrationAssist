namespace AssessmentToolkit.Core.Entities;

public enum AiProviderType { AzureOpenAi, AiFoundry, OpenAi, LocalEndpoint }

public enum AiProviderStatus { Active, Disabled, Error }

/// <summary>
/// Registered AI provider configuration.
/// The API key is never stored in plain text — only in environment / Key Vault references.
/// For the PoC, the key is supplied via environment variable and this record stores metadata only.
/// </summary>
public class AiProvider
{
    public Guid ProviderId { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public AiProviderType ProviderType { get; set; }
    public AiProviderStatus Status { get; set; } = AiProviderStatus.Active;
    /// <summary>Azure OpenAI endpoint or AI Foundry project endpoint.</summary>
    public string Endpoint { get; set; } = string.Empty;
    /// <summary>Model deployment name (e.g. gpt-4o, gpt-4-turbo).</summary>
    public string DeploymentName { get; set; } = string.Empty;
    /// <summary>API version string (e.g. 2024-02-01).</summary>
    public string? ApiVersion { get; set; }
    /// <summary>
    /// Environment variable name that holds the API key.
    /// The key itself is NEVER stored in the database.
    /// </summary>
    public string ApiKeyEnvVar { get; set; } = "AI_FOUNDRY_API_KEY";
    public bool IsDefault { get; set; } = false;
    public string? Notes { get; set; }
    public DateTimeOffset? LastTestedAt { get; set; }
    public string? LastTestResult { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
