using AssessmentToolkit.Agent;
using AssessmentToolkit.Agent.Plugins;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;

Log.Logger = new LoggerConfiguration().WriteTo.Console().CreateBootstrapLogger();

var bootstrap = await AgentBootstrapLoader.LoadAsync();

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
        if (bootstrap.AllowedPlugins.Contains("mongodb"))
            services.AddSingleton<IAssessmentPlugin, MongoDbPlugin>();
        if (bootstrap.AllowedPlugins.Contains("cassandra"))
            services.AddSingleton<IAssessmentPlugin, CassandraPlugin>();
        if (bootstrap.AllowedPlugins.Contains("sybase"))
            services.AddSingleton<IAssessmentPlugin, SybasePlugin>();

        services.AddHostedService<JobPollerService>();
    })
    .Build();

await host.RunAsync();
