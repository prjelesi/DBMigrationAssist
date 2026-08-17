using System.Text.Json;

namespace AssessmentToolkit.Agent;

/// <summary>
/// Resolves database connection credentials from a local config file or indexed environment
/// variables. This lets the agent connect to assigned databases without credentials being
/// transmitted through the portal on every job dispatch.
///
/// Priority: environment variables (AGENT_DB_n_*) override file entries for the same database ID.
///
/// ── File format (databases.json or $AGENT_DATABASES_PATH) ────────────────────────────────────
/// {
///   "databases": [
///     {
///       "databaseId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
///       "pluginId":   "postgresql",     // postgresql | oracle | sqlserver | mysql | mongodb | cassandra | sybase
///       "host":       "db.internal",
///       "port":       5432,
///       "database":   "mydb",
///       "username":   "assessment_reader",
///       "password":   "secret"
///     }
///   ]
/// }
///
/// ── Environment variable format (zero-indexed) ───────────────────────────────────────────────
///   AGENT_DB_0_ID       = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
///   AGENT_DB_0_PLUGIN   = postgresql
///   AGENT_DB_0_HOST     = db.internal
///   AGENT_DB_0_PORT     = 5432
///   AGENT_DB_0_NAME     = mydb
///   AGENT_DB_0_USER     = assessment_reader
///   AGENT_DB_0_PASSWORD = secret
///   AGENT_DB_1_ID       = ...   (next database)
/// </summary>
public sealed class LocalDatabaseStore
{
    private readonly Dictionary<Guid, LocalDatabaseProfile> _profiles = [];

    public LocalDatabaseStore(ILogger<LocalDatabaseStore> logger)
    {
        var fileCount = LoadFromFile(logger);
        var envCount  = LoadFromEnvironment(logger);

        logger.LogInformation(
            "LocalDatabaseStore: {Total} profile(s) loaded ({File} from file, {Env} from env vars).",
            _profiles.Count, fileCount, envCount);
    }

    /// <summary>Returns credentials for a database by its portal inventory ID, or null.</summary>
    public LocalDatabaseProfile? Resolve(Guid databaseId) =>
        _profiles.TryGetValue(databaseId, out var p) ? p : null;

    public IReadOnlyCollection<LocalDatabaseProfile> All => _profiles.Values;

    // ── Private loaders ───────────────────────────────────────────────────────────────────────

    private int LoadFromFile(ILogger logger)
    {
        var path = Environment.GetEnvironmentVariable("AGENT_DATABASES_PATH") ?? "databases.json";
        if (!File.Exists(path)) return 0;

        int loaded = 0;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            if (!doc.RootElement.TryGetProperty("databases", out var arr)) return 0;

            foreach (var item in arr.EnumerateArray())
            {
                var profile = ParseJson(item);
                if (profile is null) continue;
                _profiles[profile.DatabaseId] = profile;
                loaded++;
            }
            logger.LogDebug("Loaded {Count} database profile(s) from {Path}.", loaded, path);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to parse database profiles from {Path}.", path);
        }
        return loaded;
    }

    private int LoadFromEnvironment(ILogger logger)
    {
        int loaded = 0;
        for (int i = 0; ; i++)
        {
            var rawId = Environment.GetEnvironmentVariable($"AGENT_DB_{i}_ID");
            if (string.IsNullOrEmpty(rawId)) break;

            if (!Guid.TryParse(rawId, out var guid))
            {
                logger.LogWarning("AGENT_DB_{Index}_ID is not a valid GUID — skipping.", i);
                continue;
            }

            var profile = new LocalDatabaseProfile(
                DatabaseId: guid,
                PluginId:   Env($"AGENT_DB_{i}_PLUGIN")   ?? "postgresql",
                Host:       Env($"AGENT_DB_{i}_HOST")     ?? "",
                Port:       int.TryParse(Env($"AGENT_DB_{i}_PORT"), out var p) ? p : 5432,
                Database:   Env($"AGENT_DB_{i}_NAME")     ?? "",
                Username:   Env($"AGENT_DB_{i}_USER")     ?? "",
                Password:   Env($"AGENT_DB_{i}_PASSWORD") ?? ""
            );

            _profiles[guid] = profile;   // env vars win over file entries
            loaded++;
        }
        return loaded;
    }

    private static LocalDatabaseProfile? ParseJson(JsonElement e)
    {
        try
        {
            return new LocalDatabaseProfile(
                DatabaseId: e.GetProperty("databaseId").GetGuid(),
                PluginId:   e.GetProperty("pluginId").GetString() ?? "postgresql",
                Host:       e.GetProperty("host").GetString()     ?? "",
                Port:       e.TryGetProperty("port", out var pe) ? pe.GetInt32() : 5432,
                Database:   e.GetProperty("database").GetString() ?? "",
                Username:   e.GetProperty("username").GetString() ?? "",
                Password:   e.GetProperty("password").GetString() ?? ""
            );
        }
        catch { return null; }
    }

    private static string? Env(string key) => Environment.GetEnvironmentVariable(key);
}

/// <summary>Locally-stored connection credentials for one source database.</summary>
public sealed record LocalDatabaseProfile(
    Guid   DatabaseId,
    string PluginId,
    string Host,
    int    Port,
    string Database,
    string Username,
    string Password);
