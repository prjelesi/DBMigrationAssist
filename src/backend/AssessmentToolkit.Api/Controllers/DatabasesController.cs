using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;
using AssessmentToolkit.Api.Services;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NPOI.SS.UserModel;
using NPOI.XSSF.UserModel;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/databases")]
public class DatabasesController(AssessmentDbContext db) : ControllerBase
{
    private static readonly string[] ImportHeaders =
        ["Name", "Engine", "Version", "HostName", "Port", "Criticality", "OwnerName", "Environment"];

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] Guid projectId, [FromQuery] Guid? environmentId)
    {
        var query = db.Databases.Include(d => d.Environment)
            .Where(d => d.ProjectId == projectId);

        if (environmentId.HasValue)
            query = query.Where(d => d.EnvironmentId == environmentId);

        return Ok(await query.OrderBy(d => d.Name).ToListAsync());
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        var db2 = await db.Databases.Include(d => d.Environment)
            .Include(d => d.Results)
            .FirstOrDefaultAsync(d => d.DatabaseId == id);
        return db2 is null ? NotFound() : Ok(db2);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateDatabaseRequest req)
    {
        var project = await db.Projects.FindAsync(req.ProjectId);
        if (project is null) return BadRequest("Project not found.");

        var instance = new DatabaseInstance
        {
            ProjectId = req.ProjectId,
            EnvironmentId = req.EnvironmentId,
            Name = req.Name,
            Engine = req.Engine,
            Version = req.Version,
            HostName = req.HostName,
            Port = req.Port,
            Criticality = req.Criticality,
            OwnerName = req.OwnerName
        };

        db.Databases.Add(instance);
        await db.SaveChangesAsync();
        return CreatedAtAction(nameof(Get), new { id = instance.DatabaseId }, instance);
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken)
    {
        var database = await db.Databases.FindAsync([id], cancellationToken);
        if (database is null) return NotFound();

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        await db.Jobs
            .Where(job => job.DatabaseId == id)
            .ExecuteUpdateAsync(update => update.SetProperty(job => job.DatabaseId, (Guid?)null), cancellationToken);
        await db.Results
            .Where(result => result.DatabaseId == id)
            .ExecuteUpdateAsync(update => update.SetProperty(result => result.DatabaseId, (Guid?)null), cancellationToken);

        var portfolios = await db.Portfolios
            .Where(portfolio => portfolio.ProjectId == database.ProjectId)
            .ToListAsync(cancellationToken);
        foreach (var portfolio in portfolios.Where(portfolio => portfolio.DatabaseIds.Remove(id)))
            db.Entry(portfolio).Property(item => item.DatabaseIds).IsModified = true;

        db.Databases.Remove(database);
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return NoContent();
    }

    [HttpGet("{id:guid}/assessment-script")]
    public async Task<IActionResult> DownloadAssessmentScript(Guid id)
    {
        var database = await db.Databases.FindAsync(id);
        if (database is null) return NotFound();

        try
        {
            var (_, script) = OfflineAssessmentScriptFactory.Create(database);
            var fileName = $"collect-{SanitizeFileName(database.Name)}-assessment.ps1";
            return File(Encoding.UTF8.GetBytes(script), "text/plain; charset=utf-8", fileName);
        }
        catch (NotSupportedException exception)
        {
            return BadRequest(new { message = exception.Message });
        }
    }

    [HttpPost("{id:guid}/assessment-results")]
    [RequestSizeLimit(10_485_760)]
    public async Task<IActionResult> UploadAssessmentResult(Guid id, IFormFile file)
    {
        var database = await db.Databases.FindAsync(id);
        if (database is null) return NotFound();
        if (file.Length == 0) return BadRequest(new { message = "The result file is empty." });
        if (file.Length > 10_485_760) return BadRequest(new { message = "The result file must not exceed 10 MB." });
        if (!Path.GetExtension(file.FileName).Equals(".json", StringComparison.OrdinalIgnoreCase))
            return BadRequest(new { message = "Upload the JSON file produced by the offline assessment script." });

        byte[] payload;
        await using (var input = file.OpenReadStream())
        await using (var buffer = new MemoryStream())
        {
            await input.CopyToAsync(buffer);
            payload = buffer.ToArray();
        }

        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(payload, new JsonDocumentOptions { MaxDepth = 64 });
        }
        catch (JsonException)
        {
            return BadRequest(new { message = "The uploaded file is not valid JSON." });
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !TryGetString(root, "databaseId", out var databaseIdValue) ||
                !Guid.TryParse(databaseIdValue, out var embeddedDatabaseId) ||
                embeddedDatabaseId != id)
                return BadRequest(new { message = "The result file was generated for a different database." });

            if (!TryGetString(root, "schemaVersion", out var schemaVersion) || schemaVersion != "1.0")
                return BadRequest(new { message = "Unsupported or missing result schemaVersion." });

            var expectedPluginId = OfflineAssessmentScriptFactory.GetPluginId(database.Engine);
            if (!TryGetString(root, "pluginId", out var pluginId) || pluginId != expectedPluginId)
                return BadRequest(new { message = $"The result plugin must be '{expectedPluginId}' for this database." });

            if (!root.TryGetProperty("findingJson", out var finding) || finding.ValueKind != JsonValueKind.Object)
                return BadRequest(new { message = "The result file must contain a findingJson object." });

            var rawSummary = root.TryGetProperty("rawSummaryJson", out var summary) && summary.ValueKind == JsonValueKind.Object
                ? summary.GetRawText()
                : "{}";
            var pluginVersion = TryGetString(root, "pluginVersion", out var version) ? version : "offline-1.0";
            var assessedAt = TryGetString(root, "assessedAt", out var assessedAtValue) &&
                             DateTimeOffset.TryParse(assessedAtValue, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsedAssessedAt)
                ? parsedAssessedAt
                : DateTimeOffset.UtcNow;
            var completedAt = DateTimeOffset.UtcNow;
            var job = new AssessmentJob
            {
                AgentId = null,
                DatabaseId = id,
                PluginId = pluginId,
                Status = JobStatus.Completed,
                ParametersJson = JsonSerializer.Serialize(new { source = "ManualUpload", fileName = Path.GetFileName(file.FileName) }),
                StartedAt = assessedAt,
                CompletedAt = completedAt,
                UpdatedAt = completedAt
            };
            var result = new AssessmentResult
            {
                JobId = job.JobId,
                DatabaseId = id,
                PluginId = pluginId,
                PluginVersion = pluginVersion[..Math.Min(pluginVersion.Length, 100)],
                Confidence = ConfidenceLevel.Unverified,
                FindingJson = finding.GetRawText(),
                RawSummaryJson = rawSummary,
                PayloadHash = Convert.ToHexString(SHA256.HashData(payload)),
                AssessedAt = assessedAt
            };

            db.Jobs.Add(job);
            db.Results.Add(result);
            await db.SaveChangesAsync();
            return Created($"/api/databases/{id}/assessment-results/{result.ResultId}", new
            {
                result.ResultId,
                result.DatabaseId,
                result.PluginId,
                result.Confidence,
                result.AssessedAt
            });
        }
    }

    [HttpGet("import-template")]
    public IActionResult DownloadImportTemplate()
    {
        using var workbook = new XSSFWorkbook();
        var sheet = workbook.CreateSheet("Databases");
        sheet.CreateFreezePane(0, 1);

        var headerStyle = workbook.CreateCellStyle();
        headerStyle.FillForegroundColor = IndexedColors.DarkBlue.Index;
        headerStyle.FillPattern = FillPattern.SolidForeground;
        var headerFont = workbook.CreateFont();
        headerFont.IsBold = true;
        headerFont.Color = IndexedColors.White.Index;
        headerFont.FontName = "Arial";
        headerStyle.SetFont(headerFont);

        var header = sheet.CreateRow(0);
        for (var index = 0; index < ImportHeaders.Length; index++)
        {
            var cell = header.CreateCell(index);
            cell.SetCellValue(ImportHeaders[index]);
            cell.CellStyle = headerStyle;
            sheet.SetColumnWidth(index, (index is 0 or 3 or 6 or 7 ? 28 : 18) * 256);
        }

        var instructions = workbook.CreateSheet("Instructions");
        var lines = new[]
        {
            "Enter one database per row on the Databases sheet. Do not rename the columns.",
            "Required: Name, Engine, HostName, Port.",
            "Engine: Oracle, PostgreSQL, SqlServer, MySQL, MongoDB, Cassandra, or Sybase.",
            "Criticality: Critical, High, Medium, or Low. Blank defaults to Medium.",
            "Environment is optional and must exactly match an environment name in the selected project.",
            "The import is atomic: any invalid row prevents all rows from being imported."
        };
        for (var index = 0; index < lines.Length; index++)
            instructions.CreateRow(index).CreateCell(0).SetCellValue(lines[index]);
        instructions.SetColumnWidth(0, 100 * 256);

        using var output = new MemoryStream();
        workbook.Write(output, leaveOpen: true);
        return File(
            output.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "database-inventory-import-template.xlsx");
    }

    [HttpPost("import")]
    [RequestSizeLimit(5_242_880)]
    public async Task<IActionResult> Import([FromForm] Guid projectId, IFormFile file)
    {
        if (file.Length == 0) return BadRequest(new { message = "The spreadsheet is empty." });
        if (file.Length > 5_242_880) return BadRequest(new { message = "The spreadsheet must not exceed 5 MB." });
        if (!new[] { ".xlsx", ".xls" }.Contains(Path.GetExtension(file.FileName), StringComparer.OrdinalIgnoreCase))
            return BadRequest(new { message = "Upload an .xlsx or .xls file." });
        if (!await db.Projects.AnyAsync(project => project.ProjectId == projectId))
            return BadRequest(new { message = "Project not found." });

        IWorkbook workbook;
        try
        {
            await using var stream = file.OpenReadStream();
            workbook = WorkbookFactory.Create(stream);
        }
        catch (Exception exception) when (exception is IOException or InvalidOperationException)
        {
            return BadRequest(new { message = "The file is not a valid Excel workbook." });
        }

        using (workbook)
        {
            var sheet = workbook.GetSheet("Databases") ?? workbook.GetSheetAt(0);
            var headerRow = sheet.GetRow(sheet.FirstRowNum);
            if (headerRow is null)
                return BadRequest(new { message = "The spreadsheet does not contain a header row." });

            var columns = Enumerable.Range(headerRow.FirstCellNum, headerRow.LastCellNum - headerRow.FirstCellNum)
                .ToDictionary(index => GetCellValue(headerRow.GetCell(index)), index => index, StringComparer.OrdinalIgnoreCase);
            var missingHeaders = ImportHeaders.Where(name => !columns.ContainsKey(name)).ToArray();
            if (missingHeaders.Length > 0)
                return BadRequest(new { message = $"Missing columns: {string.Join(", ", missingHeaders)}." });

            var environments = await db.Environments
                .Where(environment => environment.ProjectId == projectId)
                .ToDictionaryAsync(environment => environment.Name, environment => environment.EnvironmentId);
            var existingNameList = await db.Databases
                .Where(database => database.ProjectId == projectId)
                .Select(database => database.Name.ToLower())
                .ToListAsync();
            var existingNames = existingNameList.ToHashSet(StringComparer.OrdinalIgnoreCase);
            var importedNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var instances = new List<DatabaseInstance>();
            var errors = new List<object>();

            for (var rowIndex = sheet.FirstRowNum + 1; rowIndex <= sheet.LastRowNum; rowIndex++)
            {
                var row = sheet.GetRow(rowIndex);
                if (row is null) continue;

                string Value(string column) => GetCellValue(row.GetCell(columns[column]));
                var values = ImportHeaders.ToDictionary(header => header, Value);
                if (values.Values.All(string.IsNullOrWhiteSpace)) continue;
                if (instances.Count + errors.Count >= 1000)
                {
                    errors.Add(new { row = rowIndex + 1, message = "A maximum of 1,000 data rows can be imported." });
                    break;
                }

                var rowErrors = new List<string>();
                var name = values["Name"];
                if (string.IsNullOrWhiteSpace(name)) rowErrors.Add("Name is required.");
                else if (existingNames.Contains(name.ToLower()) || !importedNames.Add(name)) rowErrors.Add("Name already exists in this project or file.");

                if (!TryParseEngine(values["Engine"], out var engine)) rowErrors.Add("Engine is invalid.");
                if (string.IsNullOrWhiteSpace(values["HostName"])) rowErrors.Add("HostName is required.");
                if (!int.TryParse(values["Port"], out var port) || port is < 1 or > 65535) rowErrors.Add("Port must be between 1 and 65535.");

                var criticality = Criticality.Medium;
                if (!string.IsNullOrWhiteSpace(values["Criticality"]) &&
                    !Enum.TryParse(values["Criticality"], true, out criticality))
                    rowErrors.Add("Criticality is invalid.");

                Guid? environmentId = null;
                if (!string.IsNullOrWhiteSpace(values["Environment"]))
                {
                    var match = environments.FirstOrDefault(pair => pair.Key.Equals(values["Environment"], StringComparison.OrdinalIgnoreCase));
                    if (match.Key is null) rowErrors.Add("Environment was not found in the selected project.");
                    else environmentId = match.Value;
                }

                if (rowErrors.Count > 0)
                {
                    errors.Add(new { row = rowIndex + 1, message = string.Join(" ", rowErrors) });
                    continue;
                }

                instances.Add(new DatabaseInstance
                {
                    ProjectId = projectId,
                    EnvironmentId = environmentId,
                    Name = name,
                    Engine = engine,
                    Version = NullIfEmpty(values["Version"]),
                    HostName = values["HostName"],
                    Port = port,
                    Criticality = criticality,
                    OwnerName = NullIfEmpty(values["OwnerName"])
                });
            }

            if (errors.Count > 0)
                return BadRequest(new { message = "No databases were imported. Correct the listed rows and upload again.", errors });
            if (instances.Count == 0)
                return BadRequest(new { message = "The spreadsheet does not contain any database rows." });

            db.Databases.AddRange(instances);
            await db.SaveChangesAsync();
            return Ok(new { imported = instances.Count });
        }
    }

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateDatabaseRequest req)
    {
        var instance = await db.Databases.FindAsync(id);
        if (instance is null) return NotFound();

        if (req.Criticality.HasValue) instance.Criticality = req.Criticality.Value;
        if (req.OwnerName is not null) instance.OwnerName = req.OwnerName;
        if (req.Version is not null) instance.Version = req.Version;
        instance.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync();
        return Ok(instance);
    }

    private static string GetCellValue(ICell? cell)
    {
        if (cell is null) return string.Empty;

        var cellType = cell.CellType == CellType.Formula ? cell.CachedFormulaResultType : cell.CellType;
        return cellType switch
        {
            CellType.String => cell.StringCellValue.Trim(),
            CellType.Numeric => cell.NumericCellValue.ToString("G15", CultureInfo.InvariantCulture),
            CellType.Boolean => cell.BooleanCellValue.ToString(CultureInfo.InvariantCulture),
            _ => string.Empty
        };
    }

    private static string? NullIfEmpty(string value) => string.IsNullOrWhiteSpace(value) ? null : value;

    private static bool TryGetString(JsonElement element, string propertyName, out string value)
    {
        if (element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String)
        {
            value = property.GetString() ?? string.Empty;
            return true;
        }

        value = string.Empty;
        return false;
    }

    private static string SanitizeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var sanitized = new string(value.Select(character => invalid.Contains(character) ? '-' : character).ToArray());
        return string.IsNullOrWhiteSpace(sanitized) ? "database" : sanitized;
    }

    private static bool TryParseEngine(string value, out EngineType engine)
    {
        if (value.Equals("SQL Server", StringComparison.OrdinalIgnoreCase)) value = nameof(EngineType.SqlServer);
        if (value.Equals("Postgres", StringComparison.OrdinalIgnoreCase)) value = nameof(EngineType.PostgreSQL);
        return Enum.TryParse(value, true, out engine) && engine != EngineType.Unknown;
    }
}

public record CreateDatabaseRequest(
    Guid ProjectId, Guid? EnvironmentId, string Name,
    EngineType Engine, string? Version, string? HostName,
    int? Port, Criticality Criticality, string? OwnerName);

public record UpdateDatabaseRequest(
    Criticality? Criticality, string? OwnerName, string? Version);
