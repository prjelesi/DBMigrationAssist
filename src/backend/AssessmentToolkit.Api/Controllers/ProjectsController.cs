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
        Ok(await db.Projects
            .AsNoTracking()
            .Select(p => new
            {
                p.ProjectId,
                p.CustomerId,
                p.Name,
                p.Description,
                p.DeploymentMode,
                p.Status,
                p.CreatedBy,
                p.CreatedAt,
                p.UpdatedAt,
                Customer = new
                {
                    p.Customer.CustomerId,
                    p.Customer.Name,
                    p.Customer.Industry,
                    p.Customer.Region,
                    p.Customer.CreatedAt,
                    p.Customer.UpdatedAt
                }
            })
            .ToListAsync());

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        var project = await db.Projects
            .AsNoTracking()
            .Where(p => p.ProjectId == id)
            .Select(p => new
            {
                p.ProjectId,
                p.CustomerId,
                p.Name,
                p.Description,
                p.DeploymentMode,
                p.Status,
                p.CreatedBy,
                p.CreatedAt,
                p.UpdatedAt,
                Customer = new
                {
                    p.Customer.CustomerId,
                    p.Customer.Name,
                    p.Customer.Industry,
                    p.Customer.Region,
                    p.Customer.CreatedAt,
                    p.Customer.UpdatedAt
                },
                Environments = p.Environments.Select(e => new
                {
                    e.EnvironmentId,
                    e.ProjectId,
                    e.Name,
                    e.Type,
                    e.Location,
                    e.ConnectivityZone,
                    e.CreatedAt,
                    e.UpdatedAt
                })
            })
            .FirstOrDefaultAsync();
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
        return CreatedAtAction(nameof(Get), new { id = project.ProjectId }, new
        {
            project.ProjectId,
            project.CustomerId,
            project.Name,
            project.Description,
            project.DeploymentMode,
            project.Status,
            project.CreatedBy,
            project.CreatedAt,
            project.UpdatedAt
        });
    }
}

public record CreateProjectRequest(
    Guid CustomerId,
    string Name,
    string? Description,
    Core.Enums.DeploymentMode DeploymentMode,
    string CreatedBy);
