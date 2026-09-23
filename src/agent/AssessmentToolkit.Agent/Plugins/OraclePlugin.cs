using Oracle.ManagedDataAccess.Client;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Assessment plugin for Oracle source databases.
/// Collects version, CDB/PDB topology, schema inventory, object counts, tablespace usage,
/// server parameters, SGA, redo logs and operational metadata. AWR performance reports
/// are supplied separately as database-scoped uploaded evidence. Collection is aligned with
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
    public string PluginId => "oracle";
    public string PluginVersion => "2.0.0";
    public string TargetEngine => "Oracle";

    public async Task<PluginResult> RunAsync(PluginContext ctx, CancellationToken ct)
    {
        var dataSource = $"//{ctx.Host}:{ctx.Port}/{ctx.Database}";
        var connString = $"User Id={ctx.Username};Password={ctx.Password};Data Source={dataSource};Connection Timeout=30;";

        try
        {
            await using var conn = new OracleConnection(connString);
            await conn.OpenAsync(ct);

            var findings = new Dictionary<string, object>();
            var sectionErrors = new Dictionary<string, object>();
            findings["collection_contract_version"] = "2.0";
            findings["awr_assessment_source"] = "UploadedEvidence";

            // ── Server identity ─────────────────────────────────────────────────────────────
            await CollectScalarSectionAsync(findings, sectionErrors, "db_version", conn,
                "SELECT BANNER FROM V$VERSION WHERE BANNER LIKE 'Oracle%' AND ROWNUM = 1", ct);
            await CollectScalarSectionAsync(findings, sectionErrors, "db_name", conn,
                "SELECT NAME FROM V$DATABASE", ct);
            await CollectScalarSectionAsync(findings, sectionErrors, "db_created", conn,
                "SELECT TO_CHAR(CREATED,'YYYY-MM-DD') FROM V$DATABASE", ct);
            await CollectScalarSectionAsync(findings, sectionErrors, "db_unique_name", conn,
                "SELECT DB_UNIQUE_NAME FROM V$DATABASE", ct);
            await CollectScalarSectionAsync(findings, sectionErrors, "platform_name", conn,
                "SELECT PLATFORM_NAME FROM V$DATABASE", ct);
            await CollectListSectionAsync(findings, sectionErrors, "oracle_components", conn, @"
                SELECT PRODUCT, VERSION, STATUS
                FROM PRODUCT_COMPONENT_VERSION
                ORDER BY PRODUCT", ct);
            await CollectListSectionAsync(findings, sectionErrors, "installed_options", conn, @"
                SELECT PARAMETER, VALUE
                FROM V$OPTION
                WHERE VALUE = 'TRUE'
                ORDER BY PARAMETER", ct);
            await CollectListSectionAsync(findings, sectionErrors, "sql_patches", conn, @"
                SELECT PATCH_ID, PATCH_TYPE, ACTION, STATUS,
                       TO_CHAR(ACTION_TIME, 'YYYY-MM-DD HH24:MI:SS') AS ACTION_TIME,
                       DESCRIPTION, SOURCE_VERSION, TARGET_VERSION
                FROM DBA_REGISTRY_SQLPATCH
                ORDER BY ACTION_TIME DESC", ct);

            // ── Character set ──────────────────────────────────────────────────────────
            await CollectScalarSectionAsync(findings, sectionErrors, "character_set", conn,
                "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_CHARACTERSET'", ct);
            await CollectScalarSectionAsync(findings, sectionErrors, "nchar_character_set", conn,
                "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_NCHAR_CHARACTERSET'", ct);

            // ── CDB / Multitenant detection (Oracle 12c+) ───────────────────────────
            await CollectScalarSectionAsync(findings, sectionErrors, "cdb", conn,
                "SELECT CDB FROM V$DATABASE", ct);
            await CollectScalarSectionAsync(findings, sectionErrors, "con_name", conn,
                "SELECT SYS_CONTEXT('USERENV','CON_NAME') FROM DUAL", ct);
            await CollectListSectionAsync(findings, sectionErrors, "pdbs", conn,
                "SELECT CON_ID, NAME, OPEN_MODE, RESTRICTED FROM V$PDBS ORDER BY CON_ID", ct);

            // ── RAC detection ───────────────────────────────────────────────────────────
            await CollectListSectionAsync(findings, sectionErrors, "rac_instances", conn,
                "SELECT INST_ID, INSTANCE_NUMBER, INSTANCE_NAME, HOST_NAME, STATUS, DATABASE_STATUS, STARTUP_TIME FROM GV$INSTANCE ORDER BY INST_ID", ct);

            // ── Server, optimizer, memory and host capacity ──────────────────────────────
            await CollectListSectionAsync(findings, sectionErrors, "key_parameters", conn, @"
                    SELECT NAME, VALUE, DESCRIPTION
                    FROM V$PARAMETER
                    WHERE NAME IN (
                        'db_block_size','sga_target','pga_aggregate_target',
                        'memory_target','processes','sessions','undo_management',
                        'log_archive_dest_1','log_mode','enable_pluggable_database',
                        'compatible','max_string_size','optimizer_mode',
                        'optimizer_features_enable','use_large_pages','sga_max_size',
                        'db_recovery_file_dest','db_recovery_file_dest_size',
                        'cluster_database','cluster_database_instances',
                        'resource_manager_plan','resource_limit'
                    )
                    ORDER BY NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "optimizer_configuration", conn, @"
                SELECT NAME, VALUE, ISDEFAULT, ISMODIFIED
                FROM V$PARAMETER
                WHERE NAME IN (
                    'optimizer_mode','optimizer_features_enable',
                    'cursor_sharing','statistics_level','parallel_degree_policy'
                )
                ORDER BY NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "system_statistics", conn, @"
                SELECT SNAME, PNAME, PVAL1, PVAL2
                FROM SYS.AUX_STATS$
                WHERE SNAME IN (
                    'CPUSPEED','IOSEEKTIM','IOTFRSPEED','SREADTIM','MREADTIM',
                    'CPUSPEEDNW','MBRC','MAXTHR','SLAVETHR','SYSSTATS_MAIN_INFO'
                )
                ORDER BY SNAME, PNAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "host_capacity", conn, @"
                SELECT NAME, VALUE
                FROM V$PARAMETER
                WHERE NAME IN (
                    'cpu_count','parallel_max_servers','processes','sessions',
                    'db_file_multiblock_read_count'
                )
                ORDER BY NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "memory_configuration", conn, @"
                SELECT NAME, VALUE, DISPLAY_VALUE
                FROM V$PARAMETER
                WHERE NAME IN (
                    'use_large_pages','memory_target','memory_max_target',
                    'sga_target','sga_max_size','pga_aggregate_target',
                    'pga_aggregate_limit'
                )
                ORDER BY NAME", ct);

            // ── SGA breakdown (factory requirement: v_$sgainfo) ──────────────────────
            await CollectListSectionAsync(findings, sectionErrors, "sga_info", conn,
                "SELECT NAME, BYTES/1048576 AS SIZE_MB, RESIZEABLE FROM V$SGAINFO ORDER BY BYTES DESC", ct);

            // ── Redo log configuration (factory requirement: v_$log) ─────────────────
            await CollectListSectionAsync(findings, sectionErrors, "redo_logs", conn,
                "SELECT GROUP#, MEMBERS, BYTES/1048576 AS SIZE_MB, STATUS, ARCHIVED FROM V$LOG ORDER BY GROUP#", ct);
            await CollectScalarSectionAsync(findings, sectionErrors, "log_mode", conn,
                "SELECT LOG_MODE FROM V$DATABASE", ct);

            // ── Top wait events (factory requirement: v_$system_event) ──────────────
            await CollectListSectionAsync(findings, sectionErrors, "top_wait_events", conn, @"
                SELECT * FROM (
                    SELECT EVENT, TOTAL_WAITS, TOTAL_TIMEOUTS,
                           ROUND(TIME_WAITED_MICRO/1000000,2) AS TIME_WAITED_SEC, WAIT_CLASS
                    FROM V$SYSTEM_EVENT
                    WHERE WAIT_CLASS != 'Idle'
                    ORDER BY TIME_WAITED_MICRO DESC
                )
                WHERE ROWNUM <= 20", ct);

            await CollectListSectionAsync(findings, sectionErrors, "rac_configuration", conn, @"
                SELECT NAME, VALUE
                FROM V$PARAMETER
                WHERE NAME IN ('cluster_database','cluster_database_instances','instance_number')
                ORDER BY NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "database_services", conn, @"
                SELECT NAME, NETWORK_NAME, FAILOVER_METHOD, FAILOVER_TYPE, GOAL, CLB_GOAL
                FROM DBA_SERVICES
                WHERE NAME NOT IN ('SYS$BACKGROUND', 'SYS$USERS')
                ORDER BY NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "resource_manager", conn, @"
                SELECT 'PARAMETER' AS ITEM_TYPE, NAME, VALUE, NULL AS STATUS
                FROM V$PARAMETER
                WHERE NAME IN ('resource_manager_plan','resource_limit')
                UNION ALL
                SELECT 'PLAN', NAME, NULL, IS_TOP_PLAN
                FROM V$RSRC_PLAN
                UNION ALL
                SELECT 'CONSUMER_GROUP', NAME, NULL, NULL
                FROM V$RSRC_CONSUMER_GROUP
                WHERE NAME != 'SYS_GROUP'
                ORDER BY ITEM_TYPE, NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "sql_plan_management", conn, @"
                SELECT 'SQL_PROFILE' AS ITEM_TYPE, NAME AS ITEM_NAME, STATUS,
                       TO_CHAR(CREATED, 'YYYY-MM-DD HH24:MI:SS') AS CREATED_AT,
                       SUBSTR(
                           REGEXP_REPLACE(
                               REGEXP_REPLACE(DBMS_LOB.SUBSTR(SQL_TEXT, 200, 1), '''([^'']|'''')*''', '?'),
                               '(^|[^[:alnum:]_])[-+]?[[:digit:]]+([.][[:digit:]]+)?',
                               '\1?'),
                           1, 50) AS SQL_TEXT_PREVIEW
                FROM DBA_SQL_PROFILES
                UNION ALL
                SELECT 'SQL_PLAN_BASELINE', SQL_HANDLE,
                       CASE WHEN ENABLED = 'YES' THEN 'ENABLED' ELSE 'DISABLED' END,
                       TO_CHAR(CREATED, 'YYYY-MM-DD HH24:MI:SS'),
                       SUBSTR(
                           REGEXP_REPLACE(
                               REGEXP_REPLACE(DBMS_LOB.SUBSTR(SQL_TEXT, 200, 1), '''([^'']|'''')*''', '?'),
                               '(^|[^[:alnum:]_])[-+]?[[:digit:]]+([.][[:digit:]]+)?',
                               '\1?'),
                           1, 50)
                FROM DBA_SQL_PLAN_BASELINES
                ORDER BY ITEM_TYPE, ITEM_NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "sql_tuning_patches", conn, @"
                SELECT NAME, CATEGORY, STATUS,
                       TO_CHAR(CREATED, 'YYYY-MM-DD HH24:MI:SS') AS CREATED_AT,
                       DESCRIPTION
                FROM DBA_SQL_PATCHES
                ORDER BY CREATED DESC", ct);
            await CollectListSectionAsync(findings, sectionErrors, "exadata", conn, @"
                SELECT COUNT(*) AS CELL_STATE_ROWS
                FROM V$CELL_STATE", ct);
            await CollectListSectionAsync(findings, sectionErrors, "hcc_usage", conn, @"
                SELECT t.OWNER, t.TABLE_NAME, t.COMPRESS_FOR,
                       ROUND(SUM(s.BYTES) / 1048576, 2) AS SIZE_MB
                FROM DBA_TABLES t
                JOIN DBA_SEGMENTS s
                  ON s.OWNER = t.OWNER AND s.SEGMENT_NAME = t.TABLE_NAME
                WHERE t.COMPRESSION = 'ENABLED'
                  AND (t.COMPRESS_FOR LIKE 'QUERY%' OR t.COMPRESS_FOR LIKE 'ARCHIVE%')
                  AND t.OWNER NOT IN ('SYS','SYSTEM')
                GROUP BY t.OWNER, t.TABLE_NAME, t.COMPRESS_FOR
                ORDER BY SIZE_MB DESC", ct);
            await CollectListSectionAsync(findings, sectionErrors, "recovery_configuration", conn, @"
                SELECT NAME, VALUE, DISPLAY_VALUE
                FROM V$PARAMETER
                WHERE NAME IN (
                    'db_recovery_file_dest','db_recovery_file_dest_size',
                    'log_archive_config','log_archive_dest_1','log_archive_dest_2',
                    'standby_file_management'
                )
                ORDER BY NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "asm_disk_groups", conn, @"
                SELECT NAME, STATE, TYPE, TOTAL_MB, FREE_MB, USABLE_FILE_MB, OFFLINE_DISKS
                FROM V$ASM_DISKGROUP
                ORDER BY NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "database_directories", conn, @"
                SELECT OWNER, DIRECTORY_NAME, DIRECTORY_PATH
                FROM DBA_DIRECTORIES
                ORDER BY OWNER, DIRECTORY_NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "restore_points", conn, @"
                SELECT NAME, SCN, TO_CHAR(TIME, 'YYYY-MM-DD HH24:MI:SS') AS CREATED_AT,
                       GUARANTEE_FLASHBACK_DATABASE, STORAGE_SIZE
                FROM V$RESTORE_POINT
                ORDER BY TIME DESC", ct);
            await CollectListSectionAsync(findings, sectionErrors, "refresh_groups", conn, @"
                SELECT ROWNER AS OWNER, RNAME AS REFRESH_GROUP, JOB,
                       TO_CHAR(NEXT_DATE, 'YYYY-MM-DD HH24:MI:SS') AS NEXT_RUN
                FROM DBA_REFRESH
                ORDER BY ROWNER, RNAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "audit_policies", conn, @"
                SELECT POLICY_NAME, AUDIT_OPTION, OBJECT_SCHEMA, OBJECT_NAME
                FROM DBA_AUDIT_POLICIES
                ORDER BY POLICY_NAME, AUDIT_OPTION", ct);
            await CollectListSectionAsync(findings, sectionErrors, "lockdown_profiles", conn, @"
                SELECT PROFILE_NAME, RULE_TYPE, RULE, CLAUSE, STATUS
                FROM DBA_LOCKDOWN_PROFILES
                ORDER BY PROFILE_NAME, RULE_TYPE, RULE", ct);

            // ── Schemas ────────────────────────────────────────────────────────────────
            await CollectListSectionAsync(findings, sectionErrors, "schemas", conn,
                "SELECT USERNAME, ACCOUNT_STATUS, CREATED FROM DBA_USERS WHERE ORACLE_MAINTAINED = 'N' ORDER BY USERNAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "database_profiles", conn, @"
                SELECT PROFILE, RESOURCE_TYPE, RESOURCE_NAME, LIMIT
                FROM DBA_PROFILES
                ORDER BY PROFILE, RESOURCE_TYPE, RESOURCE_NAME", ct);

            // Object count per schema / type
            await CollectListSectionAsync(findings, sectionErrors, "object_counts", conn, @"
                SELECT o.OWNER, o.OBJECT_TYPE, COUNT(*) AS CNT
                FROM DBA_OBJECTS o
                JOIN DBA_USERS u ON u.USERNAME = o.OWNER
                WHERE u.ORACLE_MAINTAINED = 'N'
                GROUP BY o.OWNER, o.OBJECT_TYPE
                ORDER BY o.OWNER, o.OBJECT_TYPE", ct);

            await CollectListSectionAsync(findings, sectionErrors, "feature_usage", conn, @"
                SELECT NAME, DETECTED_USAGES, CURRENTLY_USED,
                       TO_CHAR(FIRST_USAGE_DATE,'YYYY-MM-DD') AS FIRST_USAGE_DATE,
                       TO_CHAR(LAST_USAGE_DATE,'YYYY-MM-DD') AS LAST_USAGE_DATE,
                       VERSION
                FROM DBA_FEATURE_USAGE_STATISTICS
                WHERE DETECTED_USAGES > 0 OR CURRENTLY_USED = 'TRUE'
                ORDER BY NAME", ct);

            // ── Tablespace usage ───────────────────────────────────────────────────────
            await CollectListSectionAsync(findings, sectionErrors, "tablespace_usage", conn, @"
                SELECT df.tablespace_name,
                       df.total_mb,
                       (df.total_mb - NVL(fs.free_mb,0)) AS used_mb,
                       NVL(fs.free_mb,0) AS free_mb,
                       ROUND((df.total_mb - NVL(fs.free_mb,0)) / NULLIF(df.total_mb,0) * 100, 2) AS used_pct
                FROM (SELECT tablespace_name, ROUND(SUM(bytes)/1048576) total_mb FROM dba_data_files GROUP BY tablespace_name) df
                LEFT JOIN (SELECT tablespace_name, ROUND(SUM(bytes)/1048576) free_mb FROM dba_free_space GROUP BY tablespace_name) fs
                    ON df.tablespace_name = fs.tablespace_name
                ORDER BY df.tablespace_name", ct);
            await CollectListSectionAsync(findings, sectionErrors, "tablespace_inventory", conn, @"
                SELECT t.TABLESPACE_NAME, t.CONTENTS, t.STATUS, t.EXTENT_MANAGEMENT,
                       t.ALLOCATION_TYPE, t.SEGMENT_SPACE_MANAGEMENT, t.BIGFILE,
                       NVL(df.ALLOCATED_MB, 0) AS ALLOCATED_DATA_MB,
                       NVL(tf.ALLOCATED_MB, 0) AS ALLOCATED_TEMP_MB
                FROM DBA_TABLESPACES t
                LEFT JOIN (
                    SELECT TABLESPACE_NAME, ROUND(SUM(BYTES) / 1048576, 2) AS ALLOCATED_MB
                    FROM DBA_DATA_FILES
                    GROUP BY TABLESPACE_NAME
                ) df ON df.TABLESPACE_NAME = t.TABLESPACE_NAME
                LEFT JOIN (
                    SELECT TABLESPACE_NAME, ROUND(SUM(BYTES) / 1048576, 2) AS ALLOCATED_MB
                    FROM DBA_TEMP_FILES
                    GROUP BY TABLESPACE_NAME
                ) tf ON tf.TABLESPACE_NAME = t.TABLESPACE_NAME
                ORDER BY t.TABLESPACE_NAME", ct);
            await CollectListSectionAsync(findings, sectionErrors, "temporary_tablespace_usage", conn, @"
                SELECT TABLESPACE_NAME,
                       ROUND(TABLESPACE_SIZE / 1048576, 2) AS TOTAL_MB,
                       ROUND((TABLESPACE_SIZE - FREE_SPACE) / 1048576, 2) AS USED_MB,
                       ROUND(FREE_SPACE / 1048576, 2) AS FREE_MB,
                       ROUND((TABLESPACE_SIZE - FREE_SPACE) / NULLIF(TABLESPACE_SIZE, 0) * 100, 2) AS USED_PCT
                FROM DBA_TEMP_FREE_SPACE
                ORDER BY TABLESPACE_NAME", ct);

            // AWR performance detail is supplied as database-scoped uploaded evidence.
            await CollectScalarSectionAsync(findings, sectionErrors, "active_sessions", conn,
                "SELECT COUNT(*) FROM V$SESSION WHERE STATUS = 'ACTIVE'", ct);

            // ── Database links ───────────────────────────────────────────────────────
            await CollectListSectionAsync(findings, sectionErrors, "database_links", conn,
                "SELECT OWNER, DB_LINK, USERNAME, HOST FROM DBA_DB_LINKS ORDER BY OWNER, DB_LINK", ct);
            await CollectListSectionAsync(findings, sectionErrors, "synonym_mappings", conn, @"
                SELECT s.OWNER, s.SYNONYM_NAME, s.TABLE_OWNER, s.TABLE_NAME, s.DB_LINK
                FROM DBA_SYNONYMS s
                LEFT JOIN DBA_USERS u ON u.USERNAME = s.OWNER
                WHERE s.OWNER = 'PUBLIC' OR u.ORACLE_MAINTAINED = 'N'
                ORDER BY s.OWNER, s.SYNONYM_NAME", ct);

            // Invalid objects (must be resolved before migration)
            await CollectListSectionAsync(findings, sectionErrors, "invalid_objects", conn, @"
                    SELECT o.OWNER, o.OBJECT_TYPE, o.OBJECT_NAME
                    FROM DBA_OBJECTS o
                    JOIN DBA_USERS u ON u.USERNAME = o.OWNER
                    WHERE o.STATUS = 'INVALID'
                      AND u.ORACLE_MAINTAINED = 'N'
                    ORDER BY o.OWNER, o.OBJECT_TYPE, o.OBJECT_NAME", ct);
            await CollectScalarSectionAsync(findings, sectionErrors, "invalid_object_count", conn, @"
                    SELECT COUNT(*)
                    FROM DBA_OBJECTS o
                    JOIN DBA_USERS u ON u.USERNAME = o.OWNER
                    WHERE o.STATUS = 'INVALID' AND u.ORACLE_MAINTAINED = 'N'", ct);

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
                                            'ASSEMBLY','ATTRIBUTE DIMENSION','CLUSTER','CONTEXT','CUBE',
                                            'DATABASE LINK','DIMENSION','DIRECTORY','EDITION','EVALUATION CONTEXT',
                                            'FLASHBACK ARCHIVE','HIERARCHY','INDEXTYPE','INMEMORY JOIN GROUP',
                                            'JAVA CLASS','JAVA RESOURCE','JAVA SOURCE','LIBRARY',
                                            'MATERIALIZED VIEW','MATERIALIZED VIEW LOG','MATERIALIZED ZONEMAP',
                                            'MINING MODEL','OPERATOR','OUTLINE','ROLLBACK SEGMENT',
                                            'RULE','RULE SET','SYNONYM','TYPE','TYPE BODY','XML SCHEMA')
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
            await CollectListSectionAsync(findings, sectionErrors, "hourly_redo_generation", conn, @"
                                SELECT TO_CHAR(FIRST_TIME, 'YYYY-MM-DD') AS REDO_DAY,
                                       TO_CHAR(FIRST_TIME, 'HH24') AS REDO_HOUR,
                                       COUNT(*) AS LOG_SWITCHES,
                                       ROUND(SUM(BLOCKS * BLOCK_SIZE) / 1048576, 2) AS REDO_MB
                                FROM V$ARCHIVED_LOG
                                WHERE FIRST_TIME >= SYSDATE - 30
                                  AND NAME IS NOT NULL
                                GROUP BY TO_CHAR(FIRST_TIME, 'YYYY-MM-DD'),
                                         TO_CHAR(FIRST_TIME, 'HH24')
                                ORDER BY REDO_DAY DESC, REDO_HOUR", ct);
            await CollectListSectionAsync(findings, sectionErrors, "data_type_usage", conn, @"
                                SELECT c.DATA_TYPE,
                                       COUNT(*) AS COLUMN_COUNT,
                                       COUNT(DISTINCT c.OWNER || '.' || c.TABLE_NAME) AS TABLE_COUNT
                                FROM DBA_TAB_COLUMNS c
                                JOIN DBA_USERS u ON u.USERNAME = c.OWNER
                                WHERE u.ORACLE_MAINTAINED = 'N'
                                GROUP BY c.DATA_TYPE
                                ORDER BY COLUMN_COUNT DESC", ct);
            await CollectListSectionAsync(findings, sectionErrors, "largest_segments", conn, @"
                                SELECT * FROM (
                                    SELECT OWNER, SEGMENT_NAME, SEGMENT_TYPE, TABLESPACE_NAME,
                                       ROUND(BYTES / 1048576, 2) AS SIZE_MB
                                    FROM DBA_SEGMENTS
                                    WHERE OWNER NOT IN ('SYS', 'SYSTEM')
                                    ORDER BY BYTES DESC
                                )
                                WHERE ROWNUM <= 50", ct);
            await CollectListSectionAsync(findings, sectionErrors, "capacity", conn, @"
                                SELECT
                                    (SELECT ROUND(SUM(BYTES) / 1048576, 2) FROM DBA_DATA_FILES) AS ALLOCATED_DATA_MB,
                                    (SELECT ROUND(SUM(BYTES) / 1048576, 2) FROM DBA_SEGMENTS) AS USED_SEGMENT_MB,
                                    (SELECT ROUND(SUM(BYTES) / 1048576, 2) FROM DBA_TEMP_FILES) AS ALLOCATED_TEMP_MB,
                                    (SELECT ROUND(SUM(CASE WHEN AUTOEXTENSIBLE = 'YES' THEN MAXBYTES ELSE BYTES END) / 1048576, 2)
                                       FROM DBA_DATA_FILES) AS DATAFILE_MAX_MB
                                FROM DUAL", ct);
            await CollectListSectionAsync(findings, sectionErrors, "database_size_summary", conn, @"
                SELECT permanent.ALLOCATED_DATA_MB,
                       temporary.ALLOCATED_TEMP_MB,
                       permanent.ALLOCATED_DATA_MB + temporary.ALLOCATED_TEMP_MB AS TOTAL_ALLOCATED_MB,
                       GREATEST(permanent.ALLOCATED_DATA_MB - free_space.FREE_PERMANENT_MB, 0)
                           AS USED_PERMANENT_MB,
                       free_space.FREE_PERMANENT_MB,
                       ROUND(
                           (permanent.ALLOCATED_DATA_MB - free_space.FREE_PERMANENT_MB) /
                           NULLIF(permanent.ALLOCATED_DATA_MB, 0) * 100,
                           2)
                           AS PERMANENT_USED_PCT,
                       tablespaces.ONLINE_TABLESPACE_COUNT,
                       segments.TOTAL_SEGMENT_COUNT,
                       segments.USED_SEGMENT_MB,
                       largest_tablespace.LARGEST_TABLESPACE_MB,
                       segments.LARGEST_SEGMENT_MB
                FROM
                    (SELECT ROUND(NVL(SUM(BYTES), 0) / 1048576, 2) AS ALLOCATED_DATA_MB
                       FROM DBA_DATA_FILES) permanent
                CROSS JOIN
                    (SELECT ROUND(NVL(SUM(BYTES), 0) / 1048576, 2) AS ALLOCATED_TEMP_MB
                       FROM DBA_TEMP_FILES) temporary
                CROSS JOIN
                    (SELECT ROUND(NVL(SUM(BYTES), 0) / 1048576, 2) AS FREE_PERMANENT_MB
                       FROM DBA_FREE_SPACE) free_space
                CROSS JOIN
                    (SELECT ROUND(NVL(SUM(BYTES), 0) / 1048576, 2) AS USED_SEGMENT_MB,
                            COUNT(*) AS TOTAL_SEGMENT_COUNT,
                            ROUND(NVL(MAX(BYTES), 0) / 1048576, 2) AS LARGEST_SEGMENT_MB
                       FROM DBA_SEGMENTS) segments
                CROSS JOIN
                    (SELECT COUNT(*) AS ONLINE_TABLESPACE_COUNT
                       FROM DBA_TABLESPACES
                      WHERE STATUS = 'ONLINE') tablespaces
                CROSS JOIN
                    (SELECT ROUND(NVL(MAX(ALLOCATED_BYTES), 0) / 1048576, 2) AS LARGEST_TABLESPACE_MB
                       FROM (
                           SELECT TABLESPACE_NAME, SUM(BYTES) AS ALLOCATED_BYTES
                             FROM DBA_DATA_FILES GROUP BY TABLESPACE_NAME
                           UNION ALL
                           SELECT TABLESPACE_NAME, SUM(BYTES) AS ALLOCATED_BYTES
                             FROM DBA_TEMP_FILES GROUP BY TABLESPACE_NAME
                       )) largest_tablespace", ct);
            await CollectListSectionAsync(findings, sectionErrors, "per_schema_summary", conn, @"
                                SELECT u.USERNAME AS OWNER,
                                       (SELECT COUNT(*) FROM DBA_OBJECTS o
                                         WHERE o.OWNER = u.USERNAME AND o.STATUS = 'INVALID') AS INVALID_OBJECTS,
                                       (SELECT COUNT(*) FROM DBA_LOBS l
                                         WHERE l.OWNER = u.USERNAME) AS LOB_OBJECTS,
                                       (SELECT COUNT(*) FROM DBA_SOURCE s
                                         WHERE s.OWNER = u.USERNAME AND s.LINE = 1
                                           AND LOWER(s.TEXT) LIKE '%wrapped%') AS WRAPPED_OBJECTS,
                                       (SELECT COUNT(*) FROM DBA_OBJECTS o
                                         WHERE o.OWNER = u.USERNAME
                                           AND o.OBJECT_TYPE IN (
                                             'JAVA CLASS','JAVA SOURCE','LIBRARY','MATERIALIZED VIEW LOG',
                                             'MINING MODEL','OPERATOR','TYPE','TYPE BODY','XML SCHEMA'
                                           )) AS COMPATIBILITY_OBJECTS
                                FROM DBA_USERS u
                                WHERE u.ORACLE_MAINTAINED = 'N'
                                ORDER BY u.USERNAME", ct);

            // Partitioned tables
            await CollectScalarSectionAsync(findings, sectionErrors, "partitioned_table_count", conn, @"
                SELECT COUNT(*)
                FROM DBA_PART_TABLES p
                JOIN DBA_USERS u ON u.USERNAME = p.OWNER
                WHERE u.ORACLE_MAINTAINED = 'N'", ct);
            await CollectListSectionAsync(findings, sectionErrors, "partitioned_tables", conn, @"
                SELECT p.OWNER, p.TABLE_NAME, p.PARTITIONING_TYPE,
                       p.SUBPARTITIONING_TYPE, p.PARTITION_COUNT
                FROM DBA_PART_TABLES p
                JOIN DBA_USERS u ON u.USERNAME = p.OWNER
                WHERE u.ORACLE_MAINTAINED = 'N'
                ORDER BY p.OWNER, p.TABLE_NAME", ct);

            // Scheduler jobs
            await CollectListSectionAsync(findings, sectionErrors, "scheduler_jobs", conn, @"
                SELECT j.OWNER, j.JOB_NAME, j.JOB_TYPE, j.ENABLED, j.STATE,
                       j.LAST_START_DATE, j.REPEAT_INTERVAL
                FROM DBA_SCHEDULER_JOBS j
                JOIN DBA_USERS u ON u.USERNAME = j.OWNER
                WHERE u.ORACLE_MAINTAINED = 'N'
                ORDER BY j.OWNER, j.JOB_NAME", ct);

            // Total database size (sum of all data files)
            await CollectScalarSectionAsync(findings, sectionErrors, "total_size_mb", conn,
                "SELECT ROUND(SUM(bytes)/1048576) FROM DBA_DATA_FILES", ct);

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
        IDictionary<string, object> sectionErrors,
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
            sectionErrors[sectionName] = CreateSectionError(ex);
        }
    }

    private static async Task CollectScalarSectionAsync(
        IDictionary<string, object> findings,
        IDictionary<string, object> sectionErrors,
        string sectionName,
        OracleConnection conn,
        string sql,
        CancellationToken ct)
    {
        try
        {
            findings[sectionName] = await ScalarAsync(conn, sql, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sectionErrors[sectionName] = CreateSectionError(ex);
        }
    }

    private static object CreateSectionError(Exception exception)
    {
        if (exception is OracleException oracleException)
        {
            return new
            {
                category = oracleException.Number is 942 or 1031 ? "InsufficientPrivilegesOrUnavailableView" : "OracleError",
                oracleErrorCode = $"ORA-{oracleException.Number:D5}",
                message = oracleException.Message
            };
        }

        return new
        {
            category = "CollectionError",
            exceptionType = exception.GetType().Name,
            message = exception.Message
        };
    }
}
