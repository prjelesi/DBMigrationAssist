using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(IConfiguration configuration) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet("config")]
    public IActionResult GetConfiguration()
    {
        var enabled = configuration.GetValue("Authentication:Enabled", true);
        return Ok(new
        {
            enabled,
            tenantId = enabled ? configuration["AzureAd:TenantId"] : null,
            clientId = enabled ? configuration["Authentication:SpaClientId"] : null,
            apiScope = enabled ? configuration["Authentication:ApiScope"] : null
        });
    }
}