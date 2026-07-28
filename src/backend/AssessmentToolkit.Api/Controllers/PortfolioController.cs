using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/portfolios")]
public class PortfolioController(AssessmentDbContext db) : ControllerBase
{
    // ── List portfolios for a project ─────────────────────────────────────

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] Guid projectId)
    {
        var portfolios = await db.Portfolios
            .Where(p => p.ProjectId == projectId)
            .OrderBy(p => p.CreatedAt)
            .Select(p => new
            {
                p.PortfolioId,
                p.ProjectId,
                p.Name,
                p.GroupingRule,
                p.GroupKey,
                p.DatabaseIds,
                p.Notes,
                p.CreatedAt,
                p.UpdatedAt,
            })
            .ToListAsync();

        return Ok(portfolios);
    }

    // ── Get a single portfolio ────────────────────────────────────────────

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        var p = await db.Portfolios.FindAsync(id);
        return p is null ? NotFound() : Ok(p);
    }

    // ── Create (save) a portfolio ─────────────────────────────────────────

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] SavePortfolioRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Name))
            return BadRequest("Name is required.");

        var portfolio = new Portfolio
        {
            ProjectId    = req.ProjectId,
            Name         = req.Name.Trim(),
            GroupingRule = req.GroupingRule,
            GroupKey     = req.GroupKey,
            DatabaseIds  = req.DatabaseIds,
            Notes        = req.Notes,
        };

        db.Portfolios.Add(portfolio);
        await db.SaveChangesAsync();

        return CreatedAtAction(nameof(Get), new { id = portfolio.PortfolioId }, new
        {
            portfolio.PortfolioId,
            portfolio.Name,
            portfolio.GroupingRule,
            portfolio.GroupKey,
            portfolio.DatabaseIds,
            portfolio.CreatedAt,
        });
    }

    // ── Update a portfolio ────────────────────────────────────────────────

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdatePortfolioRequest req)
    {
        var portfolio = await db.Portfolios.FindAsync(id);
        if (portfolio is null) return NotFound();

        if (req.Name is not null)    portfolio.Name  = req.Name.Trim();
        if (req.Notes is not null)   portfolio.Notes = req.Notes;
        portfolio.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync();
        return Ok(portfolio);
    }

    // ── Delete ────────────────────────────────────────────────────────────

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var portfolio = await db.Portfolios.FindAsync(id);
        if (portfolio is null) return NotFound();
        db.Portfolios.Remove(portfolio);
        await db.SaveChangesAsync();
        return NoContent();
    }
}

public record SavePortfolioRequest(
    Guid ProjectId,
    string Name,
    string GroupingRule,
    string GroupKey,
    List<Guid> DatabaseIds,
    string? Notes);

public record UpdatePortfolioRequest(string? Name, string? Notes);
