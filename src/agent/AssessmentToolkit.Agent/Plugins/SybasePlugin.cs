using AdoNetCore.AseClient;
using System.Data.Common;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Read-only SAP/Sybase ASE discovery using system catalogs in the selected database.
/// </summary>
public sealed class SybasePlugin : IAssessmentPlugin
{
    public string PluginId => "sybase";
    public string PluginVersion => "1.0.0";
    public string TargetEngine => "Sybase";

    public async Task<PluginResult> RunAsync(PluginContext context, CancellationToken ct)
    {
        var connectionString =
            $"Data Source={context.Host};Port={context.Port};Database={context.Database};" +
            $"User ID={context.Username};Password={context.Password};Connection Timeout=30;";

        try
        {
            await using var connection = new AseConnection(connectionString);
            await connection.OpenAsync(ct);

            var findings = new Dictionary<string, object>();
            var sectionErrors = new Dictionary<string, string>();

            await CollectScalarAsync(findings, sectionErrors, "server_version", connection, "SELECT @@version", ct);
            await CollectScalarAsync(findings, sectionErrors, "database_name", connection, "SELECT db_name()", ct);
            await CollectScalarAsync(findings, sectionErrors, "page_size_bytes", connection, "SELECT @@maxpagesize", ct);
            await CollectQueryAsync(findings, sectionErrors, "databases", connection, @"
                SELECT name, dbid, status, status2, crdate
                FROM master..sysdatabases
                ORDER BY name", ct);
            await CollectQueryAsync(findings, sectionErrors, "objects", connection, @"
                SELECT o.name AS object_name, u.name AS owner_name,
                       CASE o.type WHEN 'U' THEN 'table' WHEN 'V' THEN 'view'
                           WHEN 'P' THEN 'procedure' WHEN 'TR' THEN 'trigger'
                           WHEN 'RI' THEN 'referential_constraint' ELSE o.type END AS object_type
                FROM sysobjects o
                JOIN sysusers u ON o.uid = u.uid
                WHERE o.type IN ('U','V','P','TR','RI')
                  AND o.name NOT LIKE 'sys%'
                ORDER BY o.type, u.name, o.name", ct);
            await CollectQueryAsync(findings, sectionErrors, "table_inventory", connection, @"
                SELECT o.name AS table_name, u.name AS owner_name,
                       row_count(db_id(), o.id) AS row_count_estimate,
                       data_pages(db_id(), o.id, 0) AS data_pages,
                       reserved_pages(db_id(), o.id, 0) AS reserved_pages
                FROM sysobjects o
                JOIN sysusers u ON o.uid = u.uid
                WHERE o.type = 'U' AND o.name NOT LIKE 'sys%'
                ORDER BY reserved_pages DESC", ct);
            await CollectQueryAsync(findings, sectionErrors, "columns", connection, @"
                SELECT u.name AS owner_name, o.name AS table_name, c.name AS column_name,
                       t.name AS data_type, c.length, c.prec, c.scale,
                       CASE WHEN (c.status & 8) = 8 THEN 1 ELSE 0 END AS allows_null,
                       CASE WHEN (c.status & 128) = 128 THEN 1 ELSE 0 END AS is_identity
                FROM syscolumns c
                JOIN sysobjects o ON c.id = o.id
                JOIN sysusers u ON o.uid = u.uid
                JOIN systypes t ON c.usertype = t.usertype
                WHERE o.type = 'U' AND o.name NOT LIKE 'sys%'
                ORDER BY u.name, o.name, c.colid", ct);
            await CollectQueryAsync(findings, sectionErrors, "indexes", connection, @"
                SELECT u.name AS owner_name, o.name AS table_name, i.name AS index_name,
                       i.indid, i.status, i.maxrowsperpage
                FROM sysindexes i
                JOIN sysobjects o ON i.id = o.id
                JOIN sysusers u ON o.uid = u.uid
                WHERE o.type = 'U' AND i.indid > 0 AND i.indid < 255
                  AND o.name NOT LIKE 'sys%'
                ORDER BY u.name, o.name, i.indid", ct);
            await CollectQueryAsync(findings, sectionErrors, "legacy_type_columns", connection, @"
                SELECT u.name AS owner_name, o.name AS table_name, c.name AS column_name, t.name AS data_type
                FROM syscolumns c
                JOIN sysobjects o ON c.id = o.id
                JOIN sysusers u ON o.uid = u.uid
                JOIN systypes t ON c.usertype = t.usertype
                WHERE o.type = 'U' AND t.name IN ('text','image','unitext','java')
                ORDER BY t.name, u.name, o.name", ct);
            await CollectQueryAsync(findings, sectionErrors, "remote_servers", connection, @"
                SELECT srvname, srvclass, srvnetname
                FROM master..sysservers
                WHERE srvid > 0
                ORDER BY srvname", ct);
            await CollectQueryAsync(findings, sectionErrors, "devices", connection, @"
                SELECT name, phyname, status, cntrltype
                FROM master..sysdevices
                ORDER BY name", ct);

            if (sectionErrors.Count > 0)
                findings["section_errors"] = sectionErrors;

            var json = JsonSerializer.Serialize(findings);
            return new PluginResult(true, json, json);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return new PluginResult(false, "{}", "{}", ex.Message);
        }
    }

    private static async Task CollectScalarAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        string sectionName,
        AseConnection connection,
        string sql,
        CancellationToken ct)
    {
        try
        {
            await using var command = connection.CreateCommand();
            command.CommandText = sql;
            command.CommandTimeout = 60;
            findings[sectionName] = (await command.ExecuteScalarAsync(ct))?.ToString() ?? string.Empty;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sectionErrors[sectionName] = ex.GetType().Name;
        }
    }

    private static async Task CollectQueryAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        string sectionName,
        AseConnection connection,
        string sql,
        CancellationToken ct)
    {
        try
        {
            findings[sectionName] = await QueryAsync(connection, sql, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sectionErrors[sectionName] = ex.GetType().Name;
        }
    }

    private static async Task<List<object>> QueryAsync(AseConnection connection, string sql, CancellationToken ct)
    {
        var rows = new List<object>();
        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.CommandTimeout = 60;
        await using DbDataReader reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>();
            for (var index = 0; index < reader.FieldCount; index++)
                row[reader.GetName(index)] = reader.IsDBNull(index) ? null : reader.GetValue(index);
            rows.Add(row);
        }
        return rows;
    }
}