using MySqlConnector;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Assessment plugin for MySQL / MariaDB source databases.
/// Collects server version, character sets, database inventory, table sizes,
/// routines, views, triggers, replication configuration and engine settings —
/// everything needed to assess migration readiness to Azure Database for MySQL.
/// Requires a read-only login with access to information_schema and SHOW GLOBAL STATUS.
///
/// Minimum privileges:
///   GRANT SELECT ON *.* TO 'assessment_reader'@'%';
///   GRANT REPLICATION CLIENT ON *.* TO 'assessment_reader'@'%';
///   GRANT PROCESS ON *.* TO 'assessment_reader'@'%';
/// </summary>
public sealed class MySqlPlugin : IAssessmentPlugin
{
    public string PluginId      => "mysql";
    public string PluginVersion => "1.1.0";
    public string TargetEngine  => "MySQL";

    public async Task<PluginResult> RunAsync(PluginContext ctx, CancellationToken ct)
    {
        var builder = new MySqlConnectionStringBuilder
        {
            Server          = ctx.Host,
            Port            = (uint)ctx.Port,
            Database        = ctx.Database.Length > 0 ? ctx.Database : "mysql",
            UserID          = ctx.Username,
            Password        = ctx.Password,
            SslMode         = MySqlSslMode.Preferred,
            ConnectionTimeout = 30,
            DefaultCommandTimeout = 60,
        };

        try
        {
            await using var conn = new MySqlConnection(builder.ConnectionString);
            await conn.OpenAsync(ct);

            var f = new Dictionary<string, object>();
            var sectionErrors = new Dictionary<string, string>();

            // ── Server identity ───────────────────────────────────────────────────────
            f["server_version"]     = await ScalarAsync(conn, "SELECT @@global.version", ct);
            f["version_comment"]    = await ScalarAsync(conn, "SELECT @@global.version_comment", ct);
            f["hostname"]           = await ScalarAsync(conn, "SELECT @@global.hostname", ct);
            f["datadir"]            = await ScalarAsync(conn, "SELECT @@global.datadir", ct);
            f["operating_system"]   = await ScalarAsync(conn, "SELECT @@global.version_compile_os", ct);

            // ── Character sets & collation ────────────────────────────────────────────
            f["character_set_server"]  = await ScalarAsync(conn, "SELECT @@global.character_set_server", ct);
            f["collation_server"]      = await ScalarAsync(conn, "SELECT @@global.collation_server", ct);
            f["character_set_results"] = await ScalarAsync(conn, "SELECT @@global.character_set_results", ct);

            // ── Connection limits ─────────────────────────────────────────────────────
            f["max_connections"]    = await ScalarAsync(conn, "SELECT @@global.max_connections", ct);
            f["active_connections"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE COMMAND != 'Sleep'", ct);

            // ── Database list with sizes ──────────────────────────────────────────────
            f["databases"] = await ListAsync(conn, @"
                SELECT 
                    table_schema                                            AS db_name,
                    COUNT(*)                                                AS table_count,
                    SUM(data_length + index_length) / 1024 / 1024          AS size_mb,
                    SUM(data_length) / 1024 / 1024                         AS data_mb
                FROM information_schema.TABLES
                WHERE table_schema NOT IN ('information_schema','mysql','performance_schema','sys')
                GROUP BY table_schema
                ORDER BY size_mb DESC", ct);

            // ── Object counts ─────────────────────────────────────────────────────────
            f["table_count"] = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM information_schema.TABLES
                WHERE TABLE_TYPE = 'BASE TABLE'
                  AND TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')", ct);

            f["view_count"] = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM information_schema.VIEWS
                WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')", ct);

            f["routine_count"] = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM information_schema.ROUTINES
                WHERE ROUTINE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')", ct);

            f["trigger_count"] = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM information_schema.TRIGGERS
                WHERE TRIGGER_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')", ct);

            f["event_count"] = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM information_schema.EVENTS
                WHERE EVENT_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')", ct);

            // ── Table inventory (top 50 by size) ──────────────────────────────────────
            f["table_inventory"] = await ListAsync(conn, @"
                SELECT 
                    TABLE_SCHEMA                                            AS schema_name,
                    TABLE_NAME                                              AS table_name,
                    ENGINE                                                  AS engine,
                    TABLE_ROWS                                              AS row_count_estimate,
                    (DATA_LENGTH + INDEX_LENGTH) / 1024                     AS total_kb,
                    DATA_LENGTH / 1024                                      AS data_kb,
                    INDEX_LENGTH / 1024                                     AS index_kb,
                    TABLE_COLLATION                                         AS collation
                FROM information_schema.TABLES
                WHERE TABLE_TYPE = 'BASE TABLE'
                  AND TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
                ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
                LIMIT 50", ct);

            // ── Routines ──────────────────────────────────────────────────────────────
            f["routines"] = await ListAsync(conn, @"
                SELECT ROUTINE_SCHEMA, ROUTINE_NAME, ROUTINE_TYPE,
                       CREATED, LAST_ALTERED
                FROM information_schema.ROUTINES
                WHERE ROUTINE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
                ORDER BY ROUTINE_SCHEMA, ROUTINE_NAME", ct);

            // ── Storage engines in use ────────────────────────────────────────────────
            f["engines_in_use"] = await ListAsync(conn, @"
                SELECT ENGINE, COUNT(*) AS table_count
                FROM information_schema.TABLES
                WHERE TABLE_TYPE = 'BASE TABLE'
                  AND TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
                GROUP BY ENGINE
                ORDER BY table_count DESC", ct);

            // ── Key global variables ──────────────────────────────────────────────────
            f["innodb_buffer_pool_size"] = await ScalarAsync(conn, "SELECT @@global.innodb_buffer_pool_size", ct);
            f["innodb_file_per_table"]   = await ScalarAsync(conn, "SELECT @@global.innodb_file_per_table", ct);
            f["sql_mode"]                = await ScalarAsync(conn, "SELECT @@global.sql_mode", ct);
                        await CollectScalarSectionAsync(f, sectionErrors, "gtid_mode", conn, "SELECT @@global.gtid_mode", ct);
                        await CollectScalarSectionAsync(f, sectionErrors, "log_bin", conn, "SELECT @@global.log_bin", ct);
                        await CollectScalarSectionAsync(f, sectionErrors, "binlog_format", conn, "SELECT @@global.binlog_format", ct);

                        // ── Migration compatibility signals ─────────────────────────────────────
                        await CollectListSectionAsync(f, sectionErrors, "non_innodb_tables", conn, @"
                                SELECT TABLE_SCHEMA AS schema_name, TABLE_NAME AS table_name, ENGINE AS engine
                                FROM information_schema.TABLES
                                WHERE TABLE_TYPE = 'BASE TABLE'
                                    AND TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
                                    AND COALESCE(ENGINE, '') <> 'InnoDB'
                                ORDER BY TABLE_SCHEMA, TABLE_NAME", ct);
                        await CollectListSectionAsync(f, sectionErrors, "foreign_key_mismatches", conn, @"
                                SELECT kcu.CONSTRAINT_SCHEMA AS schema_name, kcu.CONSTRAINT_NAME AS constraint_name,
                                             kcu.TABLE_NAME AS child_table, kcu.COLUMN_NAME AS child_column,
                                             kcu.REFERENCED_TABLE_NAME AS parent_table,
                                             kcu.REFERENCED_COLUMN_NAME AS parent_column,
                                             child.COLUMN_TYPE AS child_type, parent.COLUMN_TYPE AS parent_type,
                                             child.COLLATION_NAME AS child_collation, parent.COLLATION_NAME AS parent_collation
                                FROM information_schema.KEY_COLUMN_USAGE kcu
                                JOIN information_schema.COLUMNS child
                                    ON child.TABLE_SCHEMA = kcu.TABLE_SCHEMA
                                 AND child.TABLE_NAME = kcu.TABLE_NAME
                                 AND child.COLUMN_NAME = kcu.COLUMN_NAME
                                JOIN information_schema.COLUMNS parent
                                    ON parent.TABLE_SCHEMA = kcu.REFERENCED_TABLE_SCHEMA
                                 AND parent.TABLE_NAME = kcu.REFERENCED_TABLE_NAME
                                 AND parent.COLUMN_NAME = kcu.REFERENCED_COLUMN_NAME
                                WHERE kcu.REFERENCED_TABLE_NAME IS NOT NULL
                                    AND (child.COLUMN_TYPE <> parent.COLUMN_TYPE
                                             OR COALESCE(child.COLLATION_NAME, '') <> COALESCE(parent.COLLATION_NAME, ''))
                                ORDER BY kcu.CONSTRAINT_SCHEMA, kcu.TABLE_NAME, kcu.CONSTRAINT_NAME", ct);
                        await CollectListSectionAsync(f, sectionErrors, "special_columns", conn, @"
                                SELECT TABLE_SCHEMA AS schema_name, TABLE_NAME AS table_name,
                                             COLUMN_NAME AS column_name, COLUMN_TYPE AS column_type, EXTRA AS extra
                                FROM information_schema.COLUMNS
                                WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
                                    AND (DATA_TYPE = 'enum' OR UPPER(EXTRA) LIKE '%INVISIBLE%')
                                ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION", ct);
                        await CollectListSectionAsync(f, sectionErrors, "partitions", conn, @"
                                SELECT TABLE_SCHEMA AS schema_name, TABLE_NAME AS table_name,
                                             PARTITION_NAME AS partition_name, PARTITION_METHOD AS partition_method,
                                             PARTITION_EXPRESSION AS partition_expression, TABLE_ROWS AS row_count_estimate
                                FROM information_schema.PARTITIONS
                                WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
                                    AND PARTITION_NAME IS NOT NULL
                                ORDER BY TABLE_SCHEMA, TABLE_NAME, PARTITION_ORDINAL_POSITION", ct);
                        await CollectListSectionAsync(f, sectionErrors, "authentication_plugins", conn, @"
                                SELECT plugin, COUNT(*) AS account_count
                                FROM mysql.user
                                GROUP BY plugin
                                ORDER BY account_count DESC", ct);
                        await CollectListSectionAsync(f, sectionErrors, "buffer_pool_occupancy", conn, @"
                                SELECT MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_data' THEN VARIABLE_VALUE END) AS data_pages,
                                             MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_total' THEN VARIABLE_VALUE END) AS total_pages,
                                             ROUND(100 * MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_data' THEN CAST(VARIABLE_VALUE AS DECIMAL(30,2)) END)
                                                 / NULLIF(MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_total' THEN CAST(VARIABLE_VALUE AS DECIMAL(30,2)) END), 0), 2) AS occupancy_percent
                                FROM performance_schema.global_status
                                WHERE VARIABLE_NAME IN ('Innodb_buffer_pool_pages_data','Innodb_buffer_pool_pages_total')", ct);

            // ── Replication (best-effort) ─────────────────────────────────────────────
            try
            {
                f["replication_status"] = await ListAsync(conn, "SHOW REPLICA STATUS", ct);
            }
            catch
            {
                // Older MySQL uses SHOW SLAVE STATUS
                try { f["replication_status"] = await ListAsync(conn, "SHOW SLAVE STATUS", ct); }
                catch { f["replication_status"] = "access denied or not a replica"; }
            }

            // ── Active plugins ────────────────────────────────────────────────────────
            await CollectListSectionAsync(f, sectionErrors, "active_plugins", conn, @"
                SELECT PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_TYPE, PLUGIN_STATUS
                FROM information_schema.PLUGINS
                WHERE PLUGIN_STATUS = 'ACTIVE'
                ORDER BY PLUGIN_TYPE, PLUGIN_NAME", ct);

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

    // ── Helpers ───────────────────────────────────────────────────────────────────────────────

    private static async Task<object> ScalarAsync(MySqlConnection conn, string sql, CancellationToken ct)
    {
        await using var cmd = new MySqlCommand(sql, conn) { CommandTimeout = 60 };
        var r = await cmd.ExecuteScalarAsync(ct);
        return r?.ToString() ?? string.Empty;
    }

    private static async Task<List<object>> ListAsync(MySqlConnection conn, string sql, CancellationToken ct)
    {
        var rows = new List<object>();
        await using var cmd = new MySqlCommand(sql, conn) { CommandTimeout = 60 };
        await using var rdr = await cmd.ExecuteReaderAsync(ct);
        while (await rdr.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>();
            for (int i = 0; i < rdr.FieldCount; i++)
                row[rdr.GetName(i)] = rdr.IsDBNull(i) ? null : rdr.GetValue(i);
            rows.Add(row);
        }
        return rows;
    }

    private static async Task CollectListSectionAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        string sectionName,
        MySqlConnection conn,
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

    private static async Task CollectScalarSectionAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        string sectionName,
        MySqlConnection conn,
        string sql,
        CancellationToken ct)
    {
        try
        {
            findings[sectionName] = await ScalarAsync(conn, sql, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sectionErrors[sectionName] = ex.GetType().Name;
        }
    }
}
