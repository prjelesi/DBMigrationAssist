using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Data;
using AssessmentToolkit.Shared.Auth;
using AssessmentToolkit.Shared.Models;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace AssessmentToolkit.Api.Services;

public static class LocalAgentProvisioner
{
    public const string CreatedBy = "PlatformLocalAgent";
    private const string CustomerName = "Platform";
    private const string ProjectName = "Local Assessments";

    public static async Task ProvisionAsync(IServiceProvider services, IConfiguration config)
    {
        var bootstrapPath = config["LocalAgent:BootstrapPath"];
        if (string.IsNullOrWhiteSpace(bootstrapPath))
            return;

        await using var scope = services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AssessmentDbContext>();
        var logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("LocalAgentProvisioner");

        var customer = await db.Customers.FirstOrDefaultAsync(c => c.Name == CustomerName);
        if (customer is null)
        {
            customer = new Customer { Name = CustomerName, Industry = "Internal", Region = "Local" };
            db.Customers.Add(customer);
        }

        var project = await db.Projects.FirstOrDefaultAsync(p => p.CreatedBy == CreatedBy);
        if (project is null)
        {
            project = new Project
            {
                Customer = customer,
                Name = ProjectName,
                Description = "Platform-managed project for databases reachable by the local Discovery Agent.",
                DeploymentMode = DeploymentMode.Standalone,
                CreatedBy = CreatedBy
            };
            db.Projects.Add(project);
        }

        var agent = await db.Agents.FirstOrDefaultAsync(a => a.CreatedBy == CreatedBy);
        var persisted = await ReadBootstrapAsync(bootstrapPath);
        var psk = persisted?.Psk ?? PskAuthenticator.GeneratePsk();

        if (agent is null)
        {
            agent = new Agent
            {
                Project = project,
                Name = "Platform Local Agent",
                PskMode = PskMode.SystemGenerated,
                CreatedBy = CreatedBy
            };
            db.Agents.Add(agent);
        }

        agent.AllowedPlugins = ["postgresql", "oracle", "sqlserver", "mysql", "mongodb", "cassandra", "sybase"];
        agent.PskSalt = Convert.ToBase64String(RandomNumberGenerator.GetBytes(16));
        agent.PskHash = ComputeSaltedHash(psk, agent.PskSalt);
        agent.PskIssuedAt = persisted?.IssuedAt ?? DateTimeOffset.UtcNow;
        agent.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();

        var bootstrap = new AgentBootstrapPackage
        {
            AgentId = agent.AgentId,
            BackendUrl = config["LocalAgent:BackendUrl"] ?? "http://api:8080",
            Psk = psk,
            AllowedPlugins = agent.AllowedPlugins,
            IssuedAt = agent.PskIssuedAt.Value
        };

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(bootstrapPath))!);
        await File.WriteAllTextAsync(bootstrapPath, JsonSerializer.Serialize(bootstrap, new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            WriteIndented = true
        }));

        config[$"AgentPsk:{agent.AgentId}"] = psk;
        logger.LogInformation("Platform Local Agent {AgentId} provisioned.", agent.AgentId);
    }

    private static async Task<AgentBootstrapPackage?> ReadBootstrapAsync(string path)
    {
        if (!File.Exists(path)) return null;

        try
        {
            var json = await File.ReadAllTextAsync(path);
            return JsonSerializer.Deserialize<AgentBootstrapPackage>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string ComputeSaltedHash(string psk, string salt)
    {
        var input = Encoding.UTF8.GetBytes(salt + psk);
        return Convert.ToBase64String(SHA256.HashData(input));
    }
}