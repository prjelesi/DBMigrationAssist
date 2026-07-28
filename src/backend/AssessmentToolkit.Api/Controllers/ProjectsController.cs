using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/projects")]
public class ProjectsController(AssessmentDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List() =>
        Ok(await db.Projects.Include(p => p.Customer).ToListAsync());

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        var project = await db.Projects.Include(p => p.Customer)
            .Include(p => p.Environments)
            .FirstOrDefaultAsync(p => p.ProjectId == id);
        return project is null ? NotFound() : Ok(project);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateProjectRequest req)
    {
        var customer = await db.Customers.FindAsync(req.CustomerId);
        if (customer is null) return BadRequest("Customer not found.");

        var project = new Project
        {
            CustomerId = req.CustomerId,
            Name = req.Name,
            Description = req.Description,
            DeploymentMode = req.DeploymentMode,
            CreatedBy = req.CreatedBy
        };

        db.Projects.Add(project);
        await db.SaveChangesAsync();
        return CreatedAtAction(nameof(Get), new { id = project.ProjectId }, project);
    }
}

public record CreateProjectRequest(
    Guid CustomerId,
    string Name,
    string? Description,
    Core.Enums.DeploymentMode DeploymentMode,
    string CreatedBy);
