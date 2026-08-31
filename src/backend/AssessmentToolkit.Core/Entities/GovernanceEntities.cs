namespace AssessmentToolkit.Core.Entities;

public class ProjectMembership
{
    public Guid MembershipId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public Guid? EnvironmentId { get; set; }
    public Guid UserId { get; set; }
    public string Role { get; set; } = "Viewer";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public string CreatedBy { get; set; } = string.Empty;

    public Project Project { get; set; } = null!;
    public ProjectEnvironment? Environment { get; set; }
    public AppUser User { get; set; } = null!;
}

public class AuditEvent
{
    public long AuditEventId { get; set; }
    public Guid? ProjectId { get; set; }
    public Guid? EnvironmentId { get; set; }
    public string ActorId { get; set; } = string.Empty;
    public string ActorName { get; set; } = string.Empty;
    public string Action { get; set; } = string.Empty;
    public string ResourceType { get; set; } = string.Empty;
    public string? ResourceId { get; set; }
    public string Method { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;
    public int StatusCode { get; set; }
    public DateTimeOffset OccurredAt { get; set; } = DateTimeOffset.UtcNow;
}

public class GeneratedReport
{
    public Guid GeneratedReportId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public Guid? DatabaseId { get; set; }
    public Guid EvidenceBundleId { get; set; }
    public string ReportJson { get; set; } = "{}";
    public string State { get; set; } = "DraftReady";
    public int Version { get; set; } = 1;
    public string GeneratedBy { get; set; } = string.Empty;
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
    public string? ReviewedBy { get; set; }
    public DateTimeOffset? ReviewedAt { get; set; }
    public string? ApprovedBy { get; set; }
    public DateTimeOffset? ApprovedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Project Project { get; set; } = null!;
    public DatabaseInstance? Database { get; set; }
    public EvidenceBundle EvidenceBundle { get; set; } = null!;
}

public class EvidenceBundle
{
    public Guid EvidenceBundleId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public string BundleJson { get; set; } = "{}";
    public string ContentHash { get; set; } = string.Empty;
    public string CreatedBy { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Project Project { get; set; } = null!;
}