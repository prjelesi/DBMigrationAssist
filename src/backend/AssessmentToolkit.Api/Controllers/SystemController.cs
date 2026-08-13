using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/system")]
public class SystemController(AssessmentDbContext db, IAiAdapterService ai, IServiceProvider services) : ControllerBase
{
    // ── Status ────────────────────────────────────────────────────────────

    [HttpGet("status")]
    public async Task<IActionResult> Status(CancellationToken ct)
    {
        // Database check
        var dbOk = false;
        string? dbError = null;
        int projectCount = 0, agentCount = 0, evidenceCount = 0;
        try
        {
            projectCount  = await db.Projects.CountAsync(ct);
            agentCount    = await db.Agents.CountAsync(ct);
            evidenceCount = await db.UploadedReports.CountAsync(ct);
            dbOk = true;
        }
        catch (Exception ex) { dbError = ex.Message; }

        // AI status
        var aiStatus = !ai.IsAvailable
            ? "Not Configured"
            : ai.LastConnectionSucceeded switch
            {
                true => "Connected",
                false => "Error",
                null => "Configured"
            };
        return Ok(new
        {
            components = new[]
            {
                new { name = "API",        status = "Healthy",                 detail = "REST API is responding." },
                new { name = "Database",   status = dbOk ? "Healthy" : "Error", detail = dbOk ? $"{projectCount} projects, {agentCount} agents" : dbError ?? "Database status unavailable." },
                new { name = "Worker",     status = "Running",                  detail = "Background worker service is active." },
                new { name = "AI Foundry", status = aiStatus,
                                           detail = ai.IsAvailable ? $"{ai.ConfiguredVia}: {ai.Endpoint}" : "Configure endpoint and API key in AI Settings." },
            },
            counts = new { projectCount, agentCount, evidenceCount },
            timestamp = DateTimeOffset.UtcNow
        });
    }

    // ── Config ────────────────────────────────────────────────────────────

    [HttpGet("config")]
    public async Task<IActionResult> GetConfig()
    {
        var raw = await db.SystemConfigs.OrderBy(c => c.Key).ToListAsync();
        return Ok(raw.Select(c => new
        {
            c.Key, c.Description, c.IsSensitive, c.UpdatedAt, c.UpdatedBy,
            Value = c.IsSensitive && c.Value != null
                ? (c.Value.Length > 4 ? $"••••{c.Value[^4..]}" : "••••")
                : c.Value
        }));
    }

    [HttpPut("config")]
    public async Task<IActionResult> SetConfig([FromBody] SetConfigRequest req)
    {
        // Reject attempts to store API keys in the DB — they must stay in env vars
        if (req.Key.Contains("ApiKey", StringComparison.OrdinalIgnoreCase) ||
            req.Key.Contains("Secret",  StringComparison.OrdinalIgnoreCase) ||
            req.Key.Contains("Password", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest(new
            {
                error = "API keys and secrets cannot be stored in the database. Set them via environment variables (AZURE_OPENAI_API_KEY or AiFoundry__ApiKey).",
                hint  = "docker compose: uncomment the AiFoundry__ApiKey line and set the value."
            });
        }

        var config = await db.SystemConfigs.FirstOrDefaultAsync(c => c.Key == req.Key);
        if (config is null)
        {
            config = new SystemConfig
            {
                Key         = req.Key,
                Description = req.Description,
                IsSensitive = req.IsSensitive,
                UpdatedBy   = req.UpdatedBy
            };
            db.SystemConfigs.Add(config);
        }

        config.Value      = req.Value;
        config.UpdatedAt  = DateTimeOffset.UtcNow;
        config.UpdatedBy  = req.UpdatedBy;
        if (req.Description is not null) config.Description = req.Description;

        await db.SaveChangesAsync();

        // Reload AI adapter if AI config changed
        if (req.Key.StartsWith("AiFoundry:"))
            await ai.ReloadConfigAsync(services);

        return Ok(new { config.Key, config.UpdatedAt, aiReloaded = req.Key.StartsWith("AiFoundry:") });
    }

    [HttpDelete("config/{key}")]
    public async Task<IActionResult> DeleteConfig(string key)
    {
        var config = await db.SystemConfigs.FirstOrDefaultAsync(c => c.Key == key);
        if (config is null) return NotFound();
        db.SystemConfigs.Remove(config);
        await db.SaveChangesAsync();
        if (key.StartsWith("AiFoundry:"))
            await ai.ReloadConfigAsync(services);
        return NoContent();
    }

    // ── Agents (all projects) ─────────────────────────────────────────────

    [HttpGet("agents")]
    public async Task<IActionResult> AllAgents() =>
        Ok(await db.Agents
            .Include(a => a.Project).ThenInclude(p => p.Customer)
            .OrderBy(a => a.Project.Name).ThenBy(a => a.Name)
            .Select(a => new
            {
                a.AgentId, a.Name, a.Status, a.AllowedPlugins,
                a.LastHeartbeatAt, a.CreatedAt, a.PskMode,
                ProjectName  = a.Project.Name,
                CustomerName = a.Project.Customer != null ? a.Project.Customer.Name : null
            })
            .ToListAsync());
}

public record SetConfigRequest(
    string Key, string? Value, string? Description,
    bool IsSensitive, string? UpdatedBy);
