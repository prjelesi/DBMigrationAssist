using System.Text.Json;
using AssessmentToolkit.Api.Services;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public sealed class OracleReportEvidenceBuilderTests
{
    [Fact]
    public void Create_SummarizesCompatibilitySizingAndCollectionGaps()
    {
        var findings = JsonSerializer.Serialize(new
        {
            collection_contract_version = "2.0",
            db_version = "Oracle Database 19c",
            cdb = "YES",
            pdbs = new[] { new { NAME = "APP_PDB" } },
            rac_instances = new[] { new { INSTANCE_NAME = "orcl1" }, new { INSTANCE_NAME = "orcl2" } },
            total_size_mb = 204800,
            database_size_summary = new[]
            {
                new { TOTAL_ALLOCATED_MB = 225280, TOTAL_SEGMENT_COUNT = 4200 }
            },
            tablespace_inventory = new[]
            {
                new { TABLESPACE_NAME = "USERS", CONTENTS = "PERMANENT" },
                new { TABLESPACE_NAME = "TEMP", CONTENTS = "TEMPORARY" }
            },
            temporary_tablespace_usage = new[]
            {
                new { TABLESPACE_NAME = "TEMP", TOTAL_MB = 20480, USED_MB = 512 }
            },
            invalid_object_count = 3,
            wrapped_code = new[] { new { OWNER = "APP", OBJECT_NAME = "PKG_SECRET" } },
            unsupported_objects = new[] { new { OWNER = "APP", OBJECT_TYPE = "JAVA CLASS" } },
            database_links = new[] { new { OWNER = "APP", DB_LINK = "ERP" } },
            synonym_mappings = new[] { new { OWNER = "APP", SYNONYM_NAME = "ERP_CUSTOMERS" } },
            database_profiles = new[] { new { PROFILE = "APP_PROFILE" } },
            partitioned_table_count = 12,
            hcc_usage = new[] { new { TABLE_NAME = "ORDERS", SIZE_MB = 1024 } },
            section_errors = new
            {
                asm_disk_groups = new { oracleErrorCode = "ORA-00942" },
                lockdown_profiles = new { oracleErrorCode = "ORA-00942" }
            }
        });

        var summary = OracleReportEvidenceBuilder.Create(findings);
        var json = JsonSerializer.Serialize(summary);

        Assert.Equal("2.0", summary.CollectionContractVersion);
        Assert.Equal(1, summary.Compatibility.WrappedCodeCount);
        Assert.Equal(1, summary.Compatibility.UnsupportedObjectCount);
        Assert.Equal(1, summary.Compatibility.DatabaseLinkCount);
        Assert.Equal(1, summary.Compatibility.SynonymCount);
        Assert.Equal(1, summary.Compatibility.DatabaseProfileCount);
        Assert.Equal(12, summary.Compatibility.PartitionedTableCount);
        Assert.NotNull(summary.Sizing.DatabaseSizeSummary);
        Assert.NotNull(summary.Sizing.TablespaceInventory);
        Assert.NotNull(summary.Sizing.TemporaryTablespaceUsage);
        Assert.Equal(2, summary.CollectionGaps.Count);
        Assert.Contains("RAC", json);
        Assert.Contains("HCC", json);
    }
}
