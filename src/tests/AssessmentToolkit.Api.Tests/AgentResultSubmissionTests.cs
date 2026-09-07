using AssessmentToolkit.Api.Controllers;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public sealed class AgentResultSubmissionTests
{
    [Fact]
    public async Task SubmitResult_SecondSubmissionForJob_ReturnsConflict()
    {
        await using var db = CreateDbContext();
        var agent = new Agent { Name = "Result agent" };
        var job = new AssessmentJob
        {
            AgentId = agent.AgentId,
            Agent = agent,
            PluginId = "postgresql",
            Status = JobStatus.Assigned
        };
        db.AddRange(agent, job);
        await db.SaveChangesAsync();
        var controller = new AgentJobsController(db);
        var firstSubmission = CreateSubmission(job.JobId);

        var first = await controller.SubmitResult(agent.AgentId, firstSubmission);
        var second = await controller.SubmitResult(agent.AgentId, CreateSubmission(job.JobId));

        Assert.IsType<OkObjectResult>(first);
        Assert.IsType<ConflictObjectResult>(second);
        Assert.Equal(1, await db.Results.CountAsync(result => result.JobId == job.JobId));
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

    private static AgentResultSubmission CreateSubmission(Guid jobId) => new(
        jobId,
        "postgresql",
        "1.0",
        true,
        "{}",
        "{}",
        null,
        null,
        DateTimeOffset.UtcNow);
}