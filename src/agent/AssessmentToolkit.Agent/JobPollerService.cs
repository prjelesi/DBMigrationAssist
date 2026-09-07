using AssessmentToolkit.Agent.Plugins;
using AssessmentToolkit.Shared.Auth;
using AssessmentToolkit.Shared.Models;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace AssessmentToolkit.Agent;

/// <summary>
/// Polls the backend for pending jobs, executes the appropriate plugin,
/// and submits signed result bundles back to the backend.
/// Credentials are resolved from the local database store first (databases.json /
/// AGENT_DB_n_* env vars); credentials in the job payload are used as a fallback.
/// </summary>
public class JobPollerService(
    AgentBootstrapPackage bootstrap,
    IEnumerable<IAssessmentPlugin> plugins,
    LocalDatabaseStore dbStore,
    ILogger<JobPollerService> logger) : BackgroundService
{
    private readonly HttpClient _http = new() { BaseAddress = new Uri(bootstrap.BackendUrl) };
    private readonly Dictionary<string, IAssessmentPlugin> _plugins =
        plugins.ToDictionary(p => p.PluginId, p => p);

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        logger.LogInformation("Agent {AgentId} starting. Backend: {BackendUrl}", bootstrap.AgentId, bootstrap.BackendUrl);

        while (!ct.IsCancellationRequested)
        {
            try
            {
                await SendHeartbeatAsync(ct);
                await PollAndExecuteAsync(ct);
            }
            catch (Exception ex) when (!ct.IsCancellationRequested)
            {
                logger.LogWarning(ex, "Poll cycle error — retrying in 30 seconds.");
            }

            await Task.Delay(TimeSpan.FromSeconds(30), ct);
        }
    }

    private async Task SendHeartbeatAsync(CancellationToken ct)
    {
        var req = BuildSignedRequest(HttpMethod.Post, $"/api/agent/{bootstrap.AgentId}/heartbeat", "");
        await _http.SendAsync(req, ct);
    }

    private async Task PollAndExecuteAsync(CancellationToken ct)
    {
        var req = BuildSignedRequest(HttpMethod.Get, $"/api/agent/{bootstrap.AgentId}/jobs/next", "");
        var response = await _http.SendAsync(req, ct);

        if (response.StatusCode == System.Net.HttpStatusCode.NoContent)
            return; // No pending jobs

        response.EnsureSuccessStatusCode();

        var job = await response.Content.ReadFromJsonAsync<AgentJob>(cancellationToken: ct);
        if (job is null) return;

        logger.LogInformation("Executing job {JobId} plugin {PluginId}", job.JobId, job.PluginId);

        if (!_plugins.TryGetValue(job.PluginId, out var plugin))
        {
            logger.LogWarning("No plugin found for {PluginId} — job {JobId} skipped.", job.PluginId, job.JobId);
            return;
        }

        // Resolve connection credentials:
        // 1. Local store (databases.json or AGENT_DB_n_* env vars) — preferred, avoids
        //    transmitting credentials through the portal.
        // 2. Credentials embedded in the job payload — fallback for ad-hoc dispatches.
        string host, database, username, password;
        int port;

        var localProfile = job.DatabaseId != Guid.Empty ? dbStore.Resolve(job.DatabaseId) : null;
        if (localProfile is not null)
        {
            host     = localProfile.Host;
            port     = localProfile.Port;
            database = localProfile.Database;
            username = localProfile.Username;
            password = localProfile.Password;
            logger.LogDebug("Using local credentials for database {DatabaseId}.", job.DatabaseId);
        }
        else
        {
            host     = job.Host;
            port     = job.Port;
            database = job.Database;
            username = job.Username;
            password = job.Password;
        }

        var context = new PluginContext(
            job.JobId, job.DatabaseId,
            host, port, database, username, password, job.AdditionalParams);

        var result = await plugin.RunAsync(context, ct);

        if (!result.Success)
            logger.LogWarning("Job {JobId} plugin {PluginId} failed: {ErrorMessage}",
                job.JobId, plugin.PluginId, result.ErrorMessage);

        await SubmitResultAsync(job.JobId, plugin, result, ct);
    }

    private async Task SubmitResultAsync(Guid jobId, IAssessmentPlugin plugin, PluginResult result, CancellationToken ct)
    {
        var payload = new
        {
            JobId = jobId,
            AgentId = bootstrap.AgentId,
            plugin.PluginId,
            plugin.PluginVersion,
            result.Success,
            result.FindingJson,
            result.RawSummaryJson,
            result.ErrorMessage,
            SubmittedAt = DateTimeOffset.UtcNow
        };

        var body = JsonSerializer.Serialize(payload);
        var req = BuildSignedRequest(HttpMethod.Post, $"/api/agent/{bootstrap.AgentId}/results", body);
        req.Content = new StringContent(body, Encoding.UTF8, "application/json");

        var response = await _http.SendAsync(req, ct);
        response.EnsureSuccessStatusCode();

        logger.LogInformation("Job {JobId} result submitted. Success={Success}", jobId, result.Success);
    }

    private HttpRequestMessage BuildSignedRequest(HttpMethod method, string path, string body)
    {
        var timestamp = DateTimeOffset.UtcNow.ToString("O");
        var nonce = Guid.NewGuid().ToString("D");
        var bodyHash = PskAuthenticator.ComputeBodyHash(Encoding.UTF8.GetBytes(body));
        var signature = PskAuthenticator.ComputeSignature(bootstrap.Psk, method.Method, path, timestamp, nonce, bodyHash);

        var request = new HttpRequestMessage(method, path);
        request.Headers.Add("X-Agent-Id", bootstrap.AgentId.ToString());
        request.Headers.Add("X-Agent-Timestamp", timestamp);
        request.Headers.Add("X-Agent-Nonce", nonce);
        request.Headers.Add("X-Agent-Signature", signature);
        return request;
    }
}

public record AgentJob(
    Guid JobId,
    Guid DatabaseId,
    string PluginId,
    string Host,
    int Port,
    string Database,
    string Username,
    string Password,
    string? AdditionalParams);
