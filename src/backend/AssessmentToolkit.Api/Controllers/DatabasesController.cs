using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/databases")]
public class DatabasesController(AssessmentDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] Guid projectId, [FromQuery] Guid? environmentId)
    {
        var query = db.Databases.Include(d => d.Environment)
            .Where(d => d.ProjectId == projectId);

        if (environmentId.HasValue)
            query = query.Where(d => d.EnvironmentId == environmentId);

        return Ok(await query.OrderBy(d => d.Name).ToListAsync());
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        var db2 = await db.Databases.Include(d => d.Environment)
            .Include(d => d.Results)
            .FirstOrDefaultAsync(d => d.DatabaseId == id);
        return db2 is null ? NotFound() : Ok(db2);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateDatabaseRequest req)
    {
        var project = await db.Projects.FindAsync(req.ProjectId);
        if (project is null) return BadRequest("Project not found.");

        var instance = new DatabaseInstance
        {
            ProjectId = req.ProjectId,
            EnvironmentId = req.EnvironmentId,
            Name = req.Name,
            Engine = req.Engine,
            Version = req.Version,
            HostName = req.HostName,
            Port = req.Port,
            Criticality = req.Criticality,
            OwnerName = req.OwnerName
        };

        db.Databases.Add(instance);
        await db.SaveChangesAsync();
        return CreatedAtAction(nameof(Get), new { id = instance.DatabaseId }, instance);
    }

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateDatabaseRequest req)
    {
        var instance = await db.Databases.FindAsync(id);
        if (instance is null) return NotFound();

        if (req.Criticality.HasValue) instance.Criticality = req.Criticality.Value;
        if (req.OwnerName is not null) instance.OwnerName = req.OwnerName;
        if (req.Version is not null) instance.Version = req.Version;
        instance.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync();
        return Ok(instance);
    }
}

public record CreateDatabaseRequest(
    Guid ProjectId, Guid? EnvironmentId, string Name,
    EngineType Engine, string? Version, string? HostName,
    int? Port, Criticality Criticality, string? OwnerName);

public record UpdateDatabaseRequest(
    Criticality? Criticality, string? OwnerName, string? Version);
