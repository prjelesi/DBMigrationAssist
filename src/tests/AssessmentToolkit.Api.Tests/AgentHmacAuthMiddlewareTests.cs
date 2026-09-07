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

    [Theory]
    [InlineData("POST", "heartbeat")]
    [InlineData("GET", "jobs/next")]
    [InlineData("POST", "results")]
    public async Task InvokeAsync_ReusedNonce_ReturnsUnauthorizedWithoutCallingNextAgain(
        string method,
        string routeSuffix)
    {
        var agent = new Agent { Name = "Replay-protected agent" };
        await using var db = CreateDbContext();
        db.Agents.Add(agent);
        await db.SaveChangesAsync();

        var nextCallCount = 0;
        var middleware = new AgentHmacAuthMiddleware(_ =>
        {
            nextCallCount++;
            return Task.CompletedTask;
        });
        var nonce = Guid.NewGuid();

        await middleware.InvokeAsync(CreateSignedContext(
            agent.AgentId, agent.AgentId, nonce, method: method, routeSuffix: routeSuffix), db);
        db.ChangeTracker.Clear();
        var firstHeartbeat = await db.Agents
            .Where(candidate => candidate.AgentId == agent.AgentId)
            .Select(candidate => candidate.LastHeartbeatAt)
            .SingleAsync();
        db.ChangeTracker.Clear();

        var replay = CreateSignedContext(
            agent.AgentId, agent.AgentId, nonce, method: method, routeSuffix: routeSuffix);
        await middleware.InvokeAsync(replay, db);
        db.ChangeTracker.Clear();

        Assert.Equal(StatusCodes.Status401Unauthorized, replay.Response.StatusCode);
        Assert.Equal(1, nextCallCount);
        Assert.Equal(firstHeartbeat, await db.Agents
            .Where(candidate => candidate.AgentId == agent.AgentId)
            .Select(candidate => candidate.LastHeartbeatAt)
            .SingleAsync());
    }

    [Fact]
    public async Task InvokeAsync_SameNonceForDifferentAgents_AllowsBothRequests()
    {
        var firstAgent = new Agent { Name = "First agent" };
        var secondAgent = new Agent { Name = "Second agent" };
        await using var db = CreateDbContext();
        db.Agents.AddRange(firstAgent, secondAgent);
        await db.SaveChangesAsync();

        var nextCallCount = 0;
        var middleware = new AgentHmacAuthMiddleware(_ =>
        {
            nextCallCount++;
            return Task.CompletedTask;
        });
        var nonce = Guid.NewGuid();

        await middleware.InvokeAsync(CreateSignedContext(firstAgent.AgentId, firstAgent.AgentId, nonce), db);
        await middleware.InvokeAsync(CreateSignedContext(secondAgent.AgentId, secondAgent.AgentId, nonce), db);

        Assert.Equal(2, nextCallCount);
        Assert.Equal(2, await db.AgentRequestNonces.CountAsync(candidate => candidate.Nonce == nonce));
    }

    [Fact]
    public async Task InvokeAsync_MissingNonce_ReturnsUnauthorized()
    {
        await using var db = CreateDbContext();
        var context = CreateSignedContext(Guid.NewGuid(), Guid.NewGuid());
        context.Request.Headers.Remove("X-Agent-Nonce");
        var middleware = new AgentHmacAuthMiddleware(_ => Task.CompletedTask);

        await middleware.InvokeAsync(context, db);

        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);
    }

    [Fact]
    public async Task InvokeAsync_MalformedNonce_ReturnsUnauthorized()
    {
        await using var db = CreateDbContext();
        var context = CreateSignedContext(Guid.NewGuid(), Guid.NewGuid());
        context.Request.Headers["X-Agent-Nonce"] = "not-a-guid";
        var middleware = new AgentHmacAuthMiddleware(_ => Task.CompletedTask);

        await middleware.InvokeAsync(context, db);

        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);
    }

    [Fact]
    public async Task InvokeAsync_ExpiredTimestamp_ReturnsUnauthorized()
    {
        var agent = new Agent { Name = "Expired request agent" };
        await using var db = CreateDbContext();
        db.Agents.Add(agent);
        await db.SaveChangesAsync();
        var context = CreateSignedContext(
            agent.AgentId,
            agent.AgentId,
            timestamp: DateTimeOffset.UtcNow.Subtract(PskAuthenticator.ReplayWindow).AddSeconds(-1));
        var middleware = new AgentHmacAuthMiddleware(_ => Task.CompletedTask);

        await middleware.InvokeAsync(context, db);

        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);
        Assert.Empty(db.AgentRequestNonces);
    }

    private static AssessmentDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<AssessmentDbContext>()
            .UseSqlite("Data Source=:memory:;Foreign Keys=False")
            .Options;
        var db = new AssessmentDbContext(options);
        db.Database.OpenConnection();
        db.Database.EnsureCreated();
        return db;
    }

    private static DefaultHttpContext CreateSignedContext(
        Guid headerAgentId,
        Guid routeAgentId,
        Guid? nonce = null,
        DateTimeOffset? timestamp = null,
        string method = "POST",
        string routeSuffix = "heartbeat")
    {
        var path = $"/api/agent/{routeAgentId}/{routeSuffix}";
        var timestampHeader = (timestamp ?? DateTimeOffset.UtcNow).ToString("O");
        var nonceHeader = (nonce ?? Guid.NewGuid()).ToString("D");
        var bodyHash = PskAuthenticator.ComputeBodyHash([]);
        var signature = PskAuthenticator.ComputeSignature(Psk, method, path, timestampHeader, nonceHeader, bodyHash);
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
        context.Request.Method = method;
        context.Request.Path = path;
        context.Request.RouteValues["agentId"] = routeAgentId.ToString();
        context.Request.Headers["X-Agent-Id"] = headerAgentId.ToString();
        context.Request.Headers["X-Agent-Timestamp"] = timestampHeader;
        context.Request.Headers["X-Agent-Nonce"] = nonceHeader;
        context.Request.Headers["X-Agent-Signature"] = signature;
        context.Response.Body = new MemoryStream();
        return context;
    }
}