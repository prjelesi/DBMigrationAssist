using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace AssessmentToolkit.Api.Services;

public sealed class ServiceTokenAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    System.Text.Encodings.Web.UrlEncoder encoder,
    IConfiguration configuration)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "ServiceToken";
    public const string HeaderName = "X-Worker-Token";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(HeaderName, out var providedValues))
            return Task.FromResult(AuthenticateResult.NoResult());

        var expected = configuration["Worker:ServiceToken"];
        var provided = providedValues.ToString();
        if (string.IsNullOrWhiteSpace(expected) || string.IsNullOrWhiteSpace(provided) ||
            !CryptographicOperations.FixedTimeEquals(
                SHA256.HashData(Encoding.UTF8.GetBytes(expected)),
                SHA256.HashData(Encoding.UTF8.GetBytes(provided))))
        {
            return Task.FromResult(AuthenticateResult.Fail("Invalid service token."));
        }

        var identity = new ClaimsIdentity(
        [
            new Claim(ClaimTypes.NameIdentifier, "assessment-worker"),
            new Claim(ClaimTypes.Name, "Assessment Worker"),
            new Claim(ClaimTypes.Role, "Service")
        ], SchemeName);

        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName)));
    }
}