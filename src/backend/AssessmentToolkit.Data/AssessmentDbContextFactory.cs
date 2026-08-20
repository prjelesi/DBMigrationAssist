using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace AssessmentToolkit.Data;

public sealed class AssessmentDbContextFactory : IDesignTimeDbContextFactory<AssessmentDbContext>
{
    public AssessmentDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<AssessmentDbContext>()
            .UseNpgsql("Host=localhost;Database=assessmentdb;Username=assessment;Password=design-time-only")
            .Options;
        return new AssessmentDbContext(options);
    }
}