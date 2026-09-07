using AssessmentToolkit.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Data;

public class AssessmentDbContext(DbContextOptions<AssessmentDbContext> options) : DbContext(options)
{
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<Project> Projects => Set<Project>();
    public DbSet<ProjectEnvironment> Environments => Set<ProjectEnvironment>();
    public DbSet<DatabaseInstance> Databases => Set<DatabaseInstance>();
    public DbSet<Agent> Agents => Set<Agent>();
    public DbSet<AgentRequestNonce> AgentRequestNonces => Set<AgentRequestNonce>();
    public DbSet<AssessmentJob> Jobs => Set<AssessmentJob>();
    public DbSet<AssessmentResult> Results => Set<AssessmentResult>();

    // Evidence
    public DbSet<UploadedReport> UploadedReports => Set<UploadedReport>();

    // AI
    public DbSet<AiProvider> AiProviders => Set<AiProvider>();

    // System
    public DbSet<SystemConfig> SystemConfigs => Set<SystemConfig>();
    public DbSet<AppUser> AppUsers => Set<AppUser>();
    public DbSet<ProjectMembership> ProjectMemberships => Set<ProjectMembership>();
    public DbSet<AuditEvent> AuditEvents => Set<AuditEvent>();
    public DbSet<GeneratedReport> GeneratedReports => Set<GeneratedReport>();
    public DbSet<EvidenceBundle> EvidenceBundles => Set<EvidenceBundle>();

    // Graph
    public DbSet<GraphEdge> GraphEdges => Set<GraphEdge>();
    public DbSet<Portfolio> Portfolios => Set<Portfolio>();

    // Questionnaire
    public DbSet<QuestionnaireTemplate> QuestionnaireTemplates => Set<QuestionnaireTemplate>();
    public DbSet<QuestionnaireSection> QuestionnaireSections => Set<QuestionnaireSection>();
    public DbSet<Question> Questions => Set<Question>();
    public DbSet<QuestionnaireResponse> QuestionnaireResponses => Set<QuestionnaireResponse>();
    public DbSet<Answer> Answers => Set<Answer>();

