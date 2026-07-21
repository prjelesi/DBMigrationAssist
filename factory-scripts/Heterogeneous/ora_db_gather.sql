set pagesize 1000
set linesize 250
set feedback off
set heading on
set colsep ' | '
set underline on
set wrap off
set trimspool on
col parameter format a30 heading 'PARAMETER'
col current_value format a30 heading 'CURRENT_VALUE'
col description format a80 heading 'DESCRIPTION'
col metric format a30 heading 'METRIC'
col value format a30 heading 'VALUE'
col info_type format a30 heading 'INFO_TYPE'
col statistic_name format a20 heading 'STATISTIC_NAME'
col parameter_name format a20 heading 'PARAMETER_NAME'
col log_date format a12 heading 'LOG_DATE'
col hour_of_day format a12 heading 'HOUR_OF_DAY'
col log_switches format 999999 heading 'LOG_SWITCHES'
col redo_mb_generated format 999999999.99 heading 'REDO_MB_GENERATED'
col activity_level format a35 heading 'ACTIVITY_LEVEL'
col object_type format a20 heading 'OBJECT_TYPE'
col object_name format a30 heading 'OBJECT_NAME'
col sql_text_preview format a50 heading 'SQL_TEXT_PREVIEW'
col status format a10 heading 'STATUS'
col created_date format a20 heading 'CREATED_DATE'
col owner format a20 heading 'OWNER'
col table_name format a30 heading 'TABLE_NAME'
col hcc_type format a15 heading 'HCC_TYPE'
col size_mb format 999999999.99 heading 'SIZE_MB'
col compression_description format a30 heading 'COMPRESSION_DESCRIPTION'
col estimated_uncompressed_mb format 999999999.99 heading 'ESTIMATED_UNCOMPRESSED_MB'
col tablespace_name format a30 heading 'TABLESPACE_NAME'
col total_size_gb format a12 heading 'TOTAL_SIZE_GB'
col used_size_gb format a12 heading 'USED_SIZE_GB'
col free_size_gb format a12 heading 'FREE_SIZE_GB'
col utilization_pct format a12 heading 'UTILIZATION_PCT'
col status format a40 heading 'STATUS'
col last_ddl_time format a20 heading 'LAST_DDL_TIME'
col storage_type format a50 heading 'STORAGE_TYPE'
col schema FORMAT A30

WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT 1

 

 



SELECT 'DB OPTIMIZER CONFIGURATION BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'OPTIMIZER_MODE' as parameter,
    value as current_value,
    CASE 
        WHEN value = 'ALL_ROWS' THEN 'OLAP Targeted - Optimizes for throughput'
        WHEN value = 'FIRST_ROWS' THEN 'OLTP - Optimizes for response time'
        WHEN value = 'FIRST_ROWS_1' THEN 'OLTP Response - First 1 row'
        WHEN value = 'FIRST_ROWS_10' THEN 'OLTP Response - First 10 rows'
        WHEN value = 'FIRST_ROWS_100' THEN 'OLTP Response - First 100 rows'
        WHEN value = 'FIRST_ROWS_1000' THEN 'OLTP Response - First 1000 rows'
        ELSE 'Default/Other'
    END as description
FROM v$parameter 
WHERE name = 'optimizer_mode'
UNION ALL
SELECT 
    'OPTIMIZER_FEATURES_ENABLE' as parameter,
    value as current_value,
    'Oracle version features enabled' as description
FROM v$parameter 
WHERE name = 'optimizer_features_enable';
SELECT 'DB OPTIMIZER CONFIGURATIONO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'VERSION AND CDB INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'VERSION' as info_type,
    version as value,
    'Oracle Database Version' as description
FROM v$instance
UNION ALL
SELECT 
    'CDB_DATABASE' as info_type,
    cdb as value,
    CASE 
        WHEN cdb = 'YES' THEN 'Container Database - Memory shared across PDBs'
        WHEN cdb = 'NO' THEN 'Non-CDB - Dedicated instance memory'
        ELSE 'Unknown CDB status'
    END as description
FROM v$database
UNION ALL
SELECT 
    'CON_ID' as info_type,
    TO_CHAR(con_id) as value,
    'Current Container ID (0=CDB Root, >0=PDB)' as description
FROM v$database;
SELECT 'VERSION AND CDB INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'SYSTEM STATS INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
-- First try aux_stats$ table (traditional system statistics)
SELECT 
    sname as statistic_name,
    pname as parameter_name,
    TO_CHAR(pval1) as value,
    CASE sname
        WHEN 'CPUSPEED' THEN 'CPU Speed (MHz) - Processor performance metric'
        WHEN 'IOSEEKTIM' THEN 'IO Seek Time (ms) - Storage subsystem seek time'
        WHEN 'IOTFRSPEED' THEN 'IO Transfer Speed (KB/s) - Storage throughput'
        WHEN 'SREADTIM' THEN 'Single Block Read Time (ms) - Random IO performance'
        WHEN 'MREADTIM' THEN 'Multi Block Read Time (ms) - Sequential IO performance'
        WHEN 'CPUSPEEDNW' THEN 'CPU Speed NoWait - CPU performance without waits'
        WHEN 'MBRC' THEN 'Multi Block Read Count - Blocks read in single IO'
        WHEN 'MAXTHR' THEN 'Maximum Throughput - Peak IO throughput'
        WHEN 'SLAVETHR' THEN 'Slave Throughput - Parallel execution throughput'
        ELSE 'System statistic for performance optimization'
    END as description
FROM sys.aux_stats$
WHERE sname IN ('CPUSPEED', 'IOSEEKTIM', 'IOTFRSPEED', 'SREADTIM', 'MREADTIM', 'CPUSPEEDNW', 'MBRC', 'MAXTHR', 'SLAVETHR')
UNION ALL
-- Fallback: Show system statistics status if no data in aux_stats$
SELECT 
    'SYSTEM_STATS_STATUS' as statistic_name,
    'NOT_GATHERED' as parameter_name,
    'No system statistics found' as value,
    'System statistics not gathered - Use DBMS_STATS.GATHER_SYSTEM_STATS to collect performance metrics' as description
FROM dual
WHERE NOT EXISTS (SELECT 1 FROM sys.aux_stats$ WHERE sname IN ('CPUSPEED', 'IOSEEKTIM', 'IOTFRSPEED', 'SREADTIM', 'MREADTIM'))
UNION ALL
-- Alternative: Show current system parameters for performance insights
SELECT 
    'DB_FILE_MULTIBLOCK_READ_COUNT' as statistic_name,
    'PARAMETER' as parameter_name,
    value as value,
    'Multi-block read count parameter - Affects sequential IO performance' as description
