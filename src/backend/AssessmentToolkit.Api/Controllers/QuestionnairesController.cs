using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/questionnaires")]
public class QuestionnairesController(AssessmentDbContext db) : ControllerBase
{
    // ── Templates ────────────────────────────────────────────────────────

    [HttpGet("templates")]
    public async Task<IActionResult> ListTemplates() =>
        Ok(await db.QuestionnaireTemplates
            .Where(t => t.IsActive)
            .Include(t => t.Sections.OrderBy(s => s.Order))
            .OrderBy(t => t.Phase).ThenBy(t => t.Name)
            .ToListAsync());

    [HttpGet("templates/{id:guid}")]
    public async Task<IActionResult> GetTemplate(Guid id)
    {
        var t = await db.QuestionnaireTemplates
            .Include(t => t.Sections.OrderBy(s => s.Order))
                .ThenInclude(s => s.Questions.OrderBy(q => q.Order))
            .FirstOrDefaultAsync(t => t.TemplateId == id);
        return t is null ? NotFound() : Ok(t);
    }

    // ── Responses ────────────────────────────────────────────────────────

    [HttpGet("responses")]
    public async Task<IActionResult> ListResponses([FromQuery] Guid projectId) =>
        Ok(await db.QuestionnaireResponses
            .Where(r => r.ProjectId == projectId)
            .Include(r => r.Template)
            .OrderByDescending(r => r.UpdatedAt)
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
            return Ok(existing); // Idempotent — return existing response

        var response = new QuestionnaireResponse
        {
            ProjectId = req.ProjectId,
            TemplateId = req.TemplateId,
            Status = ResponseStatus.InProgress,
            AssignedTo = req.AssignedTo
        };

        db.QuestionnaireResponses.Add(response);
        await db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetResponse), new { id = response.ResponseId }, response);
    }

    [HttpGet("responses/{id:guid}")]
    public async Task<IActionResult> GetResponse(Guid id)
    {
        var r = await db.QuestionnaireResponses
            .Include(r => r.Template)
                .ThenInclude(t => t.Sections.OrderBy(s => s.Order))
                    .ThenInclude(s => s.Questions.OrderBy(q => q.Order))
            .Include(r => r.Answers)
            .FirstOrDefaultAsync(r => r.ResponseId == id);
        return r is null ? NotFound() : Ok(r);
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
            .Select(q => q.QuestionId)
            .ToList();

        var answeredIds = response.Answers
            .Where(a => !string.IsNullOrWhiteSpace(a.Value))
            .Select(a => a.QuestionId)
            .ToHashSet();

        var missing = requiredQuestions.Where(qId => !answeredIds.Contains(qId)).ToList();
        if (missing.Count > 0)
            return BadRequest(new { error = "Required questions are unanswered.", missingCount = missing.Count });

        response.Status = ResponseStatus.Submitted;
        response.SubmittedAt = DateTimeOffset.UtcNow;
        response.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();
        return Ok(new { response.ResponseId, response.Status, response.SubmittedAt });
    }

    // ── Seed ─────────────────────────────────────────────────────────────

    /// <summary>Seeds the default baseline questionnaire template if it does not exist.</summary>
    [HttpPost("templates/seed")]
    public async Task<IActionResult> Seed()
    {
        if (await db.QuestionnaireTemplates.AnyAsync(t => t.Name == "Database Migration Baseline"))
            return Ok(new { message = "Baseline template already exists." });

        var template = BuildBaselineTemplate();
        db.QuestionnaireTemplates.Add(template);
        await db.SaveChangesAsync();
        return Ok(new { template.TemplateId, template.Name, sectionCount = template.Sections.Count });
    }

    private static QuestionnaireTemplate BuildBaselineTemplate()
    {
        var t = new QuestionnaireTemplate
        {
            Name = "Database Migration Baseline",
            Description = "Captures business context, constraints and technical drivers needed to plan a database migration.",
            Phase = QuestionnairePhase.Baseline
        };

        t.Sections.Add(new QuestionnaireSection
        {
            Title = "Business Context",
            Description = "Understand the business drivers and stakeholders behind this migration.",
            Order = 1,
            Questions =
            [
                new Question { Text = "What is the primary business driver for this migration?", Type = QuestionType.Select, IsRequired = true, Order = 1,
                    OptionsJson = """["Cost reduction","Cloud strategy","End of support","Performance improvement","Consolidation","Compliance","Other"]""" },
                new Question { Text = "Who is the primary business owner / sponsor?", Type = QuestionType.Text, IsRequired = true, Order = 2 },
                new Question { Text = "Describe the scope of this engagement in your own words.", Type = QuestionType.Textarea, IsRequired = false, Order = 3 },
            ]
        });

        t.Sections.Add(new QuestionnaireSection
        {
            Title = "Availability & Risk",
            Description = "Downtime tolerance and business criticality.",
            Order = 2,
            Questions =
            [
                new Question { Text = "What is the maximum tolerable downtime during cutover? (hours)", Type = QuestionType.Number, IsRequired = true, Order = 1 },
                new Question { Text = "What is the Recovery Time Objective (RTO)?", Type = QuestionType.Select, IsRequired = true, Order = 2,
                    OptionsJson = """["< 1 hour","1–4 hours","4–8 hours","8–24 hours","> 24 hours","Not defined"]""" },
                new Question { Text = "What is the Recovery Point Objective (RPO)?", Type = QuestionType.Select, IsRequired = true, Order = 3,
                    OptionsJson = """["Zero data loss","< 15 minutes","< 1 hour","< 4 hours","< 24 hours","Not defined"]""" },
                new Question { Text = "Are there blackout periods when migration is not permitted?", Type = QuestionType.Boolean, IsRequired = true, Order = 4 },
                new Question { Text = "If yes, describe the blackout periods (e.g. month-end, seasonal peaks).", Type = QuestionType.Textarea, IsRequired = false, Order = 5 },
            ]
        });

        t.Sections.Add(new QuestionnaireSection
        {
            Title = "Compliance & Security",
            Description = "Regulatory and data handling requirements.",
            Order = 3,
            Questions =
            [
                new Question { Text = "Which compliance frameworks apply?", Type = QuestionType.MultiSelect, IsRequired = false, Order = 1,
                    OptionsJson = """["GDPR","PCI-DSS","HIPAA","ISO 27001","SOC 2","None","Other"]""" },
                new Question { Text = "Is data residency / sovereignty a requirement?", Type = QuestionType.Boolean, IsRequired = true, Order = 2 },
                new Question { Text = "Are there restrictions on data leaving the current environment?", Type = QuestionType.Boolean, IsRequired = true, Order = 3 },
                new Question { Text = "Describe any specific security or audit requirements.", Type = QuestionType.Textarea, IsRequired = false, Order = 4 },
            ]
        });

        t.Sections.Add(new QuestionnaireSection
        {
            Title = "Target Platform",
            Description = "Preferences for the migration destination.",
            Order = 4,
            Questions =
            [
                new Question { Text = "What is the preferred target platform?", Type = QuestionType.Select, IsRequired = true, Order = 1,
                    OptionsJson = """["Azure SQL Database","Azure SQL Managed Instance","Azure Database for PostgreSQL","Azure Database for MySQL","Azure Cosmos DB","SQL Server on IaaS","Not yet decided","Other"]""" },
                new Question { Text = "Is the target platform already provisioned?", Type = QuestionType.Boolean, IsRequired = true, Order = 2 },
                new Question { Text = "Is a hybrid / phased migration acceptable?", Type = QuestionType.Boolean, IsRequired = false, Order = 3 },
                new Question { Text = "Are there preferred Azure regions?", Type = QuestionType.Text, IsRequired = false, Order = 4 },
            ]
        });

        t.Sections.Add(new QuestionnaireSection
        {
            Title = "Technical Constraints",
            Description = "Known limitations and dependencies.",
            Order = 5,
            Questions =
            [
                new Question { Text = "Are there applications tightly coupled to the database that must be migrated together?", Type = QuestionType.Boolean, IsRequired = true, Order = 1 },
                new Question { Text = "List known application or integration dependencies.", Type = QuestionType.Textarea, IsRequired = false, Order = 2 },
                new Question { Text = "Are there database-specific features in use that may not be supported on the target?", Type = QuestionType.Textarea, IsRequired = false, Order = 3,
                    HelpText = "e.g. Oracle RAC, linked servers, CLR assemblies, specific collations" },
                new Question { Text = "Is there an existing DBA team who will support the migration?", Type = QuestionType.Boolean, IsRequired = true, Order = 4 },
            ]
        });

        return t;
    }
}

public record StartResponseRequest(Guid ProjectId, Guid TemplateId, string? AssignedTo);
public record AnswerInput(Guid QuestionId, string? Value);
public record SaveAnswersRequest(List<AnswerInput> Answers);
