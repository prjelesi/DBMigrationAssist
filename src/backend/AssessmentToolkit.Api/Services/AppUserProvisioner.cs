using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Services;

public static class AppUserProvisioner
{
    public static async Task ProvisionAsync(IServiceProvider services, IConfiguration configuration)
    {
        await using var scope = services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AssessmentDbContext>();
        if (await db.AppUsers.AnyAsync())
            return;

        var email = configuration["AppAdmin:Email"]?.Trim();
        var password = configuration["AppAdmin:Password"];
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password))
            throw new InvalidOperationException(
                "AppAdmin:Email and AppAdmin:Password are required when no application users exist.");
        if (password.Length < 12)
            throw new InvalidOperationException("The initial application administrator password must be at least 12 characters.");

        var user = new AppUser
        {
            Email = email,
            NormalizedEmail = email.ToUpperInvariant(),
            DisplayName = configuration["AppAdmin:DisplayName"]?.Trim() ?? "Administrator",
            Role = "Administrator"
        };
        var passwordHasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<AppUser>>();
        user.PasswordHash = passwordHasher.HashPassword(user, password);
        db.AppUsers.Add(user);
        await db.SaveChangesAsync();

        var logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("AppUserProvisioner");
        logger.LogInformation("Initial application administrator {Email} provisioned.", user.Email);
    }
}