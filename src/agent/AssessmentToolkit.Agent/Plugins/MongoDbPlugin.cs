using MongoDB.Bson;
using MongoDB.Driver;
using System.Text.Json;

namespace AssessmentToolkit.Agent.Plugins;

/// <summary>
/// Read-only MongoDB discovery for migration compatibility and sizing metadata.
/// Does not read application documents.
/// </summary>
public sealed class MongoDbPlugin : IAssessmentPlugin
{
    public string PluginId => "mongodb";
    public string PluginVersion => "1.0.0";
    public string TargetEngine => "MongoDB";

    public async Task<PluginResult> RunAsync(PluginContext context, CancellationToken ct)
    {
        try
        {
            var settings = new MongoClientSettings
            {
                Server = new MongoServerAddress(context.Host, context.Port),
                ConnectTimeout = TimeSpan.FromSeconds(30),
                ServerSelectionTimeout = TimeSpan.FromSeconds(30)
            };
            if (!string.IsNullOrWhiteSpace(context.Username))
            {
                settings.Credential = MongoCredential.CreateCredential(
                    string.IsNullOrWhiteSpace(context.Database) ? "admin" : context.Database,
                    context.Username,
                    context.Password);
            }

            var client = new MongoClient(settings);
            var databaseName = string.IsNullOrWhiteSpace(context.Database) ? "admin" : context.Database;
            var database = client.GetDatabase(databaseName);
            await database.RunCommandAsync<BsonDocument>(new BsonDocument("ping", 1), cancellationToken: ct);

            var findings = new Dictionary<string, object>();
            var sectionErrors = new Dictionary<string, string>();

            await CollectCommandAsync(findings, sectionErrors, "build_info", database,
                new BsonDocument("buildInfo", 1), ct);
            await CollectCommandAsync(findings, sectionErrors, "database_stats", database,
                new BsonDocument { { "dbStats", 1 }, { "scale", 1048576 } }, ct);
            await CollectCommandAsync(findings, sectionErrors, "feature_compatibility", client.GetDatabase("admin"),
                new BsonDocument { { "getParameter", 1 }, { "featureCompatibilityVersion", 1 } }, ct);
            await CollectCommandAsync(findings, sectionErrors, "replica_set", client.GetDatabase("admin"),
                new BsonDocument("replSetGetStatus", 1), ct);
            await CollectCommandAsync(findings, sectionErrors, "shards", client.GetDatabase("admin"),
                new BsonDocument("listShards", 1), ct);
            await CollectDatabaseNamesAsync(findings, sectionErrors, client, ct);
            await CollectCollectionsAsync(findings, sectionErrors, database, ct);

            if (sectionErrors.Count > 0)
                findings["section_errors"] = sectionErrors;

            var json = JsonSerializer.Serialize(findings);
            return new PluginResult(true, json, json);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return new PluginResult(false, "{}", "{}", ex.Message);
        }
    }

    private static async Task CollectCommandAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        string sectionName,
        IMongoDatabase database,
        BsonDocument command,
        CancellationToken ct)
    {
        try
        {
            var result = await database.RunCommandAsync<BsonDocument>(command, cancellationToken: ct);
            findings[sectionName] = ConvertDocument(result);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sectionErrors[sectionName] = ex.GetType().Name;
        }
    }

    private static async Task CollectDatabaseNamesAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        IMongoClient client,
        CancellationToken ct)
    {
        try
        {
            var names = await (await client.ListDatabaseNamesAsync(cancellationToken: ct)).ToListAsync(ct);
            findings["databases"] = names;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sectionErrors["databases"] = ex.GetType().Name;
        }
    }

    private static async Task CollectCollectionsAsync(
        IDictionary<string, object> findings,
        IDictionary<string, string> sectionErrors,
        IMongoDatabase database,
        CancellationToken ct)
    {
        try
        {
            var collectionDocuments = await (await database.ListCollectionsAsync(cancellationToken: ct)).ToListAsync(ct);
            var collections = new List<object>();

            foreach (var collectionDocument in collectionDocuments.Take(200))
            {
                var name = collectionDocument.GetValue("name", string.Empty).AsString;
                var collection = database.GetCollection<BsonDocument>(name);
                var indexes = new List<object>();
                try
                {
                    var indexDocuments = await (await collection.Indexes.ListAsync(ct)).ToListAsync(ct);
                    indexes.AddRange(indexDocuments.Select(ConvertDocument));
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    indexes.Add(new Dictionary<string, object?> { ["error"] = ex.GetType().Name });
                }

                collections.Add(new Dictionary<string, object?>
                {
                    ["name"] = name,
                    ["type"] = collectionDocument.GetValue("type", "collection").AsString,
                    ["options"] = collectionDocument.TryGetValue("options", out var options) ? ConvertValue(options) : null,
                    ["estimated_document_count"] = await collection.EstimatedDocumentCountAsync(cancellationToken: ct),
                    ["indexes"] = indexes
                });
            }

            findings["collections"] = collections;
            findings["collection_count"] = collectionDocuments.Count;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sectionErrors["collections"] = ex.GetType().Name;
        }
    }

    private static Dictionary<string, object?> ConvertDocument(BsonDocument document) =>
        document.Elements.ToDictionary(element => element.Name, element => ConvertValue(element.Value));

    private static object? ConvertValue(BsonValue value) => value.BsonType switch
    {
        BsonType.Document => ConvertDocument(value.AsBsonDocument),
        BsonType.Array => value.AsBsonArray.Select(ConvertValue).ToList(),
        BsonType.Null => null,
        BsonType.Boolean => value.AsBoolean,
        BsonType.Int32 => value.AsInt32,
        BsonType.Int64 => value.AsInt64,
        BsonType.Double => value.AsDouble,
        BsonType.Decimal128 => value.AsDecimal128.ToString(),
        BsonType.String => value.AsString,
        BsonType.DateTime => value.ToUniversalTime(),
        _ => value.ToString()
    };
}