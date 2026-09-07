using System.Security.Cryptography;
using System.Text;

namespace AssessmentToolkit.Shared.Auth;

/// <summary>
/// Computes and verifies per-agent HMAC-SHA256 signatures for PSK authentication.
/// Signature covers: HTTP method, path, UTC timestamp, request nonce and SHA-256 body hash.
/// Requests with a timestamp outside ±5 minutes of server time are rejected.
/// </summary>
public static class PskAuthenticator
{
    public static readonly TimeSpan ReplayWindow = TimeSpan.FromMinutes(5);

    public static string ComputeSignature(
        string psk,
        string method,
        string path,
        string timestamp,
        string nonce,
        string bodyHash)
    {
        var message = $"{method.ToUpperInvariant()}\n{path}\n{timestamp}\n{nonce}\n{bodyHash}";
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(psk));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(message));
        return Convert.ToBase64String(hash);
    }

    public static string ComputeBodyHash(ReadOnlySpan<byte> body)
    {
        Span<byte> hash = stackalloc byte[32];
        SHA256.HashData(body, hash);
        return Convert.ToBase64String(hash);
    }

    public static bool Verify(
        string psk,
        string method,
        string path,
        string timestamp,
        string nonce,
        string bodyHash,
        string providedSignature)
    {
        if (!DateTimeOffset.TryParse(timestamp, null, System.Globalization.DateTimeStyles.RoundtripKind, out var ts))
            return false;

        if ((DateTimeOffset.UtcNow - ts).Duration() > ReplayWindow)
            return false;

        var expected = ComputeSignature(psk, method, path, timestamp, nonce, bodyHash);

        // Constant-time comparison to prevent timing attacks
        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(expected),
            Encoding.UTF8.GetBytes(providedSignature));
    }

    /// <summary>
    /// Validates that a user-supplied PSK meets minimum entropy requirements.
    /// </summary>
    public static (bool Valid, string? Error) ValidatePsk(string psk)
    {
        if (string.IsNullOrWhiteSpace(psk))
            return (false, "PSK must not be empty.");

        var bytes = Encoding.UTF8.GetByteCount(psk);
        if (bytes < 32)
            return (false, $"PSK must be at least 32 bytes encoded as UTF-8 (got {bytes}).");

        // Reject trivially weak values: all same character or sequential
        if (psk.Distinct().Count() < 8)
            return (false, "PSK must contain at least 8 distinct characters.");

        return (true, null);
    }

    /// <summary>
    /// Generates a cryptographically random 32-byte PSK encoded as Base64.
    /// </summary>
    public static string GeneratePsk()
    {
        var bytes = new byte[32];
        RandomNumberGenerator.Fill(bytes);
        return Convert.ToBase64String(bytes);
    }
}