FROM v$parameter 
WHERE name = 'db_file_multiblock_read_count'
AND NOT EXISTS (SELECT 1 FROM sys.aux_stats$ WHERE sname IN ('CPUSPEED', 'IOSEEKTIM', 'IOTFRSPEED', 'SREADTIM', 'MREADTIM'))
UNION ALL
SELECT 
    'CPU_COUNT' as statistic_name,
    'PARAMETER' as parameter_name,
    value as value,
    'Number of CPUs available to Oracle - Affects parallel processing' as description
FROM v$parameter 
WHERE name = 'cpu_count'
AND NOT EXISTS (SELECT 1 FROM sys.aux_stats$ WHERE sname IN ('CPUSPEED', 'IOSEEKTIM', 'IOTFRSPEED', 'SREADTIM', 'MREADTIM'))
UNION ALL
SELECT 
    'PARALLEL_MAX_SERVERS' as statistic_name,
    'PARAMETER' as parameter_name,
    value as value,
    'Maximum parallel execution servers - Affects query performance' as description
FROM v$parameter 
WHERE name = 'parallel_max_servers'
AND NOT EXISTS (SELECT 1 FROM sys.aux_stats$ WHERE sname IN ('CPUSPEED', 'IOSEEKTIM', 'IOTFRSPEED', 'SREADTIM', 'MREADTIM'))
UNION ALL
-- Show wait events as performance indicators if no system stats
SELECT 
    'AVG_SINGLE_BLOCK_READ_TIME' as statistic_name,
    'WAIT_EVENT' as parameter_name,
    TO_CHAR(ROUND(average_wait, 2)) || ' ms' as value,
    'Average single block read time from wait events - Storage performance indicator' as description
FROM v$system_event 
WHERE event = 'db file sequential read'
AND total_waits > 0
AND NOT EXISTS (SELECT 1 FROM sys.aux_stats$ WHERE sname IN ('CPUSPEED', 'IOSEEKTIM', 'IOTFRSPEED', 'SREADTIM', 'MREADTIM'))
UNION ALL
SELECT 
    'AVG_MULTI_BLOCK_READ_TIME' as statistic_name,
    'WAIT_EVENT' as parameter_name,
    TO_CHAR(ROUND(average_wait, 2)) || ' ms' as value,
    'Average multi-block read time from wait events - Sequential IO performance indicator' as description
FROM v$system_event 
WHERE event = 'db file scattered read'
AND total_waits > 0
AND NOT EXISTS (SELECT 1 FROM sys.aux_stats$ WHERE sname IN ('CPUSPEED', 'IOSEEKTIM', 'IOTFRSPEED', 'SREADTIM', 'MREADTIM'))
ORDER BY statistic_name;
SELECT 'SYSTEM STATS INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'HUGEPAGES AND MEMORY INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'USE_LARGE_PAGES' as parameter,
    COALESCE(value, 'NOT SET (defaults to AUTO)') as current_value,
    CASE 
        WHEN value = 'TRUE' THEN 'HugePages ENABLED - 2MB page size (better performance, reduced TLB overhead)'
        WHEN value = 'FALSE' THEN 'HugePages DISABLED - 4KB page size (standard, higher memory overhead)'
        WHEN value = 'ONLY' THEN 'HugePages ONLY - Database fails if HugePages not available (strict mode)'
        WHEN value = 'AUTO' THEN 'HugePages AUTO - Oracle decides based on SGA size (recommended)'
        WHEN value IS NULL THEN 'HugePages setting not explicitly configured - Oracle uses AUTO mode by default'
        ELSE 'HugePages setting: ' || value || ' (non-standard value)'
    END as description
FROM v$parameter 
WHERE name = 'use_large_pages'
UNION ALL
SELECT 
    'HUGEPAGES_ACTUAL_USAGE' as parameter,
    CASE 
        WHEN EXISTS (SELECT 1 FROM v$sgainfo WHERE name = 'Granule Size' AND bytes >= 16777216)
        THEN 'HugePages DETECTED (Granule size >= 16MB indicates HugePages)'
        WHEN EXISTS (SELECT 1 FROM v$sgainfo WHERE name = 'Maximum SGA Size' AND resizeable = 'No')
             AND (SELECT COALESCE(value, 'AUTO') FROM v$parameter WHERE name = 'use_large_pages') != 'FALSE'
        THEN 'HugePages LIKELY (SGA not resizable + large pages not disabled)'
        WHEN EXISTS (SELECT 1 FROM v$sgainfo WHERE name = 'Maximum SGA Size' AND resizeable = 'Yes')
        THEN 'Standard 4KB pages (SGA is resizable - incompatible with HugePages)'
        WHEN (SELECT value FROM v$parameter WHERE name = 'memory_target') != '0'
        THEN 'Standard 4KB pages (AMM enabled - incompatible with HugePages)'
        ELSE 'Standard 4KB pages (HugePages not detected)'
    END as current_value,
    'HugePages detection using granule size and SGA resizeability analysis' as description
FROM dual
UNION ALL
SELECT 
    'SGA_GRANULE_SIZE' as parameter,
    CASE 
        WHEN EXISTS (SELECT 1 FROM v$sgainfo WHERE name = 'Granule Size')
        THEN TO_CHAR(ROUND((SELECT bytes FROM v$sgainfo WHERE name = 'Granule Size')/1024/1024, 2)) || ' MB'
        ELSE 'Not available'
    END as current_value,
    CASE 
        WHEN EXISTS (SELECT 1 FROM v$sgainfo WHERE name = 'Granule Size' AND bytes >= 16777216)
        THEN 'Large granule (>=16MB) indicates HugePages are active'
        WHEN EXISTS (SELECT 1 FROM v$sgainfo WHERE name = 'Granule Size' AND bytes < 16777216)
        THEN 'Small granule (<16MB) indicates standard 4KB pages'
        ELSE 'Granule size information not available'
    END as description
FROM dual
UNION ALL
SELECT 
    'MEMORY_TARGET' as parameter,
    CASE 
        WHEN value = '0' OR value IS NULL THEN '0 (DISABLED)'
        ELSE TO_CHAR(ROUND(TO_NUMBER(value)/1024/1024/1024, 2)) || ' GB'
    END as current_value,
    CASE 
        WHEN value = '0' OR value IS NULL THEN 'Automatic Memory Management DISABLED - Manual SGA/PGA tuning in use'
        ELSE 'AMM ENABLED with ' || TO_CHAR(ROUND(TO_NUMBER(value)/1024/1024/1024, 2)) || 'GB total - INCOMPATIBLE with HugePages'
    END as description
