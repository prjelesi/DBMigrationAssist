using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Enums;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public class MigrationTargetCatalogTests
{
    [Fact]
    public void ForEngine_Oracle_ReturnsFiveTargetsInPreferenceOrder()
    {
        var targets = MigrationTargetCatalog.ForEngine(EngineType.Oracle);

        Assert.Equal(
        [
            MigrationTargetCatalog.PostgreSqlFlexibleServer,
            MigrationTargetCatalog.SqlManagedInstance,
            MigrationTargetCatalog.SqlServerOnAzureVirtualMachines,
            MigrationTargetCatalog.OracleDatabaseAtAzure,
            MigrationTargetCatalog.OracleOnAzureVirtualMachines
        ], targets);
    }

    [Theory]
    [InlineData(EngineType.PostgreSQL)]
    [InlineData(EngineType.SqlServer)]
    [InlineData(EngineType.MySQL)]
    [InlineData(EngineType.MongoDB)]
    [InlineData(EngineType.Cassandra)]
    [InlineData(EngineType.Sybase)]
    [InlineData(EngineType.Unknown)]
    public void ForEngine_NonOracle_ReturnsNoTargets(EngineType engine)
    {
        Assert.Empty(MigrationTargetCatalog.ForEngine(engine));
    }

    [Fact]
    public void ForEngines_DeduplicatesAndPreservesCatalogueOrder()
    {
        var targets = MigrationTargetCatalog.ForEngines(
            [EngineType.PostgreSQL, EngineType.Oracle, EngineType.Oracle, EngineType.SqlServer]);

        Assert.Equal(MigrationTargetCatalog.ForEngine(EngineType.Oracle), targets);
    }

    [Fact]
    public void ForEngines_WithoutOracle_ReturnsNoTargets()
    {
        Assert.Empty(MigrationTargetCatalog.ForEngines([EngineType.PostgreSQL, EngineType.MySQL]));
    }

    [Fact]
    public void ForEngines_NullOrEmpty_ReturnsNoTargets()
    {
        Assert.Empty(MigrationTargetCatalog.ForEngines(null));
        Assert.Empty(MigrationTargetCatalog.ForEngines([]));
    }
}
