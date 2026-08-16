using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using System.Text;

namespace AssessmentToolkit.Api.Services;

public static class OfflineAssessmentScriptFactory
{
    public static (string PluginId, string Script) Create(DatabaseInstance database)
    {
        var pluginId = GetPluginId(database.Engine);
        var sections = GetSections(database.Engine);
        var command = GetCommand(database.Engine);
        var credentialSetup = GetCredentialSetup(database.Engine);
        var defaultFileName = $"assessment-{SanitizeFileName(database.Name)}.json";
        var sectionDefinitions = string.Join(Environment.NewLine, sections.Select(section =>
            $"    [ordered]@{{ name = {PowerShellLiteral(section.Key)}; query = {PowerShellLiteral(section.Value)} }}"));

        var script = $$"""
            # Database Migration Assessment Toolkit - offline metadata collector
            # Database: {{database.Name}} ({{database.Engine}})
            # This script performs read-only metadata queries and does not collect table data.
            # Prerequisite: the native database CLI must be installed and available on PATH.

            param(
                [Parameter(Mandatory = $true)]
                [string]$Username,
                [string]$OutputPath = "./{{defaultFileName}}"
            )

            $ErrorActionPreference = "Stop"
            $HostName = {{PowerShellLiteral(database.HostName ?? "localhost")}}
            $DatabaseName = {{PowerShellLiteral(database.Name)}}
            $Port = {{database.Port ?? GetDefaultPort(database.Engine)}}
            {{credentialSetup}}

            $sectionDefinitions = @(
            {{sectionDefinitions}}
            )

            try {
                $sections = [ordered]@{}
                foreach ($sectionDefinition in $sectionDefinitions) {
                    $query = $sectionDefinition.query
                    try {
            {{Indent(command, 12)}}
                        if ($LASTEXITCODE -ne 0) {
                            throw ($rawOutput -join [Environment]::NewLine)
                        }
                        $sections[$sectionDefinition.name] = [ordered]@{
                            status = "success"
                            rawOutput = ($rawOutput -join [Environment]::NewLine)
                        }
                    }
                    catch {
                        $errorMessage = $_.Exception.Message
                        if ($password) {
                            $errorMessage = $errorMessage.Replace($password, "[redacted]")
                        }
                        $sections[$sectionDefinition.name] = [ordered]@{
                            status = "failed"
                            error = $errorMessage
                        }
                    }
                }

                $finding = [ordered]@{
                    contractVersion = "2.0"
                    databaseName = $DatabaseName
                    engine = {{PowerShellLiteral(database.Engine.ToString())}}
                    host = $HostName
                    port = $Port
                    collectedBy = "offline-script"
                    sections = $sections
                }
                $result = [ordered]@{
                    schemaVersion = "1.0"
                    databaseId = {{PowerShellLiteral(database.DatabaseId.ToString())}}
                    pluginId = {{PowerShellLiteral(pluginId)}}
                    pluginVersion = "offline-2.0"
                    assessedAt = [DateTimeOffset]::UtcNow.ToString("o")
                    findingJson = $finding
                    rawSummaryJson = [ordered]@{
                        source = "customer-executed-script"
                        databaseName = $DatabaseName
                        engine = {{PowerShellLiteral(database.Engine.ToString())}}
                    }
                }

                $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8
                Write-Host "Assessment result written to $OutputPath"
            }
            finally {
                $password = $null
                Remove-Item Env:PGPASSWORD, Env:MYSQL_PWD, Env:SQLCMDPASSWORD -ErrorAction SilentlyContinue
                if ($credentialsPath) {
                    Remove-Item -LiteralPath $credentialsPath -Force -ErrorAction SilentlyContinue
                }
            }
            """;

        return (pluginId, script);
    }

    public static string GetPluginId(EngineType engine) => engine switch
    {
        EngineType.Oracle => "oracle",
        EngineType.PostgreSQL => "postgresql",
        EngineType.SqlServer => "sqlserver",
        EngineType.MySQL => "mysql",
        EngineType.MongoDB => "mongodb",
        EngineType.Cassandra => "cassandra",
        EngineType.Sybase => "sybase",
        _ => throw new NotSupportedException($"Offline assessment is not supported for engine '{engine}'.")
    };