FROM v$parameter 
WHERE name = 'memory_target'
UNION ALL
SELECT 
    'SGA_TARGET' as parameter,
    CASE 
        WHEN value = '0' OR value IS NULL THEN '0 (AUTO SIZING)'
        ELSE TO_CHAR(ROUND(TO_NUMBER(value)/1024/1024/1024, 2)) || ' GB'
    END as current_value,
    CASE 
        WHEN value = '0' OR value IS NULL THEN 'SGA auto-sizing enabled - Oracle manages SGA components automatically'
        ELSE 'SGA fixed at ' || TO_CHAR(ROUND(TO_NUMBER(value)/1024/1024/1024, 2)) || 'GB - Suitable for HugePages configuration'
    END as description
FROM v$parameter 
WHERE name = 'sga_target'
UNION ALL
SELECT 
    'SGA_MAX_SIZE' as parameter,
    TO_CHAR(ROUND(TO_NUMBER(value)/1024/1024/1024, 2)) || ' GB' as current_value,
    'Maximum SGA size - Important for HugePages memory allocation planning' as description
FROM v$parameter 
WHERE name = 'sga_max_size'
UNION ALL
SELECT 
    'PGA_AGGREGATE_TARGET' as parameter,
    CASE 
        WHEN value = '0' OR value IS NULL THEN '0 (AUTO SIZING)'
        ELSE TO_CHAR(ROUND(TO_NUMBER(value)/1024/1024/1024, 2)) || ' GB'
    END as current_value,
    CASE 
        WHEN value = '0' OR value IS NULL THEN 'PGA auto-sizing - Oracle manages PGA memory automatically'
        ELSE 'PGA target set to ' || TO_CHAR(ROUND(TO_NUMBER(value)/1024/1024/1024, 2)) || 'GB - Consider for total memory planning'
    END as description
FROM v$parameter 
WHERE name = 'pga_aggregate_target'
UNION ALL
SELECT 
    'TOTAL_MEMORY_ESTIMATE' as parameter,
    TO_CHAR(ROUND(
        (SELECT TO_NUMBER(value) FROM v$parameter WHERE name = 'sga_max_size')/1024/1024/1024 +
        COALESCE((SELECT TO_NUMBER(value) FROM v$parameter WHERE name = 'pga_aggregate_target')/1024/1024/1024, 0)
    , 2)) || ' GB' as current_value,
    'Estimated total Oracle memory usage (SGA + PGA) for server sizing' as description
FROM dual
UNION ALL
SELECT 
    'HUGEPAGES_RECOMMENDATION' as parameter,
    CASE 
        WHEN (SELECT value FROM v$parameter WHERE name = 'memory_target') != '0' 
        THEN 'CRITICAL: Disable AMM (set memory_target=0) to enable HugePages'
        WHEN (SELECT COALESCE(value, 'AUTO') FROM v$parameter WHERE name = 'use_large_pages') = 'FALSE' 
        THEN 'RECOMMENDED: Set use_large_pages=AUTO or TRUE for better performance'
        WHEN (SELECT TO_NUMBER(value) FROM v$parameter WHERE name = 'sga_max_size') > 4*1024*1024*1024
        THEN 'HIGHLY RECOMMENDED: Large SGA detected - HugePages will significantly improve performance'
        ELSE 'HugePages configuration appears appropriate for current workload'
    END as current_value,
    'Migration recommendation based on current memory configuration and workload' as description
FROM dual;
SELECT 'HUGEPAGES AND MEMORY INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;


SELECT 'REDO LOG INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'REDO_LOG_SIZE_MB' as metric,
    TO_CHAR(ROUND(bytes/1024/1024, 2)) as value,
    'Current redo log file size in MB' as description
FROM v$log
WHERE rownum = 1
UNION ALL
SELECT 
    'TOTAL_REDO_GROUPS' as metric,
    TO_CHAR(COUNT(*)) as value,
    'Total number of redo log groups' as description
FROM v$log
UNION ALL
SELECT 
    'ARCHIVE_LOG_MODE' as metric,
    log_mode as value,
    CASE log_mode
        WHEN 'ARCHIVELOG' THEN 'Archive logging enabled - suitable for production'
        WHEN 'NOARCHIVELOG' THEN 'Archive logging disabled - not suitable for production'
        ELSE 'Unknown archive mode'
    END as description
FROM v$database;
SELECT 'REDO LOG INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'REDO GENERATION BY HOUR INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    TO_CHAR(first_time, 'YYYY-MM-DD') as log_date,
    TO_CHAR(first_time, 'HH24') as hour_of_day,
    COUNT(*) as log_switches,
    ROUND(COUNT(*) * (SELECT bytes/1024/1024 FROM v$log WHERE rownum=1), 2) as redo_mb_generated,
    CASE 
        WHEN COUNT(*) > 20 THEN 'HIGH - Potential performance impact'
        WHEN COUNT(*) > 10 THEN 'MEDIUM - Monitor during peak hours'
        ELSE 'LOW - Normal activity'
    END as activity_level
FROM v$log_history
WHERE first_time >= SYSDATE - 30
GROUP BY TO_CHAR(first_time, 'YYYY-MM-DD'), TO_CHAR(first_time, 'HH24')
ORDER BY log_date DESC, hour_of_day;
SELECT 'REDO GENERATION BY HOUR INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;


SELECT 'SQL PROFILE AND PLAN BASELINE INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 
    'SQL_PROFILES_COUNT' as object_type,
    TO_CHAR(COUNT(*)) as object_name,
    'Total number of SQL Profiles configured' as sql_text_preview,
    'N/A' as status,
    'N/A' as created_date
FROM dba_sql_profiles
UNION ALL
SELECT 
    'SQL_BASELINES_COUNT' as object_type,
    TO_CHAR(COUNT(*)) as object_name,
    'Total number of SQL Plan Baselines configured' as sql_text_preview,
    'N/A' as status,
    'N/A' as created_date
FROM dba_sql_plan_baselines
UNION ALL
SELECT 
    'SQL_PROFILE' as object_type,
    sp.name as object_name,
    SUBSTR(TO_CHAR(SUBSTR(sp.sql_text, 1, 4000)), 1, 50) as sql_text_preview,
    sp.status as status,
    TO_CHAR(sp.created, 'YYYY-MM-DD HH24:MI') as created_date
FROM dba_sql_profiles sp
WHERE rownum <= 10
UNION ALL
SELECT 
    'SQL_PLAN_BASELINE' as object_type,
    spb.sql_handle as object_name,
    SUBSTR(TO_CHAR(SUBSTR(spb.sql_text, 1, 4000)), 1, 50) as sql_text_preview,
    spb.enabled as status,
    TO_CHAR(spb.created, 'YYYY-MM-DD HH24:MI') as created_date
