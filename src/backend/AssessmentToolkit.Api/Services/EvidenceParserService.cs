using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using AssessmentToolkit.Core.Enums;

namespace AssessmentToolkit.Api.Services;

public record ParseResult(
    ParseStatus Status,
    ConfidenceLevel Confidence,
    string? SummaryJson,
    string? ErrorMessage);

public static class EvidenceParserService
{
    private const int MaxAwrInputCharacters = 2_000_000;

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
            ReportSourceType.Awr => ParseAwr(content),
            ReportSourceType.DmaJson => ParseDma(content),
            ReportSourceType.JsonGeneric => ParseGenericJson(content),
            ReportSourceType.CsvGeneric => ParseCsv(content),
            _ => new ParseResult(
                    ParseStatus.ReviewRequired,
                    ConfidenceLevel.Low,
                    null,
                    $"No structured parser available for '{sourceType}'. Use AI parsing or review manually.")
        };
    }

    /// <summary>
    /// AI-assisted parsing for formats without a structured parser (Statspack and other free-form evidence).
    /// Falls back to the structured parser if available, or ReviewRequired if AI is not configured.
    /// </summary>
    public static async Task<ParseResult> ParseWithAiAsync(
        ReportSourceType sourceType, string content,
        IAiAdapterService ai, CancellationToken ct = default)
    {
        // Use structured parsers first where available
        if (sourceType is ReportSourceType.Awr or ReportSourceType.DmaJson or
            ReportSourceType.JsonGeneric or ReportSourceType.CsvGeneric)
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
                "High" => ConfidenceLevel.High,
                "Medium" => ConfidenceLevel.Medium,
                _ => ConfidenceLevel.Low
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
                ["reportType"] = doc["reportType"]?.ToString() ?? "unknown",
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
                warningCount += db["breakingChanges"]?.AsArray().Count ?? 0;
                featureCount += db["featureParityIssues"]?.AsArray().Count ?? 0;
            }

            summary["databaseCount"] = databaseNames.Count;
            summary["databaseNames"] = databaseNames;
            summary["blockerCount"] = blockerCount;
            summary["warningCount"] = warningCount;
            summary["featureIssues"] = featureCount;

            var confidence = databaseNames.Count > 0 ? ConfidenceLevel.High : ConfidenceLevel.Medium;
            return new ParseResult(ParseStatus.Parsed, confidence, JsonSerializer.Serialize(summary), null);
        }
        catch (Exception ex)
        {
            return new ParseResult(ParseStatus.Failed, ConfidenceLevel.Unverified, null, $"DMA parse error: {ex.Message}");
        }
    }

    private static ParseResult ParseAwr(string content)
    {
        if (string.IsNullOrWhiteSpace(content))
            return new ParseResult(ParseStatus.Failed, ConfidenceLevel.Unverified, null, "AWR report is empty.");

        try
        {
            var text = NormalizeAwrText(content[..Math.Min(content.Length, MaxAwrInputCharacters)]);
            if (!text.Contains("WORKLOAD REPOSITORY", StringComparison.OrdinalIgnoreCase) &&
                !text.Contains("AWR REPORT", StringComparison.OrdinalIgnoreCase))
            {
                return new ParseResult(
                    ParseStatus.ReviewRequired,
                    ConfidenceLevel.Low,
                    null,
                    "The file does not contain a recognizable AWR report header.");
            }

            var database = Regex.Match(
                text,
                @"(?m)^(?<database>\S+)\s+\d+\s+(?<instance>\S+)\s+\d+\s+.+?\s+(?<version>\d+(?:\.\d+)+)\s+(?<rac>YES|NO)\s*$",
                RegexOptions.IgnoreCase);
            var host = Regex.Match(
                text,
                @"(?m)^(?<host>\S+)\s+(?<platform>.+?)\s+(?<cpus>\d+)\s+(?<cores>\d+)\s+(?<sockets>\d+)\s+(?<memory>\d+(?:\.\d+)?)\s*$");

            var beginSnapshot = MatchSnapshot(text, "Begin");
            var endSnapshot = MatchSnapshot(text, "End");
            var elapsedMinutes = MatchNumber(text, @"Elapsed:\s+(?<value>[\d,.]+)\s+\(mins\)");
            var dbTimeMinutes = MatchNumber(text, @"DB Time:\s+(?<value>[\d,.]+)\s+\(mins\)");

            var loadProfile = new Dictionary<string, object?>();
            AddMetric(loadProfile, "dbTimePerSecond", text, @"(?m)^DB Time\(s\):\s+(?<value>[\d,.]+)");
            AddMetric(loadProfile, "dbCpuPerSecond", text, @"(?m)^DB CPU\(s\):\s+(?<value>[\d,.]+)");
            AddMetric(loadProfile, "redoBytesPerSecond", text, @"(?m)^Redo size(?: \(bytes\))?:\s+(?<value>[\d,.]+)");
            AddMetric(loadProfile, "logicalReadsPerSecond", text, @"(?m)^Logical reads:\s+(?<value>[\d,.]+)");
            AddMetric(loadProfile, "physicalReadsPerSecond", text, @"(?m)^Physical reads:\s+(?<value>[\d,.]+)");
            AddMetric(loadProfile, "physicalWritesPerSecond", text, @"(?m)^Physical writes:\s+(?<value>[\d,.]+)");
            AddMetric(loadProfile, "executionsPerSecond", text, @"(?m)^Executes:\s+(?<value>[\d,.]+)");
            AddMetric(loadProfile, "transactionsPerSecond", text, @"(?m)^Transactions:\s+(?<value>[\d,.]+)");

            var topTimedEvents = ParseTopTimedEvents(text);
            var recognizedValues =
                (database.Success ? 1 : 0) +
                (host.Success ? 1 : 0) +
                (beginSnapshot is not null ? 1 : 0) +
                (elapsedMinutes.HasValue ? 1 : 0) +
                loadProfile.Count +
                topTimedEvents.Count;

            if (recognizedValues < 2)
            {
                return new ParseResult(
                    ParseStatus.ReviewRequired,
                    ConfidenceLevel.Low,
                    null,
                    "The AWR header was found, but too few structured values could be extracted.");
            }

            var summary = new Dictionary<string, object?>
            {
                ["sourceType"] = "AWR",
                ["databaseName"] = database.Success ? database.Groups["database"].Value : null,
                ["instanceName"] = database.Success ? database.Groups["instance"].Value : null,
                ["databaseVersion"] = database.Success ? database.Groups["version"].Value : null,
                ["rac"] = database.Success ? database.Groups["rac"].Value : null,
                ["host"] = new Dictionary<string, object?>
                {
                    ["name"] = host.Success ? host.Groups["host"].Value : null,
                    ["platform"] = host.Success ? host.Groups["platform"].Value.Trim() : null,
                    ["cpus"] = MatchInteger(host, "cpus"),
                    ["cores"] = MatchInteger(host, "cores"),
                    ["sockets"] = MatchInteger(host, "sockets"),
                    ["memoryGb"] = MatchNumber(host, "memory")
                },
                ["snapshot"] = new Dictionary<string, object?>
                {
                    ["begin"] = beginSnapshot,
                    ["end"] = endSnapshot,
                    ["elapsedMinutes"] = elapsedMinutes,
                    ["dbTimeMinutes"] = dbTimeMinutes
                },
                ["loadProfile"] = loadProfile,
                ["topTimedEvents"] = topTimedEvents,
                ["extraction"] = new
                {
                    deterministic = true,
                    inputTruncated = content.Length > MaxAwrInputCharacters,
                    recognizedValues
                }
            };

            var confidence = database.Success && beginSnapshot is not null && loadProfile.Count >= 2
                ? ConfidenceLevel.High
                : ConfidenceLevel.Medium;
            return new ParseResult(ParseStatus.Parsed, confidence, JsonSerializer.Serialize(summary), null);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return new ParseResult(
                ParseStatus.Failed,
                ConfidenceLevel.Unverified,
                null,
                $"AWR parse error: {ex.Message}");
        }
    }

    private static string NormalizeAwrText(string content)
    {
        var withoutScripts = Regex.Replace(
            content,
            @"<(script|style)\b[^>]*>.*?</\1>",
            " ",
            RegexOptions.IgnoreCase | RegexOptions.Singleline);
        var withLineBreaks = Regex.Replace(
            withoutScripts,
            @"</?(?:br|p|div|tr|h\d|pre|table|section)\b[^>]*>",
            "\n",
            RegexOptions.IgnoreCase);
        var withoutTags = Regex.Replace(withLineBreaks, @"<[^>]+>", " ");
        var decoded = WebUtility.HtmlDecode(withoutTags).Replace('\u00A0', ' ');
        return string.Join(
            '\n',
            decoded.Split('\n')
                .Select(line => Regex.Replace(line.Trim(), @"[ \t]+", " "))
                .Where(line => line.Length > 0));
    }

    private static Dictionary<string, object?>? MatchSnapshot(string text, string kind)
    {
        var match = Regex.Match(
            text,
            $@"(?m)^{kind} Snap:\s+(?<id>\d+)\s+(?<time>.+?)(?:\s{{2,}}|\s+\d+\s+[\d.]+\s*$)",
            RegexOptions.IgnoreCase);
        if (!match.Success)
            return null;

        return new Dictionary<string, object?>
        {
            ["snapshotId"] = long.TryParse(match.Groups["id"].Value, out var id) ? id : null,
            ["time"] = match.Groups["time"].Value.Trim()
        };
    }

    private static void AddMetric(
        IDictionary<string, object?> target,
        string name,
        string text,
        string pattern)
    {
        var value = MatchNumber(text, pattern);
        if (value.HasValue)
            target[name] = value.Value;
    }

    private static double? MatchNumber(string text, string pattern)
    {
        var match = Regex.Match(text, pattern, RegexOptions.IgnoreCase);
        return match.Success ? ParseNumber(match.Groups["value"].Value) : null;
    }

    private static double? MatchNumber(Match match, string groupName) =>
        match.Success ? ParseNumber(match.Groups[groupName].Value) : null;

    private static int? MatchInteger(Match match, string groupName) =>
        match.Success && int.TryParse(match.Groups[groupName].Value, out var value) ? value : null;

    private static double? ParseNumber(string value) =>
        double.TryParse(
            value.Replace(",", string.Empty, StringComparison.Ordinal),
            NumberStyles.Float,
            CultureInfo.InvariantCulture,
            out var number)
            ? number
            : null;

    private static List<object> ParseTopTimedEvents(string text)
    {
        var headingIndex = text.IndexOf("Timed Foreground Events", StringComparison.OrdinalIgnoreCase);
        if (headingIndex < 0)
            return [];

        var section = text[headingIndex..];
        var lines = section.Split('\n').Skip(1).Take(40);
        var events = new List<object>();
        foreach (var line in lines)
        {
            var match = Regex.Match(
                line,
                @"^(?<event>.+?)\s+(?<waits>\d+)\s+(?<seconds>[\d,.]+)\s+(?<average>[\d,.]+)\s+(?<percent>[\d,.]+)\s+(?<class>.+)$");
            if (!match.Success)
                continue;

            events.Add(new
            {
                @event = match.Groups["event"].Value.Trim(),
                waits = long.TryParse(match.Groups["waits"].Value, out var waits) ? waits : 0,
                timeSeconds = ParseNumber(match.Groups["seconds"].Value),
                averageWaitMs = ParseNumber(match.Groups["average"].Value),
                dbTimePercent = ParseNumber(match.Groups["percent"].Value),
                waitClass = match.Groups["class"].Value.Trim()
            });
            if (events.Count == 10)
                break;
        }

        return events;
    }

    private static ParseResult ParseGenericJson(string content)
    {
        try
        {
            var doc = JsonDocument.Parse(content);
            var root = doc.RootElement;
            var summary = new Dictionary<string, object>
            {
                ["rootType"] = root.ValueKind.ToString(),
                ["topLevelKeys"] = root.ValueKind == JsonValueKind.Object
                    ? root.EnumerateObject().Select(p => p.Name).Take(20).ToList()
                    : (object)new List<string>(),
                ["arrayLength"] = root.ValueKind == JsonValueKind.Array ? root.GetArrayLength() : (object)"n/a"
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
                ["rowCount"] = lines.Length - 1,
                ["columns"] = headers
            };
            return new ParseResult(ParseStatus.Parsed, ConfidenceLevel.Low, JsonSerializer.Serialize(summary), null);
        }
        catch (Exception ex)
        {
            return new ParseResult(ParseStatus.Failed, ConfidenceLevel.Unverified, null, $"CSV parse error: {ex.Message}");
        }
    }
}
