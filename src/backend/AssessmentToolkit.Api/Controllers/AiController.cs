using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/ai")]
public class AiController(
    AssessmentDbContext db,
    IAiAdapterService ai,
    IDataProtectionProvider dataProtectionProvider,
    IServiceProvider services) : ControllerBase
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
        readyForReporting = ai.IsAvailable && ai.LastConnectionSucceeded == true,
        connectionStatus = !ai.IsAvailable
            ? "Not configured"
            : ai.LastConnectionSucceeded switch
            {
                true => "Connected",
                false => "Connection failed",
                null => "Not tested"
            },
        message = !ai.IsAvailable
            ? "AI Foundry is not configured. Enter the endpoint, deployment and API key below."
            : ai.LastConnectionSucceeded switch
            {
                true => "The configured deployment responded successfully.",
                false => "The last connection test failed. Check the endpoint, deployment and API key.",
                null => "Configuration loaded. Test the connection to verify model access."
            },
        configuredVia = ai.ConfiguredVia,
        endpoint = ai.Endpoint,
        deployment = ai.Deployment,
        hasStoredCredential = ai.HasStoredCredential,
        lastConnectionTestedAt = ai.LastConnectionTestedAt
    });

    [HttpPut("configuration")]
    public async Task<IActionResult> Configure([FromBody] ConfigureAiRequest req, CancellationToken ct)
    {
        if (!Uri.TryCreate(req.Endpoint, UriKind.Absolute, out var endpoint) ||
            endpoint.Scheme != Uri.UriSchemeHttps)
        {
            return BadRequest(new { error = "Endpoint must be a valid HTTPS URL." });
        }

        if (string.IsNullOrWhiteSpace(req.Deployment))
            return BadRequest(new { error = "Deployment name is required." });

        var existingCredential = await db.SystemConfigs
            .FirstOrDefaultAsync(c => c.Key == AiConfigKeys.ProtectedApiKey, ct);
        if (string.IsNullOrWhiteSpace(req.ApiKey) && existingCredential is null)
            return BadRequest(new { error = "API key is required for the initial configuration." });

        await UpsertConfig(AiConfigKeys.Endpoint, endpoint.ToString(), "AI Foundry endpoint", false, ct);
        await UpsertConfig(AiConfigKeys.Deployment, req.Deployment.Trim(), "AI Foundry deployment", false, ct);

        if (!string.IsNullOrWhiteSpace(req.ApiKey))
        {
            var protector = dataProtectionProvider.CreateProtector("AssessmentToolkit.AiFoundry.ApiKey.v1");
            await UpsertConfig(
                AiConfigKeys.ProtectedApiKey,
                protector.Protect(req.ApiKey.Trim()),
                "Encrypted AI Foundry API key",
                true,
                ct);
        }

        await db.SaveChangesAsync(ct);
        await ai.ReloadConfigAsync(services);

        return Ok(new
        {
            available = ai.IsAvailable,
            configuredVia = ai.ConfiguredVia,
            endpoint = ai.Endpoint,
            deployment = ai.Deployment,
            hasStoredCredential = ai.HasStoredCredential
        });
    }

    [HttpDelete("configuration/credential")]
    public async Task<IActionResult> ClearStoredCredential(CancellationToken ct)
    {
        var credential = await db.SystemConfigs
            .FirstOrDefaultAsync(c => c.Key == AiConfigKeys.ProtectedApiKey, ct);
        if (credential is not null)
        {
            db.SystemConfigs.Remove(credential);
            await db.SaveChangesAsync(ct);
        }

        await ai.ReloadConfigAsync(services);
        return NoContent();
    }

    // ── Test connection ───────────────────────────────────────────────────

    [HttpPost("test")]
    public async Task<IActionResult> Test(CancellationToken ct)
    {
        var result = await ai.TestConnectionAsync(ct);
        if (!result.Succeeded)
            return ai.IsAvailable
                ? StatusCode(502, result)
                : BadRequest(result);

        return Ok(result);
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
            return StatusCode(StatusCodes.Status503ServiceUnavailable, new
            {
                error = "Microsoft Foundry is required for report generation. Configure it in AI Settings."
            });

        if (ai.LastConnectionSucceeded != true)
            return StatusCode(StatusCodes.Status503ServiceUnavailable, new
            {
                error = "Microsoft Foundry must pass a connection test before report generation. Test it in AI Settings."
            });

        var project = await db.Projects.Include(p => p.Customer).FirstOrDefaultAsync(p => p.ProjectId == req.ProjectId, ct);
        if (project is null) return BadRequest("Project not found.");

        var databases    = await db.Databases.Where(d => d.ProjectId == req.ProjectId).ToListAsync(ct);
        var agentResults = await db.Results
            .Where(r => r.Database != null && r.Database.ProjectId == req.ProjectId)
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

    private async Task UpsertConfig(
        string key,
        string value,
        string description,
        bool isSensitive,
        CancellationToken ct)
    {
        var config = await db.SystemConfigs.FirstOrDefaultAsync(c => c.Key == key, ct);
        if (config is null)
        {
            config = new SystemConfig { Key = key };
            db.SystemConfigs.Add(config);
        }

        config.Value = value;
        config.Description = description;
        config.IsSensitive = isSensitive;
        config.UpdatedAt = DateTimeOffset.UtcNow;
        config.UpdatedBy = "portal";
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

public record ConfigureAiRequest(string Endpoint, string Deployment, string? ApiKey);