FROM dba_sql_plan_baselines spb
WHERE rownum <= 10
ORDER BY 1, 5 DESC;
SELECT 'SQL PROFILE AND PLAN BASELINE INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;


SELECT 'SQL PATCHES INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'SQL_PATCH_INFO' as metric,
    'SQL Patches feature not available or no patches applied' as value,
    'DBA_SQL_PATCHES view not found in this Oracle version' as description
FROM dual
WHERE NOT EXISTS (SELECT 1 FROM dba_objects WHERE object_name = 'DBA_SQL_PATCHES')
UNION ALL
SELECT 
    'SQL_PATCH_COUNT' as metric,
    TO_CHAR(COUNT(*)) as value,
    'Number of SQL patches applied (advanced tuning feature)' as description
FROM dba_sql_patches
WHERE EXISTS (SELECT 1 FROM dba_objects WHERE object_name = 'DBA_SQL_PATCHES');
SELECT 'SQL PATCHES INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'RESOURCE MANAGER INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'RESOURCE_MANAGER_PLAN' as parameter,
    value as current_value,
    CASE 
        WHEN value IS NULL OR value = '' THEN 'No Resource Manager plan active'
        ELSE 'Resource Manager plan: ' || value || ' (Resource caging active)'
    END as description
FROM v$parameter 
WHERE name = 'resource_manager_plan'
UNION ALL
SELECT 
    'RESOURCE_LIMIT' as parameter,
    value as current_value,
    CASE 
        WHEN value = 'TRUE' THEN 'Resource limits enforced'
        WHEN value = 'FALSE' THEN 'Resource limits not enforced'
        ELSE 'Unknown resource limit setting'
    END as description
FROM v$parameter 
WHERE name = 'resource_limit';
SELECT 'RESOURCE MANAGER INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'RESOURCE MANAGER PLAN AND CONSUMER GROUP INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'RESOURCE_PLAN_STATUS' as metric,
    CASE 
        WHEN COUNT(*) > 0 THEN 'Resource Manager plans are configured'
        ELSE 'No Resource Manager plans found'
    END as value,
    'Resource Manager plan configuration status' as description
FROM v$rsrc_plan
UNION ALL
SELECT 
    'CURRENT_PLAN' as metric,
    COALESCE(value, 'No plan active') as value,
    'Currently active Resource Manager plan' as description
FROM v$parameter 
WHERE name = 'resource_manager_plan'
UNION ALL
SELECT 
    'CONSUMER_GROUPS_COUNT' as metric,
    TO_CHAR(COUNT(*)) as value,
    'Number of Resource Manager consumer groups configured' as description
FROM v$rsrc_consumer_group
WHERE name != 'SYS_GROUP';
SELECT 'RESOURCE MANAGER PLAN AND CONSUMER GROUP INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'RAC INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'CLUSTER_DATABASE' as parameter,
    value as current_value,
    CASE 
        WHEN value = 'TRUE' THEN 'RAC ENABLED - This is a Real Application Cluster'
        WHEN value = 'FALSE' THEN 'RAC DISABLED - Single instance database'
        ELSE 'Unknown RAC status'
    END as description
FROM v$parameter 
WHERE name = 'cluster_database'
UNION ALL
SELECT 
    'CLUSTER_DATABASE_INSTANCES' as parameter,
    value as current_value,
    'Number of instances in RAC cluster' as description
FROM v$parameter 
WHERE name = 'cluster_database_instances'
UNION ALL
SELECT 
    'INSTANCE_NUMBER' as parameter,
    TO_CHAR(instance_number) as current_value,
    'Current instance number in RAC cluster' as description
FROM v$instance;
SELECT 'RAC INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'RAC CLUSTER NODE INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'TOTAL_RAC_NODES' as metric,
    TO_CHAR(COUNT(*)) as value,
    'Total number of nodes in RAC cluster - Critical for SKU sizing' as description
FROM gv$instance
UNION ALL
SELECT 
    'CURRENT_NODE_' || inst_id as metric,
    instance_name || ' (' || host_name || ')' as value,
    'Instance ' || inst_id || ' running on host: ' || host_name as description
FROM gv$instance
ORDER BY metric;
SELECT 'RAC CLUSTER NODE INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'DB BLOCK INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'DB_BLOCK_SIZE' as parameter,
    value as current_value,
    'Database block size (affects storage and memory calculations)' as description
FROM v$parameter 
WHERE name = 'db_block_size'
UNION ALL
SELECT 
    'COMPATIBLE' as parameter,
    value as current_value,
    'Database compatibility version (affects feature availability)' as description
FROM v$parameter 
WHERE name = 'compatible'
UNION ALL
SELECT 
    'DB_RECOVERY_FILE_DEST_SIZE' as parameter,
    TO_CHAR(ROUND(TO_NUMBER(value)/1024/1024/1024, 2)) as current_value,
    'Fast Recovery Area size in GB' as description
FROM v$parameter 
WHERE name = 'db_recovery_file_dest_size' AND value IS NOT NULL;
SELECT 'DB BLOCK INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;


SELECT 'SERVICES INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'TOTAL_SERVICES' as metric,
    TO_CHAR(COUNT(*)) as value,
    'Total number of database services configured' as description
FROM dba_services 
WHERE name NOT IN ('SYS$BACKGROUND', 'SYS$USERS')
UNION ALL
SELECT 
    'SERVICE_INFO' as metric,
    name as value,
    'Database service: ' || name || ' (Network name: ' || network_name || ')' as description
FROM dba_services 
WHERE name NOT IN ('SYS$BACKGROUND', 'SYS$USERS')
AND rownum <= 10;
SELECT 'SERVICES INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'EXADATA INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'IS_EXADATA' as metric,
    CASE 
        WHEN COUNT(*) > 0 THEN 'YES - This is an Exadata system'
        ELSE 'NO - This is not an Exadata system'
    END as value,
    'Exadata detection based on cell services' as description
FROM v$cell_state
WHERE rownum = 1
UNION ALL
SELECT 
    'EXADATA_VERSION' as metric,
    CASE 
        WHEN EXISTS (SELECT 1 FROM v$cell_state WHERE rownum = 1) 
        THEN 'Exadata system detected - Use cell commands for version details'
        ELSE 'N/A - Not an Exadata system'
    END as value,
    'Exadata software version requires cell command access' as description
FROM dual;
SELECT 'EXADATA INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;


SELECT 'DB SIZE INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    'TOTAL_DATABASE_SIZE_GB' as metric,
    TO_CHAR(ROUND(SUM(bytes)/1024/1024/1024, 2)) as value,
    'Total database size across all datafiles and tempfiles' as description
