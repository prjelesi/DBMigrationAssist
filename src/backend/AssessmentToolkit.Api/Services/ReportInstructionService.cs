using System.Security.Cryptography;
using System.Text;

namespace AssessmentToolkit.Api.Services;

public sealed record ReportInstructionDocument(string Content, string Source, string Sha256, bool IsEditable);

public interface IReportInstructionService
{
    Task<ReportInstructionDocument> GetAsync(CancellationToken ct = default);
    Task<ReportInstructionDocument> UpdateAsync(string content, string? expectedSha256, CancellationToken ct = default);
}

public sealed class ReportInstructionService(
    IConfiguration configuration,
    ILogger<ReportInstructionService> logger) : IReportInstructionService
{
    public const int MaxBytes = 64 * 1024;
    private const string DefaultRelativePath = "ReportInstructions/report-instructions.md";
    private readonly SemaphoreSlim _writeLock = new(1, 1);

    public async Task<ReportInstructionDocument> GetAsync(CancellationToken ct = default)
    {
        var externalPath = configuration["ReportGeneration:InstructionsPath"];
        if (!string.IsNullOrWhiteSpace(externalPath))
        {
            if (File.Exists(externalPath))
                return await ReadAsync(externalPath, "external", true, ct);

            try
            {
                return await SeedExternalFileAsync(externalPath, ct);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                logger.LogWarning(ex, "Could not initialize external report instructions at {Path}; using packaged defaults", externalPath);
                if (configuration.GetValue<bool>("ReportGeneration:RequireExternalInstructions"))
                    throw new InvalidOperationException("External report instructions are required but unavailable.", ex);
            }
        }

        return await ReadAsync(GetPackagedDefaultPath(), "packaged-default", false, ct);
    }

    public async Task<ReportInstructionDocument> UpdateAsync(
        string content,
        string? expectedSha256,
        CancellationToken ct = default)
    {
        Validate(content);
        var externalPath = configuration["ReportGeneration:InstructionsPath"];
        if (string.IsNullOrWhiteSpace(externalPath))
            throw new InvalidOperationException("An external report instruction path is not configured.");

        var current = await GetAsync(ct);
        if (!string.IsNullOrWhiteSpace(expectedSha256) &&
            !string.Equals(current.Sha256, expectedSha256, StringComparison.OrdinalIgnoreCase))
        {
            throw new ReportInstructionConflictException();
        }

        await _writeLock.WaitAsync(ct);
        try
        {
            if (File.Exists(externalPath) && !string.IsNullOrWhiteSpace(expectedSha256))
            {
                var latest = await ReadAsync(externalPath, "external", true, ct);
                if (!string.Equals(latest.Sha256, expectedSha256, StringComparison.OrdinalIgnoreCase))
                    throw new ReportInstructionConflictException();
            }

            var fullPath = Path.GetFullPath(externalPath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            var temporaryPath = $"{fullPath}.{Guid.NewGuid():N}.tmp";
            await File.WriteAllTextAsync(temporaryPath, content, new UTF8Encoding(false), ct);
            File.Move(temporaryPath, fullPath, true);
            logger.LogInformation("Report instructions updated at {Path}", fullPath);
            return await ReadAsync(fullPath, "external", true, ct);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    private async Task<ReportInstructionDocument> SeedExternalFileAsync(string externalPath, CancellationToken ct)
    {
        await _writeLock.WaitAsync(ct);
        try
        {
            if (File.Exists(externalPath))
                return await ReadAsync(externalPath, "external", true, ct);

            var content = await File.ReadAllTextAsync(GetPackagedDefaultPath(), ct);
            Validate(content);
            var fullPath = Path.GetFullPath(externalPath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            await File.WriteAllTextAsync(fullPath, content, new UTF8Encoding(false), ct);
            logger.LogInformation("Initialized external report instructions at {Path}", fullPath);
            return CreateDocument(content, "external", true);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    private static async Task<ReportInstructionDocument> ReadAsync(
        string path,
        string source,
        bool isEditable,
        CancellationToken ct)
    {
        var fileInfo = new FileInfo(path);
        if (fileInfo.Length > MaxBytes)
            throw new InvalidDataException($"Report instructions exceed the {MaxBytes}-byte limit.");

        var content = await File.ReadAllTextAsync(path, ct);
        Validate(content);
        return CreateDocument(content, source, isEditable);
    }

    private static ReportInstructionDocument CreateDocument(string content, string source, bool isEditable)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(content))).ToLowerInvariant();
        return new ReportInstructionDocument(content, source, hash, isEditable);
    }

    private static void Validate(string content)
    {
        if (string.IsNullOrWhiteSpace(content))
            throw new InvalidDataException("Report instructions cannot be empty.");
        if (Encoding.UTF8.GetByteCount(content) > MaxBytes)
            throw new InvalidDataException($"Report instructions exceed the {MaxBytes}-byte limit.");
    }

    private static string GetPackagedDefaultPath() => Path.Combine(AppContext.BaseDirectory, DefaultRelativePath);
}

public sealed class ReportInstructionConflictException : Exception
{
    public ReportInstructionConflictException()
        : base("Report instructions changed after they were loaded. Refresh and try again.")
    {
    }
}
