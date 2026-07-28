using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/ai")]
public class AiController(AssessmentDbContext db, IAiAdapterService ai) : ControllerBase
{
    // ── Providers ────────────────────────────────────────────────────────

    [HttpGet("providers")]
    public async Task<IActionResult> ListProviders() =>
        Ok(await db.AiProviders.OrderByDescending(p => p.IsDefault).ThenBy(p => p.Name).ToListAsync());

    [HttpPost("providers")]
    public async Task<IActionResult> RegisterProvider([FromBody] RegisterProviderRequest req)
    {
        if (req.IsDefault)
        {
            // Clear existing default
            var existing = await db.AiProviders.Where(p => p.IsDefault).ToListAsync();
            existing.ForEach(p => p.IsDefault = false);
        }

        var provider = new AiProvider
        {
            Name           = req.Name,
            ProviderType   = req.ProviderType,
            Endpoint       = req.Endpoint,
            DeploymentName = req.DeploymentName,
            ApiVersion     = req.ApiVersion,
            ApiKeyEnvVar   = req.ApiKeyEnvVar,
            IsDefault      = req.IsDefault,
            Notes          = req.Notes,
        };

        db.AiProviders.Add(provider);
        await db.SaveChangesAsync();
        return CreatedAtAction(nameof(ListProviders), new { }, new
        {
            provider.ProviderId, provider.Name, provider.ProviderType,
            provider.Endpoint, provider.DeploymentName, provider.IsDefault
        });
    }

    [HttpPatch("providers/{id:guid}")]
    public async Task<IActionResult> UpdateProvider(Guid id, [FromBody] UpdateProviderRequest req)
    {
        var provider = await db.AiProviders.FindAsync(id);
        if (provider is null) return NotFound();

        if (req.Name is not null)           provider.Name           = req.Name;
        if (req.Endpoint is not null)       provider.Endpoint       = req.Endpoint;
        if (req.DeploymentName is not null) provider.DeploymentName = req.DeploymentName;
        if (req.ApiKeyEnvVar is not null)   provider.ApiKeyEnvVar   = req.ApiKeyEnvVar;
        if (req.Notes is not null)          provider.Notes          = req.Notes;
        if (req.Status.HasValue)            provider.Status         = req.Status.Value;

        if (req.IsDefault == true)
        {
            var others = await db.AiProviders.Where(p => p.IsDefault && p.ProviderId != id).ToListAsync();
            others.ForEach(p => p.IsDefault = false);
            provider.IsDefault = true;
        }

        provider.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();
        return Ok(provider);
    }

    [HttpDelete("providers/{id:guid}")]
    public async Task<IActionResult> DeleteProvider(Guid id)
    {
        var provider = await db.AiProviders.FindAsync(id);
        if (provider is null) return NotFound();
        db.AiProviders.Remove(provider);
        await db.SaveChangesAsync();
        return NoContent();
    }

    // ── Status ───────────────────────────────────────────────────────────

    [HttpGet("status")]
    public IActionResult Status() => Ok(new
    {
        available  = ai.IsAvailable,
        message    = ai.IsAvailable
            ? "AI Foundry is configured and available."
            : "AI Foundry is not configured. Set AiFoundry:Endpoint, AiFoundry:ApiKey and AiFoundry:Deployment environment variables.",
        configuredVia = "Environment variables (AiFoundry:Endpoint / AZURE_OPENAI_ENDPOINT)"
    });

    // ── Test connection ───────────────────────────────────────────────────

    [HttpPost("test")]
    public async Task<IActionResult> Test(CancellationToken ct)
    {
        if (!ai.IsAvailable)
            return BadRequest("AI Foundry is not configured.");

        var result = await ai.CompleteAsync(
            "You are a helpful assistant.",
            "Reply with exactly: {\"status\":\"ok\",\"message\":\"Connection successful\"}",
            ct);

        if (result is null)
            return StatusCode(502, new { error = "AI returned no response." });

        return Ok(new { raw = result, aiAvailable = true });
    }

    // ── Finding enrichment ───────────────────────────────────────────────

