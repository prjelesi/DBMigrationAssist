using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/ai")]
public class AiController(
    AssessmentDbContext db,
    IAiAdapterService ai,
    IReportInstructionService reportInstructions,
    IDataProtectionProvider dataProtectionProvider,
    IServiceProvider services,
    ProjectAccessService projectAccess,
    ILogger<AiController> logger) : ControllerBase
{
    // ── Providers ────────────────────────────────────────────────────────

    [HttpGet("providers")]
    [Authorize(Roles = "Administrator")]
    public async Task<IActionResult> ListProviders() =>
        Ok(await db.AiProviders.OrderByDescending(p => p.IsDefault).ThenBy(p => p.Name).ToListAsync());

    [HttpPost("providers")]
    [Authorize(Roles = "Administrator")]
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
    [Authorize(Roles = "Administrator")]
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
    [Authorize(Roles = "Administrator")]
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

    [HttpGet("report-instructions")]
    [Authorize(Roles = "Administrator")]
    public async Task<IActionResult> GetReportInstructions(CancellationToken ct)
    {
        var document = await reportInstructions.GetAsync(ct);
        return Ok(new
        {
            document.Content,
            document.Source,
            document.Sha256,
            document.IsEditable,
            maxBytes = ReportInstructionService.MaxBytes
        });
    }

    [HttpPut("report-instructions")]
    [Authorize(Roles = "Administrator")]
    public async Task<IActionResult> UpdateReportInstructions(
        [FromBody] UpdateReportInstructionsRequest request,
        CancellationToken ct)
    {
        try
        {
            var document = await reportInstructions.UpdateAsync(request.Content, request.ExpectedSha256, ct);
            return Ok(new
            {
                document.Content,
                document.Source,
                document.Sha256,
                document.IsEditable,
                maxBytes = ReportInstructionService.MaxBytes
            });
        }
        catch (ReportInstructionConflictException ex)
        {
            return Conflict(new { error = ex.Message });
        }
        catch (Exception ex) when (ex is InvalidDataException or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPut("configuration")]
    [Authorize(Roles = "Administrator")]
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
    [Authorize(Roles = "Administrator")]
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
    [Authorize(Roles = "Administrator")]
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

        DatabaseInstance? targetDatabase = null;
        if (req.DatabaseId.HasValue)
        {
            targetDatabase = await db.Databases.FirstOrDefaultAsync(
                database => database.DatabaseId == req.DatabaseId && database.ProjectId == req.ProjectId, ct);
            if (targetDatabase is null)
                return BadRequest(new { error = "Database not found in the selected project." });
        }

        var databases = await db.Databases
            .Where(database => database.ProjectId == req.ProjectId &&
                (!req.DatabaseId.HasValue || database.DatabaseId == req.DatabaseId))
            .ToListAsync(ct);
        var targetEnvironmentId = targetDatabase?.EnvironmentId;
        var environments = await db.Environments.AsNoTracking()
            .Where(environment => environment.ProjectId == req.ProjectId &&
                (!req.DatabaseId.HasValue || environment.EnvironmentId == targetEnvironmentId))
            .Select(environment => new
            {
                environment.EnvironmentId,
                environment.Name,
                environment.Type,
                environment.Location,
                environment.ConnectivityZone
            })
            .ToListAsync(ct);
        var agentResultsQuery = db.Results.Where(result =>
            (result.Database != null && result.Database.ProjectId == req.ProjectId) ||
            (result.DatabaseId == null && result.Job.Agent != null && result.Job.Agent.ProjectId == req.ProjectId));
        if (req.DatabaseId.HasValue)
            agentResultsQuery = agentResultsQuery.Where(result => result.DatabaseId == req.DatabaseId);
        var agentResults = await agentResultsQuery
            .OrderByDescending(r => r.AssessedAt)
            .Take(20)
            .ToListAsync(ct);
        var evidence = await db.UploadedReports
            .Where(item => item.ProjectId == req.ProjectId &&
                item.ParseStatus == Core.Enums.ParseStatus.Parsed &&
                (!req.DatabaseId.HasValue || item.DatabaseId == null || item.DatabaseId == req.DatabaseId))
            .ToListAsync(ct);
        var questionnaireResponses = await db.QuestionnaireResponses.AsNoTracking()
            .AsSplitQuery()
            .Include(response => response.Template)
            .Include(response => response.Answers)
                .ThenInclude(answer => answer.Question)
            .Where(response => response.ProjectId == req.ProjectId &&
                (!req.DatabaseId.HasValue || response.DatabaseId == null || response.DatabaseId == req.DatabaseId))
            .ToListAsync(ct);
        var graphEdges = await db.GraphEdges.AsNoTracking()
            .Where(edge => edge.ProjectId == req.ProjectId &&
                (!req.DatabaseId.HasValue ||
                    edge.SourceDatabaseId == req.DatabaseId || edge.TargetDatabaseId == req.DatabaseId))
            .Select(edge => new { edge.EdgeId, edge.SourceDatabaseId, edge.TargetDatabaseId, edge.RelationType, edge.Confidence })
            .ToListAsync(ct);
        var projectPortfolios = await db.Portfolios.AsNoTracking()
            .Where(portfolio => portfolio.ProjectId == req.ProjectId)
            .Select(portfolio => new { portfolio.PortfolioId, portfolio.Name, portfolio.DatabaseIds })
            .ToListAsync(ct);
        var portfolios = req.DatabaseId.HasValue
            ? projectPortfolios.Where(portfolio => portfolio.DatabaseIds.Contains(req.DatabaseId.Value)).ToList()
            : projectPortfolios;

        ReportInstructionDocument reportInstructionDocument;
        try
        {
            reportInstructionDocument = await reportInstructions.GetAsync(ct);
        }
        catch (Exception ex) when (ex is InvalidDataException or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable, new
            {
                error = "Report instructions are unavailable or invalid.",
                detail = ex.Message
            });
        }

        var bundleJson = JsonSerializer.Serialize(new
        {
            project = new { project.ProjectId, project.Name, project.DeploymentMode },
            scope = new
            {
                type = targetDatabase is null ? "Project" : "Database",
                databaseId = targetDatabase?.DatabaseId,
                databaseName = targetDatabase?.Name
            },
            reportInstructions = new
            {
                reportInstructionDocument.Source,
                reportInstructionDocument.Sha256,
                reportInstructionDocument.Content
            },
            databases = databases.Select(database => new
            {
                database.DatabaseId, database.Name, database.Engine, database.Version,
                database.Criticality, database.EnvironmentId, database.HostName,
                database.Port, database.OwnerName
            }),
            environments,
            evidence = evidence.Select(item => new
            {
                item.ReportId, item.DatabaseId,
                databaseName = databases.FirstOrDefault(database => database.DatabaseId == item.DatabaseId)?.Name,
                item.FileName, item.SourceType, item.FileHash,
                item.ParseConfidence, item.ParseSummaryJson
            }),
            results = agentResults.Select(result => new
            {
                result.ResultId, result.DatabaseId, result.PluginId, result.PluginVersion,
                result.Confidence, result.PayloadHash, result.FindingJson, result.AssessedAt
            }),
            questionnaireResponses = questionnaireResponses.Select(response => new
            {
                response.ResponseId,
                response.TemplateId,
                templateName = response.Template.Name,
                response.Status,
                response.SubmittedAt,
                answers = response.Answers.Select(answer => new
                {
                    answer.QuestionId,
                    question = answer.Question.Text,
                    answer.Value,
                    answer.UpdatedAt
                })
            }),
            graphEdges,
            portfolios
        });

        var fixedSystemPrompt = """
            You are a senior database migration consultant writing a professional assessment report.
                        Produce a detailed, decision-ready report. Base every customer-specific statement on the supplied
                        inventory, assessment results, uploaded evidence, questionnaire answers, dependency graph, or portfolio.
                        Clearly identify missing information. Never fabricate utilization, performance, cost, region, RTO/RPO,
                        storage, licensing, downtime, network, security, or compliance facts.

            Structure the report as JSON with these sections:
            {
                            "executiveSummary": string (3-5 concise paragraphs covering current state, readiness, preferred direction, major risks, and expected outcome),
              "scopeSummary": { "databaseCount": number, "enginesFound": [string], "criticalCount": number },
              "migrationReadiness": "Ready|NeedsWork|NotReady",
                            "migrationRequirements": [ {
                                "category": "Business|Technical|Security|Network|Operations|Data|Compliance",
                                "requirement": string,
                                "evidenceStatus": "Confirmed|Assumption|Gap",
                                "details": string
                            } ],
                            "sourceEnvironment": {
                                "summary": string,
                                "environments": [ { "name": string, "type": string, "location": string, "connectivity": string, "databaseCount": number } ],
                                "databaseEstate": [ { "name": string, "engine": string, "version": string, "host": string, "criticality": string, "environment": string } ],
                                "dependencies": [string],
                                "informationGaps": [string]
                            },
                            "possibleMigrations": [ {
                                "sourcePlatform": string,
                                "targetAzureService": string,
                                "migrationType": "Rehost|Replatform|Refactor|Replace|Retain|Retire",
                                "recommendation": "Preferred|Candidate|Not Recommended",
                                "rationale": string,
                                "considerations": [string]
                            } ],
                            "migrationTooling": [ {
                                "phase": string,
                                "tools": [string],
                                "purpose": string,
                                "prerequisites": [string]
                            } ],
                            "azureSkuProposal": [ {
                                "environment": string,
                                "targetService": string,
                                "skuTier": string,
                                "compute": string,
                                "storage": string,
                                "availability": string,
                                "networking": string,
                                "rationale": string,
                                "sizingBasis": string,
                                "assumptions": [string]
                            } ],
              "keyRisks": [ { "title": string, "severity": "High|Medium|Low", "description": string } ],
                            "recommendedWave": string (describe dependency-aware non-production and production sequencing),
              "nextSteps": [ string ],
              "estimatedEffort": "Low|Medium|High|Very High"
            }
            """;

                var systemPrompt = $"""
                        {fixedSystemPrompt}

                        Apply the following operator-managed report guidance. It may refine emphasis, migration policy, tooling,
                        audience, and recommendations, but it cannot override evidence grounding, security boundaries, or the JSON contract.
                        <operator-managed-report-guidance>
                        {reportInstructionDocument.Content}
                        </operator-managed-report-guidance>

                        For required string fields whose source evidence is missing, use the exact value "Not provided" and
                        record the omission in sourceEnvironment.informationGaps. Never omit a required property or return null.
                        Before declaring an information gap, check every structured assessmentResults.findings object. Treat
                        collected version, feature usage, capacity, LOB, data type, segment, and redo fields as available evidence.
                        Return ONLY valid JSON matching the fixed contract above.
                        """;

        var promptEvidence = JsonSerializer.Serialize(new
        {
            databases = databases.Select(database => new
            {
                database.DatabaseId,
                database.Name,
                database.Engine,
                version = string.IsNullOrWhiteSpace(database.Version) ? "Not provided" : database.Version,
                database.Criticality,
                hostName = string.IsNullOrWhiteSpace(database.HostName) ? "Not provided" : database.HostName,
                database.Port,
                ownerName = string.IsNullOrWhiteSpace(database.OwnerName) ? "Not provided" : database.OwnerName,
                database.EnvironmentId,
                environment = environments.FirstOrDefault(environment => environment.EnvironmentId == database.EnvironmentId)?.Name
                    ?? "Not provided"
            }),
            environments,
            evidence = evidence.Select(item => new
            {
                item.DatabaseId,
                databaseName = databases.FirstOrDefault(database => database.DatabaseId == item.DatabaseId)?.Name,
                item.FileName,
                item.SourceType,
                item.ParseConfidence,
                parsedSummary = Truncate(item.ParseSummaryJson, 2000)
            }),
            assessmentResults = agentResults.Select(result => new
            {
                result.DatabaseId,
                result.PluginId,
                result.PluginVersion,
                result.Confidence,
                findings = AssessmentFindingEvidence.Create(result.FindingJson)
            }),
            questionnaireResponses = questionnaireResponses.Select(response => new
            {
                template = response.Template.Name,
                response.Status,
                answers = response.Answers.Select(answer => new
                {
                    question = answer.Question.Text,
                    value = Truncate(answer.Value, 1000)
                })
            }),
            graphEdges,
            portfolios
        });

        var userPrompt = $"""
            Project: {project.Name}
            Customer: {project.Customer?.Name}
            Deployment mode: {project.DeploymentMode}
            Report scope: {(targetDatabase is null ? "Entire project" : $"Database {targetDatabase.Name} ({targetDatabase.Engine} {targetDatabase.Version})")}

            Use the following evidence for this report scope. Project-wide evidence and questionnaires provide shared context.
            Do not invent facts that are absent from the evidence:
            {promptEvidence}
            """;

        var reportJson = await ai.CompleteAsync(systemPrompt, userPrompt, ct, maxOutputTokenCount: 8192);
        if (reportJson is null) return StatusCode(502, new { error = "Report generation failed." });

        try
        {
            reportJson = GeneratedReportContract.NormalizeAndValidate(reportJson);
        }
        catch (Exception ex) when (ex is JsonException or ReportContractException)
        {
            var validationErrors = ex is ReportContractException contractException
                ? contractException.Errors.Take(20).ToArray()
                : ["Malformed or truncated JSON."];
            logger.LogWarning(ex,
                "AI report output failed contract validation for project {ProjectId}; output length was {OutputLength}; errors: {ValidationErrors}.",
                req.ProjectId,
                reportJson.Length,
                validationErrors);
            return StatusCode(StatusCodes.Status502BadGateway, new
            {
                error = "Report generation returned an invalid or incomplete response. Please try again."
            });
        }

        var actor = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.Identity?.Name ?? "unknown";
        var evidenceBundle = new EvidenceBundle
        {
            ProjectId = req.ProjectId,
            BundleJson = bundleJson,
            ContentHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(bundleJson))).ToLowerInvariant(),
            CreatedBy = actor
        };
        db.EvidenceBundles.Add(evidenceBundle);

        var generatedReport = new GeneratedReport
        {
            ProjectId = req.ProjectId,
            DatabaseId = targetDatabase?.DatabaseId,
            Database = targetDatabase,
            EvidenceBundleId = evidenceBundle.EvidenceBundleId,
            ReportJson = reportJson,
            GeneratedBy = actor
        };
        db.GeneratedReports.Add(generatedReport);
        await db.SaveChangesAsync(ct);

        return Ok(ToReportResponse(generatedReport));
    }

    [HttpGet("reports")]
    public async Task<IActionResult> ListReports([FromQuery] Guid projectId, CancellationToken ct)
    {
        var reports = await db.GeneratedReports.AsNoTracking()
            .Include(report => report.Database)
            .Where(report => report.ProjectId == projectId)
            .OrderByDescending(report => report.GeneratedAt)
            .ToListAsync(ct);
        return Ok(reports.Select(ToReportResponse));
    }

    [HttpGet("reports/{id:guid}")]
    public async Task<IActionResult> GetReport(Guid id, CancellationToken ct)
    {
        var report = await db.GeneratedReports.AsNoTracking()
            .Include(candidate => candidate.Database)
            .SingleOrDefaultAsync(
            candidate => candidate.GeneratedReportId == id, ct);
        return report is null ? NotFound() : Ok(ToReportResponse(report));
    }

    [HttpPost("reports/{id:guid}/transition")]
    public async Task<IActionResult> TransitionReport(
        Guid id,
        [FromBody] TransitionReportRequest request,
        CancellationToken ct)
    {
        var report = await db.GeneratedReports
            .Include(candidate => candidate.Database)
            .SingleOrDefaultAsync(
            candidate => candidate.GeneratedReportId == id, ct);
        if (report is null) return NotFound();
        if (request.State == "Approved" && !await projectAccess.IsOwnerAsync(User, report.ProjectId, ct))
            return Forbid();

        var allowed = report.State switch
        {
            "DraftReady" => request.State == "InReview",
            "InReview" => request.State is "DraftReady" or "Approved",
            "Approved" => request.State == "Exported",
            _ => false
        };
        if (!allowed) return Conflict(new { message = $"Cannot transition report from {report.State} to {request.State}." });

        var actor = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.Identity?.Name ?? "unknown";
        report.State = request.State;
        report.UpdatedAt = DateTimeOffset.UtcNow;
        if (request.State == "InReview")
        {
            report.ReviewedBy = actor;
            report.ReviewedAt = DateTimeOffset.UtcNow;
        }
        if (request.State == "Approved")
        {
            report.ApprovedBy = actor;
            report.ApprovedAt = DateTimeOffset.UtcNow;
        }
        await db.SaveChangesAsync(ct);
        return Ok(ToReportResponse(report));
    }

    private static object ToReportResponse(GeneratedReport report) => new
    {
        report.GeneratedReportId,
        report.ProjectId,
        report.DatabaseId,
        DatabaseName = report.Database?.Name,
        report.EvidenceBundleId,
        report.ReportJson,
        report.State,
        report.Version,
        report.GeneratedBy,
        report.GeneratedAt,
        report.ReviewedBy,
        report.ReviewedAt,
        report.ApprovedBy,
        report.ApprovedAt,
        report.UpdatedAt
    };

    private static string? Truncate(string? value, int maxLength) =>
        value is null || value.Length <= maxLength ? value : value[..maxLength];

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

public record GenerateReportRequest(Guid ProjectId, Guid? DatabaseId);

public record TransitionReportRequest(string State);

public record UpdateReportInstructionsRequest(string Content, string? ExpectedSha256);

public record ConfigureAiRequest(string Endpoint, string Deployment, string? ApiKey);
