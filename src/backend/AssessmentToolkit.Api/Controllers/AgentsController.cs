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
using System.Text.Json;

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
                j.DatabaseId,
                DatabaseProjectId = j.Database != null ? (Guid?)j.Database.ProjectId : null,
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

        var targetProjectId = req.ProjectId == Guid.Empty ? agent.ProjectId : req.ProjectId;
        if (targetProjectId != agent.ProjectId && agent.CreatedBy != LocalAgentProvisioner.CreatedBy)
            return BadRequest("Only the platform discovery agent can dispatch jobs for another project.");

        var targetProjectExists = await db.Projects.AnyAsync(project => project.ProjectId == targetProjectId);
        if (!targetProjectExists)
            return BadRequest("Target project not found.");

        if (!User.IsInRole("Administrator"))
        {
            if (!Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ||
                !await db.ProjectMemberships.AnyAsync(membership =>
                    membership.ProjectId == targetProjectId && membership.UserId == userId))
                return Forbid();
        }

        var databaseId = req.DatabaseId;
        if (databaseId is null)
        {
            JobCredentials? credentials;
            try
            {
                credentials = JsonSerializer.Deserialize<JobCredentials>(
                    req.ParametersJson ?? "{}",
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }
            catch (JsonException)
            {
                return BadRequest("Manual connection details are not valid JSON.");
            }

            if (credentials is null ||
                string.IsNullOrWhiteSpace(credentials.Host) ||
                string.IsNullOrWhiteSpace(credentials.Database))
                return BadRequest("Manual jobs require a host and database/service name.");

            if (!TryGetEngine(req.PluginId, out var engine))
                return BadRequest($"Plugin '{req.PluginId}' cannot be added to database inventory.");

            var host = credentials.Host.Trim();
            var databaseName = credentials.Database.Trim();
            int? port = credentials.Port > 0 ? credentials.Port : null;
            var normalizedHost = host.ToLowerInvariant();

            var inventoryDatabase = await db.Databases.FirstOrDefaultAsync(database =>
                database.ProjectId == targetProjectId &&
                database.Engine == engine &&
                database.HostName != null &&
                database.HostName.ToLower() == normalizedHost &&
                database.Port == port &&
                database.Name == databaseName);

            if (inventoryDatabase is null)
            {
                inventoryDatabase = new DatabaseInstance
                {
                    ProjectId = targetProjectId,
                    EnvironmentId = targetProjectId == agent.ProjectId ? agent.EnvironmentId : null,
                    Name = databaseName,
                    Engine = engine,
                    HostName = host,
                    Port = port
                };
                db.Databases.Add(inventoryDatabase);
            }

            databaseId = inventoryDatabase.DatabaseId;
        }
        else if (!await db.Databases.AnyAsync(database =>
                     database.DatabaseId == databaseId && database.ProjectId == targetProjectId))
        {
            return BadRequest("The selected database does not belong to the target project.");
        }

        var job = new AssessmentJob
        {
            AgentId = id,
            DatabaseId = databaseId,
            PluginId = req.PluginId,
            ParametersJson = req.ParametersJson
        };

        db.Jobs.Add(job);
        await db.SaveChangesAsync();
        return Created($"/api/agents/{id}/jobs/{job.JobId}", new { job.JobId, job.DatabaseId, job.Status, job.PluginId });
    }

    [HttpPost("{id:guid}/jobs/{jobId:guid}/inventory")]
    public async Task<IActionResult> LinkCompletedJobToInventory(
        Guid id,
        Guid jobId,
        [FromBody] LinkJobInventoryRequest req)
    {
        var agent = await db.Agents.FindAsync(id);
        if (agent is null) return NotFound("Agent not found.");

        var job = await db.Jobs
            .Include(candidate => candidate.Database)
            .Include(candidate => candidate.Results)
            .FirstOrDefaultAsync(candidate => candidate.JobId == jobId && candidate.AgentId == id);
        if (job is null) return NotFound("Job not found.");
        if (job.Status != JobStatus.Completed)
            return BadRequest("Only completed jobs can be linked to database inventory.");
        if (req.ProjectId != agent.ProjectId && agent.CreatedBy != LocalAgentProvisioner.CreatedBy)
            return BadRequest("Only the platform discovery agent can link jobs to another project.");
        if (!await db.Projects.AnyAsync(project => project.ProjectId == req.ProjectId))
            return BadRequest("Target project not found.");

        if (!User.IsInRole("Administrator"))
        {
            if (!Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ||
                !await db.ProjectMemberships.AnyAsync(membership =>
                    membership.ProjectId == req.ProjectId && membership.UserId == userId))
                return Forbid();
        }

        if (job.Database?.ProjectId == req.ProjectId)
            return Ok(new { job.JobId, job.DatabaseId, ProjectId = req.ProjectId });

        JobCredentials? credentials = null;
        if (job.Database is null)
        {
            try
            {
                credentials = JsonSerializer.Deserialize<JobCredentials>(
                    job.ParametersJson ?? "{}",
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }
            catch (JsonException)
            {
                return BadRequest("The completed job does not contain valid connection details.");
            }
        }

        var host = (job.Database?.HostName ?? credentials?.Host)?.Trim();
        var databaseName = (job.Database?.Name ?? credentials?.Database)?.Trim();
        var port = job.Database?.Port ?? (credentials?.Port > 0 ? credentials.Port : null);
        EngineType engine;
        if (job.Database is not null)
            engine = job.Database.Engine;
        else if (!TryGetEngine(job.PluginId, out engine))
            return BadRequest($"Plugin '{job.PluginId}' cannot be added to database inventory.");

        if (string.IsNullOrWhiteSpace(host) || string.IsNullOrWhiteSpace(databaseName))
            return BadRequest("The completed job does not contain a host and database/service name.");

        var normalizedHost = host.ToLowerInvariant();
        var inventoryDatabase = await db.Databases.FirstOrDefaultAsync(database =>
            database.ProjectId == req.ProjectId &&
            database.Engine == engine &&
            database.HostName != null &&
            database.HostName.ToLower() == normalizedHost &&
            database.Port == port &&
            database.Name == databaseName);

        if (inventoryDatabase is null)
        {
            inventoryDatabase = new DatabaseInstance
            {
                ProjectId = req.ProjectId,
                EnvironmentId = req.ProjectId == agent.ProjectId ? agent.EnvironmentId : null,
                Name = databaseName,
                Engine = engine,
                HostName = host,
                Port = port
            };
            db.Databases.Add(inventoryDatabase);
        }

        job.DatabaseId = inventoryDatabase.DatabaseId;
        foreach (var result in job.Results)
            result.DatabaseId = inventoryDatabase.DatabaseId;

        await db.SaveChangesAsync();
        return Ok(new { job.JobId, DatabaseId = inventoryDatabase.DatabaseId, ProjectId = req.ProjectId });
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

    private static bool TryGetEngine(string pluginId, out EngineType engine)
    {
        engine = pluginId.ToLowerInvariant() switch
        {
            "oracle" => EngineType.Oracle,
            "postgresql" => EngineType.PostgreSQL,
            "sqlserver" => EngineType.SqlServer,
            "mysql" => EngineType.MySQL,
            "mongodb" => EngineType.MongoDB,
            "cassandra" => EngineType.Cassandra,
            "sybase" => EngineType.Sybase,
            _ => EngineType.Unknown
        };
        return engine != EngineType.Unknown;
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

public record LinkJobInventoryRequest(Guid ProjectId);
