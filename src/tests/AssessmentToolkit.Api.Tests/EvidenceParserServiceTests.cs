using System.Text.Json;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Enums;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public sealed class EvidenceParserServiceTests
{
    [Fact]
    public void Parse_AwrText_ExtractsIdentityPeriodAndWorkloadMetrics()
    {
        const string report = """
            WORKLOAD REPOSITORY report for

            DB Name         DB Id    Instance     Inst Num Startup Time    Release     RAC
            ------------ ----------- ------------ -------- --------------- ----------- ---
            ORCL          123456789  orcl1        1        20-Sep-26 10:00 19.0.0.0.0  NO

            Host Name        Platform                         CPUs Cores Sockets Memory (G)
            ---------------- -------------------------------- ---- ----- ------- ----------
            dbserver01       Linux x86 64-bit                    16     8       2      64.0

            Snap Id      Snap Time      Sessions Curs/Sess
            Begin Snap:  100 22-Sep-26 09:00:00       120      3.2
            End Snap:    101 22-Sep-26 10:00:00       135      3.5
            Elapsed:               60.00 (mins)
            DB Time:               42.50 (mins)

            Load Profile                    Per Second   Per Transaction
            DB Time(s):                           0.71              1.20
            DB CPU(s):                            0.35              0.59
            Redo size (bytes):              1048576.00        1782579.20
            Logical reads:                    12000.50          20340.00
            Physical reads:                     250.25            424.15

            Top 5 Timed Foreground Events
            Event                                 Waits   Time (s)  Avg wait (ms)   % DB time Wait Class
            db file sequential read               1200      800.0          6.67         31.4 User I/O
            DB CPU                                           650.0                       25.5
            """;

        var result = EvidenceParserService.Parse(ReportSourceType.Awr, report);

        Assert.Equal(ParseStatus.Parsed, result.Status);
        Assert.Equal(ConfidenceLevel.High, result.Confidence);
        using var summary = JsonDocument.Parse(result.SummaryJson!);
        var root = summary.RootElement;
        Assert.Equal("ORCL", root.GetProperty("databaseName").GetString());
        Assert.Equal("19.0.0.0.0", root.GetProperty("databaseVersion").GetString());
        Assert.Equal(60.0, root.GetProperty("snapshot").GetProperty("elapsedMinutes").GetDouble());
        Assert.Equal(42.5, root.GetProperty("snapshot").GetProperty("dbTimeMinutes").GetDouble());
        Assert.Equal(16, root.GetProperty("host").GetProperty("cpus").GetInt32());
        Assert.Equal(0.71, root.GetProperty("loadProfile").GetProperty("dbTimePerSecond").GetDouble());
        Assert.Contains(root.GetProperty("topTimedEvents").EnumerateArray(),
            item => item.GetProperty("event").GetString() == "db file sequential read");
    }

    [Fact]
    public void Parse_AwrWithoutRecognizableHeader_RequiresReview()
    {
        var result = EvidenceParserService.Parse(ReportSourceType.Awr, "unrelated text");

        Assert.Equal(ParseStatus.ReviewRequired, result.Status);
        Assert.Equal(ConfidenceLevel.Low, result.Confidence);
    }
}
