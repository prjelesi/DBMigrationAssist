using System.Net;
using System.Text.Json;
using AssessmentToolkit.Api.Services;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public class AiAdapterServiceTests
{
    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(true, true)]
    public async Task CompleteAsync_NegotiatesSupportedParameters(bool requiresCompletionTokens, bool requiresDefaultTemperature)
    {
        var requests = new List<JsonElement>();
        await using var server = await StartServerAsync(async context =>
        {
            using var document = await JsonDocument.ParseAsync(context.Request.Body);
            var request = document.RootElement.Clone();
            requests.Add(request);

            if (requiresCompletionTokens && request.TryGetProperty("max_tokens", out _))
            {
                await WriteErrorAsync(context, 400, "unsupported_parameter", "max_tokens",
                    "Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead.");
            }
            else if (requiresDefaultTemperature && request.TryGetProperty("temperature", out _))
            {
                await WriteErrorAsync(context, 400, "unsupported_value", "temperature",
                    "Unsupported value: 'temperature' does not support 0.2 with this model. Only the default (1) value is supported.");
            }
            else
            {
                await context.Response.WriteAsJsonAsync(new
                {
                    id = "chatcmpl-test",
                    @object = "chat.completion",
                    created = 1,
                    model = "arbitrary-deployment",
                    choices = new[]
                    {
                        new { index = 0, message = new { role = "assistant", content = "Connection successful" }, finish_reason = "stop" }
                    }
                });
            }
        });
        var service = CreateService(server);

        var response = await service.CompleteAsync("System prompt", "User prompt", maxOutputTokenCount: 1234);

        Assert.Equal("Connection successful", response);
        Assert.Equal(1 + (requiresCompletionTokens ? 1 : 0) + (requiresDefaultTemperature ? 1 : 0), requests.Count);
        var finalRequest = requests[^1];
        var tokenProperty = requiresCompletionTokens ? "max_completion_tokens" : "max_tokens";
        Assert.Equal(1234, finalRequest.GetProperty(tokenProperty).GetInt32());
        Assert.False(finalRequest.TryGetProperty(requiresCompletionTokens ? "max_tokens" : "max_completion_tokens", out _));
        Assert.Equal(!requiresDefaultTemperature, finalRequest.TryGetProperty("temperature", out var temperature));
        if (!requiresDefaultTemperature)
            Assert.Equal(0.2, temperature.GetDouble(), 5);
        Assert.Equal("System prompt", finalRequest.GetProperty("messages")[0].GetProperty("content").GetString());
        Assert.Equal("User prompt", finalRequest.GetProperty("messages")[1].GetProperty("content").GetString());
    }

    [Theory]
    [InlineData(400)]
    [InlineData(401)]
    [InlineData(403)]
    [InlineData(404)]
    public async Task TestConnectionAsync_UnrelatedFailureIsNotRetriedAndReturnsUsefulStatus(int status)
    {
        var calls = 0;
        await using var server = await StartServerAsync(async context =>
        {
            calls++;
            await WriteErrorAsync(context, status, "invalid_request", "model", "Diagnostic detail not for display");
        });
        var service = CreateService(server);

        var result = await service.TestConnectionAsync();

        Assert.False(result.Succeeded);
        Assert.False(service.LastConnectionSucceeded);
        Assert.Equal(result.TestedAt, service.LastConnectionTestedAt);
        Assert.Contains($"HTTP {status}", result.Message);
        Assert.DoesNotContain("Diagnostic detail", result.Message);
        Assert.Equal(1, calls);
    }

    [Fact]
    public async Task CompleteAsync_UnrelatedFailurePreservesNullFallback()
    {
        await using var server = await StartServerAsync(context =>
            WriteErrorAsync(context, 400, "invalid_request", "model", "Invalid request."));

        Assert.Null(await CreateService(server).CompleteAsync("System", "User"));
    }

    [Fact]
    public async Task TestConnectionAsync_CallerCancellationPropagates()
    {
        await using var server = await StartServerAsync(_ => Task.CompletedTask);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            CreateService(server).TestConnectionAsync(cancellation.Token));
    }

    private static AiAdapterService CreateService(WebApplication server)
    {
        var addresses = server.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!;
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["AiFoundry:Endpoint"] = addresses.Addresses.Single(),
            ["AiFoundry:Deployment"] = "arbitrary-deployment",
            ["AiFoundry:ApiKey"] = "test-key"
        }).Build();
        return new AiAdapterService(config, NullLogger<AiAdapterService>.Instance, new EphemeralDataProtectionProvider());
    }

    private static async Task<WebApplication> StartServerAsync(RequestDelegate handler)
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(options => options.Listen(IPAddress.Loopback, 0));
        var app = builder.Build();
        app.Run(handler);
        await app.StartAsync();
        return app;
    }

    private static Task WriteErrorAsync(HttpContext context, int status, string code, string parameter, string message)
    {
        context.Response.StatusCode = status;
        return context.Response.WriteAsJsonAsync(new { error = new { code, param = parameter, message, type = "invalid_request_error" } });
    }
}
