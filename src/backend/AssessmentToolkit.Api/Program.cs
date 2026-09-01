using AssessmentToolkit.Api.Middleware;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
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

var controllers = builder.Services.AddControllers()
    .AddJsonOptions(o => o.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter()));

builder.Services.AddAuthentication(options =>
    {
        options.DefaultScheme = "PortalOrService";
        options.DefaultChallengeScheme = "PortalOrService";
    })
    .AddPolicyScheme("PortalOrService", null, options =>
        options.ForwardDefaultSelector = context =>
            context.Request.Headers.ContainsKey(ServiceTokenAuthenticationHandler.HeaderName)
                ? ServiceTokenAuthenticationHandler.SchemeName
                : CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(CookieAuthenticationDefaults.AuthenticationScheme, options =>
    {
        options.Cookie.Name = "AssessmentToolkit.Session";
        options.Cookie.HttpOnly = true;
        options.Cookie.SameSite = SameSiteMode.Strict;
        options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
        options.ExpireTimeSpan = TimeSpan.FromHours(8);
        options.SlidingExpiration = true;
        options.Events.OnRedirectToLogin = context =>
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return Task.CompletedTask;
        };
        options.Events.OnRedirectToAccessDenied = context =>
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return Task.CompletedTask;
        };
    })
    .AddScheme<AuthenticationSchemeOptions, ServiceTokenAuthenticationHandler>(
        ServiceTokenAuthenticationHandler.SchemeName,
        _ => { });
builder.Services.AddAuthorization(options =>
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build());
builder.Services.AddAntiforgery(options =>
{
    options.Cookie.Name = "AssessmentToolkit.Antiforgery";
    options.Cookie.HttpOnly = true;
    options.Cookie.SameSite = SameSiteMode.Strict;
    options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
    options.HeaderName = "X-CSRF-TOKEN";
});
builder.Services.AddScoped<IPasswordHasher<AppUser>, PasswordHasher<AppUser>>();
builder.Services.AddScoped<ProjectAccessService>();

// AI Foundry adapter — singleton, used by evidence parser, finding enricher and report generator
builder.Services.AddSingleton<IAiAdapterService, AiAdapterService>();
builder.Services.AddSingleton<IReportInstructionService, ReportInstructionService>();
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
app.UseAuthentication();
app.UseAuthorization();
app.UseMiddleware<GovernanceMiddleware>();

app.UseWhen(
    context => context.Request.Path.StartsWithSegments("/api") &&
        !context.Request.Path.StartsWithSegments("/api/agent") &&
        !HttpMethods.IsGet(context.Request.Method) &&
        !HttpMethods.IsHead(context.Request.Method) &&
        !HttpMethods.IsOptions(context.Request.Method),
    branch => branch.Use(async (context, next) =>
    {
        if (context.User.IsInRole("Service"))
        {
            await next(context);
            return;
        }

        try
        {
            await context.RequestServices.GetRequiredService<IAntiforgery>().ValidateRequestAsync(context);
            await next(context);
        }
        catch (AntiforgeryValidationException)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsJsonAsync(new { message = "Invalid antiforgery token." });
        }
    }));

// Agent endpoints use PSK/HMAC auth - applied only to /api/agent/* routes
app.UseWhen(
    ctx => ctx.Request.Path.StartsWithSegments("/api/agent"),
    branch => branch.UseMiddleware<AgentHmacAuthMiddleware>());

app.MapControllers();
app.MapHealthChecks("/health").AllowAnonymous();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AssessmentDbContext>();
    await db.Database.MigrateAsync();
}

await AppUserProvisioner.ProvisionAsync(app.Services, app.Configuration);
await LocalAgentProvisioner.ProvisionAsync(app.Services, app.Configuration);
await app.Services.GetRequiredService<IAiAdapterService>().ReloadConfigAsync(app.Services);

await app.RunAsync();
