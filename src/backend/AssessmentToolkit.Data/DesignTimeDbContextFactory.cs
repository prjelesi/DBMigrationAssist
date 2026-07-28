using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;

namespace AssessmentToolkit.Data;

/// <summary>
/// Allows dotnet-ef to instantiate the DbContext at design-time for migrations
/// without needing the full ASP.NET Core host to start.
/// </summary>
public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AssessmentDbContext>
{
    public AssessmentDbContext CreateDbContext(string[] args)
    {
        var config = new ConfigurationBuilder()
            .AddEnvironmentVariables()
            .Build();

        var connString = config["ConnectionStrings__Postgres"]
            ?? "Host=localhost;Port=5432;Database=assessmentdb;Username=assessment;Password=assessment_dev_password";

        var opts = new DbContextOptionsBuilder<AssessmentDbContext>()
            .UseNpgsql(connString)
            .Options;

        return new AssessmentDbContext(opts);
    }
}
