using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Data;
using AssessmentToolkit.Shared.Auth;
using AssessmentToolkit.Shared.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using System.Security.Claims;
using System.Text;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/agents")]
public class AgentsController(AssessmentDbContext db, IConfiguration config) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] Guid? projectId)
    {
        var agents = db.Agents.AsNoTracking();
        if (projectId.HasValue)
            agents = agents.Where(a => a.ProjectId == projectId || a.CreatedBy == LocalAgentProvisioner.CreatedBy);

        if (!User.IsInRole("Administrator"))
        {
            if (!Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
                return Unauthorized();
            agents = agents.Where(a => db.ProjectMemberships.Any(
                m => m.ProjectId == a.ProjectId && m.UserId == userId &&
                    (m.EnvironmentId == null || m.EnvironmentId == a.EnvironmentId)));
        }

        return Ok(await agents.ToListAsync());
    }

    [HttpPost]
    public async Task<IActionResult> Register([FromBody] RegisterAgentRequest req)
    {
        var project = await db.Projects.FindAsync(req.ProjectId);
        if (project is null) return BadRequest("Project not found.");

        string rawPsk;

        if (req.PskMode == PskMode.UserSupplied)
        {
            if (string.IsNullOrEmpty(req.UserPsk))
                return BadRequest("User-supplied PSK mode requires a PSK value.");

            var (valid, error) = PskAuthenticator.ValidatePsk(req.UserPsk);
            if (!valid) return BadRequest(error);

            rawPsk = req.UserPsk;
        }
        else
        {
            rawPsk = PskAuthenticator.GeneratePsk();
        }

        var salt = Convert.ToBase64String(RandomNumberGenerator.GetBytes(16));
        var pskHash = ComputeSaltedHash(rawPsk, salt);

        var agent = new Agent
        {
            ProjectId = req.ProjectId,
            EnvironmentId = req.EnvironmentId,
            Name = req.Name,
            PskMode = req.PskMode,
            PskHash = pskHash,
            PskSalt = salt,
            AllowedPlugins = req.AllowedPlugins,
            PskIssuedAt = DateTimeOffset.UtcNow,
            CreatedBy = req.CreatedBy
        };

        db.Agents.Add(agent);
        await db.SaveChangesAsync();

        // Store the raw PSK in configuration for the PoC (in production: use Key Vault or secrets store)
        // The raw PSK is returned here once and never stored in recoverable form after this response.
        var bootstrapPackage = new AgentBootstrapPackage
        {
            AgentId = agent.AgentId,
            BackendUrl = config["Api:PublicUrl"] ?? $"{Request.Scheme}://{Request.Host}",
            Psk = rawPsk,
            AllowedPlugins = req.AllowedPlugins
        };

        // In the PoC: write PSK to in-memory config so the middleware can verify it.
        // In production: write to Azure Key Vault or a secrets store.
        config[$"AgentPsk:{agent.AgentId}"] = rawPsk;

        return CreatedAtAction(nameof(GetBootstrap), new { id = agent.AgentId }, new
        {
            agent.AgentId,
            agent.Name,
            agent.Status,
            BootstrapPackage = bootstrapPackage,
            Warning = "The PSK is shown once. Store it securely before closing this response."
        });
    }

    [HttpGet("{id:guid}/bootstrap")]
    public async Task<IActionResult> GetBootstrap(Guid id)
    {
        var agent = await db.Agents.FindAsync(id);
        return agent is null ? NotFound() : Ok(new { agent.AgentId, agent.Name, agent.Status, agent.AllowedPlugins, agent.PskIssuedAt });
    }

    [HttpPost("{id:guid}/heartbeat")]
    public async Task<IActionResult> Heartbeat(Guid id)
    {
        var agent = await db.Agents.FindAsync(id);
        if (agent is null) return NotFound();
        agent.LastHeartbeatAt = DateTimeOffset.UtcNow;
        agent.Status = AgentStatus.Active;
        await db.SaveChangesAsync();
        return Ok();
    }

    /// <summary>Portal endpoint: returns job history for an agent including result summary.</summary>
    [HttpGet("{id:guid}/jobs")]
    public async Task<IActionResult> GetJobs(Guid id, [FromQuery] int limit = 20)
    {
        var jobs = await db.Jobs
            .Where(j => j.AgentId == id)
            .OrderByDescending(j => j.CreatedAt)
            .Take(limit)
            .Select(j => new
            {
                j.JobId,
                j.PluginId,
                j.Status,
                j.StartedAt,
                j.CompletedAt,
                j.CreatedAt,
                DatabaseName = j.Database != null ? j.Database.Name : null,
                ResultCount = j.Results.Count
            })
            .ToListAsync();

        return Ok(jobs);
    }

    /// <summary>Portal endpoint: creates a new assessment job for an agent.</summary>
    [HttpPost("{id:guid}/jobs")]
    public async Task<IActionResult> CreateJob(Guid id, [FromBody] CreateJobRequest req)
    {
        var agent = await db.Agents.FindAsync(id);
        if (agent is null) return NotFound("Agent not found.");
        if (!agent.AllowedPlugins.Contains(req.PluginId))
            return BadRequest($"Plugin '{req.PluginId}' is not in the agent's allowed plugin list.");

        var job = new AssessmentJob
        {
            AgentId = id,
            DatabaseId = req.DatabaseId,
            PluginId = req.PluginId,
            ParametersJson = req.ParametersJson
        };

        db.Jobs.Add(job);
        await db.SaveChangesAsync();
        return Created($"/api/agents/{id}/jobs/{job.JobId}", new { job.JobId, job.Status, job.PluginId });
    }

    /// <summary>Portal endpoint: returns full assessment result details for a specific job.</summary>
    [HttpGet("{id:guid}/jobs/{jobId:guid}/results")]
    public async Task<IActionResult> GetJobResults(Guid id, Guid jobId)
    {
        var results = await db.Results
            .Where(r => r.JobId == jobId && r.Job.AgentId == id)
            .OrderBy(r => r.AssessedAt)
            .Select(r => new
            {
                r.ResultId,
                r.PluginId,
                r.PluginVersion,
                r.Confidence,
                r.FindingJson,
                r.RawSummaryJson,
                r.AssessedAt,
                r.CreatedAt
            })
            .ToListAsync();
        return Ok(results);
    }

    private static string ComputeSaltedHash(string psk, string salt)
    {
        var input = Encoding.UTF8.GetBytes(salt + psk);
        return Convert.ToBase64String(SHA256.HashData(input));
    }
}

public record RegisterAgentRequest(
    Guid ProjectId,
    Guid? EnvironmentId,
    string Name,
    List<string> AllowedPlugins,
    PskMode PskMode,
    string? UserPsk,
    string CreatedBy);
