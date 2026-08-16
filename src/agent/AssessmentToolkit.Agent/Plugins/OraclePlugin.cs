using Oracle.ManagedDataAccess.Client;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Assessment plugin for Oracle source databases.
/// Collects version, CDB/PDB topology, schema inventory, object counts, tablespace usage,
/// server parameters, SGA, redo logs, wait events and AWR availability — aligned with
/// the Azure Cloud Accelerate Factory info-gather script requirements.
///
/// Required grants (minimum):
///   GRANT CREATE SESSION         TO assessment_reader;
///   GRANT SELECT_CATALOG_ROLE    TO assessment_reader;
///   GRANT SELECT ON sys.aux_stats$ TO assessment_reader;
///   GRANT SELECT ON v_$instance  TO assessment_reader;
///   GRANT SELECT ON v_$database  TO assessment_reader;
///   GRANT SELECT ON v_$parameter TO assessment_reader;
///   GRANT SELECT ON v_$sgainfo   TO assessment_reader;
///   GRANT SELECT ON v_$system_event TO assessment_reader;
///   GRANT SELECT ON v_$log       TO assessment_reader;
///   GRANT SELECT ON v_$log_history TO assessment_reader;
///   GRANT SELECT ON v_$pdbs      TO assessment_reader;  -- Oracle 12c+ (multitenant)
///   GRANT SELECT ON gv_$instance TO assessment_reader;  -- Oracle RAC
/// </summary>
public sealed class OraclePlugin : IAssessmentPlugin
{
    public string PluginId      => "oracle";
    public string PluginVersion => "1.2.0";
    public string TargetEngine  => "Oracle";

