using AssessmentToolkit.Core.Entities;
using AssessmentToolkit.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AssessmentToolkit.Api.Controllers;

[ApiController]
[Route("api/users")]
[Authorize(Roles = "Administrator")]
public sealed class UsersController(
    AssessmentDbContext db,
    IPasswordHasher<AppUser> passwordHasher) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) =>
        Ok(await db.AppUsers.AsNoTracking()
            .OrderBy(user => user.Email)
            .Select(user => new
            {
                user.UserId, user.Email, user.DisplayName, user.Role,
                user.IsActive, user.CreatedAt, user.LastLoginAt
            })
            .ToListAsync(ct));

    [HttpPost]
    public async Task<IActionResult> Create(CreateUserRequest request, CancellationToken ct)
    {
        var email = request.Email.Trim();
        var normalizedEmail = email.ToUpperInvariant();
        if (await db.AppUsers.AnyAsync(user => user.NormalizedEmail == normalizedEmail, ct))
            return Conflict(new { message = "A user with this email already exists." });
        if (request.Password.Length < 12)
            return BadRequest(new { message = "Password must be at least 12 characters." });

        var user = new AppUser
        {
            Email = email,
            NormalizedEmail = normalizedEmail,
            DisplayName = request.DisplayName.Trim(),
            Role = "User"
        };
        user.PasswordHash = passwordHasher.HashPassword(user, request.Password);
        db.AppUsers.Add(user);
        await db.SaveChangesAsync(ct);
        return CreatedAtAction(nameof(List), new { }, new
        {
            user.UserId, user.Email, user.DisplayName, user.Role, user.IsActive, user.CreatedAt
        });
    }

    [HttpPatch("{id:guid}/status")]
    public async Task<IActionResult> SetStatus(Guid id, SetUserStatusRequest request, CancellationToken ct)
    {
        var user = await db.AppUsers.SingleOrDefaultAsync(candidate => candidate.UserId == id, ct);
        if (user is null) return NotFound();
        user.IsActive = request.IsActive;
        await db.SaveChangesAsync(ct);
        return NoContent();
    }
}

public sealed record CreateUserRequest(string Email, string DisplayName, string Password);
public sealed record SetUserStatusRequest(bool IsActive);