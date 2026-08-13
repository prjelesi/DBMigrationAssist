using Azure;
using Azure.AI.OpenAI;
using AssessmentToolkit.Data;
using OpenAI.Chat;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Logging;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Services;

/// <summary>
/// Central AI service — configured once, used everywhere.
/// Config priority: DB (system_config table) → environment variables → not available.
/// API key is NEVER stored in plain text in DB — only in env vars or Key Vault.
/// </summary>
public interface IAiAdapterService
{
    bool IsAvailable { get; }
    string ConfiguredVia { get; }
    string? Endpoint { get; }
    string? Deployment { get; }
    bool HasStoredCredential { get; }
    bool? LastConnectionSucceeded { get; }
    DateTimeOffset? LastConnectionTestedAt { get; }
    Task<string?> CompleteAsync(string systemPrompt, string userPrompt, CancellationToken ct = default);
    Task<AiConnectionTestResult> TestConnectionAsync(CancellationToken ct = default);
    Task ReloadConfigAsync(IServiceProvider services);
}

public record AiConnectionTestResult(bool Succeeded, string Message, DateTimeOffset TestedAt);

public static class AiConfigKeys
{
    public const string Endpoint = "AiFoundry:Endpoint";
    public const string Deployment = "AiFoundry:Deployment";
    public const string ProtectedApiKey = "AiFoundry:ProtectedApiKey";
}

public class AiAdapterService : IAiAdapterService
{
    private AzureOpenAIClient? _client;
    private string? _deployment;
    private readonly IConfiguration _config;
    private readonly ILogger<AiAdapterService> _log;
    private readonly IDataProtector _credentialProtector;

    public bool IsAvailable => _client is not null && !string.IsNullOrEmpty(_deployment);
    public string ConfiguredVia { get; private set; } = "Not configured";
    public string? Endpoint { get; private set; }
    public string? Deployment => _deployment;
    public bool HasStoredCredential { get; private set; }
    public bool? LastConnectionSucceeded { get; private set; }
    public DateTimeOffset? LastConnectionTestedAt { get; private set; }

    public AiAdapterService(
        IConfiguration config,
        ILogger<AiAdapterService> log,
        IDataProtectionProvider dataProtectionProvider)
    {
        _config = config;
        _log = log;
        _credentialProtector = dataProtectionProvider.CreateProtector("AssessmentToolkit.AiFoundry.ApiKey.v1");
        // Initial load from env vars only — DB not available at singleton construction time
        TryInitFromEnv();
    }

    /// <summary>
    /// Called after DB is available to load config from system_config table.
    /// DB config overrides env vars for endpoint and deployment; API key always comes from env.
    /// </summary>
    public async Task ReloadConfigAsync(IServiceProvider services)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AssessmentDbContext>();

        var configs = await db.SystemConfigs
            .Where(c => c.Key.StartsWith("AiFoundry:"))
            .ToDictionaryAsync(c => c.Key, c => c.Value ?? "");

        var endpoint = FirstNonEmpty(
            configs.GetValueOrDefault(AiConfigKeys.Endpoint),
            _config["AiFoundry:Endpoint"],
            _config["AZURE_OPENAI_ENDPOINT"]);
        var deployment = FirstNonEmpty(
            configs.GetValueOrDefault(AiConfigKeys.Deployment),
            _config["AiFoundry:Deployment"],
            _config["AZURE_OPENAI_DEPLOYMENT"],
            "gpt-4o");
        var protectedApiKey = configs.GetValueOrDefault(AiConfigKeys.ProtectedApiKey);
        var apiKey = TryUnprotect(protectedApiKey) ?? FirstNonEmpty(
            _config["AiFoundry:ApiKey"],
            _config["AZURE_OPENAI_API_KEY"],
            _config["AI_FOUNDRY_API_KEY"]);

        HasStoredCredential = !string.IsNullOrWhiteSpace(protectedApiKey);
        LastConnectionSucceeded = null;
        LastConnectionTestedAt = null;

        if (string.IsNullOrEmpty(endpoint) || string.IsNullOrEmpty(apiKey))
        {
            _log.LogInformation("AI Foundry not fully configured after DB reload — rules-based fallback active.");
            _client = null;
            _deployment = null;
            Endpoint = endpoint;
            ConfiguredVia = "Not configured";
            return;
        }

        try
        {
            _client     = new AzureOpenAIClient(new Uri(endpoint), new AzureKeyCredential(apiKey));
            _deployment = deployment;
            Endpoint = endpoint;
            ConfiguredVia = HasStoredCredential ? "Portal (encrypted)" : "Environment variables";
            _log.LogInformation("AI Foundry reloaded from DB config: endpoint={Endpoint} deployment={Deployment}", endpoint, deployment);
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Failed to reinitialise AzureOpenAIClient after config reload.");
            _client = null;
            ConfiguredVia = "Configuration error";
        }
    }

    public async Task<string?> CompleteAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
    {
        if (!IsAvailable) return null;

        try
        {
            var chat = _client!.GetChatClient(_deployment);
            var response = await chat.CompleteChatAsync(
                [ChatMessage.CreateSystemMessage(systemPrompt), ChatMessage.CreateUserMessage(userPrompt)],
                new ChatCompletionOptions { Temperature = 0.2f, MaxOutputTokenCount = 2048 },
                ct);
            return response.Value.Content[0].Text;
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "AI completion failed.");
            return null;
        }
    }

    public async Task<AiConnectionTestResult> TestConnectionAsync(CancellationToken ct = default)
    {
        var testedAt = DateTimeOffset.UtcNow;
        if (!IsAvailable)
            return new(false, "AI Foundry is not configured.", testedAt);

        var response = await CompleteAsync(
            "You are a connectivity test. Follow the user's response format exactly.",
            "Reply with exactly: Connection successful",
            ct);
        var succeeded = !string.IsNullOrWhiteSpace(response);

        LastConnectionSucceeded = succeeded;
        LastConnectionTestedAt = testedAt;
        return new(
            succeeded,
            succeeded ? "Connection successful." : "The configured deployment did not return a response.",
            testedAt);
    }

    private void TryInitFromEnv()
    {
        var endpoint   = _config["AiFoundry:Endpoint"]   ?? _config["AZURE_OPENAI_ENDPOINT"];
        var apiKey     = _config["AiFoundry:ApiKey"]      ?? _config["AZURE_OPENAI_API_KEY"] ?? _config["AI_FOUNDRY_API_KEY"];
        var deployment = _config["AiFoundry:Deployment"]  ?? _config["AZURE_OPENAI_DEPLOYMENT"] ?? "gpt-4o";

        if (string.IsNullOrEmpty(endpoint) || string.IsNullOrEmpty(apiKey))
        {
            _log.LogInformation("AI Foundry env vars not set — will check DB config on first request.");
            return;
        }

        try
        {
            _client     = new AzureOpenAIClient(new Uri(endpoint), new AzureKeyCredential(apiKey));
            _deployment = deployment;
            Endpoint = endpoint;
            ConfiguredVia = "Environment variables";
            _log.LogInformation("AI Foundry configured from env: endpoint={Endpoint}", endpoint);
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Failed to initialise from env vars.");
            ConfiguredVia = "Configuration error";
        }
    }

    private string? TryUnprotect(string? protectedApiKey)
    {
        if (string.IsNullOrWhiteSpace(protectedApiKey)) return null;

        try
        {
            return _credentialProtector.Unprotect(protectedApiKey);
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "The stored AI Foundry credential could not be decrypted.");
            return null;
        }
    }

    private static string? FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
}
