using System.Text.Json;
using System.Text.Json.Nodes;
using AssessmentToolkit.Api.Services;
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

    private static void AssertInvalid(string output)
    {
        var exception = Record.Exception(() => GeneratedReportContract.NormalizeAndValidate(output));

        Assert.True(exception is JsonException or ReportContractException,
            $"Expected a JSON or report contract exception, but received {exception?.GetType().Name ?? "no exception"}.");
    }
}
