using System.Text.Json;
using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;

namespace AssessmentToolkit.Api.Services;

public interface IQuestionnaireTemplateLoader
{
    IReadOnlyList<QuestionnaireTemplate> LoadTemplates();
}

public sealed class QuestionnaireTemplateLoader(IWebHostEnvironment environment) : IQuestionnaireTemplateLoader
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true
    };

    public IReadOnlyList<QuestionnaireTemplate> LoadTemplates()
    {
        var directory = Path.Combine(environment.ContentRootPath, "QuestionnaireTemplates");
        if (!Directory.Exists(directory))
            throw new DirectoryNotFoundException($"Questionnaire template directory was not found: {directory}");

        var templates = Directory.EnumerateFiles(directory, "*.json", SearchOption.TopDirectoryOnly)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .Select(LoadTemplate)
            .ToList();

        if (templates.Count == 0)
            throw new InvalidDataException($"No JSON questionnaire templates were found in {directory}.");

        var duplicate = templates
            .GroupBy(template => new { template.Name, template.Version })
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
            throw new InvalidDataException($"Duplicate questionnaire template '{duplicate.Key.Name}' version {duplicate.Key.Version}.");

        return templates;
    }

    private QuestionnaireTemplate LoadTemplate(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            var definition = JsonSerializer.Deserialize<TemplateDefinition>(stream, SerializerOptions)
                ?? throw new InvalidDataException("The file is empty.");
            Validate(definition);

            var template = new QuestionnaireTemplate
            {
                Name = definition.Name.Trim(),
                Description = definition.Description?.Trim(),
                Phase = ParseEnum<QuestionnairePhase>(definition.Phase, "phase"),
                Version = definition.Version
            };

            foreach (var (sectionDefinition, sectionIndex) in definition.Sections.Select((value, index) => (value, index)))
            {
                var section = new QuestionnaireSection
                {
                    Title = sectionDefinition.Title.Trim(),
                    Description = sectionDefinition.Description?.Trim(),
                    Order = sectionIndex + 1
                };

                foreach (var (questionDefinition, questionIndex) in sectionDefinition.Questions.Select((value, index) => (value, index)))
                {
                    var type = ParseEnum<QuestionType>(questionDefinition.Type, "question type");
                    if (type is QuestionType.Select or QuestionType.MultiSelect && questionDefinition.Options.Count == 0)
                        throw new InvalidDataException($"Question '{questionDefinition.Text}' requires at least one option.");
                    if (questionDefinition.AllowCustomAnswer && type is not (QuestionType.Select or QuestionType.MultiSelect))
                        throw new InvalidDataException($"Question '{questionDefinition.Text}' can allow custom answers only for Select or MultiSelect types.");

                    section.Questions.Add(new Question
                    {
                        Text = questionDefinition.Text.Trim(),
                        HelpText = questionDefinition.HelpText?.Trim(),
                        Type = type,
                        IsRequired = questionDefinition.Required,
                        AllowCustomAnswer = questionDefinition.AllowCustomAnswer,
                        AllowAttachments = questionDefinition.AllowAttachments,
                        Order = questionIndex + 1,
                        OptionsJson = questionDefinition.Options.Count == 0
                            ? null
                            : JsonSerializer.Serialize(questionDefinition.Options)
                    });
                }

                template.Sections.Add(section);
            }

            return template;
        }
        catch (Exception exception) when (exception is not InvalidDataException)
        {
            throw new InvalidDataException($"Cannot load questionnaire template '{Path.GetFileName(path)}': {exception.Message}", exception);
        }
    }

    private static void Validate(TemplateDefinition definition)
    {
        if (string.IsNullOrWhiteSpace(definition.Name))
            throw new InvalidDataException("Template name is required.");
        if (definition.Version < 1)
            throw new InvalidDataException($"Template '{definition.Name}' must have a version of 1 or greater.");
        if (definition.Sections.Count == 0)
            throw new InvalidDataException($"Template '{definition.Name}' must contain at least one section.");

        foreach (var section in definition.Sections)
        {
            if (string.IsNullOrWhiteSpace(section.Title))
                throw new InvalidDataException($"Template '{definition.Name}' contains a section without a title.");
            if (section.Questions.Count == 0)
                throw new InvalidDataException($"Section '{section.Title}' must contain at least one question.");
            if (section.Questions.Any(question => string.IsNullOrWhiteSpace(question.Text)))
                throw new InvalidDataException($"Section '{section.Title}' contains a question without text.");
        }
    }

    private static TEnum ParseEnum<TEnum>(string value, string fieldName) where TEnum : struct, Enum
    {
        if (Enum.TryParse<TEnum>(value, true, out var result))
            return result;
        throw new InvalidDataException($"Unsupported {fieldName} '{value}'. Allowed values: {string.Join(", ", Enum.GetNames<TEnum>())}.");
    }

    private sealed class TemplateDefinition
    {
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string Phase { get; set; } = nameof(QuestionnairePhase.Baseline);
        public int Version { get; set; } = 1;
        public List<SectionDefinition> Sections { get; set; } = [];
    }

    private sealed class SectionDefinition
    {
        public string Title { get; set; } = string.Empty;
        public string? Description { get; set; }
        public List<QuestionDefinition> Questions { get; set; } = [];
    }

    private sealed class QuestionDefinition
    {
        public string Text { get; set; } = string.Empty;
        public string? HelpText { get; set; }
        public string Type { get; set; } = nameof(QuestionType.Text);
        public bool Required { get; set; }
        public bool AllowCustomAnswer { get; set; }
        public bool AllowAttachments { get; set; }
        public List<string> Options { get; set; } = [];
    }
}