FROM (
    SELECT bytes FROM v$datafile
    UNION ALL
    SELECT bytes FROM v$tempfile
)
UNION ALL
SELECT 
    'DATAFILES_SIZE_GB' as metric,
    TO_CHAR(ROUND(SUM(bytes)/1024/1024/1024, 2)) as value,
    'Total size of permanent datafiles (excludes temp files)' as description
FROM v$datafile
UNION ALL
SELECT 
    'TEMPFILES_SIZE_GB' as metric,
    TO_CHAR(ROUND(SUM(bytes)/1024/1024/1024, 2)) as value,
    'Total size of temporary datafiles' as description
FROM v$tempfile
UNION ALL
SELECT 
    'USED_SPACE_GB' as metric,
    TO_CHAR(ROUND(SUM(bytes - NVL(free_space, 0))/1024/1024/1024, 2)) as value,
    'Total used space in database (allocated minus free space)' as description
FROM (
    SELECT 
        ts.tablespace_name,
        ts.bytes,
        fs.free_space
    FROM (
        SELECT tablespace_name, SUM(bytes) as bytes
        FROM dba_data_files
        GROUP BY tablespace_name
    ) ts
    LEFT JOIN (
        SELECT tablespace_name, SUM(bytes) as free_space
        FROM dba_free_space
        GROUP BY tablespace_name
    ) fs ON ts.tablespace_name = fs.tablespace_name
)
UNION ALL
SELECT 
    'FREE_SPACE_GB' as metric,
    TO_CHAR(ROUND(SUM(NVL(free_space, 0))/1024/1024/1024, 2)) as value,
    'Total free space available in database' as description
FROM (
    SELECT 
        ts.tablespace_name,
        ts.bytes,
        fs.free_space
    FROM (
        SELECT tablespace_name, SUM(bytes) as bytes
        FROM dba_data_files
        GROUP BY tablespace_name
    ) ts
    LEFT JOIN (
        SELECT tablespace_name, SUM(bytes) as free_space
        FROM dba_free_space
        GROUP BY tablespace_name
    ) fs ON ts.tablespace_name = fs.tablespace_name
)
UNION ALL
SELECT 
    'SPACE_UTILIZATION_PCT' as metric,
    TO_CHAR(ROUND(
        (SUM(bytes - NVL(free_space, 0)) / SUM(bytes)) * 100, 2
    )) || '%' as value,
    'Database space utilization percentage (used/total)' as description
FROM (
    SELECT 
        ts.tablespace_name,
        ts.bytes,
        fs.free_space
    FROM (
        SELECT tablespace_name, SUM(bytes) as bytes
        FROM dba_data_files
        GROUP BY tablespace_name
    ) ts
    LEFT JOIN (
        SELECT tablespace_name, SUM(bytes) as free_space
        FROM dba_free_space
        GROUP BY tablespace_name
    ) fs ON ts.tablespace_name = fs.tablespace_name
)
UNION ALL
SELECT 
    'TOTAL_TABLESPACES' as metric,
    TO_CHAR(COUNT(*)) as value,
    'Total number of tablespaces in database' as description
FROM dba_tablespaces
WHERE status = 'ONLINE'
UNION ALL
SELECT 
    'LARGEST_TABLESPACE_GB' as metric,
    TO_CHAR(ROUND(MAX(bytes)/1024/1024/1024, 2)) as value,
    'Size of largest tablespace in database' as description
FROM (
    SELECT tablespace_name, SUM(bytes) as bytes
    FROM dba_data_files
    GROUP BY tablespace_name
)
UNION ALL
SELECT 
    'TOTAL_SEGMENTS' as metric,
    TO_CHAR(COUNT(*)) as value,
    'Total number of database segments (tables, indexes, etc.)' as description
FROM dba_segments
WHERE owner NOT IN ('SYS', 'SYSTEM', 'SYSAUX', 'SYSMAN', 'DBSNMP')
UNION ALL
SELECT 
    'LARGEST_SEGMENT_GB' as metric,
    TO_CHAR(ROUND(MAX(bytes)/1024/1024/1024, 2)) as value,
    'Size of largest database segment' as description
FROM dba_segments
WHERE owner NOT IN ('SYS', 'SYSTEM', 'SYSAUX', 'SYSMAN', 'DBSNMP');
SELECT 'DB SIZE INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;

SELECT 'TOP 20 TABLESPACE SIZE INFO BEGIN' AS Query_Description,CURRENT_TIMESTAMP FROM dual;
SELECT 
    tablespace_name,
    TO_CHAR(ROUND(total_size_gb, 2)) || ' GB' as total_size_gb,
    TO_CHAR(ROUND(used_size_gb, 2)) || ' GB' as used_size_gb,
    TO_CHAR(ROUND(free_size_gb, 2)) || ' GB' as free_size_gb,
    TO_CHAR(ROUND(utilization_pct, 2)) || '%' as utilization_pct,
    CASE 
        WHEN utilization_pct > 95 THEN 'CRITICAL - Immediate attention needed'
        WHEN utilization_pct > 85 THEN 'WARNING - Monitor closely'
        WHEN utilization_pct > 70 THEN 'NORMAL - Good utilization'
        ELSE 'LOW - Consider cleanup or optimization'
    END as status
FROM (
    SELECT 
        ts.tablespace_name,
        ts.total_size_gb,
        NVL(us.used_size_gb, 0) as used_size_gb,
        ts.total_size_gb - NVL(us.used_size_gb, 0) as free_size_gb,
        CASE 
            WHEN ts.total_size_gb > 0 THEN 
                (NVL(us.used_size_gb, 0) / ts.total_size_gb) * 100
            ELSE 0
        END as utilization_pct
    FROM (
        SELECT tablespace_name, SUM(bytes)/1024/1024/1024 as total_size_gb
        FROM dba_data_files
        GROUP BY tablespace_name
    ) ts
    LEFT JOIN (
        SELECT 
            tablespace_name, 
            (SUM(bytes) - NVL(SUM(free_bytes), 0))/1024/1024/1024 as used_size_gb
        FROM (
            SELECT tablespace_name, bytes, 0 as free_bytes
            FROM dba_data_files
            UNION ALL
            SELECT tablespace_name, 0 as bytes, bytes as free_bytes
            FROM dba_free_space
        )
        GROUP BY tablespace_name
    ) us ON ts.tablespace_name = us.tablespace_name
    WHERE ts.tablespace_name NOT LIKE '%TEMP%'
    ORDER BY ts.total_size_gb DESC
)
WHERE rownum <= 20;
SELECT 'TOP 20 TABLESPACE SIZE INFO END' AS Query_Description,CURRENT_TIMESTAMP FROM dual;


