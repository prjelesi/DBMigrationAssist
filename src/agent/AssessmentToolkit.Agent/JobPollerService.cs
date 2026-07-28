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
/// </summary>
public class JobPollerService(
    AgentBootstrapPackage bootstrap,
    IEnumerable<IAssessmentPlugin> plugins,
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
            logger.LogWarning("No plugin found for {PluginId}", job.PluginId);
            return;
        }

        var context = new PluginContext(
            job.JobId, job.DatabaseId,
            job.Host, job.Port, job.Database,
            job.Username, job.Password, job.AdditionalParams);

        var result = await plugin.RunAsync(context, ct);

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
        var bodyHash = PskAuthenticator.ComputeBodyHash(Encoding.UTF8.GetBytes(body));
        var signature = PskAuthenticator.ComputeSignature(bootstrap.Psk, method.Method, path, timestamp, bodyHash);

        var request = new HttpRequestMessage(method, path);
        request.Headers.Add("X-Agent-Id", bootstrap.AgentId.ToString());
        request.Headers.Add("X-Agent-Timestamp", timestamp);
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
