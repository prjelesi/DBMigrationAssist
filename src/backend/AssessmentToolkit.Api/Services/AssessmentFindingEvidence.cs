using System.Text.Json;

namespace AssessmentToolkit.Api.Services;

public static class AssessmentFindingEvidence
{
    private const int MaxArrayItems = 50;

    private static readonly HashSet<string> IncludedFields = new(StringComparer.OrdinalIgnoreCase)
    {
        "db_version", "db_name", "db_created", "db_unique_name", "platform_name",
        "oracle_components", "installed_options", "sql_patches",
        "character_set", "nchar_character_set", "cdb", "con_name", "pdbs", "rac_instances",
        "key_parameters", "optimizer_configuration", "system_statistics", "host_capacity",
        "memory_configuration", "sga_info", "top_wait_events", "log_mode", "redo_logs", "active_sessions",
        "rac_configuration", "database_services", "resource_manager", "sql_plan_management",
        "sql_tuning_patches", "database_profiles", "synonym_mappings",
        "database_directories", "restore_points", "refresh_groups",
        "audit_policies", "lockdown_profiles",
        "exadata", "hcc_usage", "recovery_configuration", "asm_disk_groups",
        "schemas", "object_counts", "per_schema_summary", "invalid_object_count", "invalid_objects",
        "wrapped_code", "unsupported_objects",
        "feature_usage", "partitioned_table_count", "partitioned_tables", "scheduler_jobs",
        "database_links", "data_type_usage", "lob_size", "largest_segments",
        "total_size_mb", "capacity", "database_size_summary", "tablespace_usage",
        "tablespace_inventory", "temporary_tablespace_usage", "daily_redo_generation",
        "hourly_redo_generation", "section_errors", "collection_contract_version",
        "awr_assessment_source"
    };

    public static object Create(string? findingJson)
    {
        if (string.IsNullOrWhiteSpace(findingJson))
            return new { status = "No findings submitted" };

        try
        {
            using var document = JsonDocument.Parse(findingJson);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
                return new { status = "Findings are not a JSON object" };

            var findings = new Dictionary<string, object?>();
            foreach (var property in document.RootElement.EnumerateObject())
            {
                if (!IncludedFields.Contains(property.Name)) continue;
                findings[property.Name] = ToBoundedValue(property.Value);
            }

            return findings;
        }
        catch (JsonException)
        {
            return new { status = "Findings contain invalid JSON" };
        }
    }

    private static object? ToBoundedValue(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Array => ToBoundedArray(value),
        JsonValueKind.Object => value.EnumerateObject().ToDictionary(
            property => property.Name,
            property => ToBoundedValue(property.Value)),
        JsonValueKind.String => value.GetString(),
        JsonValueKind.Number when value.TryGetInt64(out var integer) => integer,
        JsonValueKind.Number when value.TryGetDecimal(out var number) => number,
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        _ => null
    };

    private static object ToBoundedArray(JsonElement value)
    {
        var totalCount = value.GetArrayLength();
        var items = value.EnumerateArray().Take(MaxArrayItems).Select(ToBoundedValue).ToArray();
        if (totalCount <= MaxArrayItems)
            return items;

        return new
        {
            totalCount,
            includedCount = items.Length,
            truncated = true,
            items
        };
    }
}