--------------------------------------------------------------------------------
-- 1. NOT IN SCOPE OBJECTS REPORT
--------------------------------------------------------------------------------
SELECT 'NOT IN SCOPE OBJECTS INFO BEGIN' AS Query_Description, CURRENT_TIMESTAMP FROM dual;

SELECT owner,
       object_name,
       object_type
FROM (
    /* Objets standards */
    SELECT owner,
           object_name,
           object_type
    FROM   dba_objects
    WHERE  object_type IN (
        'ASSEMBLY',
        'ATTRIBUTE DIMENSION',
        'CLUSTER',
        'CONTEXT',
        'CUBE',
        'DIMENSION',
        'EDITION',
        'FLASHBACK ARCHIVE',
        'HIERARCHY',
        'INDEXTYPE',
        'INMEMORY JOIN GROUP',
        'JAVA CLASS',
        'JAVA SOURCE',
        'JAVA RESOURCE',
        'LIBRARY',
        'LOB',
        'LOB PARTITION',
        'LOB SUBPARTITION',
        'MATERIALIZED VIEW LOG',
        'MATERIALIZED ZONEMAP',
        'MINING MODEL',
        'OPERATOR',
        'OUTLINE',
        'ROLLBACK SEGMENT',
        'SUMMARY'
    )
and owner not in ('SYS','SYSTEM','XDB','MDSYS','CTXSYS','WMSYS','ORDSYS',
        'ORDDATA','ORDPLUGINS','OWBSYS','OWBSYS_AUDIT','SYSMAN','DBSNMP',
        'APPQOSSYS','FLOWS_FILES','PUBLIC','OE','SH','SCOTT','PM','HR',
        'BI','IX','EXFSYS','ORACLE_OCM','SI_INFORMTN_SCHEMA','AUDSYS',
        'DBSFWUSER','DVF','DVSYS','GSMADMIN_INTERNAL','REMOTE_SCHEDULER_AGENT',
        'LBACSYS','OJVMSYS','OLAPSYS')
    UNION ALL
    /* Synonyms (y compris PUBLIC) */
    SELECT owner,
           synonym_name,
           'SYNONYM'
    FROM   dba_synonyms  
where table_owner not in ('SYS','SYSTEM','XDB','MDSYS','CTXSYS','WMSYS','ORDSYS',
        'ORDDATA','ORDPLUGINS','OWBSYS','OWBSYS_AUDIT','SYSMAN','DBSNMP',
        'APPQOSSYS','FLOWS_FILES','PUBLIC','OE','SH','SCOTT','PM','HR',
        'BI','IX','EXFSYS','ORACLE_OCM','SI_INFORMTN_SCHEMA','AUDSYS',
        'DBSFWUSER','DVF','DVSYS','GSMADMIN_INTERNAL','REMOTE_SCHEDULER_AGENT',
        'LBACSYS','OJVMSYS','OLAPSYS')
    UNION ALL
    /* Database links */
    SELECT owner,
           db_link,
           'DATABASE LINK'
    FROM   dba_db_links
    UNION ALL
    /* Profiles */
    SELECT DISTINCT
           profile,
           profile,
           'PROFILE'
    FROM   dba_profiles 
    UNION ALL
    /* Directories */
    SELECT owner,
           directory_name,
           'DIRECTORY'
    FROM   dba_directories
    UNION ALL
    /* Restore points */
    SELECT 'SYS' AS owner,
           name,
           'RESTORE POINT'
    FROM   v$restore_point
    UNION ALL
    /* Refresh groups */
    SELECT ROWNER,
           rname,
           'REFRESH GROUP'
    FROM   dba_refresh
    UNION ALL
    /* Audit policies */
    SELECT 'SYS',
           policy_name,
           'AUDIT POLICY'
    FROM   dba_audit_policies
    UNION ALL
    /* Lockdown profiles (CDB) */
    SELECT 'SYS',
           profile_name,
           'LOCKDOWN PROFILE'
    FROM   dba_lockdown_profiles
    UNION ALL
    /* Pluggable databases */
    SELECT 'SYS',
           name,
           'PLUGGABLE DATABASE'
    FROM   v$pdbs
    UNION ALL
    /* ASM Disk Groups (si visibles) */
    SELECT 'ASM',
           name,
           'DISK GROUP'
    FROM   v$asm_diskgroup
)
ORDER BY object_type, owner, object_name;




SELECT 'NOT IN SCOPE OBJECTS INFO END' AS Query_Description, CURRENT_TIMESTAMP FROM dual;

--------------------------------------------------------------------------------
-- 2. WRAPPED OBJECTS REPORT
--------------------------------------------------------------------------------
SELECT 'WRAPPED OBJECTS INFO BEGIN' AS Query_Description, CURRENT_TIMESTAMP FROM dual;

SELECT
    (SELECT instance_name FROM v$instance) AS instance_name,
    a.owner,
    a.object_name,
    a.object_type,
    a.status
FROM dba_objects a
WHERE a.owner NOT IN (
        'SYS','SYSTEM','OUTLN','XDB','MDSYS','CTXSYS','WMSYS','ORDSYS',
        'ORDDATA','ORDPLUGINS','OWBSYS','OWBSYS_AUDIT','SYSMAN','DBSNMP',
        'APPQOSSYS','FLOWS_FILES','PUBLIC','OE','SH','SCOTT','PM','HR',
        'BI','IX','EXFSYS','ORACLE_OCM','SI_INFORMTN_SCHEMA','AUDSYS',
        'DBSFWUSER','DVF','DVSYS','GSMADMIN_INTERNAL','REMOTE_SCHEDULER_AGENT',
        'LBACSYS','OJVMSYS','OLAPSYS'
			)
  AND EXISTS (
        SELECT 1
        FROM all_source b
        WHERE b.owner = a.owner
          AND b.name = a.object_name
          AND b.line = 1
          AND UPPER(b.text) LIKE '%WRAPPED%'
      )
ORDER BY a.owner, a.object_type, a.object_name;

SELECT 'WRAPPED OBJECTS INFO END' AS Query_Description, CURRENT_TIMESTAMP FROM dual;

--------------------------------------------------------------------------------
-- 3. INVALID OBJECTS REPORT
--------------------------------------------------------------------------------
SELECT 'INVALID OBJECTS INFO BEGIN' AS Query_Description, CURRENT_TIMESTAMP FROM dual;

SELECT
    (SELECT instance_name FROM v$instance) AS instance_name,
    owner,
    object_name,
    object_type,
    status
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN (
        'SYS','SYSTEM','OUTLN','XDB','MDSYS','CTXSYS','WMSYS','ORDSYS',
        'ORDDATA','ORDPLUGINS','OWBSYS','OWBSYS_AUDIT','SYSMAN','DBSNMP',
        'APPQOSSYS','FLOWS_FILES','PUBLIC','OE','SH','SCOTT','PM','HR',
        'BI','IX','EXFSYS','ORACLE_OCM','SI_INFORMTN_SCHEMA','AUDSYS',
        'DBSFWUSER','DVF','DVSYS','GSMADMIN_INTERNAL','REMOTE_SCHEDULER_AGENT',
        'LBACSYS','OJVMSYS','OLAPSYS'
		)
