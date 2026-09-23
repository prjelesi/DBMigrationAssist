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
            ["schemas"] = new[] { new { USERNAME = "APP" } },
            ["invalid_objects"] = new[] { new { OWNER = "APP", OBJECT_TYPE = "VIEW", OBJECT_NAME = "BROKEN_VIEW" } },
            ["sga_info"] = new[] { new { NAME = "Maximum SGA Size", SIZE_MB = 8192 } },
            ["top_wait_events"] = new[] { new { EVENT = "db file sequential read", TIME_WAITED_SEC = 42.5 } },
            ["feature_usage"] = new[] { new { NAME = "Partitioning", CURRENTLY_USED = "TRUE" } },
            ["total_size_mb"] = 20480,
            ["daily_redo_generation"] = new[] { new { REDO_DAY = "2026-09-08", REDO_GB = 4.2 } }
        });

        var json = JsonSerializer.Serialize(AssessmentFindingEvidence.Create(source));

        Assert.Contains("Oracle Database 21c", json);
        Assert.Contains("Partitioning", json);
        Assert.Contains("total_size_mb", json);
        Assert.Contains("daily_redo_generation", json);
        Assert.Contains("APP", json);
        Assert.Contains("BROKEN_VIEW", json);
        Assert.Contains("Maximum SGA Size", json);
        Assert.Contains("db file sequential read", json);
    }

    [Fact]
    public void Create_LimitsLargeCollectionsWithoutHidingTruncation()
    {
        var source = JsonSerializer.Serialize(new
        {
            feature_usage = Enumerable.Range(1, 75).Select(index => new { name = $"Feature {index}" })
        });

        var json = JsonSerializer.Serialize(AssessmentFindingEvidence.Create(source));
        using var document = JsonDocument.Parse(json);
        var featureUsage = document.RootElement.GetProperty("feature_usage");

        Assert.Equal(75, featureUsage.GetProperty("totalCount").GetInt32());
        Assert.Equal(50, featureUsage.GetProperty("includedCount").GetInt32());
        Assert.True(featureUsage.GetProperty("truncated").GetBoolean());
        Assert.Equal(50, featureUsage.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public void Create_PreservesNewOracleAssessmentSections()
    {
        var source = JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["system_statistics"] = new[] { new { NAME = "CPU_COUNT", VALUE = "16" } },
            ["memory_configuration"] = new[] { new { NAME = "USE_LARGE_PAGES", VALUE = "ONLY" } },
            ["sql_plan_management"] = new { profileCount = 2, baselineCount = 3 },
            ["sql_tuning_patches"] = new[] { new { NAME = "PATCH_1", STATUS = "ENABLED" } },
            ["database_profiles"] = new[] { new { PROFILE = "APP_PROFILE", RESOURCE_NAME = "PASSWORD_LIFE_TIME" } },
            ["synonym_mappings"] = new[] { new { OWNER = "APP", SYNONYM_NAME = "ERP_CUSTOMERS", TABLE_OWNER = "ERP" } },
            ["resource_manager"] = new { activePlan = "APP_PLAN", consumerGroupCount = 4 },
            ["database_services"] = new[] { new { NAME = "orders.example" } },
            ["exadata"] = new { detected = false },
            ["hcc_usage"] = Array.Empty<object>(),
            ["recovery_configuration"] = new { FRA_SIZE_BYTES = 107374182400L },
            ["asm_disk_groups"] = new[] { new { NAME = "DATA", TOTAL_MB = 102400 } },
            ["tablespace_inventory"] = new[] { new { TABLESPACE_NAME = "USERS", CONTENTS = "PERMANENT" } },
            ["temporary_tablespace_usage"] = new[] { new { TABLESPACE_NAME = "TEMP", USED_MB = 512 } },
            ["database_size_summary"] = new[] { new { TOTAL_ALLOCATED_MB = 153600, TOTAL_SEGMENT_COUNT = 4200 } },
            ["database_directories"] = new[] { new { DIRECTORY_NAME = "EXPORT_DIR" } },
            ["restore_points"] = new[] { new { NAME = "BEFORE_RELEASE" } },
            ["refresh_groups"] = Array.Empty<object>(),
            ["audit_policies"] = new[] { new { POLICY_NAME = "APP_AUDIT" } },
            ["lockdown_profiles"] = Array.Empty<object>()
        });

        var json = JsonSerializer.Serialize(AssessmentFindingEvidence.Create(source));

        Assert.Contains("system_statistics", json);
        Assert.Contains("memory_configuration", json);
        Assert.Contains("sql_plan_management", json);
        Assert.Contains("sql_tuning_patches", json);
        Assert.Contains("database_profiles", json);
        Assert.Contains("synonym_mappings", json);
        Assert.Contains("resource_manager", json);
        Assert.Contains("database_services", json);
        Assert.Contains("exadata", json);
        Assert.Contains("hcc_usage", json);
        Assert.Contains("recovery_configuration", json);
        Assert.Contains("asm_disk_groups", json);
        Assert.Contains("tablespace_inventory", json);
        Assert.Contains("temporary_tablespace_usage", json);
        Assert.Contains("database_size_summary", json);
        Assert.Contains("database_directories", json);
        Assert.Contains("restore_points", json);
        Assert.Contains("refresh_groups", json);
        Assert.Contains("audit_policies", json);
        Assert.Contains("lockdown_profiles", json);
    }
}