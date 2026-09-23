using System.Text.Json;

namespace AssessmentToolkit.Api.Services;

public sealed record OracleCompatibilityEvidence(
    int InvalidObjectCount,
    int WrappedCodeCount,
    int UnsupportedObjectCount,
    int DatabaseLinkCount,
    int SynonymCount,
    int DatabaseProfileCount,
    int PartitionedTableCount,
    int SchedulerJobCount,
    int HccObjectCount,
    int DataTypeCount,
    int InstalledOptionCount,
    int UsedFeatureCount);

public sealed record OracleTopologyEvidence(
    string? Cdb,
    int PdbCount,
    int RacInstanceCount,
    bool? ExadataDetected);

public sealed record OracleSizingEvidence(
    decimal? TotalSizeMb,
    JsonElement? Capacity,
    JsonElement? DatabaseSizeSummary,
    JsonElement? TablespaceInventory,
    JsonElement? TemporaryTablespaceUsage,
    JsonElement? HostCapacity,
    JsonElement? MemoryConfiguration,
    JsonElement? RedoGeneration);

public sealed record OracleReportEvidence(
    string? CollectionContractVersion,
    string? DatabaseVersion,
    OracleTopologyEvidence Topology,
    OracleCompatibilityEvidence Compatibility,
    OracleSizingEvidence Sizing,
    IReadOnlyList<string> CollectionGaps,
    IReadOnlyList<string> TargetDecisionSignals);

public static class OracleReportEvidenceBuilder
{
    public static OracleReportEvidence Create(string? findingJson)
    {
        if (string.IsNullOrWhiteSpace(findingJson))
            return Empty(["Findings were not submitted."]);

        try
        {
            using var document = JsonDocument.Parse(findingJson);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
                return Empty(["Findings are not a JSON object."]);

            var root = document.RootElement;
            var topology = new OracleTopologyEvidence(
                GetString(root, "cdb"),
                GetCollectionCount(root, "pdbs"),
                GetCollectionCount(root, "rac_instances"),
                GetExadataState(root));
            var compatibility = new OracleCompatibilityEvidence(
                GetInteger(root, "invalid_object_count") ?? GetCollectionCount(root, "invalid_objects"),
                GetCollectionCount(root, "wrapped_code"),
                GetCollectionCount(root, "unsupported_objects"),
                GetCollectionCount(root, "database_links"),
                GetCollectionCount(root, "synonym_mappings"),
                GetCollectionCount(root, "database_profiles"),
                GetInteger(root, "partitioned_table_count") ?? GetCollectionCount(root, "partitioned_tables"),
                GetCollectionCount(root, "scheduler_jobs"),
                GetCollectionCount(root, "hcc_usage"),
                GetCollectionCount(root, "data_type_usage"),
                GetCollectionCount(root, "installed_options"),
                GetCollectionCount(root, "feature_usage"));
            var sizing = new OracleSizingEvidence(
                GetDecimal(root, "total_size_mb"),
                CloneProperty(root, "capacity"),
                CloneProperty(root, "database_size_summary"),
                CloneProperty(root, "tablespace_inventory"),
                CloneProperty(root, "temporary_tablespace_usage"),
                CloneProperty(root, "host_capacity"),
                CloneProperty(root, "memory_configuration"),
                CloneProperty(root, "hourly_redo_generation") ?? CloneProperty(root, "daily_redo_generation"));
            var collectionGaps = GetObjectPropertyNames(root, "section_errors");

            return new OracleReportEvidence(
                GetString(root, "collection_contract_version"),
                GetString(root, "db_version"),
                topology,
                compatibility,
                sizing,
                collectionGaps,
                BuildTargetDecisionSignals(topology, compatibility, sizing, collectionGaps));
        }
        catch (JsonException)
        {
            return Empty(["Findings contain invalid JSON."]);
        }
    }

