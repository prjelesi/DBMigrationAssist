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
    public string PluginVersion => "1.2.0";
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
            var sectionErrors = new Dictionary<string, string>();

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

                        // ── Migration blockers ────────────────────────────────────────────────
                        await CollectListSectionAsync(f, sectionErrors, "tables_without_primary_key", conn, @"
                                SELECT n.nspname AS schema_name, c.relname AS table_name
                                FROM pg_class c
                                JOIN pg_namespace n ON n.oid = c.relnamespace
                                WHERE c.relkind IN ('r','p')
                                    AND n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
                                    AND NOT EXISTS (
                                            SELECT 1 FROM pg_constraint k
                                            WHERE k.conrelid = c.oid AND k.contype = 'p')
                                ORDER BY n.nspname, c.relname", ct);
                        await CollectListSectionAsync(f, sectionErrors, "non_integer_primary_keys", conn, @"
                                SELECT tc.table_schema AS schema_name, tc.table_name,
                                             string_agg(c.data_type, ', ' ORDER BY kcu.ordinal_position) AS key_types
                                FROM information_schema.table_constraints tc
                                JOIN information_schema.key_column_usage kcu
                                    ON kcu.constraint_name = tc.constraint_name
                                 AND kcu.constraint_schema = tc.constraint_schema
                                JOIN information_schema.columns c
                                    ON c.table_schema = kcu.table_schema
                                 AND c.table_name = kcu.table_name
                                 AND c.column_name = kcu.column_name
                                WHERE tc.constraint_type = 'PRIMARY KEY'
                                    AND tc.table_schema NOT IN ('pg_catalog','information_schema')
                                GROUP BY tc.table_schema, tc.table_name
                                HAVING bool_or(c.data_type NOT IN ('smallint','integer','bigint'))
                                ORDER BY tc.table_schema, tc.table_name", ct);
                        await CollectListSectionAsync(f, sectionErrors, "problematic_columns", conn, @"
                                SELECT table_schema AS schema_name, table_name, column_name, data_type, udt_name
                                FROM information_schema.columns
                                WHERE table_schema NOT IN ('pg_catalog','information_schema')
                                    AND (data_type IN ('ARRAY','USER-DEFINED','xml','money') OR udt_name = 'oid')
                                ORDER BY table_schema, table_name, ordinal_position", ct);
                        await CollectListSectionAsync(f, sectionErrors, "json_columns", conn, @"
                                SELECT table_schema AS schema_name, table_name, column_name, data_type
                                FROM information_schema.columns
                                WHERE table_schema NOT IN ('pg_catalog','information_schema')
                                    AND data_type IN ('json','jsonb')
                                ORDER BY table_schema, table_name, ordinal_position", ct);
                        await CollectListSectionAsync(f, sectionErrors, "partitions", conn, @"
                                SELECT parent_ns.nspname AS schema_name, parent.relname AS parent_table,
                                             child_ns.nspname AS partition_schema, child.relname AS partition_name
                                FROM pg_inherits i
                                JOIN pg_class parent ON parent.oid = i.inhparent
                                JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
                                JOIN pg_class child ON child.oid = i.inhrelid
                                JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
                                ORDER BY parent_ns.nspname, parent.relname, child.relname", ct);
                        await CollectListSectionAsync(f, sectionErrors, "foreign_keys", conn, @"
                                SELECT n.nspname AS schema_name, c.relname AS table_name,
                                             k.conname AS constraint_name, pg_get_constraintdef(k.oid) AS definition
                                FROM pg_constraint k
                                JOIN pg_class c ON c.oid = k.conrelid
                                JOIN pg_namespace n ON n.oid = c.relnamespace
                                WHERE k.contype = 'f'
                                    AND n.nspname NOT IN ('pg_catalog','information_schema')
                                ORDER BY n.nspname, c.relname, k.conname", ct);
                        await CollectListSectionAsync(f, sectionErrors, "tablespaces_and_collations", conn, @"
                                SELECT n.nspname AS schema_name, c.relname AS object_name,
                                             c.relkind AS object_kind, t.spcname AS tablespace_name,
                                             col.collname AS collation_name
                                FROM pg_class c
                                JOIN pg_namespace n ON n.oid = c.relnamespace
                                LEFT JOIN pg_tablespace t ON t.oid = NULLIF(c.reltablespace, 0)
                                LEFT JOIN pg_collation col ON col.oid = c.relcollation
                                WHERE n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
                                    AND (c.reltablespace <> 0 OR c.relcollation <> 0)
                                ORDER BY n.nspname, c.relname", ct);

            // ── Extensions ─────────────────────────────────────────────────────────────
            f["extensions"] = await ListAsync(conn,
                "SELECT extname, extversion FROM pg_extension ORDER BY extname", ct);

            // ── Connection settings ───────────────────────────────────────────────────
            f["max_connections"]    = await ScalarAsync(conn, "SELECT setting::int FROM pg_settings WHERE name='max_connections'", ct);
            f["active_connections"] = await ScalarAsync(conn, "SELECT COUNT(*) FROM pg_stat_activity WHERE state='active'", ct);

            // ── WAL / replication ──────────────────────────────────────────────────────
            f["wal_level"]          = await ScalarAsync(conn, "SELECT setting FROM pg_settings WHERE name='wal_level'", ct);
            await CollectListSectionAsync(f, sectionErrors, "replication_slots", conn,
                "SELECT slot_name, plugin, active, restart_lsn FROM pg_replication_slots", ct);
            await CollectListSectionAsync(f, sectionErrors, "replication_standbys", conn,
                "SELECT client_addr, state, sync_state FROM pg_stat_replication", ct);

            // ── All databases on this server ────────────────────────────────────────
            f["databases"] = await ListAsync(conn, @"
                SELECT datname,
                       pg_encoding_to_char(encoding) AS encoding,
                       pg_size_pretty(pg_database_size(datname)) AS size
                FROM pg_database WHERE datistemplate = false ORDER BY datname", ct);

            if (sectionErrors.Count > 0)
                f["section_errors"] = sectionErrors;

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

    private static async Task CollectListSectionAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        string sectionName,
        NpgsqlConnection conn,
        string sql,
        CancellationToken ct)
    {
        try
        {
            findings[sectionName] = await ListAsync(conn, sql, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sectionErrors[sectionName] = ex.GetType().Name;
        }
    }
}
