using System.Security.Claims;
using AssessmentToolkit.Data;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Services;

public sealed class ProjectAccessService(AssessmentDbContext db)
{
    private static readonly IReadOnlyDictionary<string, int> RoleLevels =
        new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            ["Viewer"] = 1,
            ["Contributor"] = 2,
            ["Owner"] = 3
        };

    public async Task<bool> CanAccessAsync(
        ClaimsPrincipal principal,
        Guid projectId,
        Guid? environmentId,
        bool write,
        CancellationToken cancellationToken)
    {
        if (principal.IsInRole("Administrator")) return true;
        if (!Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var userId)) return false;

        var roles = await db.ProjectMemberships
            .AsNoTracking()
            .Where(m => m.UserId == userId && m.ProjectId == projectId &&
                (m.EnvironmentId == null || m.EnvironmentId == environmentId))
            .Select(m => m.Role)
            .ToListAsync(cancellationToken);

        var requiredLevel = write ? 2 : 1;
        return roles.Any(role => RoleLevels.TryGetValue(role, out var level) && level >= requiredLevel);
    }

    public async Task<bool> IsOwnerAsync(
        ClaimsPrincipal principal,
        Guid projectId,
        CancellationToken cancellationToken)
    {
        if (principal.IsInRole("Administrator")) return true;
        if (!Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var userId)) return false;
        return await db.ProjectMemberships.AnyAsync(
            m => m.UserId == userId && m.ProjectId == projectId && m.EnvironmentId == null && m.Role == "Owner",
            cancellationToken);
    }
}