    [HttpPost("enrich/{resultId:guid}")]
    public async Task<IActionResult> EnrichFinding(Guid resultId, CancellationToken ct)
    {
        var result = await db.Results
            .Include(r => r.Database)
            .FirstOrDefaultAsync(r => r.ResultId == resultId, ct);

        if (result is null) return NotFound();

        if (!ai.IsAvailable)
            return BadRequest("AI Foundry is not configured. Cannot enrich findings.");

        var systemPrompt = """
            You are a database migration expert. Given raw assessment findings, provide:
            1. A recommended migration path (source → target)
            2. Key risks (max 3, with severity High/Medium/Low)
            3. Estimated migration complexity: Low / Medium / High / Very High
            4. Top 3 remediation steps
            Return ONLY valid JSON with fields: migrationPath, risks, complexity, remediationSteps.
            """;

        var userPrompt = $"""
            Engine: {result.Database?.Engine}
            Plugin: {result.PluginId}
            Findings:
            {result.FindingJson[..Math.Min(result.FindingJson.Length, 4000)]}
            """;

        var enriched = await ai.CompleteAsync(systemPrompt, userPrompt, ct);
        if (enriched is null) return StatusCode(502, new { error = "AI enrichment failed." });

        // Merge AI enrichment into the existing finding JSON
        result.FindingJson = MergeJson(result.FindingJson, enriched);
        result.Confidence  = Core.Enums.ConfidenceLevel.High;
        await db.SaveChangesAsync(ct);

        return Ok(new { result.ResultId, result.Confidence, enrichment = enriched });
    }

    // ── Report generation ─────────────────────────────────────────────────

    [HttpPost("generate-report")]
    public async Task<IActionResult> GenerateReport([FromBody] GenerateReportRequest req, CancellationToken ct)
    {
        if (!ai.IsAvailable)
            return BadRequest("AI Foundry is not configured.");

        var project = await db.Projects.Include(p => p.Customer).FirstOrDefaultAsync(p => p.ProjectId == req.ProjectId, ct);
        if (project is null) return BadRequest("Project not found.");

        var databases    = await db.Databases.Where(d => d.ProjectId == req.ProjectId).ToListAsync(ct);
        var agentResults = await db.Results
            .Where(r => r.Job.Agent.ProjectId == req.ProjectId)
            .OrderByDescending(r => r.AssessedAt)
            .Take(20)
            .ToListAsync(ct);
        var evidence     = await db.UploadedReports
            .Where(e => e.ProjectId == req.ProjectId && e.ParseStatus == Core.Enums.ParseStatus.Parsed)
            .ToListAsync(ct);

        var systemPrompt = """
            You are a senior database migration consultant writing a professional assessment report.
            Structure the report as JSON with these sections:
            {
              "executiveSummary": string (2-3 paragraphs),
              "scopeSummary": { "databaseCount": number, "enginesFound": [string], "criticalCount": number },
              "migrationReadiness": "Ready|NeedsWork|NotReady",
              "keyRisks": [ { "title": string, "severity": "High|Medium|Low", "description": string } ],
              "recommendedWave": string (describe the recommended migration order),
              "nextSteps": [ string ],
              "estimatedEffort": "Low|Medium|High|Very High"
            }
            Return ONLY valid JSON.
            """;

        var dbSummary = string.Join("\n", databases.Select(d =>
            $"- {d.Name} ({d.Engine} {d.Version}) | Criticality: {d.Criticality} | Host: {d.HostName}"));

        var evidenceSummary = string.Join("\n", evidence.Select(e =>
            $"- {e.FileName} ({e.SourceType}) | Confidence: {e.ParseConfidence}"));

        var userPrompt = $"""
            Project: {project.Name}
            Customer: {project.Customer?.Name}
            Deployment mode: {project.DeploymentMode}

            Databases in scope ({databases.Count}):
            {dbSummary}

            Evidence files ingested ({evidence.Count}):
            {evidenceSummary}

            Assessment results available: {agentResults.Count}
            """;

        var reportJson = await ai.CompleteAsync(systemPrompt, userPrompt, ct);
        if (reportJson is null) return StatusCode(502, new { error = "Report generation failed." });

        return Ok(new { projectId = req.ProjectId, reportJson, generatedAt = DateTimeOffset.UtcNow });
    }

    private static string MergeJson(string baseJson, string enrichmentJson)
    {
        try
        {
            using var baseDoc       = System.Text.Json.JsonDocument.Parse(baseJson);
            using var enrichmentDoc = System.Text.Json.JsonDocument.Parse(enrichmentJson);
            var merged = new System.Text.Json.Nodes.JsonObject();
            foreach (var prop in baseDoc.RootElement.EnumerateObject())
                merged[prop.Name] = System.Text.Json.Nodes.JsonNode.Parse(prop.Value.GetRawText());
            merged["_aiEnrichment"] = System.Text.Json.Nodes.JsonNode.Parse(enrichmentJson);
            return merged.ToJsonString();
        }
        catch { return baseJson; }
    }
}

public record RegisterProviderRequest(
    string Name, AiProviderType ProviderType, string Endpoint,
    string DeploymentName, string? ApiVersion,
    string ApiKeyEnvVar, bool IsDefault, string? Notes);

public record UpdateProviderRequest(
    string? Name, string? Endpoint, string? DeploymentName,
    string? ApiKeyEnvVar, string? Notes,
    AiProviderStatus? Status, bool? IsDefault);

public record GenerateReportRequest(Guid ProjectId);
