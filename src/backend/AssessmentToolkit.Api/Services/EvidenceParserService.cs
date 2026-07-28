using System.Text.Json;
using System.Text.Json.Nodes;
using AssessmentToolkit.Core.Enums;

namespace AssessmentToolkit.Api.Services;

public record ParseResult(
    ParseStatus Status,
    ConfidenceLevel Confidence,
    string? SummaryJson,
    string? ErrorMessage);

public static class EvidenceParserService
{
    public static ReportSourceType DetectSourceType(string fileName, string? declaredType)
    {
        if (!string.IsNullOrEmpty(declaredType) &&
            Enum.TryParse<ReportSourceType>(declaredType, true, out var declared))
            return declared;

        var lower = fileName.ToLowerInvariant();
        if (lower.Contains("dma") && lower.EndsWith(".json")) return ReportSourceType.DmaJson;
        if (lower.Contains("awr") && (lower.EndsWith(".html") || lower.EndsWith(".txt"))) return ReportSourceType.Awr;
        if (lower.Contains("statspack") && lower.EndsWith(".txt")) return ReportSourceType.Statspack;
        if ((lower.Contains("azure") || lower.Contains("migrate")) && lower.EndsWith(".json")) return ReportSourceType.AzureMigrate;
        if (lower.EndsWith(".csv")) return ReportSourceType.CsvGeneric;
        if (lower.EndsWith(".json")) return ReportSourceType.JsonGeneric;
        return ReportSourceType.Other;
    }

    public static ParseResult Parse(ReportSourceType sourceType, string content)
    {
        return sourceType switch
        {
            ReportSourceType.DmaJson     => ParseDma(content),
            ReportSourceType.JsonGeneric => ParseGenericJson(content),
            ReportSourceType.CsvGeneric  => ParseCsv(content),
            _ => new ParseResult(
                    ParseStatus.ReviewRequired,
                    ConfidenceLevel.Low,
                    null,
                    $"No structured parser available for '{sourceType}'. Use AI parsing or review manually.")
        };
    }

    /// <summary>
    /// AI-assisted parsing for formats without a structured parser (AWR, Statspack, etc.).
    /// Falls back to the structured parser if available, or ReviewRequired if AI is not configured.
    /// </summary>
    public static async Task<ParseResult> ParseWithAiAsync(
        ReportSourceType sourceType, string content,
        IAiAdapterService ai, CancellationToken ct = default)
    {
        // Use structured parsers first where available
        if (sourceType is ReportSourceType.DmaJson or ReportSourceType.JsonGeneric or ReportSourceType.CsvGeneric)
            return Parse(sourceType, content);

        if (!ai.IsAvailable)
        {
            return new ParseResult(
                ParseStatus.ReviewRequired,
                ConfidenceLevel.Low,
                null,
                $"No structured parser for '{sourceType}' and AI Foundry is not configured. Review manually.");
        }

        var systemPrompt = """
            You are a database migration assessment analyst.
            Analyse the provided database report or output and extract key findings as a JSON object.
            Return ONLY valid JSON — no markdown, no explanation.
            The JSON must include these fields if present in the source:
            {
              "source_type": string,
              "database_name": string or null,
              "database_version": string or null,
              "db_size_gb": number or null,
              "key_findings": [ { "category": string, "severity": "High|Medium|Low|Info", "description": string } ],
              "migration_blockers": [ string ],
              "recommendations": [ string ],
              "unsupported_features": [ string ],
              "performance_concerns": [ string ],
              "confidence": "High|Medium|Low"
            }
            """;

        var userPrompt = $"""
            Source type: {sourceType}
            Content (truncated to first 8000 chars):
            {content[..Math.Min(content.Length, 8000)]}
            """;

        try
        {
            var aiResponse = await ai.CompleteAsync(systemPrompt, userPrompt, ct);
            if (string.IsNullOrWhiteSpace(aiResponse))
                return new ParseResult(ParseStatus.ReviewRequired, ConfidenceLevel.Low, null, "AI returned empty response.");

            using var doc = JsonDocument.Parse(aiResponse);
            var confidenceStr = doc.RootElement.TryGetProperty("confidence", out var confProp)
                ? confProp.GetString() : "Medium";

            var confidence = confidenceStr switch
            {
                "High"   => ConfidenceLevel.High,
                "Medium" => ConfidenceLevel.Medium,
                _        => ConfidenceLevel.Low
            };

            return new ParseResult(ParseStatus.Parsed, confidence, aiResponse, null);
        }
        catch (JsonException)
        {
            return new ParseResult(ParseStatus.ReviewRequired, ConfidenceLevel.Low, null,
                "AI response was not valid JSON. Review manually.");
        }
        catch (Exception ex)
        {
            return new ParseResult(ParseStatus.Failed, ConfidenceLevel.Unverified, null,
                $"AI parsing failed: {ex.Message}");
        }
    }

