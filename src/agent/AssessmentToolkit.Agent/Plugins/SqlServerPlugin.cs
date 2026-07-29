using Microsoft.Data.SqlClient;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Assessment plugin for Microsoft SQL Server source databases.
/// Collects version, edition, database/schema inventory, table sizes, stored procedures,
/// functions, views, indexes, triggers, linked servers and data-type usage.
/// Requires a login with VIEW DATABASE STATE and SELECT on system catalog views.
/// </summary>
public sealed class SqlServerPlugin : IAssessmentPlugin
{
    public string PluginId      => "sqlserver";
    public string PluginVersion => "1.0.0";
    public string TargetEngine  => "SqlServer";

    public async Task<PluginResult> RunAsync(PluginContext ctx, CancellationToken ct)
    {
        var connString =
            $"Server={ctx.Host},{ctx.Port};" +
            $"Database={ctx.Database};" +
            $"User Id={ctx.Username};" +
            $"Password={ctx.Password};" +
            "TrustServerCertificate=True;" +
            "Connect Timeout=30;";

        try
        {
            await using var conn = new SqlConnection(connString);
            await conn.OpenAsync(ct);

            var f = new Dictionary<string, object>();

            // ── Server identity ───────────────────────────────────────────────────────
            f["server_version"]   = await ScalarAsync(conn, "SELECT @@VERSION", ct);
            f["edition"]          = await ScalarAsync(conn, "SELECT SERVERPROPERTY('Edition')", ct);
            f["product_version"]  = await ScalarAsync(conn, "SELECT SERVERPROPERTY('ProductVersion')", ct);
            f["product_level"]    = await ScalarAsync(conn, "SELECT SERVERPROPERTY('ProductLevel')", ct);
            f["server_collation"] = await ScalarAsync(conn, "SELECT SERVERPROPERTY('Collation')", ct);
            f["instance_name"]    = await ScalarAsync(conn, "SELECT SERVERPROPERTY('InstanceName')", ct);

            // ── Database list ─────────────────────────────────────────────────────────
            f["databases"] = await ListAsync(conn, @"
                SELECT name,
                       state_desc,
                       compatibility_level,
                       collation_name,
                       recovery_model_desc,
                       CAST(DATABASEPROPERTYEX(name,'IsEncrypted') AS BIT) AS is_encrypted
                FROM sys.databases
                WHERE database_id > 4
                ORDER BY name", ct);

            // ── Current database summary ──────────────────────────────────────────────
            f["table_count"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0", ct);

            f["view_count"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped = 0", ct);

            f["stored_procedure_count"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0", ct);

            f["function_count"] = await ScalarAsync(conn, @"
                SELECT COUNT(*) FROM sys.objects
                WHERE type IN ('FN','IF','TF') AND is_ms_shipped = 0", ct);

            f["index_count"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM sys.indexes WHERE type > 0", ct);

            f["trigger_count"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM sys.triggers WHERE is_ms_shipped = 0", ct);

            f["foreign_key_count"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM sys.foreign_keys WHERE is_ms_shipped = 0", ct);

            // ── Table inventory (top 50 by size) ──────────────────────────────────────
            f["table_inventory"] = await ListAsync(conn, @"
                SELECT TOP 50
                    s.name                              AS schema_name,
                    t.name                              AS table_name,
                    SUM(p.rows)                         AS row_count_estimate,
                    SUM(a.total_pages) * 8              AS total_kb,
                    SUM(a.used_pages)  * 8              AS used_kb
                FROM sys.tables     t
                JOIN sys.schemas    s ON t.schema_id  = s.schema_id
                JOIN sys.indexes    i ON t.object_id  = i.object_id AND i.type IN (0, 1)
                JOIN sys.partitions p ON i.object_id  = p.object_id AND i.index_id = p.index_id
                JOIN sys.allocation_units a ON p.partition_id = a.container_id
                WHERE t.is_ms_shipped = 0
                GROUP BY s.name, t.name
                ORDER BY total_kb DESC", ct);

            // ── Stored procedures ─────────────────────────────────────────────────────
            f["stored_procedures"] = await ListAsync(conn, @"
                SELECT s.name AS schema_name, p.name AS procedure_name,
                       CONVERT(VARCHAR(20), p.create_date, 120) AS create_date,
                       CONVERT(VARCHAR(20), p.modify_date, 120) AS modify_date
                FROM sys.procedures p
                JOIN sys.schemas    s ON p.schema_id = s.schema_id
                WHERE p.is_ms_shipped = 0
                ORDER BY s.name, p.name", ct);

            // ── Data-type usage (migration compatibility signal) ───────────────────────
            f["data_type_usage"] = await ListAsync(conn, @"
                SELECT t.name AS type_name, COUNT(*) AS column_count
                FROM sys.columns c
                JOIN sys.types   t ON c.user_type_id = t.user_type_id
                GROUP BY t.name
                ORDER BY column_count DESC", ct);

            // ── Non-standard / legacy type flags ──────────────────────────────────────
            f["legacy_type_columns"] = await ListAsync(conn, @"
                SELECT s.name AS schema_name, tbl.name AS table_name,
                       c.name AS column_name, tp.name AS data_type
                FROM sys.columns c
                JOIN sys.tables  tbl ON c.object_id    = tbl.object_id
                JOIN sys.schemas s   ON tbl.schema_id  = s.schema_id
                JOIN sys.types   tp  ON c.user_type_id = tp.user_type_id
                WHERE tp.name IN ('text','ntext','image','sql_variant','xml',
                                  'hierarchyid','geography','geometry')
                  AND tbl.is_ms_shipped = 0
                ORDER BY tp.name, s.name, tbl.name", ct);

            // ── Indexes ───────────────────────────────────────────────────────────────
            f["indexes"] = await ListAsync(conn, @"
                SELECT s.name  AS schema_name,
                       t.name  AS table_name,
                       i.name  AS index_name,
                       i.type_desc,
                       i.is_unique,
                       i.is_primary_key,
                       user_seeks + user_scans + user_lookups AS total_reads,
                       user_updates                           AS total_writes
                FROM sys.indexes           i
                JOIN sys.tables            t  ON i.object_id = t.object_id
                JOIN sys.schemas           s  ON t.schema_id = s.schema_id
                LEFT JOIN sys.dm_db_index_usage_stats u
                    ON i.object_id = u.object_id AND i.index_id = u.index_id
                       AND u.database_id = DB_ID()
                WHERE i.type > 0 AND t.is_ms_shipped = 0
                ORDER BY total_reads DESC, s.name, t.name", ct);

            // ── Linked servers ────────────────────────────────────────────────────────
            f["linked_servers"] = await ListAsync(conn, @"
                SELECT name, product, provider, data_source, is_remote_login_enabled
                FROM sys.servers
                WHERE is_linked = 1
                ORDER BY name", ct);

            // ── Database size ─────────────────────────────────────────────────────────
            f["database_size_mb"] = await ScalarAsync(conn, @"
                SELECT CAST(SUM(size * 8.0 / 1024) AS BIGINT)
                FROM sys.database_files
                WHERE type IN (0, 1)", ct);

            // ── SQL Server Agent jobs (best-effort, requires msdb access) ─────────────
            try
            {
                f["agent_jobs"] = await ListAsync(conn, @"
                    SELECT j.name AS job_name,
                           j.enabled,
                           CASE j.last_run_outcome
                               WHEN 1 THEN 'Succeeded'
                               WHEN 0 THEN 'Failed'
                               WHEN 3 THEN 'Cancelled'
                               ELSE 'Unknown'
                           END AS last_run_outcome
                    FROM msdb.dbo.sysjobs j
                    ORDER BY j.name", ct);
            }
            catch
            {
                f["agent_jobs"] = "access denied or msdb unavailable";
            }

            // ── Active connections ────────────────────────────────────────────────────
            f["active_connections"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1", ct);

            var json = JsonSerializer.Serialize(f);
            return new PluginResult(true, json, json);
        }
        catch (Exception ex)
        {
            return new PluginResult(false, "{}", "{}", ex.Message);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────────────────────

    private static async Task<object> ScalarAsync(SqlConnection conn, string sql, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 60 };
        var r = await cmd.ExecuteScalarAsync(ct);
        return r?.ToString() ?? string.Empty;
    }

    private static async Task<List<object>> ListAsync(SqlConnection conn, string sql, CancellationToken ct)
    {
        var rows = new List<object>();
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 60 };
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
}
