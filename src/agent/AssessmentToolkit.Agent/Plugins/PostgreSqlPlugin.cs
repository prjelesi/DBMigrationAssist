using Npgsql;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Assessment plugin for PostgreSQL source databases.
/// Collects server metadata, table/index/function inventory, data-type usage,
/// replication configuration and connection settings — everything needed to
/// assess migration readiness to Azure Database for PostgreSQL.
/// Requires a read-only login with access to pg_catalog and information_schema.
/// </summary>
public sealed class PostgreSqlPlugin : IAssessmentPlugin
{
    public string PluginId      => "postgresql";
    public string PluginVersion => "1.1.0";
    public string TargetEngine  => "PostgreSQL";

    public async Task<PluginResult> RunAsync(PluginContext ctx, CancellationToken ct)
    {
        var connString =
            $"Host={ctx.Host};Port={ctx.Port};Database={ctx.Database};" +
            $"Username={ctx.Username};Password={ctx.Password};" +
            "Timeout=30;CommandTimeout=60;" +
            "SSL Mode=Prefer;Trust Server Certificate=true;";

        try
        {
            await using var conn = new NpgsqlConnection(connString);
            await conn.OpenAsync(ct);

            var f = new Dictionary<string, object>();

            // ── Server identity ───────────────────────────────────────────────────────────────
            f["server_version"]      = await ScalarAsync(conn, "SELECT version()", ct);
            f["version_number"]      = await ScalarAsync(conn, "SELECT current_setting('server_version_num')::int", ct);
            f["database_encoding"]   = await ScalarAsync(conn,
                "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = current_database()", ct);
            f["server_collation"]    = await ScalarAsync(conn,
                "SELECT datcollate FROM pg_database WHERE datname = current_database()", ct);

            // ── Size ───────────────────────────────────────────────────────────────────
            f["database_size_bytes"] = await ScalarAsync(conn, "SELECT pg_database_size(current_database())", ct);
            f["database_size_pretty"]= await ScalarAsync(conn, "SELECT pg_size_pretty(pg_database_size(current_database()))", ct);

            // ── Object counts ───────────────────────────────────────────────────────────
            f["table_count"]        = await ScalarAsync(conn, "SELECT COUNT(*) FROM pg_stat_user_tables", ct);
            f["view_count"]         = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM information_schema.views
                WHERE table_schema NOT IN ('pg_catalog','information_schema')", ct);
            f["function_count"]     = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM pg_proc p
                JOIN pg_namespace n ON p.pronamespace = n.oid
                WHERE n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')", ct);
            f["index_count"]        = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM pg_indexes
                WHERE schemaname NOT IN ('pg_catalog','information_schema')", ct);
            f["foreign_key_count"]  = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM information_schema.table_constraints
                WHERE constraint_type = 'FOREIGN KEY'
                  AND table_schema NOT IN ('pg_catalog','information_schema')", ct);
            f["sequence_count"]     = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM information_schema.sequences
                WHERE sequence_schema NOT IN ('pg_catalog','information_schema')", ct);
            f["trigger_count"]      = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM information_schema.triggers
                WHERE trigger_schema NOT IN ('pg_catalog','information_schema')", ct);

            // ── Table inventory (top 50 by size) ──────────────────────────────────
            f["table_inventory"] = await ListAsync(conn, @"
                SELECT schemaname                                        AS schema_name,
                       relname                                           AS table_name,
                       n_live_tup                                        AS live_rows,
                       n_dead_tup                                        AS dead_rows,
                      pg_size_pretty(pg_total_relation_size(relid))     AS total_size,
                      pg_total_relation_size(relid)                     AS total_bytes
                FROM pg_stat_user_tables
                ORDER BY total_bytes DESC
                LIMIT 50", ct);

            // ── Index usage (top 50) ───────────────────────────────────────────────
            f["index_usage"] = await ListAsync(conn, @"
                SELECT schemaname                                       AS schema_name,
                       relname                                          AS table_name,
                       indexrelname                                     AS index_name,
                       idx_scan                                         AS scans,
                       idx_tup_read                                     AS tuples_read,
                       pg_size_pretty(pg_relation_size(indexrelid))     AS index_size
                FROM pg_stat_user_indexes
                ORDER BY idx_scan DESC
                LIMIT 50", ct);

            // ── Data-type usage (migration compatibility signal) ──────────────────
            f["data_type_usage"] = await ListAsync(conn, @"
                SELECT data_type, COUNT(*) AS column_count
                FROM information_schema.columns
                WHERE table_schema NOT IN ('pg_catalog','information_schema')
                GROUP BY data_type
                ORDER BY column_count DESC", ct);

            // ── Extensions ─────────────────────────────────────────────────────────────
            f["extensions"] = await ListAsync(conn,
                "SELECT extname, extversion FROM pg_extension ORDER BY extname", ct);

            // ── Connection settings ───────────────────────────────────────────────────
            f["max_connections"]    = await ScalarAsync(conn, "SELECT setting::int FROM pg_settings WHERE name='max_connections'", ct);
            f["active_connections"] = await ScalarAsync(conn, "SELECT COUNT(*) FROM pg_stat_activity WHERE state='active'", ct);

            // ── WAL / replication ──────────────────────────────────────────────────────
            f["wal_level"]          = await ScalarAsync(conn, "SELECT setting FROM pg_settings WHERE name='wal_level'", ct);
            f["replication_slots"]  = await ListAsync(conn,
                "SELECT slot_name, plugin, active, restart_lsn FROM pg_replication_slots", ct);
            f["replication_standbys"] = await ListAsync(conn,
                "SELECT client_addr, state, sync_state FROM pg_stat_replication", ct);

            // ── All databases on this server ────────────────────────────────────────
            f["databases"] = await ListAsync(conn, @"
                SELECT datname,
                       pg_encoding_to_char(encoding) AS encoding,
                       pg_size_pretty(pg_database_size(datname)) AS size
                FROM pg_database WHERE datistemplate = false ORDER BY datname", ct);

            var json = JsonSerializer.Serialize(f);
            return new PluginResult(true, json, json);
        }
        catch (Exception ex)
        {
            return new PluginResult(false, "{}", "{}", ex.Message);
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────────────────

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
        await using var rdr = await cmd.ExecuteReaderAsync(ct);
        while (await rdr.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>();
            for (var i = 0; i < rdr.FieldCount; i++)
                row[rdr.GetName(i)] = rdr.IsDBNull(i) ? null : rdr.GetValue(i);
            rows.Add(row);
        }
        return rows;
    }
}
