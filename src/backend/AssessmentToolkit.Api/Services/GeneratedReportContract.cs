using System.Text.Json;

namespace AssessmentToolkit.Api.Services;

public static class GeneratedReportContract
{
    private const int MaxOutputLength = 1_000_000;
    private const int MaxStringLength = 20_000;
    private const int MaxCollectionItems = 100;

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false
    };

    public static string NormalizeAndValidate(string value)
    {
        if (value.Length > MaxOutputLength)
            throw new ReportContractException(["Report output exceeds the maximum allowed size."]);

        var normalized = StripMarkdownFence(value);
        using var document = JsonDocument.Parse(normalized);
        if (document.RootElement.ValueKind != JsonValueKind.Object)
            throw new ReportContractException(["Report root must be a JSON object."]);

        var report = document.RootElement.Deserialize<ReportDocument>(SerializerOptions)
            ?? throw new ReportContractException(["Report root must be a JSON object."]);
        var errors = Validate(report);
        if (errors.Count > 0)
            throw new ReportContractException(errors);

        return JsonSerializer.Serialize(document.RootElement);
    }

    private static string StripMarkdownFence(string value)
    {
        var normalized = value.Trim();
        if (!normalized.StartsWith("```", StringComparison.Ordinal))
            return normalized;

        var firstLineEnd = normalized.IndexOf('\n');
        if (firstLineEnd >= 0 && normalized.EndsWith("```", StringComparison.Ordinal))
            return normalized[(firstLineEnd + 1)..^3].Trim();

        return normalized;
    }

    private static List<string> Validate(ReportDocument report)
    {
        var errors = new List<string>();

        ValidateString(report.ExecutiveSummary, "executiveSummary", errors);
        ValidateScope(report.ScopeSummary, errors);
        ValidateEnum(report.MigrationReadiness, "migrationReadiness", ["Ready", "NeedsWork", "NotReady"], errors);
        ValidateCollection(report.MigrationRequirements, "migrationRequirements", errors, (item, path) =>
        {
            ValidateEnum(item.Category, $"{path}.category", ["Business", "Technical", "Security", "Network", "Operations", "Data", "Compliance"], errors);
            ValidateString(item.Requirement, $"{path}.requirement", errors);
            ValidateEnum(item.EvidenceStatus, $"{path}.evidenceStatus", ["Confirmed", "Assumption", "Gap"], errors);
            ValidateString(item.Details, $"{path}.details", errors);
        });
        ValidateSourceEnvironment(report.SourceEnvironment, errors);
        ValidateCollection(report.PossibleMigrations, "possibleMigrations", errors, (item, path) =>
        {
            ValidateString(item.SourcePlatform, $"{path}.sourcePlatform", errors);
            ValidateString(item.TargetAzureService, $"{path}.targetAzureService", errors);
            ValidateEnum(item.MigrationType, $"{path}.migrationType", ["Rehost", "Replatform", "Refactor", "Replace", "Retain", "Retire"], errors);
            ValidateEnum(item.Recommendation, $"{path}.recommendation", ["Preferred", "Candidate", "Not Recommended"], errors);
            ValidateString(item.Rationale, $"{path}.rationale", errors);
            ValidateStringCollection(item.Considerations, $"{path}.considerations", errors);
        });
        ValidateCollection(report.MigrationTooling, "migrationTooling", errors, (item, path) =>
        {
            ValidateString(item.Phase, $"{path}.phase", errors);
            ValidateStringCollection(item.Tools, $"{path}.tools", errors);
            ValidateString(item.Purpose, $"{path}.purpose", errors);
            ValidateStringCollection(item.Prerequisites, $"{path}.prerequisites", errors);
        });
        ValidateCollection(report.AzureSkuProposal, "azureSkuProposal", errors, (item, path) =>
        {
            ValidateString(item.Environment, $"{path}.environment", errors);
            ValidateString(item.TargetService, $"{path}.targetService", errors);
            ValidateString(item.SkuTier, $"{path}.skuTier", errors);
            ValidateString(item.Compute, $"{path}.compute", errors);
            ValidateString(item.Storage, $"{path}.storage", errors);
            ValidateString(item.Availability, $"{path}.availability", errors);
            ValidateString(item.Networking, $"{path}.networking", errors);
            ValidateString(item.Rationale, $"{path}.rationale", errors);
            ValidateString(item.SizingBasis, $"{path}.sizingBasis", errors);
            ValidateStringCollection(item.Assumptions, $"{path}.assumptions", errors);
        });
        ValidateCollection(report.KeyRisks, "keyRisks", errors, (item, path) =>
        {
            ValidateString(item.Title, $"{path}.title", errors);
            ValidateEnum(item.Severity, $"{path}.severity", ["High", "Medium", "Low"], errors);
            ValidateString(item.Description, $"{path}.description", errors);
        });
        ValidateString(report.RecommendedWave, "recommendedWave", errors);
        ValidateStringCollection(report.NextSteps, "nextSteps", errors);
        ValidateEnum(report.EstimatedEffort, "estimatedEffort", ["Low", "Medium", "High", "Very High"], errors);

        return errors;
    }

    private static void ValidateScope(ScopeSummary? scope, List<string> errors)
    {
        if (scope is null)
        {
            errors.Add("scopeSummary is required.");
            return;
        }

        if (scope.DatabaseCount < 0)
            errors.Add("scopeSummary.databaseCount must be non-negative.");
        ValidateStringCollection(scope.EnginesFound, "scopeSummary.enginesFound", errors);
        if (scope.CriticalCount < 0)
            errors.Add("scopeSummary.criticalCount must be non-negative.");
    }

    private static void ValidateSourceEnvironment(SourceEnvironment? source, List<string> errors)
    {
        if (source is null)
        {
            errors.Add("sourceEnvironment is required.");
            return;
        }

        ValidateString(source.Summary, "sourceEnvironment.summary", errors);
        ValidateCollection(source.Environments, "sourceEnvironment.environments", errors, (item, path) =>
        {
            ValidateString(item.Name, $"{path}.name", errors);
            ValidateString(item.Type, $"{path}.type", errors);
            ValidateString(item.Location, $"{path}.location", errors);
            ValidateString(item.Connectivity, $"{path}.connectivity", errors);
            if (item.DatabaseCount < 0)
                errors.Add($"{path}.databaseCount must be non-negative.");
        });
        ValidateCollection(source.DatabaseEstate, "sourceEnvironment.databaseEstate", errors, (item, path) =>
        {
            ValidateString(item.Name, $"{path}.name", errors);
            ValidateString(item.Engine, $"{path}.engine", errors);
            ValidateString(item.Version, $"{path}.version", errors);
            ValidateString(item.Host, $"{path}.host", errors);
            ValidateString(item.Criticality, $"{path}.criticality", errors);
            ValidateString(item.Environment, $"{path}.environment", errors);
        });
        ValidateStringCollection(source.Dependencies, "sourceEnvironment.dependencies", errors);
        ValidateStringCollection(source.InformationGaps, "sourceEnvironment.informationGaps", errors);
    }

    private static void ValidateEnum(string? value, string path, string[] allowed, List<string> errors)
    {
        ValidateString(value, path, errors);
        if (value is not null && !allowed.Contains(value, StringComparer.Ordinal))
            errors.Add($"{path} has an unsupported value.");
    }

    private static void ValidateString(string? value, string path, List<string> errors)
    {
        if (value is null)
            errors.Add($"{path} is required.");
        else if (value.Length > MaxStringLength)
            errors.Add($"{path} exceeds the maximum allowed length.");
    }

    private static void ValidateStringCollection(List<string>? values, string path, List<string> errors)
    {
        ValidateCollection(values, path, errors, (value, itemPath) => ValidateString(value, itemPath, errors));
    }

    private static void ValidateCollection<T>(
        List<T>? values,
        string path,
        List<string> errors,
        Action<T, string> validateItem)
    {
        if (values is null)
        {
            errors.Add($"{path} is required.");
            return;
        }

        if (values.Count > MaxCollectionItems)
        {
            errors.Add($"{path} exceeds the maximum allowed item count.");
            return;
        }

        for (var index = 0; index < values.Count; index++)
        {
            var item = values[index];
            if (item is null)
                errors.Add($"{path}[{index}] must not be null.");
            else
                validateItem(item, $"{path}[{index}]");
        }
    }

    private sealed class ReportDocument
    {
        public required string ExecutiveSummary { get; init; }
        public required ScopeSummary ScopeSummary { get; init; }
        public required string MigrationReadiness { get; init; }
        public required List<MigrationRequirement> MigrationRequirements { get; init; }
        public required SourceEnvironment SourceEnvironment { get; init; }
        public required List<MigrationOption> PossibleMigrations { get; init; }
        public required List<MigrationToolingItem> MigrationTooling { get; init; }
        public required List<AzureSkuProposal> AzureSkuProposal { get; init; }
        public required List<RiskItem> KeyRisks { get; init; }
        public required string RecommendedWave { get; init; }
        public required List<string> NextSteps { get; init; }
        public required string EstimatedEffort { get; init; }
    }

    private sealed class ScopeSummary
    {
        public required int DatabaseCount { get; init; }
        public required List<string> EnginesFound { get; init; }
        public required int CriticalCount { get; init; }
    }

    private sealed class MigrationRequirement
    {
        public required string Category { get; init; }
        public required string Requirement { get; init; }
        public required string EvidenceStatus { get; init; }
        public required string Details { get; init; }
    }

    private sealed class SourceEnvironment
    {
        public required string Summary { get; init; }
        public required List<SourceEnvironmentItem> Environments { get; init; }
        public required List<DatabaseEstateItem> DatabaseEstate { get; init; }
        public required List<string> Dependencies { get; init; }
        public required List<string> InformationGaps { get; init; }
    }

    private sealed class SourceEnvironmentItem
    {
        public required string Name { get; init; }
        public required string Type { get; init; }
        public required string Location { get; init; }
        public required string Connectivity { get; init; }
        public required int DatabaseCount { get; init; }
    }

    private sealed class DatabaseEstateItem
    {
        public required string Name { get; init; }
        public required string Engine { get; init; }
        public required string Version { get; init; }
        public required string Host { get; init; }
        public required string Criticality { get; init; }
        public required string Environment { get; init; }
    }

    private sealed class MigrationOption
    {
        public required string SourcePlatform { get; init; }
        public required string TargetAzureService { get; init; }
        public required string MigrationType { get; init; }
        public required string Recommendation { get; init; }
        public required string Rationale { get; init; }
        public required List<string> Considerations { get; init; }
    }

    private sealed class MigrationToolingItem
    {
        public required string Phase { get; init; }
        public required List<string> Tools { get; init; }
        public required string Purpose { get; init; }
        public required List<string> Prerequisites { get; init; }
    }

    private sealed class AzureSkuProposal
    {
        public required string Environment { get; init; }
        public required string TargetService { get; init; }
        public required string SkuTier { get; init; }
        public required string Compute { get; init; }
        public required string Storage { get; init; }
        public required string Availability { get; init; }
        public required string Networking { get; init; }
        public required string Rationale { get; init; }
        public required string SizingBasis { get; init; }
        public required List<string> Assumptions { get; init; }
    }

    private sealed class RiskItem
    {
        public required string Title { get; init; }
        public required string Severity { get; init; }
        public required string Description { get; init; }
    }
}

public sealed class ReportContractException(IReadOnlyList<string> errors)
    : Exception("Generated report does not satisfy the required contract.")
{
    public IReadOnlyList<string> Errors { get; } = errors;
}
