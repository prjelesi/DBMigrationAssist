using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

/// <summary>
/// Agent-facing endpoints. All routes under /api/agent/* pass through
/// AgentHmacAuthMiddleware which validates the PSK/HMAC signature before
/// this controller is reached.
/// </summary>
[ApiController]
[AllowAnonymous]
[Route("api/agent/{agentId:guid}")]
public class AgentJobsController(AssessmentDbContext db) : ControllerBase
{
    /// <summary>
    /// Heartbeat — called by the agent every poll cycle to signal it is alive.
    /// The HMAC middleware already updates LastHeartbeatAt as a side-effect;
    /// this endpoint just returns 200 to complete the request.
    /// </summary>
    [HttpPost("heartbeat")]
    public async Task<IActionResult> Heartbeat(Guid agentId)
    {
        var agent = await db.Agents.FindAsync(agentId);
        if (agent is null) return NotFound();
        agent.LastHeartbeatAt = DateTimeOffset.UtcNow;
        agent.Status = Core.Enums.AgentStatus.Active;
        agent.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();
        return Ok(new { agentId, serverTime = DateTimeOffset.UtcNow });
    }

    /// <summary>
    /// Returns the next pending job for this agent, or 204 if none.
    /// </summary>
    [HttpGet("jobs/next")]
    public async Task<IActionResult> NextJob(Guid agentId)
    {
        var job = await db.Jobs
            .Include(j => j.Database)
            .Where(j => j.AgentId == agentId && j.Status == JobStatus.Pending)
            .OrderBy(j => j.CreatedAt)
            .FirstOrDefaultAsync();

        if (job is null) return NoContent();

        job.Status = JobStatus.Assigned;
        job.StartedAt = DateTimeOffset.UtcNow;
        job.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();

        // Credentials are stored in ParametersJson by the portal when dispatching the job.
        // Fall back to empty strings if not provided — agent will fail gracefully.
        var creds = System.Text.Json.JsonSerializer.Deserialize<JobCredentials>(
            job.ParametersJson ?? "{}",
            new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? new JobCredentials("", 0, "", "", "");

        return Ok(new
        {
            job.JobId,
            DatabaseId = job.DatabaseId ?? Guid.Empty,
            job.PluginId,
            Host     = job.Database?.HostName ?? creds.Host,
            Port     = job.Database?.Port     ?? creds.Port,
            Database = job.Database?.Name     ?? creds.Database,
            Username = creds.Username,
            Password = creds.Password,
            AdditionalParams = job.ParametersJson
        });
    }

    /// <summary>
    /// Accepts a completed assessment result bundle from the agent.
    /// </summary>
    [HttpPost("results")]
    public async Task<IActionResult> SubmitResult(Guid agentId, [FromBody] AgentResultSubmission submission)
    {
        var job = await db.Jobs
            .FirstOrDefaultAsync(candidate => candidate.JobId == submission.JobId);
        if (job is null || job.AgentId != agentId) return BadRequest("Job not found for this agent.");

        var result = new AssessmentResult
        {
            JobId = submission.JobId,
            DatabaseId = job.DatabaseId,
            PluginId = submission.PluginId,
            PluginVersion = submission.PluginVersion,
            Confidence = submission.Success ? ConfidenceLevel.High : ConfidenceLevel.Low,
            FindingJson = submission.FindingJson ?? "{}",
            RawSummaryJson = submission.RawSummaryJson ?? "{}",
            PayloadHash = submission.PayloadHash,
            AssessedAt = submission.SubmittedAt
        };

        job.Status = submission.Success ? JobStatus.Completed : JobStatus.Failed;
        job.CompletedAt = DateTimeOffset.UtcNow;
        job.UpdatedAt = DateTimeOffset.UtcNow;

        db.Results.Add(result);
        await db.SaveChangesAsync();

        return Ok(new { result.ResultId, job.Status });
    }

}

public record AgentResultSubmission(
    Guid JobId, string PluginId, string PluginVersion,
    bool Success, string? FindingJson, string? RawSummaryJson,
    string? ErrorMessage, string? PayloadHash, DateTimeOffset SubmittedAt);

/// <summary>
/// Credentials are stored only in ParametersJson (JSONB) — never in plain columns.
/// For production deployments, inject them via Azure Key Vault or secrets.
/// </summary>
public record JobCredentials(string Host, int Port, string Database, string Username, string Password);

public record CreateJobRequest(
    Guid? DatabaseId,
    Guid ProjectId,
    string PluginId,
    /// <summary>JSON object with at minimum: host, port, database, username, password</summary>
    string? ParametersJson);
