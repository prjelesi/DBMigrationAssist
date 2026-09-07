using System.Reflection;
using AssessmentToolkit.Api.Controllers;
using Microsoft.AspNetCore.Authorization;
using Xunit;

namespace AssessmentToolkit.Api.Tests;

public sealed class AdministrativeAuthorizationTests
{
    public static TheoryData<Type, string> AdministrativeActions => new()
    {
        { typeof(AiController), nameof(AiController.ListProviders) },
        { typeof(AiController), nameof(AiController.RegisterProvider) },
        { typeof(AiController), nameof(AiController.UpdateProvider) },
        { typeof(AiController), nameof(AiController.DeleteProvider) },
        { typeof(AiController), nameof(AiController.GetReportInstructions) },
        { typeof(AiController), nameof(AiController.UpdateReportInstructions) },
        { typeof(AiController), nameof(AiController.Configure) },
        { typeof(AiController), nameof(AiController.ClearStoredCredential) },
        { typeof(AiController), nameof(AiController.Test) },
        { typeof(SystemController), nameof(SystemController.GetConfig) },
        { typeof(SystemController), nameof(SystemController.SetConfig) },
        { typeof(SystemController), nameof(SystemController.DeleteConfig) },
        { typeof(SystemController), nameof(SystemController.AllAgents) }
    };

    [Theory]
    [MemberData(nameof(AdministrativeActions))]
    public void AdministrativeAction_RequiresAdministratorRole(Type controllerType, string methodName)
    {
        var method = controllerType.GetMethod(methodName, BindingFlags.Instance | BindingFlags.Public);

        var authorization = Assert.Single(method!.GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal("Administrator", authorization.Roles);
    }
}