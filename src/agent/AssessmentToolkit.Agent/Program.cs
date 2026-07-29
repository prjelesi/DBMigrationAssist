using AssessmentToolkit.Agent;
using AssessmentToolkit.Agent.Plugins;
using AssessmentToolkit.Shared.Models;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using System.Text.Json;

Log.Logger = new LoggerConfiguration().WriteTo.Console().CreateBootstrapLogger();

// Load bootstrap package from file or environment variable
var bootstrapPath = Environment.GetEnvironmentVariable("AGENT_BOOTSTRAP_PATH") ?? "bootstrap.json";
AgentBootstrapPackage bootstrap;

if (File.Exists(bootstrapPath))
{
    var json = await File.ReadAllTextAsync(bootstrapPath);
    bootstrap = JsonSerializer.Deserialize<AgentBootstrapPackage>(json)
        ?? throw new InvalidOperationException("Invalid bootstrap package.");
}
else
{
    // Allow individual env vars for container injection
    bootstrap = new AgentBootstrapPackage
    {
        AgentId = Guid.Parse(Environment.GetEnvironmentVariable("AGENT_ID")
            ?? throw new InvalidOperationException("AGENT_ID environment variable is required.")),
        BackendUrl = Environment.GetEnvironmentVariable("AGENT_BACKEND_URL")
            ?? throw new InvalidOperationException("AGENT_BACKEND_URL environment variable is required."),
        Psk = Environment.GetEnvironmentVariable("AGENT_PSK")
            ?? throw new InvalidOperationException("AGENT_PSK environment variable is required."),
        AllowedPlugins = (Environment.GetEnvironmentVariable("AGENT_PLUGINS") ?? "postgresql,oracle")
            .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .ToList()
    };
}

var host = Host.CreateDefaultBuilder(args)
    .UseSerilog((ctx, lc) => lc.ReadFrom.Configuration(ctx.Configuration).WriteTo.Console())
    .ConfigureServices(services =>
    {
        services.AddSingleton(bootstrap);
        services.AddSingleton<LocalDatabaseStore>();

        // Register plugins that are enabled in the bootstrap package
        if (bootstrap.AllowedPlugins.Contains("postgresql"))
            services.AddSingleton<IAssessmentPlugin, PostgreSqlPlugin>();
        if (bootstrap.AllowedPlugins.Contains("oracle"))
            services.AddSingleton<IAssessmentPlugin, OraclePlugin>();
        if (bootstrap.AllowedPlugins.Contains("sqlserver"))
            services.AddSingleton<IAssessmentPlugin, SqlServerPlugin>();

        if (bootstrap.AllowedPlugins.Contains("mysql"))
            services.AddSingleton<IAssessmentPlugin, MySqlPlugin>();

        services.AddHostedService<JobPollerService>();
    })
    .Build();

await host.RunAsync();