    public async Task<PluginResult> RunAsync(PluginContext ctx, CancellationToken ct)
    {
        var dataSource = $"//{ctx.Host}:{ctx.Port}/{ctx.Database}";
        var connString = $"User Id={ctx.Username};Password={ctx.Password};Data Source={dataSource};Connection Timeout=30;";

        try
        {
            await using var conn = new OracleConnection(connString);
            await conn.OpenAsync(ct);

            var findings = new Dictionary<string, object>();
            var sectionErrors = new Dictionary<string, string>();

            // ── Server identity ─────────────────────────────────────────────────────────────
            findings["db_version"] = await ScalarAsync(conn,
                "SELECT BANNER FROM V$VERSION WHERE BANNER LIKE 'Oracle%' AND ROWNUM = 1", ct);
            findings["db_name"] = await ScalarAsync(conn,
                "SELECT NAME FROM V$DATABASE", ct);
            findings["db_created"] = await ScalarAsync(conn,
                "SELECT TO_CHAR(CREATED,'YYYY-MM-DD') FROM V$DATABASE", ct);
            findings["db_unique_name"] = await ScalarAsync(conn,
                "SELECT DB_UNIQUE_NAME FROM V$DATABASE", ct);
            findings["platform_name"] = await ScalarAsync(conn,
                "SELECT PLATFORM_NAME FROM V$DATABASE", ct);

            // ── Character set ──────────────────────────────────────────────────────────
            findings["character_set"] = await ScalarAsync(conn,
                "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_CHARACTERSET'", ct);
            findings["nchar_character_set"] = await ScalarAsync(conn,
                "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_NCHAR_CHARACTERSET'", ct);

            // ── CDB / Multitenant detection (Oracle 12c+) ───────────────────────────
            try
            {
                findings["cdb"] = await ScalarAsync(conn,
                    "SELECT CDB FROM V$DATABASE", ct);
                findings["con_name"] = await ScalarAsync(conn,
                    "SELECT SYS_CONTEXT('USERENV','CON_NAME') FROM DUAL", ct);
                findings["pdbs"] = await ListAsync(conn,
                    "SELECT CON_ID, NAME, OPEN_MODE, RESTRICTED FROM V$PDBS ORDER BY CON_ID", ct);
            }
            catch { findings["cdb"] = "NO"; /* Pre-12c or V$PDBS not accessible */ }

            // ── RAC detection ───────────────────────────────────────────────────────────
            try
            {
                findings["rac_instances"] = await ListAsync(conn,
                    "SELECT INST_ID, INSTANCE_NAME, HOST_NAME, STATUS FROM GV$INSTANCE ORDER BY INST_ID", ct);
            }
            catch { findings["rac_instances"] = "single instance or GV$INSTANCE not accessible"; }

            // ── Key server parameters (factory requirement: v_$parameter) ───────────────
            try
            {
                findings["key_parameters"] = await ListAsync(conn, @"
                    SELECT NAME, VALUE, DESCRIPTION
                    FROM V$PARAMETER
                    WHERE NAME IN (
                        'db_block_size','sga_target','pga_aggregate_target',
                        'memory_target','processes','sessions','undo_management',
                        'log_archive_dest_1','log_mode','enable_pluggable_database',
                        'compatible','max_string_size','optimizer_mode'
                    )
                    ORDER BY NAME", ct);
            }
            catch { findings["key_parameters"] = "V$PARAMETER not accessible"; }

            // ── SGA breakdown (factory requirement: v_$sgainfo) ──────────────────────
            try
            {
                findings["sga_info"] = await ListAsync(conn,
                    "SELECT NAME, BYTES/1048576 AS SIZE_MB, RESIZEABLE FROM V$SGAINFO ORDER BY BYTES DESC", ct);
            }
            catch { findings["sga_info"] = "V$SGAINFO not accessible"; }

            // ── Redo log configuration (factory requirement: v_$log) ─────────────────
            try
            {
                findings["redo_logs"] = await ListAsync(conn,
                    "SELECT GROUP#, MEMBERS, BYTES/1048576 AS SIZE_MB, STATUS, ARCHIVED FROM V$LOG ORDER BY GROUP#", ct);
                findings["log_mode"] = await ScalarAsync(conn,
                    "SELECT LOG_MODE FROM V$DATABASE", ct);
            }
            catch { findings["redo_logs"] = "V$LOG not accessible"; }

            // ── Top wait events (factory requirement: v_$system_event) ──────────────
            try
            {
                findings["top_wait_events"] = await ListAsync(conn, @"
                    SELECT EVENT, TOTAL_WAITS, TOTAL_TIMEOUTS,
                           ROUND(TIME_WAITED_MICRO/1000000,2) AS TIME_WAITED_SEC, WAIT_CLASS
                    FROM V$SYSTEM_EVENT
                    WHERE WAIT_CLASS != 'Idle'
                    ORDER BY TIME_WAITED_MICRO DESC
                    FETCH FIRST 20 ROWS ONLY", ct);
            }
            catch { findings["top_wait_events"] = "V$SYSTEM_EVENT not accessible"; }

            // ── Schemas ────────────────────────────────────────────────────────────────
            findings["schemas"] = await ListAsync(conn,
                "SELECT USERNAME, ACCOUNT_STATUS, CREATED FROM DBA_USERS WHERE ORACLE_MAINTAINED = 'N' ORDER BY USERNAME", ct);

            // Object count per schema / type
            findings["object_counts"] = await ListAsync(conn,
                "SELECT OWNER, OBJECT_TYPE, COUNT(*) AS CNT FROM DBA_OBJECTS WHERE ORACLE_MAINTAINED = 'N' GROUP BY OWNER, OBJECT_TYPE ORDER BY OWNER, OBJECT_TYPE", ct);

            // ── Tablespace usage ───────────────────────────────────────────────────────
            findings["tablespace_usage"] = await ListAsync(conn, @"
                SELECT df.tablespace_name,
                       df.total_mb,
                       (df.total_mb - NVL(fs.free_mb,0)) AS used_mb
                FROM (SELECT tablespace_name, ROUND(SUM(bytes)/1048576) total_mb FROM dba_data_files GROUP BY tablespace_name) df
                LEFT JOIN (SELECT tablespace_name, ROUND(SUM(bytes)/1048576) free_mb FROM dba_free_space GROUP BY tablespace_name) fs
                    ON df.tablespace_name = fs.tablespace_name
                ORDER BY df.tablespace_name", ct);

            // ── AWR + active sessions ───────────────────────────────────────────────
            findings["awr_available"]  = await AwrAvailableAsync(conn, ct);
            findings["active_sessions"] = await ScalarAsync(conn,
                "SELECT COUNT(*) FROM V$SESSION WHERE STATUS = 'ACTIVE'", ct);

            // ── Database links ───────────────────────────────────────────────────────
            try { findings["database_links"] = await ListAsync(conn,
                "SELECT DB_LINK, USERNAME, HOST FROM DBA_DB_LINKS ORDER BY DB_LINK", ct); }
            catch { findings["database_links"] = "access denied"; }

            // Invalid objects (must be resolved before migration)
            try
            {
                findings["invalid_objects"] = await ListAsync(conn, @"
                    SELECT OWNER, OBJECT_TYPE, OBJECT_NAME
                    FROM DBA_OBJECTS
                    WHERE STATUS = 'INVALID'
                      AND ORACLE_MAINTAINED = 'N'
                    ORDER BY OWNER, OBJECT_TYPE, OBJECT_NAME", ct);
                findings["invalid_object_count"] = await ScalarAsync(conn, @"
                    SELECT COUNT(*) FROM DBA_OBJECTS
                    WHERE STATUS = 'INVALID' AND ORACLE_MAINTAINED = 'N'", ct);
            }
            catch { findings["invalid_objects"] = "access denied"; }

                        // Migration compatibility signals
                        await CollectListSectionAsync(findings, sectionErrors, "wrapped_code", conn, @"
                                SELECT OWNER, NAME AS OBJECT_NAME, TYPE AS OBJECT_TYPE
                                FROM DBA_SOURCE
                                WHERE LINE = 1
                                    AND LOWER(TEXT) LIKE '%wrapped%'
                                    AND OWNER NOT IN ('SYS','SYSTEM')
                                ORDER BY OWNER, TYPE, NAME", ct);
                        await CollectListSectionAsync(findings, sectionErrors, "unsupported_objects", conn, @"
                                SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS
                                FROM DBA_OBJECTS
                                WHERE OWNER NOT IN ('SYS','SYSTEM')
                                    AND OBJECT_TYPE IN (
                                            'DATABASE LINK','DIRECTORY','EDITION','EVALUATION CONTEXT',
                                            'JAVA CLASS','JAVA RESOURCE','JAVA SOURCE','MATERIALIZED VIEW',
                                            'MATERIALIZED VIEW LOG','RULE','RULE SET','SYNONYM',
                                            'TYPE','TYPE BODY','XML SCHEMA')
                                ORDER BY OWNER, OBJECT_TYPE, OBJECT_NAME", ct);
                        await CollectListSectionAsync(findings, sectionErrors, "lob_size", conn, @"
                                SELECT l.OWNER, l.TABLE_NAME, l.COLUMN_NAME, l.SEGMENT_NAME,
                                             ROUND(SUM(s.BYTES) / 1048576, 2) AS SIZE_MB
                                FROM DBA_LOBS l
                                JOIN DBA_SEGMENTS s
                                    ON s.OWNER = l.OWNER AND s.SEGMENT_NAME = l.SEGMENT_NAME
                                WHERE l.OWNER NOT IN ('SYS','SYSTEM')
                                GROUP BY l.OWNER, l.TABLE_NAME, l.COLUMN_NAME, l.SEGMENT_NAME
                                ORDER BY SIZE_MB DESC", ct);
                        await CollectListSectionAsync(findings, sectionErrors, "daily_redo_generation", conn, @"
                                SELECT TO_CHAR(TRUNC(FIRST_TIME), 'YYYY-MM-DD') AS REDO_DAY,
                                             COUNT(*) AS ARCHIVED_LOGS,
                                             ROUND(SUM(BLOCKS * BLOCK_SIZE) / 1073741824, 2) AS REDO_GB
                                FROM V$ARCHIVED_LOG
                                WHERE FIRST_TIME >= SYSDATE - 7
                                    AND NAME IS NOT NULL
                                GROUP BY TRUNC(FIRST_TIME)
                                ORDER BY TRUNC(FIRST_TIME)", ct);

            // Partitioned tables
            try
            {
                findings["partitioned_table_count"] = await ScalarAsync(conn,
                    "SELECT COUNT(*) FROM DBA_PART_TABLES WHERE ORACLE_MAINTAINED = 'N'", ct);
                findings["partitioned_tables"] = await ListAsync(conn, @"
                    SELECT OWNER, TABLE_NAME, PARTITIONING_TYPE, PARTITION_COUNT
                    FROM DBA_PART_TABLES
                    WHERE ORACLE_MAINTAINED = 'N'
                    ORDER BY OWNER, TABLE_NAME", ct);
            }
            catch { findings["partitioned_tables"] = "access denied"; }

            // Scheduler jobs
            try
            {
                findings["scheduler_jobs"] = await ListAsync(conn, @"
                    SELECT OWNER, JOB_NAME, JOB_TYPE, ENABLED, STATE, LAST_START_DATE
                    FROM DBA_SCHEDULER_JOBS
                    WHERE ORACLE_MAINTAINED = 'N'
                    ORDER BY OWNER, JOB_NAME", ct);
            }
            catch { findings["scheduler_jobs"] = "access denied"; }

            // Total database size (sum of all data files)
            try
            {
                findings["total_size_mb"] = await ScalarAsync(conn, @"
                    SELECT ROUND(SUM(bytes)/1048576) FROM dba_data_files", ct);
            }
            catch { findings["total_size_mb"] = "access denied"; }

            if (sectionErrors.Count > 0)
                findings["section_errors"] = sectionErrors;

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

    private static async Task CollectListSectionAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        string sectionName,
        OracleConnection conn,
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