    private static OracleReportEvidence Empty(IReadOnlyList<string> gaps)
    {
        var topology = new OracleTopologyEvidence(null, 0, 0, null);
        var compatibility = new OracleCompatibilityEvidence(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        var sizing = new OracleSizingEvidence(null, null, null, null, null, null, null, null);
        return new OracleReportEvidence(null, null, topology, compatibility, sizing, gaps, []);
    }

    private static IReadOnlyList<string> BuildTargetDecisionSignals(
        OracleTopologyEvidence topology,
        OracleCompatibilityEvidence compatibility,
        OracleSizingEvidence sizing,
        IReadOnlyList<string> collectionGaps)
    {
        var signals = new List<string>();
        if (string.Equals(topology.Cdb, "YES", StringComparison.OrdinalIgnoreCase))
            signals.Add($"Multitenant CDB detected with {topology.PdbCount} visible PDBs.");
        if (topology.RacInstanceCount > 1)
            signals.Add($"RAC topology detected with {topology.RacInstanceCount} visible instances.");
        if (topology.ExadataDetected == true)
            signals.Add("Exadata platform indicators were detected.");
        if (compatibility.HccObjectCount > 0)
            signals.Add($"{compatibility.HccObjectCount} HCC-compressed objects require target compatibility review.");
        if (compatibility.WrappedCodeCount > 0)
            signals.Add($"{compatibility.WrappedCodeCount} wrapped code objects require source recovery or manual treatment.");
        if (compatibility.UnsupportedObjectCount > 0)
            signals.Add($"{compatibility.UnsupportedObjectCount} Oracle-specific objects require conversion review.");
        if (compatibility.DatabaseLinkCount > 0)
            signals.Add($"{compatibility.DatabaseLinkCount} database links indicate external database dependencies.");
        if (compatibility.SynonymCount > 0)
            signals.Add($"{compatibility.SynonymCount} synonyms require target-object dependency validation.");
        if (compatibility.DatabaseProfileCount > 0)
            signals.Add($"{compatibility.DatabaseProfileCount} database profile rules require target security-policy mapping.");
        if (compatibility.PartitionedTableCount > 0)
            signals.Add($"{compatibility.PartitionedTableCount} partitioned tables require target partitioning validation.");
        if (sizing.TotalSizeMb.HasValue)
            signals.Add($"Allocated Oracle datafile size is {sizing.TotalSizeMb.Value:0.##} MB.");
        if (collectionGaps.Count > 0)
            signals.Add($"{collectionGaps.Count} assessment sections were unavailable and must be treated as evidence gaps.");
        return signals;
    }

    private static string? GetString(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var value))
            return null;
        return value.ValueKind == JsonValueKind.String ? value.GetString() : value.ToString();
    }

    private static int? GetInteger(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var value))
            return null;
        if (value.TryGetInt32(out var integer))
            return integer;
        return int.TryParse(value.ToString(), out integer) ? integer : null;
    }

    private static decimal? GetDecimal(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var value))
            return null;
        if (value.TryGetDecimal(out var number))
            return number;
        return decimal.TryParse(
            value.ToString(),
            System.Globalization.NumberStyles.Number,
            System.Globalization.CultureInfo.InvariantCulture,
            out number)
            ? number
            : null;
    }

    private static int GetCollectionCount(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var value))
            return 0;
        if (value.ValueKind == JsonValueKind.Array)
            return value.GetArrayLength();
        if (value.ValueKind == JsonValueKind.Object &&
            value.TryGetProperty("totalCount", out var totalCount) &&
            totalCount.TryGetInt32(out var count))
            return count;
        return 0;
    }

    private static JsonElement? CloneProperty(JsonElement root, string propertyName) =>
        root.TryGetProperty(propertyName, out var value) ? value.Clone() : null;

    private static IReadOnlyList<string> GetObjectPropertyNames(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var value) || value.ValueKind != JsonValueKind.Object)
            return [];
        return value.EnumerateObject().Select(property => property.Name).Order().ToArray();
    }

    private static bool? GetExadataState(JsonElement root)
    {
        if (!root.TryGetProperty("exadata", out var exadata))
            return null;
        if (exadata.ValueKind == JsonValueKind.Object &&
            exadata.TryGetProperty("detected", out var detected) &&
            detected.ValueKind is JsonValueKind.True or JsonValueKind.False)
            return detected.GetBoolean();
        if (exadata.ValueKind == JsonValueKind.Array && exadata.GetArrayLength() > 0)
        {
            var first = exadata[0];
            if (first.TryGetProperty("CELL_STATE_ROWS", out var rows) && rows.TryGetInt32(out var count))
                return count > 0;
        }
        return null;
    }
}
