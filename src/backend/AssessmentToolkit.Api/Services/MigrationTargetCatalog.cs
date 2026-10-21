using AssessmentToolkit.Core.Enums;

namespace AssessmentToolkit.Api.Services;

/// <summary>
/// Maps a source database engine to the Azure migration targets a generated report must assess.
/// Targets are listed in modernization-first preference order; an empty result means the engine
/// has no mandated target comparison and the report keeps its previous free-form behaviour.
/// </summary>
public static class MigrationTargetCatalog
{
    public const string PostgreSqlFlexibleServer = "Azure Database for PostgreSQL Flexible Server";
    public const string SqlManagedInstance = "Azure SQL Managed Instance";
    public const string SqlServerOnAzureVirtualMachines = "SQL Server on Azure Virtual Machines";
    public const string OracleDatabaseAtAzure = "Oracle Database@Azure";
    public const string OracleOnAzureVirtualMachines = "Oracle Database on Azure Virtual Machines";

    private static readonly string[] OracleTargets =
    [
        PostgreSqlFlexibleServer,
        SqlManagedInstance,
        SqlServerOnAzureVirtualMachines,
        OracleDatabaseAtAzure,
        OracleOnAzureVirtualMachines
    ];

    private static readonly string[] NoTargets = [];

    public static IReadOnlyList<string> ForEngine(EngineType engine) => engine switch
    {
        EngineType.Oracle => OracleTargets,
        _ => NoTargets
    };

    /// <summary>
    /// Resolves the union of required targets across every engine in a report's scope,
    /// preserving catalogue order and removing duplicates.
    /// </summary>
    public static IReadOnlyList<string> ForEngines(IEnumerable<EngineType>? engines)
    {
        if (engines is null)
        {
            return NoTargets;
        }

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var ordered = new List<string>();

        foreach (var engine in engines)
        {
            foreach (var target in ForEngine(engine))
            {
                if (seen.Add(target))
                {
                    ordered.Add(target);
                }
            }
        }

        return ordered.Count == 0 ? NoTargets : ordered;
    }
}
