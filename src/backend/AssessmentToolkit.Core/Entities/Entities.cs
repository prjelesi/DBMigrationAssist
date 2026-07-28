using AssessmentToolkit.Core.Enums;

namespace AssessmentToolkit.Core.Entities;

public class GraphEdge
{
    public Guid EdgeId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public Guid SourceDatabaseId { get; set; }
    public Guid TargetDatabaseId { get; set; }
    public string RelationType { get; set; } = "COMMUNICATES_WITH";
    public string Protocol { get; set; } = "Unknown";
    public string Direction { get; set; } = "Bidirectional";
    public string Confidence { get; set; } = "Unverified";
    public string? Notes { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Project Project { get; set; } = null!;
    public DatabaseInstance SourceDatabase { get; set; } = null!;
    public DatabaseInstance TargetDatabase { get; set; } = null!;
}

public class Portfolio
{
    public Guid PortfolioId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string GroupingRule { get; set; } = string.Empty;
    public string GroupKey { get; set; } = string.Empty;
    public List<Guid> DatabaseIds { get; set; } = [];
    public string? Notes { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Project Project { get; set; } = null!;
}

public class Customer
{
    public Guid CustomerId { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public string? Industry { get; set; }
    public string? Region { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ICollection<Project> Projects { get; set; } = [];
}

public class Project
{
    public Guid ProjectId { get; set; } = Guid.NewGuid();
    public Guid CustomerId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public DeploymentMode DeploymentMode { get; set; }
    public string Status { get; set; } = "Active";
    public string CreatedBy { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Customer Customer { get; set; } = null!;
    public ICollection<ProjectEnvironment> Environments { get; set; } = [];
    public ICollection<Agent> Agents { get; set; } = [];
}

public class ProjectEnvironment
{
    public Guid EnvironmentId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty; // Production, UAT, DR, Dev, Custom
    public string? Location { get; set; }
    public string? ConnectivityZone { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Project Project { get; set; } = null!;
    public ICollection<DatabaseInstance> Databases { get; set; } = [];
    public ICollection<Agent> Agents { get; set; } = [];
}

public class DatabaseInstance
{
    public Guid DatabaseId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public Guid? EnvironmentId { get; set; }
    public string Name { get; set; } = string.Empty;
    public EngineType Engine { get; set; }
    public string? Version { get; set; }
    public string? HostName { get; set; }
    public int? Port { get; set; }
    public Criticality Criticality { get; set; } = Criticality.Medium;
    public string? OwnerName { get; set; }
    public string MetadataJson { get; set; } = "{}";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Project Project { get; set; } = null!;
    public ProjectEnvironment? Environment { get; set; }
    public ICollection<AssessmentResult> Results { get; set; } = [];
}

public class Agent
{
    public Guid AgentId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public Guid? EnvironmentId { get; set; }
    public string Name { get; set; } = string.Empty;
    public AgentStatus Status { get; set; } = AgentStatus.Registered;
    public PskMode PskMode { get; set; } = PskMode.SystemGenerated;
    /// <summary>Salted hash of the PSK — raw value is never stored.</summary>
    public string PskHash { get; set; } = string.Empty;
    public string PskSalt { get; set; } = string.Empty;
    public List<string> AllowedPlugins { get; set; } = [];
    public DateTimeOffset? LastHeartbeatAt { get; set; }
    public DateTimeOffset? PskIssuedAt { get; set; }
    public string CreatedBy { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Project Project { get; set; } = null!;
    public ProjectEnvironment? Environment { get; set; }
    public ICollection<AssessmentJob> Jobs { get; set; } = [];
}

public class AssessmentJob
{
    public Guid JobId { get; set; } = Guid.NewGuid();
    public Guid AgentId { get; set; }
    public Guid? DatabaseId { get; set; }
    public string PluginId { get; set; } = string.Empty;
    public JobStatus Status { get; set; } = JobStatus.Pending;
    public string? ParametersJson { get; set; }
    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Agent Agent { get; set; } = null!;
    public DatabaseInstance? Database { get; set; }
    public ICollection<AssessmentResult> Results { get; set; } = [];
}

public class AssessmentResult
{
    public Guid ResultId { get; set; } = Guid.NewGuid();
    public Guid JobId { get; set; }
    public Guid? DatabaseId { get; set; }
    public string PluginId { get; set; } = string.Empty;
    public string PluginVersion { get; set; } = string.Empty;
    public ConfidenceLevel Confidence { get; set; } = ConfidenceLevel.High;
    public string FindingJson { get; set; } = "{}";
    public string RawSummaryJson { get; set; } = "{}";
    public string? PayloadHash { get; set; }
    public DateTimeOffset AssessedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public AssessmentJob Job { get; set; } = null!;
    public DatabaseInstance? Database { get; set; }
}
