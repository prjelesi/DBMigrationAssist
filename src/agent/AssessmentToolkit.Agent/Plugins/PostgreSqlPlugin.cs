using Npgsql;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Assessment plugin for PostgreSQL source databases.
/// Collects version, database list, table/index counts, size and replication state.
/// </summary>
public class PostgreSqlPlugin : IAssessmentPlugin
{
    public string PluginId => "postgresql";
    public string PluginVersion => "1.0.0";
    public string TargetEngine => "PostgreSQL";

    public async Task<PluginResult> RunAsync(PluginContext ctx, CancellationToken ct)
    {
        var connString = $"Host={ctx.Host};Port={ctx.Port};Database={ctx.Database};Username={ctx.Username};Password={ctx.Password};Timeout=30;CommandTimeout=60";

        try
        {
            await using var conn = new NpgsqlConnection(connString);
            await conn.OpenAsync(ct);

            var findings = new Dictionary<string, object>();

            // Server version
            findings["server_version"] = await ScalarAsync(conn, "SELECT version();", ct);

            // Database list
            findings["databases"] = await ListAsync(conn,
                "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;", ct);

            // Table count in current DB
            findings["table_count"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');", ct);

            // Total DB size
            findings["database_size_bytes"] = await ScalarAsync(conn,
                $"SELECT pg_database_size('{ctx.Database}');", ct);

            // Extension list
            findings["extensions"] = await ListAsync(conn,
                "SELECT extname, extversion FROM pg_extension ORDER BY extname;", ct);

            // Active connections
            findings["max_connections"] = await ScalarAsync(conn,
                "SELECT setting FROM pg_settings WHERE name = 'max_connections';", ct);

            // Check replication
            findings["replication_slots"] = await ListAsync(conn,
                "SELECT slot_name, active FROM pg_replication_slots;", ct);

            var findingJson = JsonSerializer.Serialize(findings);

            return new PluginResult(true, findingJson, findingJson);
        }
        catch (Exception ex)
        {
            return new PluginResult(false, "{}", "{}", ex.Message);
        }
    }

    private static async Task<object> ScalarAsync(NpgsqlConnection conn, string sql, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(sql, conn);
        var result = await cmd.ExecuteScalarAsync(ct);
        return result ?? DBNull.Value;
    }

    private static async Task<List<object?>> ListAsync(NpgsqlConnection conn, string sql, CancellationToken ct)
    {
        var rows = new List<object?>();
        await using var cmd = new NpgsqlCommand(sql, conn);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>();
            for (var i = 0; i < reader.FieldCount; i++)
                row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            rows.Add(row);
        }
        return rows;
    }
}
