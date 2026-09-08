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
        "key_parameters", "log_mode", "redo_logs", "awr_available", "active_sessions",
        "object_counts", "invalid_object_count", "wrapped_code", "unsupported_objects",
        "feature_usage", "partitioned_table_count", "partitioned_tables", "scheduler_jobs",
        "database_links", "data_type_usage", "lob_size", "largest_segments",
        "total_size_mb", "capacity", "tablespace_usage", "daily_redo_generation", "section_errors"
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
        JsonValueKind.Array => value.EnumerateArray().Take(MaxArrayItems).Select(ToBoundedValue).ToArray(),
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
}