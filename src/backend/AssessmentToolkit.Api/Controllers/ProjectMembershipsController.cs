using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/projects/{projectId:guid}/memberships")]
public sealed class ProjectMembershipsController(
    AssessmentDbContext db,
    ProjectAccessService access) : ControllerBase
{
    private static readonly HashSet<string> ValidRoles = new(StringComparer.OrdinalIgnoreCase)
    {
        "Viewer", "Contributor", "Owner"
    };

    [HttpGet]
    public async Task<IActionResult> List(Guid projectId, CancellationToken ct)
    {
        if (!await access.IsOwnerAsync(User, projectId, ct)) return Forbid();
        return Ok(await db.ProjectMemberships.AsNoTracking()
            .Where(m => m.ProjectId == projectId)
            .Select(m => new
            {
                m.MembershipId, m.ProjectId, m.EnvironmentId, m.UserId,
                m.User.Email, m.User.DisplayName, m.Role, m.CreatedAt, m.CreatedBy
            })
            .ToListAsync(ct));
    }

    [HttpPost]
    public async Task<IActionResult> Create(
        Guid projectId,
        [FromBody] SaveMembershipRequest request,
        CancellationToken ct)
    {
        if (!await access.IsOwnerAsync(User, projectId, ct)) return Forbid();
        if (!ValidRoles.Contains(request.Role)) return BadRequest("Role must be Viewer, Contributor, or Owner.");
        if (!await db.AppUsers.AnyAsync(u => u.UserId == request.UserId, ct)) return BadRequest("User not found.");
        if (request.EnvironmentId.HasValue && !await db.Environments.AnyAsync(
            e => e.EnvironmentId == request.EnvironmentId && e.ProjectId == projectId, ct))
            return BadRequest("Environment is not part of this project.");

        var membership = await db.ProjectMemberships.SingleOrDefaultAsync(
            m => m.ProjectId == projectId && m.EnvironmentId == request.EnvironmentId && m.UserId == request.UserId,
            ct);
        if (membership is null)
        {
            membership = new ProjectMembership
            {
                ProjectId = projectId,
                EnvironmentId = request.EnvironmentId,
                UserId = request.UserId,
                CreatedBy = User.Identity?.Name ?? "unknown"
            };
            db.ProjectMemberships.Add(membership);
        }
        membership.Role = ValidRoles.First(role => role.Equals(request.Role, StringComparison.OrdinalIgnoreCase));
        await db.SaveChangesAsync(ct);
        return Ok(membership);
    }

    [HttpDelete("{membershipId:guid}")]
    public async Task<IActionResult> Delete(Guid projectId, Guid membershipId, CancellationToken ct)
    {
        if (!await access.IsOwnerAsync(User, projectId, ct)) return Forbid();
        var membership = await db.ProjectMemberships.SingleOrDefaultAsync(
            m => m.MembershipId == membershipId && m.ProjectId == projectId, ct);
        if (membership is null) return NotFound();
        db.ProjectMemberships.Remove(membership);
        await db.SaveChangesAsync(ct);
        return NoContent();
    }
}

public sealed record SaveMembershipRequest(Guid UserId, Guid? EnvironmentId, string Role);