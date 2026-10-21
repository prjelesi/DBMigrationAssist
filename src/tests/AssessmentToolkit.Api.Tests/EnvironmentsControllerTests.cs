using System.Text.Json;
using AssessmentToolkit.Api.Controllers;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public sealed class EnvironmentsControllerTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task Create_ReturnsSerializableEnvironmentWithoutProjectNavigation()
    {
        await using var db = CreateDbContext();
        var project = new Project { Name = "Validation project" };
        db.Projects.Add(project);
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();

        var result = await new EnvironmentsController(db).Create(
            new CreateEnvironmentRequest(project.ProjectId, "Development", "Dev", "Local", "Private"));

        var created = Assert.IsType<CreatedAtActionResult>(result);
        using var document = Serialize(created.Value);
        Assert.Equal(project.ProjectId, document.RootElement.GetProperty("projectId").GetGuid());
        Assert.Equal("Development", document.RootElement.GetProperty("name").GetString());
        Assert.False(document.RootElement.TryGetProperty("project", out _));
        Assert.Equal(1, await db.Environments.CountAsync());
    }

    [Fact]
    public async Task Get_WithDatabases_ReturnsSerializableDatabaseDetails()
    {
        await using var db = CreateDbContext();
        var project = new Project { Name = "Validation project" };
        var environment = new ProjectEnvironment { Name = "Development", Project = project };
        var database = new DatabaseInstance { Name = "Orders", Project = project, Environment = environment };
        db.Databases.Add(database);
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();

        var result = await new EnvironmentsController(db).Get(environment.EnvironmentId);

        var ok = Assert.IsType<OkObjectResult>(result);
        using var document = Serialize(ok.Value);
        var item = Assert.Single(document.RootElement.GetProperty("databases").EnumerateArray());
        Assert.Equal(database.DatabaseId, item.GetProperty("databaseId").GetGuid());
        Assert.Equal("Orders", item.GetProperty("name").GetString());
        Assert.False(item.TryGetProperty("environment", out _));
    }

    [Fact]
    public async Task List_WithTrackedRelationships_ReturnsSerializableEnvironment()
    {
        await using var db = CreateDbContext();
        var project = new Project { Name = "Validation project" };
        var environment = new ProjectEnvironment { Name = "Development", Project = project };
        db.Environments.Add(environment);
        await db.SaveChangesAsync();

        var result = await new EnvironmentsController(db).List(project.ProjectId);

        var ok = Assert.IsType<OkObjectResult>(result);
        using var document = Serialize(ok.Value);
        var item = Assert.Single(document.RootElement.EnumerateArray());
        Assert.Equal(environment.EnvironmentId, item.GetProperty("environmentId").GetGuid());
        Assert.False(item.TryGetProperty("project", out _));
    }

    [Fact]
    public async Task Update_WithTrackedProject_PreservesFieldsAndReturnsSerializableResponse()
    {
        await using var db = CreateDbContext();
        var project = new Project { Name = "Validation project" };
        var environment = new ProjectEnvironment
        {
            Name = "Development", Type = "Dev", Project = project, ConnectivityZone = "Private"
        };
        db.Environments.Add(environment);
        await db.SaveChangesAsync();

        var result = await new EnvironmentsController(db).Update(
            environment.EnvironmentId, new UpdateEnvironmentRequest(null, null, "Azure", null));

        var ok = Assert.IsType<OkObjectResult>(result);
        using var document = Serialize(ok.Value);
        Assert.Equal("Azure", document.RootElement.GetProperty("location").GetString());
        Assert.Equal("Development", document.RootElement.GetProperty("name").GetString());
        Assert.Equal("Private", document.RootElement.GetProperty("connectivityZone").GetString());
        db.ChangeTracker.Clear();
        Assert.Equal("Azure", (await db.Environments.SingleAsync()).Location);
    }

    [Fact]
    public async Task MissingProjectOrEnvironment_PreservesErrorResponses()
    {
        await using var db = CreateDbContext();
        var controller = new EnvironmentsController(db);

        Assert.IsType<BadRequestObjectResult>(await controller.Create(
            new CreateEnvironmentRequest(Guid.NewGuid(), "Development", "Dev", null, null)));
        Assert.IsType<NotFoundResult>(await controller.Get(Guid.NewGuid()));
        Assert.IsType<NotFoundResult>(await controller.Update(
            Guid.NewGuid(), new UpdateEnvironmentRequest(null, null, null, null)));
    }

    private static JsonDocument Serialize(object? value) =>
        JsonDocument.Parse(JsonSerializer.Serialize(value, JsonOptions));

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
}
