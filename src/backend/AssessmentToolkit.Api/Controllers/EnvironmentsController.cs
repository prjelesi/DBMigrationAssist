using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/environments")]
public class EnvironmentsController(AssessmentDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] Guid projectId) =>
        Ok((await db.Environments.AsNoTracking()
            .Where(e => e.ProjectId == projectId).ToListAsync()).Select(ToResponse));

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        var env = await db.Environments.Include(e => e.Databases).FirstOrDefaultAsync(e => e.EnvironmentId == id);
        return env is null ? NotFound() : Ok(ToResponse(env));
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateEnvironmentRequest req)
    {
        var project = await db.Projects.FindAsync(req.ProjectId);
        if (project is null) return BadRequest("Project not found.");

        var env = new ProjectEnvironment
        {
            ProjectId = req.ProjectId,
            Name = req.Name,
            Type = req.Type,
            Location = req.Location,
            ConnectivityZone = req.ConnectivityZone
        };

        db.Environments.Add(env);
        await db.SaveChangesAsync();
        return CreatedAtAction(nameof(Get), new { id = env.EnvironmentId }, ToResponse(env));
    }

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateEnvironmentRequest req)
    {
        var env = await db.Environments.FindAsync(id);
        if (env is null) return NotFound();

        if (req.Name             is not null) env.Name             = req.Name;
        if (req.Type             is not null) env.Type             = req.Type;
        if (req.Location         is not null) env.Location         = req.Location;
        if (req.ConnectivityZone is not null) env.ConnectivityZone = req.ConnectivityZone;
        env.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync();
        return Ok(ToResponse(env));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var env = await db.Environments.FindAsync(id);
        if (env is null) return NotFound();
        db.Environments.Remove(env);
        await db.SaveChangesAsync();
        return NoContent();
    }

    private static object ToResponse(ProjectEnvironment environment) => new
    {
        environment.EnvironmentId,
        environment.ProjectId,
        environment.Name,
        environment.Type,
        environment.Location,
        environment.ConnectivityZone,
        environment.CreatedAt,
        environment.UpdatedAt,
        Databases = environment.Databases.Select(database => new
        {
            database.DatabaseId,
            database.ProjectId,
            database.EnvironmentId,
            database.Name,
            database.Engine,
            database.Version,
            database.HostName,
            database.Port,
            database.Criticality,
            database.OwnerName,
            database.MetadataJson,
            database.CreatedAt,
            database.UpdatedAt
        })
    };
}

public record CreateEnvironmentRequest(
    Guid ProjectId, string Name, string Type,
    string? Location, string? ConnectivityZone);

public record UpdateEnvironmentRequest(
    string? Name, string? Type,
    string? Location, string? ConnectivityZone);
