using AssessmentToolkit.Api.Middleware;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Serilog;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseSerilog((ctx, lc) => lc
    .ReadFrom.Configuration(ctx.Configuration)
    .WriteTo.Console());

var postgresDataSourceBuilder = new NpgsqlDataSourceBuilder(
    builder.Configuration.GetConnectionString("Postgres"));
postgresDataSourceBuilder.EnableDynamicJson();
var postgresDataSource = postgresDataSourceBuilder.Build();
builder.Services.AddSingleton(postgresDataSource);
builder.Services.AddDbContext<AssessmentDbContext>(opts =>
    opts.UseNpgsql(postgresDataSource));

var dataProtection = builder.Services.AddDataProtection()
    .SetApplicationName("AssessmentToolkit");
var dataProtectionKeysPath = builder.Configuration["DataProtection:KeysPath"];
if (!string.IsNullOrWhiteSpace(dataProtectionKeysPath))
    dataProtection.PersistKeysToFileSystem(new DirectoryInfo(dataProtectionKeysPath));

builder.Services.AddControllers()
    .AddJsonOptions(o => o.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter()));

// AI Foundry adapter — singleton, used by evidence parser, finding enricher and report generator
builder.Services.AddSingleton<IAiAdapterService, AiAdapterService>();
builder.Services.AddSingleton<IQuestionnaireTemplateLoader, QuestionnaireTemplateLoader>();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
    c.SwaggerDoc("v1", new() { Title = "Assessment Toolkit API", Version = "v1" }));

builder.Services.AddHealthChecks()
    .AddNpgSql(builder.Configuration.GetConnectionString("Postgres")!);

var app = builder.Build();

app.UseSerilogRequestLogging();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

// Agent endpoints use PSK/HMAC auth - applied only to /api/agent/* routes
app.UseWhen(
    ctx => ctx.Request.Path.StartsWithSegments("/api/agent"),
    branch => branch.UseMiddleware<AgentHmacAuthMiddleware>());

app.MapControllers();
app.MapHealthChecks("/health");

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AssessmentDbContext>();
    await db.Database.MigrateAsync();
}

await app.Services.GetRequiredService<IAiAdapterService>().ReloadConfigAsync(app.Services);

await app.RunAsync();
