using AssessmentToolkit.Data;
using AssessmentToolkit.Worker;
using Microsoft.EntityFrameworkCore;

var builder = Host.CreateApplicationBuilder(args);

var connStr = builder.Configuration.GetConnectionString("Postgres")
    ?? throw new InvalidOperationException(
        "ConnectionStrings:Postgres is not configured. Set the environment variable ConnectionStrings__Postgres.");

builder.Services.AddDbContextFactory<AssessmentDbContext>(opts =>
    opts.UseNpgsql(connStr));

var apiBaseUrl = builder.Configuration["Worker:ApiBaseUrl"] ?? "http://api:8080";
builder.Services.AddHttpClient("api", c =>
{
    c.BaseAddress = new Uri(apiBaseUrl);
    c.Timeout = TimeSpan.FromSeconds(30);
});

builder.Services.AddHostedService<WorkerStatusReporter>();
builder.Services.AddHostedService<AgentHealthService>();
builder.Services.AddHostedService<JobTimeoutService>();
builder.Services.AddHostedService<ResultEnrichmentService>();

var host = builder.Build();
host.Run();
