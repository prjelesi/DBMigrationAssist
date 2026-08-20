using System.Security.Claims;
using System.Text.Json;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Middleware;

public sealed class GovernanceMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(
        HttpContext context,
        AssessmentDbContext db,
        ProjectAccessService access)
    {
        if (!context.Request.Path.StartsWithSegments("/api") ||
            context.Request.Path.StartsWithSegments("/api/auth"))
        {
            await next(context);
            return;
        }

        if (context.User.IsInRole("Service"))
        {
            if (!context.Request.Path.StartsWithSegments("/api/ai/enrich"))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                return;
            }

            await next(context);
            await WriteAuditAsync(context, db, null, null);
            return;
        }

        var scope = await ResolveScopeAsync(context, db);
        if (scope.ProjectId.HasValue && !await access.CanAccessAsync(
            context.User,
            scope.ProjectId.Value,
            scope.EnvironmentId,
            IsWrite(context.Request.Method),
            context.RequestAborted))
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            await context.Response.WriteAsJsonAsync(new { message = "You do not have access to this project scope." });
            return;
        }

        await next(context);
        await WriteAuditAsync(context, db, scope.ProjectId, scope.EnvironmentId);
    }

    private static bool IsWrite(string method) =>
        !HttpMethods.IsGet(method) && !HttpMethods.IsHead(method) && !HttpMethods.IsOptions(method);

    private static async Task<(Guid? ProjectId, Guid? EnvironmentId)> ResolveScopeAsync(
        HttpContext context,
        AssessmentDbContext db)
    {
        Guid? projectId = TryGuid(context.Request.Query["projectId"]);
        Guid? environmentId = TryGuid(context.Request.Query["environmentId"]);

        if (!projectId.HasValue && IsWrite(context.Request.Method) &&
            context.Request.ContentType?.StartsWith("application/json", StringComparison.OrdinalIgnoreCase) == true)
        {
            context.Request.EnableBuffering();
            try
            {
                using var document = await JsonDocument.ParseAsync(context.Request.Body, cancellationToken: context.RequestAborted);
                if (document.RootElement.TryGetProperty("projectId", out var projectProperty))
                    projectId = TryGuid(projectProperty.GetString());
                if (document.RootElement.TryGetProperty("environmentId", out var environmentProperty))
                    environmentId = TryGuid(environmentProperty.GetString());
            }
            catch (JsonException) { }
            finally
            {
                context.Request.Body.Position = 0;
            }
        }

        var segments = context.Request.Path.Value?.Split('/', StringSplitOptions.RemoveEmptyEntries) ?? [];
        var resourceIdSegment = segments.Length > 3 &&
            segments[1].Equals("ai", StringComparison.OrdinalIgnoreCase) &&
            segments[2].Equals("reports", StringComparison.OrdinalIgnoreCase)
                ? segments[3]
                : segments.ElementAtOrDefault(2);
        if (resourceIdSegment is null || !Guid.TryParse(resourceIdSegment, out var resourceId))
            return (projectId, environmentId);

        switch (segments[1].ToLowerInvariant())
        {
            case "projects":
                projectId ??= resourceId;
                break;
            case "environments":
                var environment = await db.Environments.AsNoTracking()
                    .Where(e => e.EnvironmentId == resourceId)
                    .Select(e => new { e.ProjectId, e.EnvironmentId })
                    .FirstOrDefaultAsync(context.RequestAborted);
                projectId ??= environment?.ProjectId;
                environmentId ??= environment?.EnvironmentId;
                break;
            case "databases":
                var database = await db.Databases.AsNoTracking()
                    .Where(d => d.DatabaseId == resourceId)
                    .Select(d => new { d.ProjectId, d.EnvironmentId })
                    .FirstOrDefaultAsync(context.RequestAborted);
                projectId ??= database?.ProjectId;
                environmentId ??= database?.EnvironmentId;
                break;
            case "agents":
                var agent = await db.Agents.AsNoTracking()
                    .Where(a => a.AgentId == resourceId)
                    .Select(a => new { a.ProjectId, a.EnvironmentId })
                    .FirstOrDefaultAsync(context.RequestAborted);
                projectId ??= agent?.ProjectId;
                environmentId ??= agent?.EnvironmentId;
                break;
            case "evidence":
                projectId ??= await db.UploadedReports.AsNoTracking()
                    .Where(r => r.ReportId == resourceId)
                    .Select(r => (Guid?)r.ProjectId)
                    .FirstOrDefaultAsync(context.RequestAborted);
                break;
            case "portfolios":
                projectId ??= await db.Portfolios.AsNoTracking()
                    .Where(p => p.PortfolioId == resourceId)
                    .Select(p => (Guid?)p.ProjectId)
                    .FirstOrDefaultAsync(context.RequestAborted);
                break;
            case "ai" when segments.Length > 3 && segments[2].Equals("reports", StringComparison.OrdinalIgnoreCase):
                projectId ??= await db.GeneratedReports.AsNoTracking()
                    .Where(r => r.GeneratedReportId == resourceId)
                    .Select(r => (Guid?)r.ProjectId)
                    .FirstOrDefaultAsync(context.RequestAborted);
                break;
        }

        return (projectId, environmentId);
    }

    private static async Task WriteAuditAsync(
        HttpContext context,
        AssessmentDbContext db,
        Guid? projectId,
        Guid? environmentId)
    {
        if (!IsWrite(context.Request.Method) || context.Response.StatusCode >= 400) return;

        var segments = context.Request.Path.Value?.Split('/', StringSplitOptions.RemoveEmptyEntries) ?? [];
        db.AuditEvents.Add(new AuditEvent
        {
            ProjectId = projectId,
            EnvironmentId = environmentId,
            ActorId = context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "unknown",
            ActorName = context.User.Identity?.Name ?? "unknown",
            Action = $"{context.Request.Method} {context.Request.Path}",
            ResourceType = segments.Length > 1 ? segments[1] : "api",
            ResourceId = segments.FirstOrDefault(segment => Guid.TryParse(segment, out _)),
            Method = context.Request.Method,
            Path = context.Request.Path,
            StatusCode = context.Response.StatusCode
        });
        await db.SaveChangesAsync(context.RequestAborted);
    }

    private static Guid? TryGuid(string? value) => Guid.TryParse(value, out var id) ? id : null;
}