    private static int GetDefaultPort(EngineType engine) => engine switch
    {
        EngineType.Oracle => 1521,
        EngineType.PostgreSQL => 5432,
        EngineType.SqlServer => 1433,
        EngineType.MySQL => 3306,
        EngineType.MongoDB => 27017,
        EngineType.Cassandra => 9042,
        EngineType.Sybase => 5000,
        _ => 0
    };

    private static string GetCommand(EngineType engine) => engine switch
    {
        EngineType.PostgreSQL => """
            $env:PGPASSWORD = $password
            $rawOutput = & psql --host $HostName --port $Port --dbname $DatabaseName --username $Username --no-align --tuples-only --command $query 2>&1
            """,
        EngineType.Oracle => """
            $login = 'CONNECT "' + $Username.Replace('"', '""') + '"/"' + $password.Replace('"', '""') + '"@//' + $HostName + ':' + $Port + '/' + $DatabaseName
            $sqlPlusInput = $login + "`nSET PAGESIZE 50000 LINESIZE 32767 FEEDBACK OFF`n" + $query + "`nEXIT"
            $rawOutput = $sqlPlusInput | & sqlplus -L /nolog 2>&1
            """,
        EngineType.SqlServer => """
            $env:SQLCMDPASSWORD = $password
            $rawOutput = & sqlcmd -S "$HostName,$Port" -d $DatabaseName -U $Username -Q $query -W -s "|" 2>&1
            """,
        EngineType.MySQL => """
            $env:MYSQL_PWD = $password
            $rawOutput = & mysql --host=$HostName --port=$Port --database=$DatabaseName --user=$Username --batch --execute=$query 2>&1
            """,
        EngineType.MongoDB => """
            $rawOutput = & mongosh --host $HostName --port $Port --username $Username --authenticationDatabase $DatabaseName $DatabaseName --quiet --eval $query 2>&1
            """,
        EngineType.Cassandra => """
            $rawOutput = & cqlsh $HostName $Port --credentials $credentialsPath --disable-history -e $query 2>&1
            """,
        EngineType.Sybase => """
            $isqlInput = $query + "`ngo`n"
            $rawOutput = $isqlInput | & isql -S $HostName -U $Username 2>&1
            """,
        _ => throw new NotSupportedException()
    };

    private static string GetCredentialSetup(EngineType engine) => engine switch
    {
        EngineType.MongoDB or EngineType.Sybase => """
            # The native CLI owns the hidden interactive password prompt.
            $password = $null
            $credentialsPath = $null
            """,
        EngineType.Cassandra => """
            $securePassword = Read-Host "Password for $Username" -AsSecureString
            $password = [System.Net.NetworkCredential]::new("", $securePassword).Password
            $credentialsPath = [System.IO.Path]::GetTempFileName()
            @(
                "[PlainTextAuthProvider]"
                "username = $Username"
                "password = $password"
            ) | Set-Content -LiteralPath $credentialsPath -Encoding utf8
            if ($IsWindows -or $env:OS -eq "Windows_NT") {
                & icacls $credentialsPath /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
            }
            else {
                & chmod 600 $credentialsPath
            }
            """,
        _ => """
            $securePassword = Read-Host "Password for $Username" -AsSecureString
            $password = [System.Net.NetworkCredential]::new("", $securePassword).Password
            $credentialsPath = $null
            """
    };

