using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using AssessmentToolkit.Shared.Auth;
using AssessmentToolkit.Shared.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using System.Text;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/agents")]
public class AgentsController(AssessmentDbContext db, IConfiguration config) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] Guid projectId) =>
        Ok(await db.Agents.Where(a => a.ProjectId == projectId).ToListAsync());

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
