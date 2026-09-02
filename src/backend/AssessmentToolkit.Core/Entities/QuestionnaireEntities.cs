using AssessmentToolkit.Core.Enums;

namespace AssessmentToolkit.Core.Entities;

/// <summary>Reusable questionnaire template (e.g. "Database Migration Baseline").</summary>
public class QuestionnaireTemplate
{
    public Guid TemplateId { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public QuestionnairePhase Phase { get; set; }
    public int Version { get; set; } = 1;
    public bool IsActive { get; set; } = true;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ICollection<QuestionnaireSection> Sections { get; set; } = [];
}

/// <summary>Logical section grouping within a template.</summary>
public class QuestionnaireSection
{
    public Guid SectionId { get; set; } = Guid.NewGuid();
    public Guid TemplateId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int Order { get; set; }

    public QuestionnaireTemplate Template { get; set; } = null!;
    public ICollection<Question> Questions { get; set; } = [];
}

/// <summary>Individual question within a section.</summary>
public class Question
{
    public Guid QuestionId { get; set; } = Guid.NewGuid();
    public Guid SectionId { get; set; }
    public string Text { get; set; } = string.Empty;
    public string? HelpText { get; set; }
    public QuestionType Type { get; set; }
    public bool IsRequired { get; set; }
    public bool AllowCustomAnswer { get; set; }
    public bool AllowAttachments { get; set; }
    public int Order { get; set; }
    /// <summary>JSON array of option strings for Select/MultiSelect types.</summary>
    public string? OptionsJson { get; set; }

    public QuestionnaireSection Section { get; set; } = null!;
}

/// <summary>A project-wide or database-specific instance of a questionnaire template.</summary>
public class QuestionnaireResponse
{
    public Guid ResponseId { get; set; } = Guid.NewGuid();
    public Guid ProjectId { get; set; }
    public Guid? DatabaseId { get; set; }
    public Guid TemplateId { get; set; }
    public ResponseStatus Status { get; set; } = ResponseStatus.NotStarted;
    public string? AssignedTo { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? SubmittedAt { get; set; }

    public Project Project { get; set; } = null!;
    public DatabaseInstance? Database { get; set; }
    public QuestionnaireTemplate Template { get; set; } = null!;
    public ICollection<Answer> Answers { get; set; } = [];
}

/// <summary>A single answer to a question within a response.</summary>
public class Answer
{
    public Guid AnswerId { get; set; } = Guid.NewGuid();
    public Guid ResponseId { get; set; }
    public Guid QuestionId { get; set; }
    /// <summary>Stored as plain text or JSON depending on question type.</summary>
    public string? Value { get; set; }
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public QuestionnaireResponse Response { get; set; } = null!;
    public Question Question { get; set; } = null!;
}
