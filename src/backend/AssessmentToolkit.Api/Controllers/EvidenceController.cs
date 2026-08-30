using System.Security.Cryptography;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/evidence")]
public class EvidenceController(
    AssessmentDbContext db,
    IConfiguration config,
    IAiAdapterService ai,
    ProjectAccessService projectAccess) : ControllerBase
{
    private string StorageRoot =>
        config["Evidence:StorageRoot"] ?? Path.Combine(Directory.GetCurrentDirectory(), "evidence");

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] Guid projectId) =>
        Ok(await db.UploadedReports
            .Where(r => r.ProjectId == projectId)
            .OrderByDescending(r => r.UploadedAt)
            .Select(r => new
            {
                r.ReportId, r.FileName, r.SourceType,
                r.DatabaseId, DatabaseName = r.Database != null ? r.Database.Name : null,
                r.FileSizeBytes, r.ParseStatus, r.ParseConfidence,
                r.UploadedBy, r.UploadedAt, r.ParseErrorMessage,
                r.QuestionnaireResponseId, r.QuestionId,
                HasSummary = r.ParseSummaryJson != null
            })
            .ToListAsync());

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        var report = await db.UploadedReports
            .Where(r => r.ReportId == id)
            .Select(r => new
            {
                r.ReportId, r.ProjectId,
                r.DatabaseId, DatabaseName = r.Database != null ? r.Database.Name : null,
                r.QuestionnaireResponseId, r.QuestionId,
                r.FileName, r.SourceType, r.FileSizeBytes, r.FileHash,
                r.ParseStatus, r.ParseConfidence, r.ParseSummaryJson, r.ParseErrorMessage,
                r.UploadedBy, r.UploadedAt, r.UpdatedAt
            })
            .FirstOrDefaultAsync();
        return report is null ? NotFound() : Ok(report);
    }

    [HttpGet("{id:guid}/download")]
    public async Task<IActionResult> Download(Guid id)
    {
        var report = await db.UploadedReports.FirstOrDefaultAsync(r => r.ReportId == id);
        if (report is null) return NotFound();
        if (!System.IO.File.Exists(report.StoragePath)) return NotFound("File not found on storage.");

        return PhysicalFile(report.StoragePath, "application/octet-stream", report.FileName);
    }

    [HttpPost("upload")]
    [RequestSizeLimit(52_428_800)] // 50 MB
    public async Task<IActionResult> Upload(
        [FromForm] Guid projectId,
        [FromForm] Guid? databaseId,
        [FromForm] string uploadedBy,
        [FromForm] string? sourceType,
        [FromForm] Guid? questionnaireResponseId,
        [FromForm] Guid? questionId,
        IFormFile file)
    {
        if (file.Length == 0) return BadRequest("File is empty.");

        var project = await db.Projects.FindAsync(projectId);
        if (project is null) return BadRequest("Project not found.");
        if (!await projectAccess.CanAccessAsync(
                User,
                projectId,
                environmentId: null,
                write: true,
                HttpContext.RequestAborted))
            return Forbid();

        if (databaseId.HasValue && !await db.Databases.AnyAsync(database =>
                database.DatabaseId == databaseId.Value && database.ProjectId == projectId))
            return BadRequest("Database does not belong to this project.");

        if (questionnaireResponseId.HasValue != questionId.HasValue)
            return BadRequest("Questionnaire response and question must be provided together.");

        if (questionnaireResponseId.HasValue && questionId.HasValue)
        {
            var response = await db.QuestionnaireResponses.FindAsync(questionnaireResponseId.Value);
            if (response is null || response.ProjectId != projectId)
                return BadRequest("Questionnaire response does not belong to this project.");
            if (response.Status == ResponseStatus.Submitted)
                return BadRequest("Cannot attach documents to a submitted response.");

            var allowsAttachments = await db.Questions.AnyAsync(question =>
                question.QuestionId == questionId.Value &&
                question.AllowAttachments &&
                question.Section.TemplateId == response.TemplateId);
            if (!allowsAttachments)
                return BadRequest("This question does not allow attachments.");
        }

        // Compute SHA-256 of file content
        await using var stream = file.OpenReadStream();
        var hashBytes = await SHA256.HashDataAsync(stream);
        var fileHash = Convert.ToHexString(hashBytes).ToLowerInvariant();
        stream.Position = 0;

        // Detect source type
        var detectedType = EvidenceParserService.DetectSourceType(file.FileName, sourceType);

        // Persist to storage volume
        var projectDir = Path.Combine(StorageRoot, projectId.ToString());
        Directory.CreateDirectory(projectDir);
        var storedName = $"{Guid.NewGuid()}_{Path.GetFileName(file.FileName)}";
        var storagePath = Path.Combine(projectDir, storedName);

        await using (var dest = System.IO.File.Create(storagePath))
            await file.CopyToAsync(dest);

        // Create metadata record (status Pending — parse will run next)
        var report = new UploadedReport
        {
            ProjectId = projectId,
            DatabaseId = databaseId,
            QuestionnaireResponseId = questionnaireResponseId,
            QuestionId = questionId,
            FileName = file.FileName,
            SourceType = detectedType,
            FileSizeBytes = file.Length,
            FileHash = fileHash,
            StoragePath = storagePath,
            ParseStatus = questionnaireResponseId.HasValue ? ParseStatus.ReviewRequired : ParseStatus.Pending,
            UploadedBy = uploadedBy
        };

        db.UploadedReports.Add(report);
        await db.SaveChangesAsync();

        // Questionnaire documents are retained as respondent-supplied evidence and reviewed as-is.
        if (!questionnaireResponseId.HasValue)
            await ParseInlineAsync(report);

        return CreatedAtAction(nameof(Get), new { id = report.ReportId }, new
        {
            report.ReportId, report.FileName, report.SourceType,
            report.DatabaseId,
            report.FileSizeBytes, report.ParseStatus, report.ParseConfidence,
            report.ParseErrorMessage
        });
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var report = await db.UploadedReports.FindAsync(id);
        if (report is null) return NotFound();

        // Remove file from storage
        if (System.IO.File.Exists(report.StoragePath))
            System.IO.File.Delete(report.StoragePath);

        db.UploadedReports.Remove(report);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("{id:guid}/reparse")]
    public async Task<IActionResult> Reparse(Guid id)
    {
        var report = await db.UploadedReports.FindAsync(id);
        if (report is null) return NotFound();
        if (!System.IO.File.Exists(report.StoragePath))
            return BadRequest("File not found on storage. Cannot reparse.");

        await ParseInlineAsync(report);
        return Ok(new { report.ReportId, report.ParseStatus, report.ParseConfidence });
    }

    // ── Private helpers ───────────────────────────────────────────────────

    private async Task ParseInlineAsync(UploadedReport report)
    {
        try
        {
            report.ParseStatus = ParseStatus.Parsing;
            await db.SaveChangesAsync();

            var content = await System.IO.File.ReadAllTextAsync(report.StoragePath);

            // Use AI for unsupported formats (AWR, Statspack, etc.); structured parsers for known types
            var result = await EvidenceParserService.ParseWithAiAsync(report.SourceType, content, ai);

            report.ParseStatus      = result.Status;
            report.ParseConfidence  = result.Confidence;
            report.ParseSummaryJson = result.SummaryJson;
            report.ParseErrorMessage = result.ErrorMessage;
            report.UpdatedAt = DateTimeOffset.UtcNow;
        }
        catch (Exception ex)
        {
            report.ParseStatus       = ParseStatus.Failed;
            report.ParseErrorMessage = ex.Message;
            report.UpdatedAt         = DateTimeOffset.UtcNow;
        }

        await db.SaveChangesAsync();
    }
}
