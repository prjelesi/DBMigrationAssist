using AssessmentToolkit.Api.Middleware;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using AssessmentToolkit.Shared.Auth;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public sealed class AgentHmacAuthMiddlewareTests
{
    private const string Psk = "test-agent-psk-with-at-least-32-bytes";

    [Fact]
    public async Task InvokeAsync_MatchingAgentIdentity_ContinuesAndUpdatesHeartbeat()
    {
        var agent = new Agent { Name = "Matching agent" };
        await using var db = CreateDbContext();
        db.Agents.Add(agent);
        await db.SaveChangesAsync();

        var nextCalled = false;
        var middleware = new AgentHmacAuthMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });
        var context = CreateSignedContext(agent.AgentId, agent.AgentId);

        await middleware.InvokeAsync(context, db);

        Assert.True(nextCalled);
        Assert.Equal(StatusCodes.Status200OK, context.Response.StatusCode);
        Assert.NotNull(agent.LastHeartbeatAt);
    }

    [Fact]
    public async Task InvokeAsync_MismatchedAgentIdentity_ReturnsForbiddenWithoutSideEffects()
    {
        var agent = new Agent { Name = "Authenticated agent" };
        await using var db = CreateDbContext();
        db.Agents.Add(agent);
        await db.SaveChangesAsync();

        var nextCalled = false;
        var middleware = new AgentHmacAuthMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });
        var context = CreateSignedContext(agent.AgentId, Guid.NewGuid());

        await middleware.InvokeAsync(context, db);

        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status403Forbidden, context.Response.StatusCode);
        Assert.Null(agent.LastHeartbeatAt);
    }

    private static AssessmentDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<AssessmentDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        return new AssessmentDbContext(options);
    }

    private static DefaultHttpContext CreateSignedContext(Guid headerAgentId, Guid routeAgentId)
    {
        var path = $"/api/agent/{routeAgentId}/heartbeat";
        var timestamp = DateTimeOffset.UtcNow.ToString("O");
        var bodyHash = PskAuthenticator.ComputeBodyHash([]);
        var signature = PskAuthenticator.ComputeSignature(Psk, "POST", path, timestamp, bodyHash);
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                [$"AgentPsk:{headerAgentId}"] = Psk
            })
            .Build();

        var context = new DefaultHttpContext
        {
            RequestServices = new ServiceCollection()
                .AddSingleton<IConfiguration>(configuration)
                .BuildServiceProvider()
        };
        context.Request.Method = HttpMethods.Post;
        context.Request.Path = path;
        context.Request.RouteValues["agentId"] = routeAgentId.ToString();
        context.Request.Headers["X-Agent-Id"] = headerAgentId.ToString();
        context.Request.Headers["X-Agent-Timestamp"] = timestamp;
        context.Request.Headers["X-Agent-Signature"] = signature;
        context.Response.Body = new MemoryStream();
        return context;
    }
}