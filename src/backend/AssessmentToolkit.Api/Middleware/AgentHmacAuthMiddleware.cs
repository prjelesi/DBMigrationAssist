using AssessmentToolkit.Data;
using AssessmentToolkit.Shared.Auth;
using Microsoft.EntityFrameworkCore;
using System.Text;

namespace AssessmentToolkit.Api.Middleware;

/// <summary>
/// Validates PSK/HMAC-SHA256 signatures on all /api/agent/* requests.
/// Rejects requests with missing, invalid or replayed signatures.
/// </summary>
public class AgentHmacAuthMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context, AssessmentDbContext db)
    {
        var agentIdHeader = context.Request.Headers["X-Agent-Id"].FirstOrDefault();
        var signatureHeader = context.Request.Headers["X-Agent-Signature"].FirstOrDefault();
        var timestampHeader = context.Request.Headers["X-Agent-Timestamp"].FirstOrDefault();
        var nonceHeader = context.Request.Headers["X-Agent-Nonce"].FirstOrDefault();

        if (string.IsNullOrEmpty(agentIdHeader) || string.IsNullOrEmpty(signatureHeader) ||
            string.IsNullOrEmpty(timestampHeader) || string.IsNullOrEmpty(nonceHeader))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = "Missing agent authentication headers." });
            return;
        }

        if (!Guid.TryParse(nonceHeader, out var nonce))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid request nonce." });
            return;
        }

        if (!Guid.TryParse(agentIdHeader, out var agentId))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid agent identifier." });
            return;
        }

        if (!context.Request.RouteValues.TryGetValue("agentId", out var routeValue) ||
            !Guid.TryParse(Convert.ToString(routeValue), out var routeAgentId) ||
            routeAgentId != agentId)
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            await context.Response.WriteAsJsonAsync(new { error = "Agent identity does not match the requested route." });
            return;
        }

        var agent = await db.Agents.FirstOrDefaultAsync(a =>
            a.AgentId == agentId && a.Status != Core.Enums.AgentStatus.Revoked);
        if (agent is null)
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = "Agent not found or revoked." });
            return;
        }

        // Buffer the body so we can compute the hash
        context.Request.EnableBuffering();
        using var reader = new StreamReader(context.Request.Body, Encoding.UTF8, leaveOpen: true);
        var body = await reader.ReadToEndAsync();
        context.Request.Body.Position = 0;

        var bodyHash = PskAuthenticator.ComputeBodyHash(Encoding.UTF8.GetBytes(body));

        // Derive the PSK from the stored hash for verification
        // In production: re-derive or use a secure comparison path
        var psk = ResolvePsk(agent, context.RequestServices);
        if (psk is null)
        {
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            await context.Response.WriteAsJsonAsync(new { error = "Agent PSK configuration error." });
            return;
        }

        var valid = PskAuthenticator.Verify(
            psk,
            context.Request.Method,
            context.Request.Path.ToString(),
            timestampHeader,
            nonceHeader,
            bodyHash,
            signatureHeader);

        if (!valid)
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid or expired agent signature." });
            return;
        }

        if (!DateTimeOffset.TryParse(
                timestampHeader,
                null,
                System.Globalization.DateTimeStyles.RoundtripKind,
                out var timestamp))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid agent timestamp." });
            return;
        }

        db.AgentRequestNonces.Add(new Core.Entities.AgentRequestNonce
        {
            AgentId = agentId,
            Nonce = nonce,
            ExpiresAt = timestamp + PskAuthenticator.ReplayWindow
        });

        // Stamp the agent identity into the request for downstream use
        context.Items["AgentId"] = agentId;
        context.Items["Agent"] = agent;

        // Update heartbeat
        agent.LastHeartbeatAt = DateTimeOffset.UtcNow;
        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            db.ChangeTracker.Clear();
            if (await db.AgentRequestNonces.AnyAsync(
                candidate => candidate.AgentId == agentId && candidate.Nonce == nonce))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { error = "Agent request nonce has already been used." });
                return;
            }

            throw;
        }

        await next(context);
    }

    private static string? ResolvePsk(Core.Entities.Agent agent, IServiceProvider services)
    {
        // The PSK resolver reads from a secure config or key store in production.
        // For the PoC, the PSK is available via environment variable keyed by agent ID.
        var configKey = $"AgentPsk:{agent.AgentId}";
        var config = services.GetService<IConfiguration>();
        return config?[configKey];
    }
}
