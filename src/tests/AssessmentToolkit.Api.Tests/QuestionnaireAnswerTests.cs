using AssessmentToolkit.Api.Controllers;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public sealed class QuestionnaireAnswerTests
{
    [Fact]
    public async Task SaveAnswers_NewAnswer_IsInsertedAndReadableAfterReload()
    {
        await using var db = CreateDbContext();
        var (response, question) = await SeedAsync(db);
        var controller = new QuestionnairesController(db, new UnusedTemplateLoader());

        var result = await controller.SaveAnswers(response.ResponseId,
            new SaveAnswersRequest([new AnswerInput(question.QuestionId, "Initial answer")]));

        Assert.IsType<OkObjectResult>(result);
        db.ChangeTracker.Clear();
        var saved = await db.Answers.SingleAsync();
        Assert.Equal(response.ResponseId, saved.ResponseId);
        Assert.Equal(question.QuestionId, saved.QuestionId);
        Assert.Equal("Initial answer", saved.Value);
        Assert.Equal(ResponseStatus.InProgress, (await db.QuestionnaireResponses.SingleAsync()).Status);
    }

    [Fact]
    public async Task SaveAnswers_ExistingAnswer_UpdatesWithoutCreatingDuplicate()
    {
        await using var db = CreateDbContext();
        var (response, question) = await SeedAsync(db);
        var answer = new Answer
        {
            ResponseId = response.ResponseId, QuestionId = question.QuestionId, Value = "Original"
        };
        db.Answers.Add(answer);
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        var controller = new QuestionnairesController(db, new UnusedTemplateLoader());

        var result = await controller.SaveAnswers(response.ResponseId,
            new SaveAnswersRequest([new AnswerInput(question.QuestionId, "Updated")]));

        Assert.IsType<OkObjectResult>(result);
        db.ChangeTracker.Clear();
        var saved = await db.Answers.SingleAsync();
        Assert.Equal(answer.AnswerId, saved.AnswerId);
        Assert.Equal("Updated", saved.Value);
    }

    [Fact]
    public async Task SaveAnswers_RepeatedQuestionInRequest_InsertsOneAnswerWithFinalValue()
    {
        await using var db = CreateDbContext();
        var (response, question) = await SeedAsync(db);
        var controller = new QuestionnairesController(db, new UnusedTemplateLoader());

        var result = await controller.SaveAnswers(response.ResponseId,
            new SaveAnswersRequest([
                new AnswerInput(question.QuestionId, "First"),
                new AnswerInput(question.QuestionId, "Final")
            ]));

        Assert.IsType<OkObjectResult>(result);
        db.ChangeTracker.Clear();
        Assert.Equal("Final", (await db.Answers.SingleAsync()).Value);
    }

    [Fact]
    public async Task SaveAnswers_SubmittedResponse_RejectsWithoutAddingAnswer()
    {
        await using var db = CreateDbContext();
        var (response, question) = await SeedAsync(db);
        var persistedResponse = await db.QuestionnaireResponses.SingleAsync();
        persistedResponse.Status = ResponseStatus.Submitted;
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        var controller = new QuestionnairesController(db, new UnusedTemplateLoader());

        var result = await controller.SaveAnswers(response.ResponseId,
            new SaveAnswersRequest([new AnswerInput(question.QuestionId, "Rejected")]));

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Empty(await db.Answers.ToListAsync());
    }

    [Fact]
    public async Task SaveAnswers_MissingResponse_ReturnsNotFound()
    {
        await using var db = CreateDbContext();
        var controller = new QuestionnairesController(db, new UnusedTemplateLoader());

        Assert.IsType<NotFoundResult>(await controller.SaveAnswers(
            Guid.NewGuid(), new SaveAnswersRequest([])));
    }

    private static async Task<(QuestionnaireResponse Response, Question Question)> SeedAsync(AssessmentDbContext db)
    {
        var project = new Project { Name = "Validation project" };
        var template = new QuestionnaireTemplate { Name = "Validation template" };
        var section = new QuestionnaireSection { Title = "Baseline", Template = template };
        var question = new Question { Text = "Context", Section = section };
        var response = new QuestionnaireResponse { Project = project, Template = template };
        db.AddRange(question, response);
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        return (response, question);
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

    private sealed class UnusedTemplateLoader : IQuestionnaireTemplateLoader
    {
        public IReadOnlyList<QuestionnaireTemplate> LoadTemplates() =>
            throw new InvalidOperationException("Template loading is not part of saving answers.");
    }
}