    private static ParseResult ParseDma(string content)
    {
        try
        {
            var doc = JsonNode.Parse(content)!;
            var summary = new Dictionary<string, object>
            {
                ["reportType"]     = doc["reportType"]?.ToString() ?? "unknown",
                ["targetPlatform"] = doc["targetPlatform"]?.ToString() ?? "unknown",
                ["assessmentDate"] = doc["assessmentDate"]?.ToString() ?? "",
            };

            var databases = doc["databases"]?.AsArray() ?? doc["serverSummary"]?.AsArray() ?? [];
            var blockerCount = 0; var warningCount = 0; var featureCount = 0;
            var databaseNames = new List<string>();

            foreach (var db in databases)
            {
                if (db == null) continue;
                databaseNames.Add(db["databaseName"]?.ToString() ?? db["name"]?.ToString() ?? "");
                blockerCount += db["migrationBlockers"]?.AsArray().Count ?? 0;
                warningCount += db["breakingChanges"]?.AsArray().Count   ?? 0;
                featureCount += db["featureParityIssues"]?.AsArray().Count ?? 0;
            }

            summary["databaseCount"] = databaseNames.Count;
            summary["databaseNames"] = databaseNames;
            summary["blockerCount"]  = blockerCount;
            summary["warningCount"]  = warningCount;
            summary["featureIssues"] = featureCount;

            var confidence = databaseNames.Count > 0 ? ConfidenceLevel.High : ConfidenceLevel.Medium;
            return new ParseResult(ParseStatus.Parsed, confidence, JsonSerializer.Serialize(summary), null);
        }
        catch (Exception ex)
        {
            return new ParseResult(ParseStatus.Failed, ConfidenceLevel.Unverified, null, $"DMA parse error: {ex.Message}");
        }
    }

    private static ParseResult ParseGenericJson(string content)
    {
        try
        {
            var doc  = JsonDocument.Parse(content);
            var root = doc.RootElement;
            var summary = new Dictionary<string, object>
            {
                ["rootType"]     = root.ValueKind.ToString(),
                ["topLevelKeys"] = root.ValueKind == JsonValueKind.Object
                    ? root.EnumerateObject().Select(p => p.Name).Take(20).ToList()
                    : (object)new List<string>(),
                ["arrayLength"]  = root.ValueKind == JsonValueKind.Array ? root.GetArrayLength() : (object)"n/a"
            };
            return new ParseResult(ParseStatus.Parsed, ConfidenceLevel.Low, JsonSerializer.Serialize(summary), null);
        }
        catch (Exception ex)
        {
            return new ParseResult(ParseStatus.Failed, ConfidenceLevel.Unverified, null, $"JSON parse error: {ex.Message}");
        }
    }

    private static ParseResult ParseCsv(string content)
    {
        try
        {
            var lines = content.Split('\n', StringSplitOptions.RemoveEmptyEntries);
            if (lines.Length == 0)
                return new ParseResult(ParseStatus.Failed, ConfidenceLevel.Unverified, null, "Empty CSV file.");

            var headers = lines[0].Split(',').Select(h => h.Trim('"', ' ')).ToList();
            var summary = new Dictionary<string, object>
            {
                ["columnCount"] = headers.Count,
                ["rowCount"]    = lines.Length - 1,
                ["columns"]     = headers
            };
            return new ParseResult(ParseStatus.Parsed, ConfidenceLevel.Low, JsonSerializer.Serialize(summary), null);
        }
        catch (Exception ex)
        {
            return new ParseResult(ParseStatus.Failed, ConfidenceLevel.Unverified, null, $"CSV parse error: {ex.Message}");
        }
    }
}
