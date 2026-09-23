using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Core.Enums;

namespace AssessmentToolkit.Api.Services;

public static class AssessmentResultSelection
{
    public static IQueryable<AssessmentResult> LatestSuccessfulPerDatabase(
        this IQueryable<AssessmentResult> source)
    {
        var successful = source.Where(result => result.Job.Status == JobStatus.Completed);
        var latest = successful
            .GroupBy(result => new { result.DatabaseId, result.PluginId })
            .Select(group => new
            {
                group.Key.DatabaseId,
                group.Key.PluginId,
                AssessedAt = group.Max(result => result.AssessedAt)
            });

        return
            from result in successful
            join latestResult in latest
                on new { result.DatabaseId, result.PluginId, result.AssessedAt }
                equals new { latestResult.DatabaseId, latestResult.PluginId, latestResult.AssessedAt }
            select result;
    }
}
