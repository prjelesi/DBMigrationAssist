using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/graph")]
public class GraphController(AssessmentDbContext db) : ControllerBase
{
    // ── GET edges for a project ───────────────────────────────────────────

    [HttpGet("edges")]
    public async Task<IActionResult> GetEdges([FromQuery] Guid projectId)
    {
        var edges = await db.GraphEdges
            .Where(e => e.ProjectId == projectId)
            .OrderBy(e => e.CreatedAt)
            .Select(e => new
            {
                e.EdgeId,
                e.ProjectId,
                e.SourceDatabaseId,
                e.TargetDatabaseId,
                e.RelationType,
                e.Protocol,
                e.Direction,
                e.Confidence,
                e.Notes,
                e.CreatedAt,
                e.UpdatedAt,
            })
            .ToListAsync();

        return Ok(edges);
    }

    // ── Batch save (replace all edges for a project) ──────────────────────

    /// <summary>
    /// Replaces all edges for the given project in a single transaction.
    /// The frontend sends the full canvas state; we delete stale rows and
    /// upsert what is currently on the canvas.
    /// </summary>
    [HttpPost("edges/batch")]
    public async Task<IActionResult> BatchSave([FromBody] BatchSaveRequest req)
    {
        if (req.ProjectId == Guid.Empty) return BadRequest("projectId is required.");

        await using var tx = await db.Database.BeginTransactionAsync();

        // Remove edges that are no longer in the canvas
        var incoming = req.Edges.Select(e => e.EdgeId).ToHashSet();
        var toDelete = await db.GraphEdges
            .Where(e => e.ProjectId == req.ProjectId && !incoming.Contains(e.EdgeId))
            .ToListAsync();
        db.GraphEdges.RemoveRange(toDelete);

        // Upsert
        foreach (var dto in req.Edges)
        {
            var existing = await db.GraphEdges.FindAsync(dto.EdgeId);
            if (existing is null)
            {
                db.GraphEdges.Add(new GraphEdge
                {
                    EdgeId           = dto.EdgeId,
                    ProjectId        = req.ProjectId,
                    SourceDatabaseId = dto.SourceDatabaseId,
                    TargetDatabaseId = dto.TargetDatabaseId,
                    RelationType     = dto.RelationType ?? "COMMUNICATES_WITH",
                    Protocol         = dto.Protocol    ?? "Unknown",
                    Direction        = dto.Direction   ?? "Bidirectional",
                    Confidence       = dto.Confidence  ?? "Unverified",
                    Notes            = dto.Notes,
                });
            }
            else
            {
                existing.Confidence  = dto.Confidence  ?? existing.Confidence;
                existing.Protocol    = dto.Protocol    ?? existing.Protocol;
                existing.Direction   = dto.Direction   ?? existing.Direction;
                existing.RelationType = dto.RelationType ?? existing.RelationType;
                existing.Notes       = dto.Notes       ?? existing.Notes;
                existing.UpdatedAt   = DateTimeOffset.UtcNow;
            }
        }

        await db.SaveChangesAsync();
        await tx.CommitAsync();

        return Ok(new { saved = req.Edges.Count, deleted = toDelete.Count });
    }

    // ── Delete a single edge ──────────────────────────────────────────────

    [HttpDelete("edges/{edgeId:guid}")]
    public async Task<IActionResult> DeleteEdge(Guid edgeId)
    {
        var edge = await db.GraphEdges.FindAsync(edgeId);
        if (edge is null) return NotFound();
        db.GraphEdges.Remove(edge);
        await db.SaveChangesAsync();
        return NoContent();
    }
}

// ── Request models ────────────────────────────────────────────────────────────

public record BatchSaveRequest(Guid ProjectId, List<EdgeDto> Edges);

public record EdgeDto(
    Guid   EdgeId,
    Guid   SourceDatabaseId,
    Guid   TargetDatabaseId,
    string? RelationType,
    string? Protocol,
    string? Direction,
    string? Confidence,
    string? Notes);
