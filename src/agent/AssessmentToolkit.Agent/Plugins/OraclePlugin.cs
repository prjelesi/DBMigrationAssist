using Oracle.ManagedDataAccess.Client;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Assessment plugin for Oracle source databases.
/// Collects version, schema list, object counts, AWR availability and tablespace usage.
/// Requires SELECT on DBA_ views or at minimum V$SESSION / V$DATABASE.
/// </summary>
public class OraclePlugin : IAssessmentPlugin
{
    public string PluginId => "oracle";
    public string PluginVersion => "1.0.0";
    public string TargetEngine => "Oracle";

    public async Task<PluginResult> RunAsync(PluginContext ctx, CancellationToken ct)
    {
        // Oracle connection string: Data Source=//host:port/service
        var dataSource = $"//{ctx.Host}:{ctx.Port}/{ctx.Database}";
        var connString = $"User Id={ctx.Username};Password={ctx.Password};Data Source={dataSource};Connection Timeout=30;";

        try
        {
            await using var conn = new OracleConnection(connString);
            await conn.OpenAsync(ct);

            var findings = new Dictionary<string, object>();

            // Database version
            findings["db_version"] = await ScalarAsync(conn,
                "SELECT BANNER FROM V$VERSION WHERE BANNER LIKE 'Oracle%' AND ROWNUM = 1", ct);

            // DB name and created date
            findings["db_name"] = await ScalarAsync(conn,
                "SELECT NAME FROM V$DATABASE", ct);

            // Character set
            findings["character_set"] = await ScalarAsync(conn,
                "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_CHARACTERSET'", ct);

            // Schema (user) list
            findings["schemas"] = await ListAsync(conn,
                "SELECT USERNAME, ACCOUNT_STATUS, CREATED FROM DBA_USERS WHERE ORACLE_MAINTAINED = 'N' ORDER BY USERNAME", ct);

            // Object count per schema/type
            findings["object_counts"] = await ListAsync(conn,
                "SELECT OWNER, OBJECT_TYPE, COUNT(*) AS CNT FROM DBA_OBJECTS WHERE ORACLE_MAINTAINED = 'N' GROUP BY OWNER, OBJECT_TYPE ORDER BY OWNER, OBJECT_TYPE", ct);

            // Tablespace usage
            findings["tablespace_usage"] = await ListAsync(conn,
                @"SELECT df.tablespace_name,
                         df.total_mb,
                         (df.total_mb - NVL(fs.free_mb,0)) AS used_mb
                  FROM (SELECT tablespace_name, ROUND(SUM(bytes)/1048576) total_mb FROM dba_data_files GROUP BY tablespace_name) df
                  LEFT JOIN (SELECT tablespace_name, ROUND(SUM(bytes)/1048576) free_mb FROM dba_free_space GROUP BY tablespace_name) fs
                    ON df.tablespace_name = fs.tablespace_name
                  ORDER BY df.tablespace_name", ct);

            // Check if AWR is licensed
            findings["awr_available"] = await AwrAvailableAsync(conn, ct);

            // Active sessions
            findings["active_sessions"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM V$SESSION WHERE STATUS = 'ACTIVE'", ct);

            var findingJson = JsonSerializer.Serialize(findings);
            return new PluginResult(true, findingJson, findingJson);
        }
        catch (Exception ex)
        {
            return new PluginResult(false, "{}", "{}", ex.Message);
        }
    }

    private static async Task<bool> AwrAvailableAsync(OracleConnection conn, CancellationToken ct)
    {
        try
        {
            await using var cmd = new OracleCommand(
                "SELECT COUNT(*) FROM DBA_HIST_SNAPSHOT WHERE ROWNUM = 1", conn);
            cmd.CommandTimeout = 10;
            var result = await cmd.ExecuteScalarAsync(ct);
            return Convert.ToInt32(result) >= 0;
        }
        catch { return false; }
    }

    private static async Task<object> ScalarAsync(OracleConnection conn, string sql, CancellationToken ct)
    {
        await using var cmd = new OracleCommand(sql, conn) { CommandTimeout = 30 };
        var result = await cmd.ExecuteScalarAsync(ct);
        return result ?? DBNull.Value;
    }

    private static async Task<List<object?>> ListAsync(OracleConnection conn, string sql, CancellationToken ct)
    {
        var rows = new List<object?>();
        await using var cmd = new OracleCommand(sql, conn) { CommandTimeout = 60 };
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
