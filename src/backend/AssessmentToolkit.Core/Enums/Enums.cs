namespace AssessmentToolkit.Core.Enums;

public enum DeploymentMode { Standalone, Connected, AirGapped }

public enum EngineType { Oracle, PostgreSQL, SqlServer, MySQL, MongoDB, Cassandra, Sybase, Unknown }

public enum AgentStatus { Registered, Active, Offline, Revoked }

public enum JobStatus { Pending, Assigned, Running, Completed, Failed, Cancelled }

public enum ConfidenceLevel { High, Medium, Low, Unverified }

public enum ReportState
{
    Pending,
    QuestionnaireActive,
    BundleReady,
    AiGenerating,
    DraftReady,
    InReview,
    Approved,
    Exported
}

public enum Criticality { Low, Medium, High, Critical }

public enum PskMode { SystemGenerated, UserSupplied }

public enum ParseStatus { Pending, Parsing, Parsed, Failed, ReviewRequired }

public enum ReportSourceType { DmaJson, Awr, Statspack, AzureMigrate, CsvGeneric, JsonGeneric, Other }
