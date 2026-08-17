using Cassandra;
using System.Collections;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Read-only Cassandra discovery using system and system_schema metadata tables.
/// Does not read application rows.
/// </summary>
public sealed class CassandraPlugin : IAssessmentPlugin
{
    public string PluginId => "cassandra";
    public string PluginVersion => "1.0.0";
    public string TargetEngine => "Cassandra";

    public async Task<PluginResult> RunAsync(PluginContext context, CancellationToken ct)
    {
        ICluster? cluster = null;
        try
        {
            var builder = Cluster.Builder()
                .AddContactPoint(context.Host)
                .WithPort(context.Port)
                .WithQueryTimeout(60000);
            if (!string.IsNullOrWhiteSpace(context.Username))
                builder = builder.WithCredentials(context.Username, context.Password);

            cluster = builder.Build();
            var session = await cluster.ConnectAsync();
            ct.ThrowIfCancellationRequested();

            var findings = new Dictionary<string, object>();
            var sectionErrors = new Dictionary<string, string>();

            await CollectQueryAsync(findings, sectionErrors, "server_identity", session,
                "SELECT cluster_name, release_version, cql_version, data_center, rack, partitioner FROM system.local", ct);
            await CollectQueryAsync(findings, sectionErrors, "keyspaces", session,
                "SELECT keyspace_name, durable_writes, replication FROM system_schema.keyspaces", ct);
            await CollectQueryAsync(findings, sectionErrors, "tables", session,
                "SELECT keyspace_name, table_name, bloom_filter_fp_chance, caching, compaction, compression, default_time_to_live, gc_grace_seconds FROM system_schema.tables", ct);
            await CollectQueryAsync(findings, sectionErrors, "columns", session,
                "SELECT keyspace_name, table_name, column_name, kind, position, type FROM system_schema.columns", ct);
            await CollectQueryAsync(findings, sectionErrors, "indexes", session,
                "SELECT keyspace_name, table_name, index_name, kind, options FROM system_schema.indexes", ct);
            await CollectQueryAsync(findings, sectionErrors, "materialized_views", session,
                "SELECT keyspace_name, view_name, base_table_name FROM system_schema.views", ct);
            await CollectQueryAsync(findings, sectionErrors, "user_defined_types", session,
                "SELECT keyspace_name, type_name, field_names, field_types FROM system_schema.types", ct);
            await CollectQueryAsync(findings, sectionErrors, "functions", session,
                "SELECT keyspace_name, function_name, argument_types, return_type, language, called_on_null_input FROM system_schema.functions", ct);
            await CollectQueryAsync(findings, sectionErrors, "aggregates", session,
                "SELECT keyspace_name, aggregate_name, argument_types, return_type, state_type FROM system_schema.aggregates", ct);
            await CollectQueryAsync(findings, sectionErrors, "size_estimates", session,
                "SELECT keyspace_name, table_name, range_start, range_end, mean_partition_size, partitions_count FROM system.size_estimates", ct);
            await CollectPeersAsync(findings, sectionErrors, session, ct);

            if (sectionErrors.Count > 0)
                findings["section_errors"] = sectionErrors;

            var json = JsonSerializer.Serialize(findings);
            return new PluginResult(true, json, json);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return new PluginResult(false, "{}", "{}", ex.Message);
        }
        finally
        {
            cluster?.Dispose();
        }
    }

    private static async Task CollectPeersAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        ISession session,
        CancellationToken ct)
    {
        try
        {
            findings["peers"] = await QueryAsync(session,
                "SELECT peer, native_address, native_port, data_center, rack, release_version, tokens FROM system.peers_v2", ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            try
            {
                findings["peers"] = await QueryAsync(session,
                    "SELECT peer, rpc_address, data_center, rack, release_version, tokens FROM system.peers", ct);
            }
            catch (Exception fallbackEx) when (fallbackEx is not OperationCanceledException)
            {
                sectionErrors["peers"] = fallbackEx.GetType().Name;
            }
        }
    }

    private static async Task CollectQueryAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        string sectionName,
        ISession session,
        string cql,
        CancellationToken ct)
    {
        try
        {
            findings[sectionName] = await QueryAsync(session, cql, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sectionErrors[sectionName] = ex.GetType().Name;
        }
    }

    private static async Task<List<object>> QueryAsync(ISession session, string cql, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        var rowSet = await session.ExecuteAsync(new SimpleStatement(cql));
        ct.ThrowIfCancellationRequested();
        var rows = new List<object>();
        var columnNames = rowSet.Columns.Select(column => column.Name).ToArray();

        foreach (var row in rowSet)
        {
            var values = new Dictionary<string, object?>();
            foreach (var columnName in columnNames)
                values[columnName] = Normalize(row.GetValue<object>(columnName));
            rows.Add(values);
        }

        return rows;
    }

    private static object? Normalize(object? value)
    {
        if (value is null || value is string || value.GetType().IsPrimitive || value is decimal || value is DateTime || value is DateTimeOffset || value is Guid)
            return value;
        if (value is byte[] bytes)
            return Convert.ToHexString(bytes);
        if (value is IDictionary dictionary)
            return dictionary.Keys.Cast<object>().ToDictionary(key => key.ToString() ?? string.Empty, key => Normalize(dictionary[key]));
        if (value is IEnumerable sequence)
            return sequence.Cast<object?>().Select(Normalize).ToList();
        return value.ToString();
    }
}