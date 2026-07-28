using Azure;
using Azure.AI.OpenAI;
using AssessmentToolkit.Data;
using OpenAI.Chat;
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
    Task<string?> CompleteAsync(string systemPrompt, string userPrompt, CancellationToken ct = default);
    Task ReloadConfigAsync(IServiceProvider services);
}

public class AiAdapterService : IAiAdapterService
{
    private AzureOpenAIClient? _client;
    private string? _deployment;
    private readonly IConfiguration _config;
    private readonly ILogger<AiAdapterService> _log;

    public bool IsAvailable => _client is not null && !string.IsNullOrEmpty(_deployment);

    public AiAdapterService(IConfiguration config, ILogger<AiAdapterService> log)
    {
        _config = config;
        _log = log;
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

        var endpoint   = configs.GetValueOrDefault("AiFoundry:Endpoint")   ?? _config["AiFoundry:Endpoint"]   ?? _config["AZURE_OPENAI_ENDPOINT"];
        var deployment = configs.GetValueOrDefault("AiFoundry:Deployment") ?? _config["AiFoundry:Deployment"] ?? _config["AZURE_OPENAI_DEPLOYMENT"] ?? "gpt-4o";
        // API key: never from DB — always from env
        var apiKey     = _config["AiFoundry:ApiKey"] ?? _config["AZURE_OPENAI_API_KEY"] ?? _config["AI_FOUNDRY_API_KEY"];

        if (string.IsNullOrEmpty(endpoint) || string.IsNullOrEmpty(apiKey))
        {
            _log.LogInformation("AI Foundry not fully configured after DB reload — rules-based fallback active.");
            _client = null;
            return;
        }

        try
        {
            _client     = new AzureOpenAIClient(new Uri(endpoint), new AzureKeyCredential(apiKey));
            _deployment = deployment;
            _log.LogInformation("AI Foundry reloaded from DB config: endpoint={Endpoint} deployment={Deployment}", endpoint, deployment);
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Failed to reinitialise AzureOpenAIClient after config reload.");
            _client = null;
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
            _log.LogInformation("AI Foundry configured from env: endpoint={Endpoint}", endpoint);
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Failed to initialise from env vars.");
        }
    }
}
