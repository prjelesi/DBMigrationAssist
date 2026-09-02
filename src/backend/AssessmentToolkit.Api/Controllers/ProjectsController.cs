using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/projects")]
public class ProjectsController(
    AssessmentDbContext db,
    ProjectAccessService projectAccess,
    ILogger<ProjectsController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List()
    {
        var projects = db.Projects.AsNoTracking();
        if (!User.IsInRole("Administrator"))
        {
            if (!Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
                return Unauthorized();
            projects = projects.Where(p => db.ProjectMemberships.Any(m => m.ProjectId == p.ProjectId && m.UserId == userId));
        }

        return Ok(await projects
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
            }

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
        if (Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
        {
            db.ProjectMemberships.Add(new ProjectMembership
            {
                ProjectId = project.ProjectId,
                UserId = userId,
                Role = "Owner",
                CreatedBy = User.Identity?.Name ?? req.CreatedBy
            });
        }
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

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken)
    {
        var project = await db.Projects.FindAsync([id], cancellationToken);
        if (project is null) return NotFound();
        if (!await projectAccess.IsOwnerAsync(User, id, cancellationToken)) return Forbid();

        var evidencePaths = await db.UploadedReports
            .Where(report => report.ProjectId == id)
            .Select(report => report.StoragePath)
            .ToListAsync(cancellationToken);

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        await db.QuestionnaireResponses
            .Where(response => response.ProjectId == id)
            .ExecuteDeleteAsync(cancellationToken);
        await db.GeneratedReports
            .Where(report => report.ProjectId == id)
            .ExecuteDeleteAsync(cancellationToken);

        db.Projects.Remove(project);
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        foreach (var evidencePath in evidencePaths)
        {
            try
            {
                if (System.IO.File.Exists(evidencePath)) System.IO.File.Delete(evidencePath);
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Could not delete evidence file {EvidencePath} for project {ProjectId}", evidencePath, id);
            }
        }

        return NoContent();
    }
}

public record CreateProjectRequest(
    Guid CustomerId,
    string Name,
    string? Description,
    Core.Enums.DeploymentMode DeploymentMode,
    string CreatedBy);
