using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public sealed class AssessmentResultSelectionTests
{
    [Fact]
    public async Task LatestSuccessfulPerDatabase_KeepsOneSuccessfulResultForEachDatabase()
    {
        await using var db = CreateDbContext();
        var firstDatabase = Guid.NewGuid();
        var secondDatabase = Guid.NewGuid();
        AddResult(db, firstDatabase, JobStatus.Completed, new DateTimeOffset(2026, 9, 20, 10, 0, 0, TimeSpan.Zero));
        var expectedFirst = AddResult(db, firstDatabase, JobStatus.Completed, new DateTimeOffset(2026, 9, 21, 10, 0, 0, TimeSpan.Zero));
        AddResult(db, firstDatabase, JobStatus.Failed, new DateTimeOffset(2026, 9, 22, 10, 0, 0, TimeSpan.Zero));
        var expectedSecond = AddResult(db, secondDatabase, JobStatus.Completed, new DateTimeOffset(2026, 9, 19, 10, 0, 0, TimeSpan.Zero));
        await db.SaveChangesAsync();

        var results = await db.Results.LatestSuccessfulPerDatabase().ToListAsync();

        Assert.Equal(2, results.Count);
        Assert.Contains(results, result => result.ResultId == expectedFirst.ResultId);
        Assert.Contains(results, result => result.ResultId == expectedSecond.ResultId);
    }

    [Fact]
    public void LatestSuccessfulPerDatabase_TranslatesForPostgres()
    {
        var options = new DbContextOptionsBuilder<AssessmentDbContext>()
            .UseNpgsql("Host=localhost;Database=translation_only;Username=test;Password=test")
            .Options;
        using var db = new AssessmentDbContext(options);

        var sql = db.Results.LatestSuccessfulPerDatabase().ToQueryString();

        Assert.Contains("MAX", sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("assessment_job", sql, StringComparison.OrdinalIgnoreCase);
    }

    private static AssessmentResult AddResult(
        AssessmentDbContext db,
        Guid databaseId,
        JobStatus status,
        DateTimeOffset assessedAt)
    {
        var job = new AssessmentJob
        {
            DatabaseId = databaseId,
            PluginId = "oracle",
            Status = status
        };
        var result = new AssessmentResult
        {
            Job = job,
            JobId = job.JobId,
            DatabaseId = databaseId,
            PluginId = "oracle",
            AssessedAt = assessedAt
        };
        db.Add(result);
        return result;
    }

    private static AssessmentDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<AssessmentDbContext>()
            .UseInMemoryDatabase($"assessment-results-{Guid.NewGuid()}")
            .Options;
        return new AssessmentDbContext(options);
    }
}