    private static IReadOnlyDictionary<string, string> GetSections(EngineType engine) => engine switch
    {
        EngineType.PostgreSQL => new Dictionary<string, string>
        {
            ["identity"] = "SELECT version() AS server_version, current_database() AS database_name;",
            ["capacity"] = "SELECT pg_database_size(current_database()) AS database_size_bytes;",
            ["objects"] = "SELECT table_type, COUNT(*) AS object_count FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') GROUP BY table_type;",
            ["extensions"] = "SELECT extname, extversion FROM pg_extension ORDER BY extname;",
            ["tablesWithoutPrimaryKey"] = "SELECT n.nspname AS schema_name, c.relname AS table_name FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind IN ('r','p') AND n.nspname NOT IN ('pg_catalog','information_schema','pg_toast') AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'p') ORDER BY n.nspname, c.relname;",
            ["problematicColumns"] = "SELECT table_schema, table_name, column_name, data_type, udt_name FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog','information_schema') AND (data_type IN ('ARRAY','USER-DEFINED','xml','money') OR udt_name = 'oid') ORDER BY table_schema, table_name, ordinal_position;",
            ["jsonColumns"] = "SELECT table_schema, table_name, column_name, data_type FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog','information_schema') AND data_type IN ('json','jsonb') ORDER BY table_schema, table_name, ordinal_position;",
            ["partitions"] = "SELECT parent_ns.nspname AS schema_name, parent.relname AS parent_table, child_ns.nspname AS partition_schema, child.relname AS partition_name FROM pg_inherits i JOIN pg_class parent ON parent.oid = i.inhparent JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace JOIN pg_class child ON child.oid = i.inhrelid JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace ORDER BY parent_ns.nspname, parent.relname, child.relname;"
        },
        EngineType.Oracle => new Dictionary<string, string>
        {
            ["identity"] = "SELECT BANNER AS SERVER_VERSION FROM V$VERSION WHERE BANNER LIKE 'Oracle%' AND ROWNUM = 1; SELECT NAME AS DATABASE_NAME, PLATFORM_NAME, LOG_MODE FROM V$DATABASE;",
            ["capacity"] = "SELECT ROUND(SUM(BYTES)/1048576) AS TOTAL_SIZE_MB FROM DBA_DATA_FILES;",
            ["objects"] = "SELECT OBJECT_TYPE, COUNT(*) AS OBJECT_COUNT FROM DBA_OBJECTS WHERE OWNER NOT IN ('SYS','SYSTEM') GROUP BY OBJECT_TYPE ORDER BY OBJECT_TYPE;",
            ["invalidObjects"] = "SELECT OWNER, OBJECT_TYPE, OBJECT_NAME FROM DBA_OBJECTS WHERE STATUS = 'INVALID' AND OWNER NOT IN ('SYS','SYSTEM') ORDER BY OWNER, OBJECT_TYPE, OBJECT_NAME;",
            ["wrappedCode"] = "SELECT OWNER, NAME AS OBJECT_NAME, TYPE AS OBJECT_TYPE FROM DBA_SOURCE WHERE LINE = 1 AND LOWER(TEXT) LIKE '%wrapped%' AND OWNER NOT IN ('SYS','SYSTEM') ORDER BY OWNER, TYPE, NAME;",
            ["unsupportedObjects"] = "SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS FROM DBA_OBJECTS WHERE OWNER NOT IN ('SYS','SYSTEM') AND OBJECT_TYPE IN ('DATABASE LINK','DIRECTORY','JAVA CLASS','JAVA RESOURCE','JAVA SOURCE','MATERIALIZED VIEW','MATERIALIZED VIEW LOG','SYNONYM','TYPE','TYPE BODY','XML SCHEMA') ORDER BY OWNER, OBJECT_TYPE, OBJECT_NAME;",
            ["lobSize"] = "SELECT l.OWNER, l.TABLE_NAME, l.COLUMN_NAME, l.SEGMENT_NAME, ROUND(SUM(s.BYTES)/1048576,2) AS SIZE_MB FROM DBA_LOBS l JOIN DBA_SEGMENTS s ON s.OWNER = l.OWNER AND s.SEGMENT_NAME = l.SEGMENT_NAME WHERE l.OWNER NOT IN ('SYS','SYSTEM') GROUP BY l.OWNER, l.TABLE_NAME, l.COLUMN_NAME, l.SEGMENT_NAME ORDER BY SIZE_MB DESC;",
            ["dailyRedoGeneration"] = "SELECT TO_CHAR(TRUNC(FIRST_TIME),'YYYY-MM-DD') AS REDO_DAY, COUNT(*) AS ARCHIVED_LOGS, ROUND(SUM(BLOCKS * BLOCK_SIZE)/1073741824,2) AS REDO_GB FROM V$ARCHIVED_LOG WHERE FIRST_TIME >= SYSDATE - 7 AND NAME IS NOT NULL GROUP BY TRUNC(FIRST_TIME) ORDER BY TRUNC(FIRST_TIME);"
        },
        EngineType.SqlServer => new Dictionary<string, string>
        {
            ["identity"] = "SELECT @@VERSION AS server_version, DB_NAME() AS database_name;",
            ["capacity"] = "SELECT SUM(size) * 8 * 1024 AS database_size_bytes FROM sys.database_files;",
            ["objects"] = "SELECT type_desc, COUNT(*) AS object_count FROM sys.objects WHERE is_ms_shipped = 0 GROUP BY type_desc ORDER BY type_desc;"
        },
        EngineType.MySQL => new Dictionary<string, string>
        {
            ["identity"] = "SELECT VERSION() AS server_version, DATABASE() AS database_name;",
            ["capacity"] = "SELECT SUM(data_length + index_length) AS database_size_bytes FROM information_schema.tables WHERE table_schema = DATABASE();",
            ["objects"] = "SELECT table_type, COUNT(*) AS object_count FROM information_schema.tables WHERE table_schema = DATABASE() GROUP BY table_type;",
            ["engines"] = "SELECT engine, COUNT(*) AS table_count FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE' GROUP BY engine;",
            ["nonInnoDbTables"] = "SELECT TABLE_SCHEMA, TABLE_NAME, ENGINE FROM information_schema.TABLES WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_SCHEMA = DATABASE() AND COALESCE(ENGINE,'') <> 'InnoDB' ORDER BY TABLE_NAME;",
            ["specialColumns"] = "SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, EXTRA FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND (DATA_TYPE = 'enum' OR UPPER(EXTRA) LIKE '%INVISIBLE%') ORDER BY TABLE_NAME, ORDINAL_POSITION;",
            ["partitions"] = "SELECT TABLE_SCHEMA, TABLE_NAME, PARTITION_NAME, PARTITION_METHOD, PARTITION_EXPRESSION, TABLE_ROWS FROM information_schema.PARTITIONS WHERE TABLE_SCHEMA = DATABASE() AND PARTITION_NAME IS NOT NULL ORDER BY TABLE_NAME, PARTITION_ORDINAL_POSITION;",
            ["authenticationPlugins"] = "SELECT plugin, COUNT(*) AS account_count FROM mysql.user GROUP BY plugin ORDER BY account_count DESC;",
            ["bufferPoolOccupancy"] = "SELECT MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_data' THEN VARIABLE_VALUE END) AS data_pages, MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_total' THEN VARIABLE_VALUE END) AS total_pages FROM performance_schema.global_status WHERE VARIABLE_NAME IN ('Innodb_buffer_pool_pages_data','Innodb_buffer_pool_pages_total');"
        },
        EngineType.MongoDB => new Dictionary<string, string>
        {
            ["inventory"] = "EJSON.stringify({ serverVersion: db.version(), databaseName: db.getName(), stats: db.stats(), collections: db.getCollectionNames() })"
        },
        EngineType.Cassandra => new Dictionary<string, string>
        {
            ["identity"] = "SELECT cluster_name, release_version FROM system.local;",
            ["keyspaces"] = "SELECT keyspace_name, durable_writes, replication FROM system_schema.keyspaces;",
            ["tables"] = "SELECT keyspace_name, table_name FROM system_schema.tables;"
        },
        EngineType.Sybase => new Dictionary<string, string>
        {
            ["identity"] = "SELECT @@version AS server_version SELECT db_name() AS database_name",
            ["objects"] = "SELECT type, count(*) AS object_count FROM sysobjects WHERE type IN ('U','V') GROUP BY type"
        },
        _ => throw new NotSupportedException()
    };

    private static string PowerShellLiteral(string value) => $"'{value.Replace("'", "''")}'";

    private static string SanitizeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var sanitized = new string(value.Select(character => invalid.Contains(character) ? '-' : character).ToArray());
        return string.IsNullOrWhiteSpace(sanitized) ? "database" : sanitized;
    }

    private static string Indent(string value, int spaces)
    {
        var prefix = new string(' ', spaces);
        return string.Join(Environment.NewLine, value.Split(Environment.NewLine).Select(line => prefix + line));
    }
}