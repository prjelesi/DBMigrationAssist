using AssessmentToolkit.Core.Enums;

namespace AssessmentToolkit.Core.Entities;

/// <summary>
/// Metadata record for a customer-uploaded evidence file.
/// The actual file bytes are stored on the configured storage volume.
/// </summary>
public class UploadedReport
{
    public Guid ReportId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public Guid? QuestionnaireResponseId { get; set; }
    public Guid? QuestionId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public ReportSourceType SourceType { get; set; } = ReportSourceType.Other;
    public long FileSizeBytes { get; set; }
    /// <summary>SHA-256 hex digest of the uploaded file content.</summary>
    public string FileHash { get; set; } = string.Empty;
    /// <summary>Relative path within the evidence storage volume.</summary>
    public string StoragePath { get; set; } = string.Empty;
    public ParseStatus ParseStatus { get; set; } = ParseStatus.Pending;
    public ConfidenceLevel ParseConfidence { get; set; } = ConfidenceLevel.Unverified;
    /// <summary>Structured summary extracted by the parser.</summary>
    public string? ParseSummaryJson { get; set; }
    public string? ParseErrorMessage { get; set; }
    public string UploadedBy { get; set; } = string.Empty;
    public DateTimeOffset UploadedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Project Project { get; set; } = null!;
    public QuestionnaireResponse? QuestionnaireResponse { get; set; }
    public Question? Question { get; set; }
}
