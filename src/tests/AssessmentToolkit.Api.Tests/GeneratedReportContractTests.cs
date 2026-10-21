using System.Text.Json;
using System.Text.Json.Nodes;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Enums;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public class GeneratedReportContractTests
{
    private const string ValidReport = """
        {
          "executiveSummary": "Assessment summary",
          "scopeSummary": { "databaseCount": 1, "enginesFound": ["Oracle"], "criticalCount": 0 },
          "migrationReadiness": "NeedsWork",
          "migrationRequirements": [
            { "category": "Technical", "requirement": "Validate compatibility", "evidenceStatus": "Confirmed", "details": "Assessment completed" }
          ],
          "sourceEnvironment": {
            "summary": "One Oracle database",
            "environments": [
              { "name": "Production", "type": "Production", "location": "On-premises", "connectivity": "Private", "databaseCount": 1 }
            ],
            "databaseEstate": [
              { "name": "Orders", "engine": "Oracle", "version": "19c", "host": "db01", "criticality": "High", "environment": "Production" }
            ],
            "dependencies": [],
            "informationGaps": []
          },
          "possibleMigrations": [
            { "sourcePlatform": "Oracle", "targetAzureService": "Azure Database for PostgreSQL", "migrationType": "Replatform", "recommendation": "Preferred", "rationale": "Meets requirements", "considerations": [] }
          ],
          "migrationTooling": [
            { "phase": "Assess", "tools": ["DMA"], "purpose": "Assess compatibility", "prerequisites": [] }
          ],
          "azureSkuProposal": [
            { "environment": "Production", "targetService": "Azure Database for PostgreSQL", "skuTier": "TBD", "compute": "TBD", "storage": "TBD", "availability": "TBD", "networking": "Private", "rationale": "Requires sizing", "sizingBasis": "Insufficient evidence", "assumptions": [] }
          ],
          "keyRisks": [
            { "title": "Compatibility", "severity": "High", "description": "Requires remediation" }
          ],
          "recommendedWave": "Validate in non-production first",
          "nextSteps": ["Complete compatibility testing"],
          "estimatedEffort": "High"
        }
        """;

    [Fact]
    public void NormalizeAndValidate_ValidReport_ReturnsNormalizedObject()
    {
        var normalized = GeneratedReportContract.NormalizeAndValidate(ValidReport);

        using var document = JsonDocument.Parse(normalized);
        Assert.Equal(JsonValueKind.Object, document.RootElement.ValueKind);
        Assert.Equal("NeedsWork", document.RootElement.GetProperty("migrationReadiness").GetString());
    }

    [Fact]
    public void NormalizeAndValidate_MarkdownFencedReport_ReturnsNormalizedObject()
    {
        var normalized = GeneratedReportContract.NormalizeAndValidate($"```json\n{ValidReport}\n```");

        using var document = JsonDocument.Parse(normalized);
        Assert.Equal("Assessment summary", document.RootElement.GetProperty("executiveSummary").GetString());
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("[]")]
    [InlineData("null")]
    [InlineData("{\"executiveSummary\":")]
    public void NormalizeAndValidate_InvalidOrIncompleteJson_Rejects(string output)
    {
        AssertInvalid(output);
    }

    [Fact]
    public void NormalizeAndValidate_MissingRequiredArray_Rejects()
    {
        AssertInvalid(ValidReport.Replace(
            "\"nextSteps\": [\"Complete compatibility testing\"],",
            ""));
    }

    [Fact]
    public void NormalizeAndValidate_WrongCollectionType_Rejects()
    {
      var report = JsonNode.Parse(ValidReport)!.AsObject();
      report["keyRisks"] = new JsonObject();

      AssertInvalid(report.ToJsonString());
    }

    [Theory]
    [InlineData("\"migrationReadiness\": \"NeedsWork\"", "\"migrationReadiness\": \"Unknown\"")]
    [InlineData("\"estimatedEffort\": \"High\"", "\"estimatedEffort\": \"Extreme\"")]
    [InlineData("\"severity\": \"High\"", "\"severity\": \"Critical\"")]
    public void NormalizeAndValidate_InvalidEnumValue_Rejects(string validValue, string invalidValue)
    {
        AssertInvalid(ValidReport.Replace(validValue, invalidValue));
    }

    [Fact]
    public void NormalizeAndValidate_AllRequiredTargetsPresent_Succeeds()
    {
        var report = ReportWithTargets(BuildTargets());

        var normalized = GeneratedReportContract.NormalizeAndValidate(report, OracleTargets);

        using var document = JsonDocument.Parse(normalized);
        var targets = document.RootElement.GetProperty("targetAssessment");
        Assert.Equal(OracleTargets.Count, targets.GetArrayLength());
    }

    [Fact]
    public void NormalizeAndValidate_TargetAssessmentMissing_Rejects()
    {
        AssertInvalid(ValidReport, OracleTargets);
    }

    [Fact]
    public void NormalizeAndValidate_RequiredTargetMissing_Rejects()
    {
        var targets = BuildTargets();
        targets.RemoveAt(targets.Count - 1);

        AssertInvalid(ReportWithTargets(targets), OracleTargets);
    }

    [Fact]
    public void NormalizeAndValidate_DuplicateTarget_Rejects()
    {
        var targets = BuildTargets();
        targets[^1]!["target"] = MigrationTargetCatalog.OracleDatabaseAtAzure;

        AssertInvalid(ReportWithTargets(targets), OracleTargets);
    }

    [Fact]
    public void NormalizeAndValidate_UnknownTarget_Rejects()
    {
        var targets = BuildTargets();
        targets.Add(TargetNode("Google Cloud SQL", "Viable"));

        AssertInvalid(ReportWithTargets(targets), OracleTargets);
    }

    [Fact]
    public void NormalizeAndValidate_NoRecommendedTarget_Rejects()
    {
        var targets = BuildTargets();
        foreach (var target in targets)
            target!["verdict"] = "Viable";

        AssertInvalid(ReportWithTargets(targets), OracleTargets);
    }

    [Fact]
    public void NormalizeAndValidate_MultipleRecommendedTargets_Rejects()
    {
        var targets = BuildTargets();
        targets[0]!["verdict"] = "Recommended";
        targets[1]!["verdict"] = "Recommended";

        AssertInvalid(ReportWithTargets(targets), OracleTargets);
    }

    [Fact]
    public void NormalizeAndValidate_InvalidTargetVerdict_Rejects()
    {
        var targets = BuildTargets();
        targets[0]!["verdict"] = "Maybe";

        AssertInvalid(ReportWithTargets(targets), OracleTargets);
    }

    [Fact]
    public void NormalizeAndValidate_TargetMissingField_Rejects()
    {
        var targets = BuildTargets();
        targets[0]!.AsObject().Remove("evidenceGaps");

        AssertInvalid(ReportWithTargets(targets), OracleTargets);
    }

    [Fact]
    public void NormalizeAndValidate_NoRequiredTargets_IgnoresTargetAssessment()
    {
        var normalized = GeneratedReportContract.NormalizeAndValidate(ValidReport, []);

        using var document = JsonDocument.Parse(normalized);
        Assert.False(document.RootElement.TryGetProperty("targetAssessment", out _));
    }

    [Fact]
    public void NormalizeAndValidate_NoRequiredTargets_StillAcceptsIncompleteTargetAssessment()
    {
        var targets = BuildTargets();
        targets.RemoveAt(0);
        foreach (var target in targets)
            target!["verdict"] = "Viable";

        var normalized = GeneratedReportContract.NormalizeAndValidate(ReportWithTargets(targets), null);

        using var document = JsonDocument.Parse(normalized);
        Assert.Equal(targets.Count, document.RootElement.GetProperty("targetAssessment").GetArrayLength());
    }

    private static IReadOnlyList<string> OracleTargets => MigrationTargetCatalog.ForEngine(EngineType.Oracle);

    private static JsonArray BuildTargets()
    {
        var targets = new JsonArray();
        foreach (var target in OracleTargets)
        {
            var verdict = target == MigrationTargetCatalog.OracleDatabaseAtAzure ? "Recommended" : "Viable";
            targets.Add(TargetNode(target, verdict));
        }

        return targets;
    }

    private static JsonObject TargetNode(string target, string verdict) => new()
    {
        ["target"] = target,
        ["verdict"] = verdict,
        ["fitSummary"] = "Assessed against collected evidence.",
        ["blockers"] = new JsonArray(),
        ["remediation"] = new JsonArray(),
        ["evidenceGaps"] = new JsonArray(),
        ["confidence"] = "Medium"
    };

    private static string ReportWithTargets(JsonArray targets)
    {
        var report = JsonNode.Parse(ValidReport)!.AsObject();
        report["targetAssessment"] = targets;
        return report.ToJsonString();
    }

    private static void AssertInvalid(string output, IReadOnlyList<string>? requiredTargets = null)
    {
        var exception = Record.Exception(() => GeneratedReportContract.NormalizeAndValidate(output, requiredTargets));

        Assert.True(exception is JsonException or ReportContractException,
            $"Expected a JSON or report contract exception, but received {exception?.GetType().Name ?? "no exception"}.");
    }
}