ORDER BY owner, object_type, object_name;

SELECT 'INVALID OBJECTS INFO END' AS Query_Description, CURRENT_TIMESTAMP FROM dual;

SELECT 'LOB INFO BEGIN' AS Query_Description, CURRENT_TIMESTAMP FROM dual;
SELECT 
       l.owner,
       COUNT(*)                           AS lob_count,
       SUM(s.bytes)/1024/1024             AS total_lob_size_mb,
       MAX(s.bytes)/1024/1024             AS largest_lob_size_mb,
       MIN(s.bytes)/1024/1024             AS smallest_lob_size_mb
FROM   dba_lobs l
       JOIN dba_segments s
            ON l.segment_name = s.segment_name
           AND l.owner = s.owner
WHERE  l.owner NOT IN (
        'SYS','SYSTEM','OUTLN','XDB','MDSYS','CTXSYS','WMSYS',
        'ORDSYS','ORDDATA','ORDPLUGINS','OWBSYS','OWBSYS_AUDIT',
        'SYSMAN','DBSNMP','APPQOSSYS','FLOWS_FILES','PUBLIC',
        'OE','SH','SCOTT','PM','HR','BI','IX','EXFSYS',
        'ORACLE_OCM','SI_INFORMTN_SCHEMA','AUDSYS','DBSFWUSER',
        'DVF','DVSYS','GSMADMIN_INTERNAL','REMOTE_SCHEDULER_AGENT',
        'LBACSYS'
       )
GROUP BY l.owner
ORDER BY total_lob_size_mb DESC;
SELECT 'LOB INFO END' AS Query_Description, CURRENT_TIMESTAMP FROM dual;



SELECT 'SUMMARY COUNTS PER SCHEMA BEGIN' AS Query_Description, CURRENT_TIMESTAMP FROM dual;

SELECT
    o.owner AS schema,
    NVL(inv.invalid_cnt, 0) AS invalid_objects,
    NVL(lob.lob_cnt, 0)     AS lob_objects,
    NVL(nis.nis_cnt, 0)     AS unsupported_objects,
    NVL(wrp.wrapped_cnt, 0) AS wrapped_objects
FROM
    ( SELECT DISTINCT owner
      FROM dba_objects
      WHERE owner NOT IN (
          'SYS','SYSTEM','OUTLN','XDB','MDSYS','CTXSYS','WMSYS','ORDSYS',
          'ORDDATA','ORDPLUGINS','OWBSYS','OWBSYS_AUDIT','SYSMAN','DBSNMP',
          'APPQOSSYS','FLOWS_FILES','PUBLIC','OE','SH','SCOTT','PM','HR',
          'BI','IX','EXFSYS','ORACLE_OCM','SI_INFORMTN_SCHEMA','AUDSYS',
          'DBSFWUSER','DVF','DVSYS','GSMADMIN_INTERNAL',
          'REMOTE_SCHEDULER_AGENT','LBACSYS','OJVMSYS','OLAPSYS'
      )
    ) o
LEFT JOIN
    ( SELECT owner, COUNT(*) invalid_cnt
      FROM dba_objects
      WHERE status = 'INVALID'
      GROUP BY owner
    ) inv
ON o.owner = inv.owner
LEFT JOIN
    ( SELECT owner, COUNT(*) lob_cnt
      FROM dba_lobs
      GROUP BY owner
    ) lob
ON o.owner = lob.owner
LEFT JOIN
    ( SELECT owner, COUNT(*) nis_cnt
      FROM dba_objects
      WHERE object_type IN (
          'ASSEMBLY','ATTRIBUTE DIMENSION','CLUSTER','CONTEXT','CUBE',
          'DIMENSION','EDITION','FLASHBACK ARCHIVE','HIERARCHY',
          'INDEXTYPE','INMEMORY JOIN GROUP','JAVA CLASS','JAVA SOURCE',
          'JAVA RESOURCE','LIBRARY','LOB','LOB PARTITION',
          'LOB SUBPARTITION','MATERIALIZED VIEW LOG',
          'MATERIALIZED ZONEMAP','MINING MODEL','OPERATOR','OUTLINE',
          'ROLLBACK SEGMENT','SUMMARY'
      )
      GROUP BY owner
    ) nis
ON o.owner = nis.owner
LEFT JOIN
    ( SELECT a.owner, COUNT(*) wrapped_cnt
      FROM dba_objects a
      WHERE EXISTS (
          SELECT 1
          FROM all_source s
          WHERE s.owner = a.owner
            AND s.name  = a.object_name
            AND s.line  = 1
            AND UPPER(s.text) LIKE '%WRAPPED%'
      )
      GROUP BY a.owner
    ) wrp
ON o.owner = wrp.owner;

SELECT owner,
       object_type,
       COUNT(*) AS count
