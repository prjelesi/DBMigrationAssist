using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/questionnaires")]
public class QuestionnairesController(
    AssessmentDbContext db,
    IQuestionnaireTemplateLoader templateLoader) : ControllerBase
{
    // ── Templates ────────────────────────────────────────────────────────

    [HttpGet("templates")]
    public async Task<IActionResult> ListTemplates() =>
        Ok(await db.QuestionnaireTemplates
            .AsNoTracking()
            .Where(t => t.IsActive)
            .OrderBy(t => t.Phase).ThenBy(t => t.Name)
            .Select(t => new
            {
                t.TemplateId,
                t.Name,
                t.Description,
                t.Phase,
                t.Version,
                t.IsActive,
                t.CreatedAt,
                Sections = t.Sections
                    .OrderBy(s => s.Order)
                    .Select(s => new
                    {
                        s.SectionId,
                        s.TemplateId,
                        s.Title,
                        s.Description,
                        s.Order
                    })
                    .ToList()
            })
            .ToListAsync());

    [HttpGet("templates/{id:guid}")]
    public async Task<IActionResult> GetTemplate(Guid id)
    {
        var t = await db.QuestionnaireTemplates
            .AsNoTracking()
            .Where(t => t.TemplateId == id)
            .Select(t => new
            {
                t.TemplateId,
                t.Name,
                t.Description,
                t.Phase,
                t.Version,
                t.IsActive,
                t.CreatedAt,
                Sections = t.Sections
                    .OrderBy(s => s.Order)
                    .Select(s => new
                    {
                        s.SectionId,
                        s.TemplateId,
                        s.Title,
                        s.Description,
                        s.Order,
                        Questions = s.Questions
                            .OrderBy(q => q.Order)
                            .Select(q => new
                            {
                                q.QuestionId,
                                q.SectionId,
                                q.Text,
                                q.HelpText,
                                q.Type,
                                q.IsRequired,
                                q.AllowCustomAnswer,
                                q.AllowAttachments,
                                q.Order,
                                q.OptionsJson
                            })
                            .ToList()
                    })
                    .ToList()
            })
            .FirstOrDefaultAsync();
        return t is null ? NotFound() : Ok(t);
    }

    // ── Responses ────────────────────────────────────────────────────────

    [HttpGet("responses")]
    public async Task<IActionResult> ListResponses([FromQuery] Guid projectId) =>
        Ok(await db.QuestionnaireResponses
            .AsNoTracking()
            .Where(r => r.ProjectId == projectId)
            .OrderByDescending(r => r.UpdatedAt)
            .Select(r => new
            {
                r.ResponseId,
                r.ProjectId,
                r.TemplateId,
                r.Status,
                r.AssignedTo,
                r.CreatedAt,
                r.UpdatedAt,
                r.SubmittedAt,
                Template = new
                {
                    r.Template.TemplateId,
                    r.Template.Name,
                    r.Template.Description,
                    r.Template.Phase,
                    r.Template.Version
                }
            })
            .ToListAsync());

    [HttpPost("responses")]
    public async Task<IActionResult> StartResponse([FromBody] StartResponseRequest req)
    {
        var project = await db.Projects.FindAsync(req.ProjectId);
        if (project is null) return BadRequest("Project not found.");

        var template = await db.QuestionnaireTemplates.FindAsync(req.TemplateId);
        if (template is null) return BadRequest("Template not found.");

        var existing = await db.QuestionnaireResponses
            .FirstOrDefaultAsync(r => r.ProjectId == req.ProjectId && r.TemplateId == req.TemplateId);
        if (existing is not null)
            return Ok(ToResponseSummary(existing));

        var response = new QuestionnaireResponse
        {
            ProjectId = req.ProjectId,
            TemplateId = req.TemplateId,
            Status = ResponseStatus.InProgress,
            AssignedTo = req.AssignedTo
        };

        db.QuestionnaireResponses.Add(response);
        await db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetResponse), new { id = response.ResponseId }, ToResponseSummary(response));
    }

    [HttpGet("responses/{id:guid}")]
    public async Task<IActionResult> GetResponse(Guid id)
    {
        var r = await db.QuestionnaireResponses
            .AsNoTracking()
            .Where(r => r.ResponseId == id)
            .Select(r => new
            {
                r.ResponseId,
                r.ProjectId,
                r.TemplateId,
                r.Status,
                r.AssignedTo,
                r.CreatedAt,
                r.UpdatedAt,
                r.SubmittedAt,
                Template = new
                {
                    r.Template.TemplateId,
                    r.Template.Name,
                    r.Template.Description,
                    r.Template.Phase,
                    r.Template.Version,
                    Sections = r.Template.Sections
                        .OrderBy(s => s.Order)
                        .Select(s => new
                        {
                            s.SectionId,
                            s.TemplateId,
                            s.Title,
                            s.Description,
                            s.Order,
                            Questions = s.Questions
                                .OrderBy(q => q.Order)
                                .Select(q => new
                                {
                                    q.QuestionId,
                                    q.SectionId,
                                    q.Text,
                                    q.HelpText,
                                    q.Type,
                                    q.IsRequired,
                                    q.AllowCustomAnswer,
                                    q.AllowAttachments,
                                    q.Order,
                                    q.OptionsJson
                                })
                                .ToList()
                        })
                        .ToList()
                },
                Answers = r.Answers
                    .Select(a => new
                    {
                        a.AnswerId,
                        a.ResponseId,
                        a.QuestionId,
                        a.Value,
                        a.UpdatedAt
                    })
                    .ToList()
            })
            .FirstOrDefaultAsync(r => r.ResponseId == id);
        return r is null ? NotFound() : Ok(r);
    }

    private static object ToResponseSummary(QuestionnaireResponse response) => new
    {
        response.ResponseId,
        response.ProjectId,
        response.TemplateId,
        response.Status,
        response.AssignedTo,
        response.CreatedAt,
        response.UpdatedAt,
        response.SubmittedAt
    };

    [HttpGet("responses/{id:guid}/attachments")]
    public async Task<IActionResult> ListAttachments(Guid id)
    {
        if (!await db.QuestionnaireResponses.AnyAsync(response => response.ResponseId == id))
            return NotFound();

        return Ok(await db.UploadedReports
            .Where(report => report.QuestionnaireResponseId == id)
            .OrderBy(report => report.UploadedAt)
            .Select(report => new
            {
                report.ReportId,
                report.ProjectId,
                report.QuestionnaireResponseId,
                report.QuestionId,
                report.FileName,
                report.FileSizeBytes,
                report.ParseStatus,
                report.UploadedBy,
                report.UploadedAt
            })
            .ToListAsync());
    }

    [HttpPut("responses/{id:guid}/answers")]
    public async Task<IActionResult> SaveAnswers(Guid id, [FromBody] SaveAnswersRequest req)
    {
        var response = await db.QuestionnaireResponses
            .Include(r => r.Answers)
            .FirstOrDefaultAsync(r => r.ResponseId == id);

        if (response is null) return NotFound();
        if (response.Status == ResponseStatus.Submitted)
            return BadRequest("Cannot edit a submitted response.");

        foreach (var incoming in req.Answers)
        {
            var existing = response.Answers.FirstOrDefault(a => a.QuestionId == incoming.QuestionId);
            if (existing is null)
            {
                response.Answers.Add(new Answer
                {
                    ResponseId = id,
                    QuestionId = incoming.QuestionId,
                    Value = incoming.Value
                });
            }
            else
            {
                existing.Value = incoming.Value;
                existing.UpdatedAt = DateTimeOffset.UtcNow;
            }
        }

        response.Status = ResponseStatus.InProgress;
        response.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();
        return Ok(new { response.ResponseId, response.Status, savedCount = req.Answers.Count });
    }

    [HttpPost("responses/{id:guid}/submit")]
    public async Task<IActionResult> Submit(Guid id)
    {
        var response = await db.QuestionnaireResponses
            .Include(r => r.Template)
                .ThenInclude(t => t.Sections)
                    .ThenInclude(s => s.Questions)
            .Include(r => r.Answers)
            .FirstOrDefaultAsync(r => r.ResponseId == id);

        if (response is null) return NotFound();

        var requiredQuestions = response.Template.Sections
            .SelectMany(s => s.Questions)
            .Where(q => q.IsRequired)
            .Select(q => new { q.QuestionId, q.AllowAttachments })
            .ToList();

        var answeredIds = response.Answers
            .Where(a => HasMeaningfulAnswer(a.Value))
            .Select(a => a.QuestionId)
            .ToHashSet();

        var attachedQuestionIds = (await db.UploadedReports
            .Where(report => report.QuestionnaireResponseId == id && report.QuestionId.HasValue)
            .Select(report => report.QuestionId!.Value)
            .ToListAsync())
            .ToHashSet();

        var missing = requiredQuestions
            .Where(question =>
                !answeredIds.Contains(question.QuestionId) &&
                !(question.AllowAttachments && attachedQuestionIds.Contains(question.QuestionId)))
            .Select(question => question.QuestionId)
            .ToList();
        if (missing.Count > 0)
            return BadRequest(new { error = "Required questions are unanswered.", missingCount = missing.Count });

        response.Status = ResponseStatus.Submitted;
        response.SubmittedAt = DateTimeOffset.UtcNow;
        response.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();
        return Ok(new { response.ResponseId, response.Status, response.SubmittedAt });
    }

    private static bool HasMeaningfulAnswer(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return false;

        return value.Split('|').Any(part =>
        {
            if (!part.StartsWith("Custom: ", StringComparison.Ordinal))
                return !string.IsNullOrWhiteSpace(part);

            var customValue = part["Custom: ".Length..];
            try
            {
                customValue = Uri.UnescapeDataString(customValue);
            }
            catch (UriFormatException)
            {
                // Treat malformed escape sequences as their literal customer input.
            }

            return !string.IsNullOrWhiteSpace(customValue);
        });
    }

    // ── Template synchronization ─────────────────────────────────────────

    /// <summary>Imports new template versions from the API's QuestionnaireTemplates JSON directory.</summary>
    [HttpPost("templates/seed")]
    public async Task<IActionResult> Seed()
    {
        IReadOnlyList<QuestionnaireTemplate> yamlTemplates;
        try
        {
            yamlTemplates = templateLoader.LoadTemplates();
        }
        catch (InvalidDataException exception)
        {
            return BadRequest(new { error = exception.Message });
        }

        var imported = new List<string>();
        var unchanged = new List<string>();

        foreach (var template in yamlTemplates)
        {
            var existingVersions = await db.QuestionnaireTemplates
                .Where(item => item.Name == template.Name)
                .ToListAsync();

            if (existingVersions.Any(item => item.Version >= template.Version))
            {
                unchanged.Add($"{template.Name} v{template.Version}");
                continue;
            }

            foreach (var existing in existingVersions)
                existing.IsActive = false;

            db.QuestionnaireTemplates.Add(template);
            imported.Add($"{template.Name} v{template.Version}");
        }

        foreach (var versions in db.ChangeTracker.Entries<QuestionnaireTemplate>()
                     .Select(entry => entry.Entity)
                     .GroupBy(template => template.Name))
        {
            var latestVersion = versions.Max(template => template.Version);
            foreach (var template in versions)
                template.IsActive = template.Version == latestVersion;
        }

        await db.SaveChangesAsync();
        return Ok(new { imported, unchanged });
    }
}

public record StartResponseRequest(Guid ProjectId, Guid TemplateId, string? AssignedTo);
public record AnswerInput(Guid QuestionId, string? Value);
public record SaveAnswersRequest(List<AnswerInput> Answers);