    protected override void OnModelCreating(ModelBuilder mb)
    {
        // Schema: core
        mb.Entity<Customer>().ToTable("customer", "core")
            .HasKey(e => e.CustomerId);
        mb.Entity<Project>().ToTable("project", "core")
            .HasKey(e => e.ProjectId);
        mb.Entity<ProjectEnvironment>().ToTable("environment", "core")
            .HasKey(e => e.EnvironmentId);

        // Schema: inventory
        mb.Entity<DatabaseInstance>().ToTable("database_instance", "inventory")
            .HasKey(e => e.DatabaseId);
        mb.Entity<DatabaseInstance>().Property(e => e.MetadataJson)
            .HasColumnType("jsonb");

        // Schema: assessment
        mb.Entity<Agent>().ToTable("agent", "assessment")
            .HasKey(e => e.AgentId);
        mb.Entity<Agent>().Property(e => e.AllowedPlugins)
            .HasColumnType("jsonb");
        mb.Entity<AgentRequestNonce>().ToTable("agent_request_nonce", "assessment")
            .HasKey(e => new { e.AgentId, e.Nonce });

        mb.Entity<AssessmentJob>().ToTable("assessment_job", "assessment")
            .HasKey(e => e.JobId);
        mb.Entity<AssessmentResult>().ToTable("assessment_result", "assessment")
            .HasKey(e => e.ResultId);
        mb.Entity<AssessmentResult>().Property(e => e.FindingJson).HasColumnType("jsonb");
        mb.Entity<AssessmentResult>().Property(e => e.RawSummaryJson).HasColumnType("jsonb");

        // Relationships
        mb.Entity<Project>().HasOne(e => e.Customer).WithMany(e => e.Projects)
            .HasForeignKey(e => e.CustomerId);
        mb.Entity<ProjectEnvironment>().HasOne(e => e.Project).WithMany(e => e.Environments)
            .HasForeignKey(e => e.ProjectId);
        mb.Entity<DatabaseInstance>().HasOne(e => e.Project).WithMany()
            .HasForeignKey(e => e.ProjectId);
        mb.Entity<DatabaseInstance>().HasOne(e => e.Environment).WithMany(e => e.Databases)
            .HasForeignKey(e => e.EnvironmentId);
        mb.Entity<Agent>().HasOne(e => e.Project).WithMany(e => e.Agents)
            .HasForeignKey(e => e.ProjectId);
        mb.Entity<Agent>().HasOne(e => e.Environment).WithMany(e => e.Agents)
            .HasForeignKey(e => e.EnvironmentId);
        mb.Entity<AgentRequestNonce>().HasOne(e => e.Agent).WithMany()
            .HasForeignKey(e => e.AgentId)
            .OnDelete(DeleteBehavior.Cascade);
        mb.Entity<AssessmentJob>().HasOne(e => e.Agent).WithMany(e => e.Jobs)
            .HasForeignKey(e => e.AgentId);
        mb.Entity<AssessmentResult>().HasOne(e => e.Job).WithMany(e => e.Results)
            .HasForeignKey(e => e.JobId);

        // Composite indexes
        mb.Entity<DatabaseInstance>().HasIndex(e => new { e.ProjectId, e.EnvironmentId });
        mb.Entity<Agent>().HasIndex(e => new { e.ProjectId, e.EnvironmentId });
        mb.Entity<AgentRequestNonce>().HasIndex(e => e.ExpiresAt);
        mb.Entity<AssessmentJob>().HasIndex(e => new { e.AgentId, e.Status });
        mb.Entity<AssessmentResult>().HasIndex(e => e.JobId).IsUnique();

        // Schema: questionnaire
        mb.Entity<QuestionnaireTemplate>().ToTable("template", "questionnaire").HasKey(e => e.TemplateId);
        mb.Entity<QuestionnaireSection>().ToTable("section", "questionnaire").HasKey(e => e.SectionId);
        mb.Entity<Question>().ToTable("question", "questionnaire").HasKey(e => e.QuestionId);
        mb.Entity<Question>().Property(e => e.OptionsJson).HasColumnType("jsonb");
        mb.Entity<QuestionnaireResponse>().ToTable("response", "questionnaire").HasKey(e => e.ResponseId);
        mb.Entity<Answer>().ToTable("answer", "questionnaire").HasKey(e => e.AnswerId);

        mb.Entity<QuestionnaireSection>().HasOne(e => e.Template).WithMany(e => e.Sections)
            .HasForeignKey(e => e.TemplateId);
        mb.Entity<Question>().HasOne(e => e.Section).WithMany(e => e.Questions)
            .HasForeignKey(e => e.SectionId);
        mb.Entity<QuestionnaireResponse>().HasOne(e => e.Project).WithMany()
            .HasForeignKey(e => e.ProjectId);
        mb.Entity<QuestionnaireResponse>().HasOne(e => e.Database).WithMany()
            .HasForeignKey(e => e.DatabaseId)
            .OnDelete(DeleteBehavior.Restrict);
        mb.Entity<QuestionnaireResponse>().HasOne(e => e.Template).WithMany()
            .HasForeignKey(e => e.TemplateId);
        mb.Entity<Answer>().HasOne(e => e.Response).WithMany(e => e.Answers)
            .HasForeignKey(e => e.ResponseId);
        mb.Entity<Answer>().HasOne(e => e.Question).WithMany()
            .HasForeignKey(e => e.QuestionId);

        mb.Entity<Answer>().HasIndex(e => new { e.ResponseId, e.QuestionId }).IsUnique();
        mb.Entity<QuestionnaireResponse>()
            .HasIndex(e => new { e.ProjectId, e.TemplateId }, "IX_response_ProjectId_TemplateId_project")
            .IsUnique()
            .HasFilter("\"DatabaseId\" IS NULL");
        mb.Entity<QuestionnaireResponse>()
            .HasIndex(e => new { e.ProjectId, e.DatabaseId, e.TemplateId }, "IX_response_ProjectId_DatabaseId_TemplateId_database")
            .IsUnique()
            .HasFilter("\"DatabaseId\" IS NOT NULL");

        // Schema: assessment — UploadedReport
        mb.Entity<UploadedReport>().ToTable("uploaded_report", "assessment").HasKey(e => e.ReportId);
        mb.Entity<UploadedReport>().Property(e => e.ParseSummaryJson).HasColumnType("jsonb");
        mb.Entity<UploadedReport>().HasOne(e => e.Project).WithMany()
            .HasForeignKey(e => e.ProjectId);
        mb.Entity<UploadedReport>().HasOne(e => e.Database).WithMany()
            .HasForeignKey(e => e.DatabaseId)
            .OnDelete(DeleteBehavior.SetNull);
        mb.Entity<UploadedReport>().HasOne(e => e.QuestionnaireResponse).WithMany()
            .HasForeignKey(e => e.QuestionnaireResponseId)
            .OnDelete(DeleteBehavior.SetNull);
        mb.Entity<UploadedReport>().HasOne(e => e.Question).WithMany()
            .HasForeignKey(e => e.QuestionId)
            .OnDelete(DeleteBehavior.SetNull);
        mb.Entity<UploadedReport>().HasIndex(e => e.ProjectId);
        mb.Entity<UploadedReport>().HasIndex(e => e.DatabaseId);
        mb.Entity<UploadedReport>().HasIndex(e => new { e.QuestionnaireResponseId, e.QuestionId });
        mb.Entity<UploadedReport>().HasIndex(e => e.FileHash);

        // Schema: graph
        mb.Entity<GraphEdge>().ToTable("edge", "graph").HasKey(e => e.EdgeId);
        mb.Entity<GraphEdge>().HasOne(e => e.Project).WithMany().HasForeignKey(e => e.ProjectId);
        mb.Entity<GraphEdge>().HasOne(e => e.SourceDatabase).WithMany().HasForeignKey(e => e.SourceDatabaseId)
            .OnDelete(DeleteBehavior.Cascade);
        mb.Entity<GraphEdge>().HasOne(e => e.TargetDatabase).WithMany().HasForeignKey(e => e.TargetDatabaseId)
            .OnDelete(DeleteBehavior.Cascade);
        mb.Entity<GraphEdge>().HasIndex(e => e.ProjectId);

        mb.Entity<Portfolio>().ToTable("portfolio", "graph").HasKey(e => e.PortfolioId);
        mb.Entity<Portfolio>().Property(e => e.DatabaseIds).HasColumnType("jsonb");
        mb.Entity<Portfolio>().HasOne(e => e.Project).WithMany().HasForeignKey(e => e.ProjectId);
        mb.Entity<Portfolio>().HasIndex(e => e.ProjectId);

        // Schema: core — AI providers
        mb.Entity<AiProvider>().ToTable("ai_provider", "core").HasKey(e => e.ProviderId);

        // Schema: core — system config
        mb.Entity<SystemConfig>().ToTable("system_config", "core").HasKey(e => e.Key);

        // Schema: core — application users
        mb.Entity<AppUser>().ToTable("app_user", "core").HasKey(e => e.UserId);
        mb.Entity<AppUser>().HasIndex(e => e.NormalizedEmail).IsUnique();
        mb.Entity<AppUser>().Property(e => e.Email).HasMaxLength(320);
        mb.Entity<AppUser>().Property(e => e.NormalizedEmail).HasMaxLength(320);
        mb.Entity<AppUser>().Property(e => e.DisplayName).HasMaxLength(200);
        mb.Entity<AppUser>().Property(e => e.Role).HasMaxLength(32);

        // Schema: governance
        mb.Entity<ProjectMembership>().ToTable("project_membership", "core").HasKey(e => e.MembershipId);
        mb.Entity<ProjectMembership>().HasOne(e => e.Project).WithMany().HasForeignKey(e => e.ProjectId);
        mb.Entity<ProjectMembership>().HasOne(e => e.Environment).WithMany().HasForeignKey(e => e.EnvironmentId)
            .OnDelete(DeleteBehavior.Cascade);
        mb.Entity<ProjectMembership>().HasOne(e => e.User).WithMany().HasForeignKey(e => e.UserId);
        mb.Entity<ProjectMembership>().HasIndex(e => new { e.ProjectId, e.EnvironmentId, e.UserId }).IsUnique();
        mb.Entity<ProjectMembership>().Property(e => e.Role).HasMaxLength(32);

        mb.Entity<AuditEvent>().ToTable("audit_event", "audit").HasKey(e => e.AuditEventId);
        mb.Entity<AuditEvent>().HasIndex(e => new { e.ProjectId, e.OccurredAt });
        mb.Entity<AuditEvent>().Property(e => e.ActorId).HasMaxLength(100);
        mb.Entity<AuditEvent>().Property(e => e.Action).HasMaxLength(100);
        mb.Entity<AuditEvent>().Property(e => e.ResourceType).HasMaxLength(100);
        mb.Entity<AuditEvent>().Property(e => e.Method).HasMaxLength(16);

        // Schema: reporting
        mb.Entity<GeneratedReport>().ToTable("generated_report", "reporting").HasKey(e => e.GeneratedReportId);
        mb.Entity<GeneratedReport>().Property(e => e.ReportJson).HasColumnType("jsonb");
        mb.Entity<GeneratedReport>().HasOne(e => e.Project).WithMany().HasForeignKey(e => e.ProjectId);
        mb.Entity<GeneratedReport>().HasOne(e => e.Database).WithMany().HasForeignKey(e => e.DatabaseId)
            .OnDelete(DeleteBehavior.SetNull);
        mb.Entity<GeneratedReport>().HasOne(e => e.EvidenceBundle).WithMany().HasForeignKey(e => e.EvidenceBundleId)
            .OnDelete(DeleteBehavior.Restrict);
        mb.Entity<GeneratedReport>().HasIndex(e => new { e.ProjectId, e.GeneratedAt });
        mb.Entity<GeneratedReport>().HasIndex(e => new { e.DatabaseId, e.GeneratedAt });
        mb.Entity<GeneratedReport>().Property(e => e.State).HasMaxLength(32);

        mb.Entity<EvidenceBundle>().ToTable("evidence_bundle", "reporting").HasKey(e => e.EvidenceBundleId);
        mb.Entity<EvidenceBundle>().Property(e => e.BundleJson).HasColumnType("jsonb");
        mb.Entity<EvidenceBundle>().HasOne(e => e.Project).WithMany().HasForeignKey(e => e.ProjectId);
        mb.Entity<EvidenceBundle>().HasIndex(e => new { e.ProjectId, e.CreatedAt });
        mb.Entity<EvidenceBundle>().HasIndex(e => e.ContentHash);
    }
}