FROM (
    /* Standard Objects */
    SELECT owner,
           object_name,
           object_type
    FROM   dba_objects
    WHERE  object_type IN (
        'ASSEMBLY',
        'ATTRIBUTE DIMENSION',
        'CLUSTER',
        'CONTEXT',
        'CUBE',
        'DIMENSION',
        'EDITION',
        'FLASHBACK ARCHIVE',
        'HIERARCHY',
        'INDEXTYPE',
        'INMEMORY JOIN GROUP',
        'JAVA CLASS',
        'JAVA SOURCE',
        'JAVA RESOURCE',
        'LIBRARY',
        'LOB',
        'LOB PARTITION',
        'LOB SUBPARTITION',
        'MATERIALIZED VIEW LOG',
        'MATERIALIZED ZONEMAP',
        'MINING MODEL',
        'OPERATOR',
        'OUTLINE',
        'ROLLBACK SEGMENT',
        'SUMMARY'
    )
    AND owner NOT IN ('SYS','SYSTEM','XDB','MDSYS','CTXSYS','WMSYS','ORDSYS',
        'ORDDATA','ORDPLUGINS','OWBSYS','OWBSYS_AUDIT','SYSMAN','DBSNMP',
        'APPQOSSYS','FLOWS_FILES','PUBLIC','OE','SH','SCOTT','PM','HR',
        'BI','IX','EXFSYS','ORACLE_OCM','SI_INFORMTN_SCHEMA','AUDSYS',
        'DBSFWUSER','DVF','DVSYS','GSMADMIN_INTERNAL','REMOTE_SCHEDULER_AGENT',
        'LBACSYS','OJVMSYS','OLAPSYS')
    UNION ALL
    /* Synonyms */
    SELECT owner,
           synonym_name,
           'SYNONYM'
    FROM   dba_synonyms  
    WHERE owner NOT IN ('SYS','SYSTEM','XDB','MDSYS','CTXSYS','WMSYS','ORDSYS',
        'ORDDATA','ORDPLUGINS','OWBSYS','OWBSYS_AUDIT','SYSMAN','DBSNMP',
        'APPQOSSYS','FLOWS_FILES','PUBLIC','OE','SH','SCOTT','PM','HR',
        'BI','IX','EXFSYS','ORACLE_OCM','SI_INFORMTN_SCHEMA','AUDSYS',
        'DBSFWUSER','DVF','DVSYS','GSMADMIN_INTERNAL','REMOTE_SCHEDULER_AGENT',
        'LBACSYS','OJVMSYS','OLAPSYS')
    UNION ALL
    /* Database links */
    SELECT owner,
           db_link,
           'DATABASE LINK'
    FROM   dba_db_links
    UNION ALL
    /* Profiles */
    SELECT DISTINCT
           profile AS owner,
           profile AS object_name,
           'PROFILE' AS object_type
    FROM   dba_profiles
    UNION ALL
    /* Directories */
    SELECT owner,
           directory_name,
           'DIRECTORY'
    FROM   dba_directories
    UNION ALL
    /* Restore points */
    SELECT 'SYS' AS owner,
           name AS object_name,
           'RESTORE POINT' AS object_type
    FROM   v$restore_point
    UNION ALL
    /* Refresh groups */
    SELECT ROWNER AS owner,
           rname AS object_name,
           'REFRESH GROUP' AS object_type
    FROM   dba_refresh
    UNION ALL
    /* Audit policies */
    SELECT 'SYS' AS owner,
           policy_name AS object_name,
           'AUDIT POLICY' AS object_type
    FROM   dba_audit_policies
    UNION ALL
    /* Lockdown profiles (CDB) */
    SELECT 'SYS' AS owner,
           profile_name AS object_name,
           'LOCKDOWN PROFILE' AS object_type
    FROM   dba_lockdown_profiles
    UNION ALL
    /* Pluggable databases */
    SELECT 'SYS' AS owner,
           name AS object_name,
           'PLUGGABLE DATABASE' AS object_type
    FROM   v$pdbs
    UNION ALL
    /* ASM Disk Groups */
    SELECT 'ASM' AS owner,
           name AS object_name,
           'DISK GROUP' AS object_type
    FROM   v$asm_diskgroup
)
GROUP BY owner, object_type
ORDER BY owner, object_type;


SELECT 'SUMMARY COUNTS PER SCHEMA END' AS Query_Description, CURRENT_TIMESTAMP FROM dual;



SELECT 'ORACLE SYSTEM SUMMARY BEGIN' AS Query_Description, CURRENT_TIMESTAMP FROM dual;

-- Current Oracle Version(s)
SELECT 'ORACLE_VERSION' AS metric,
       version AS value,
       'Oracle database version' AS description
FROM v$instance;

-- Number of Oracle instances (across cluster)
SELECT 'ORACLE_INSTANCES_COUNT' AS metric,
       COUNT(*) AS value,
       'Total Oracle instances detected' AS description
FROM gv$instance;

-- Number of RAC Clusters

SELECT 'RAC_INSTANCES_COUNT' AS metric,
       COUNT(*) AS value,
       'Total RAC instances detected' AS description
FROM gv$instance;

-- Number of Exadata Instances
SELECT 'EXADATA_INSTANCES_COUNT' AS metric,
       COUNT(DISTINCT inst_id) AS value,
       'Total Exadata instances (detected via cell services)' AS description
FROM gv$instance i
WHERE EXISTS (SELECT 1 FROM v$cell_state c WHERE ROWNUM = 1);

-- Total Oracle CPU cores
 

SELECT 'TOTAL_CPU_CORES' AS metric,
       value AS cpu_cores,
       'Total number of CPU cores available to Oracle' AS description
FROM v$parameter
WHERE name = 'cpu_count';
-- Number of Oracle Databases (CDB + PDBs)
SELECT 'TOTAL_DATABASES' AS metric,
       (SELECT COUNT(*) FROM v$database) + (SELECT COUNT(*) FROM v$pdbs) AS value,
       'Total databases including root + PDBs' AS description
FROM dual;

-- Total size of all databases
SELECT 'TOTAL_DB_SIZE_GB' AS metric,
       TO_CHAR(ROUND(SUM(bytes)/1024/1024/1024,2)) AS value,
       'Total size of all datafiles and tempfiles across all databases' AS description
FROM (
    SELECT bytes FROM v$datafile
    UNION ALL
    SELECT bytes FROM v$tempfile
);

-- Number of schemas (excluding default Oracle ones)
SELECT 'TOTAL_SCHEMAS' AS metric,
       COUNT(*) AS value,
       'Number of user schemas excluding SYS, SYSTEM, etc.' AS description
FROM dba_users
WHERE username NOT IN ('SYS','SYSTEM','OUTLN','XDB','MDSYS','CTXSYS','WMSYS','ORDSYS',
                       'ORDDATA','ORDPLUGINS','OWBSYS','OWBSYS_AUDIT','SYSMAN','DBSNMP',
                       'APPQOSSYS','FLOWS_FILES','PUBLIC','OE','SH','SCOTT','PM','HR',
                       'BI','IX','EXFSYS','ORACLE_OCM','SI_INFORMTN_SCHEMA','AUDSYS',
                       'DBSFWUSER','DVF','DVSYS','GSMADMIN_INTERNAL','REMOTE_SCHEDULER_AGENT',
                       'LBACSYS','OJVMSYS','OLAPSYS');

-- Summary Table: Cores, Memory, #Schemas, DB Size
SELECT 
    /* CPU cores */
    (SELECT value 
     FROM v$parameter 
     WHERE name = 'cpu_count') AS proc_cores,
    /* Memory */
    (SELECT ROUND(value/1024/1024/1024,2)
     FROM v$parameter
     WHERE name = 'sga_max_size') AS memory_gb,
    /* Schemas */
    (SELECT COUNT(*)
     FROM dba_users
     WHERE oracle_maintained = 'N') AS num_schemas,
    /* Database size */
    (SELECT ROUND(SUM(bytes)/1024/1024/1024,2)
     FROM v$datafile) AS total_db_size_gb
FROM dual;

SELECT 'ORACLE SYSTEM SUMMARY END' AS Query_Description, CURRENT_TIMESTAMP FROM dual;

exit;
