using System.Text.Json;
using AssessmentToolkit.Api.Services;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public class AssessmentFindingEvidenceTests
{
    [Fact]
    public void Create_PreservesDecisionFieldsBeyondLegacyTruncationLimit()
    {
        var source = JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["db_version"] = "Oracle Database 21c",
            ["schemas"] = new string('x', 4000),
            ["feature_usage"] = new[] { new { NAME = "Partitioning", CURRENTLY_USED = "TRUE" } },
            ["total_size_mb"] = 20480,
            ["daily_redo_generation"] = new[] { new { REDO_DAY = "2026-09-08", REDO_GB = 4.2 } }
        });

        var json = JsonSerializer.Serialize(AssessmentFindingEvidence.Create(source));

        Assert.Contains("Oracle Database 21c", json);
        Assert.Contains("Partitioning", json);
        Assert.Contains("total_size_mb", json);
        Assert.Contains("daily_redo_generation", json);
        Assert.DoesNotContain("schemas", json);
    }

    [Fact]
    public void Create_LimitsLargeCollections()
    {
        var source = JsonSerializer.Serialize(new
        {
            feature_usage = Enumerable.Range(1, 75).Select(index => new { name = $"Feature {index}" })
        });

        var json = JsonSerializer.Serialize(AssessmentFindingEvidence.Create(source));
        using var document = JsonDocument.Parse(json);

        Assert.Equal(50, document.RootElement.GetProperty("feature_usage").GetArrayLength());
    }
}