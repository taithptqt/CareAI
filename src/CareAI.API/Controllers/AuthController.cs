using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/auth")]
public class AuthController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly IConfiguration _config;
    private readonly ILogger<AuthController> _logger;

    public AuthController(CareAiDbContext db, IConfiguration config, ILogger<AuthController> logger)
    {
        _db = db;
        _config = config;
        _logger = logger;
    }

    /// <summary>
    /// Đăng ký tài khoản Người thân mới (Caregiver Registration)
    /// </summary>
    [HttpPost("register")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Register([FromBody] RegisterCaregiverRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password) ||
            string.IsNullOrWhiteSpace(request.FullName) || string.IsNullOrWhiteSpace(request.PhoneNumber))
        {
            return BadRequest(new { error = "Họ tên, SĐT, Email và Mật khẩu không được để trống." });
        }

        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var exists = await _db.Caregivers.AnyAsync(c => c.Email == normalizedEmail, ct);
        if (exists)
        {
            return Conflict(new { error = "Email này đã được đăng ký tài khoản trong hệ thống." });
        }

        var caregiver = new Caregiver
        {
            Id = Guid.NewGuid().ToString(),
            FullName = request.FullName.Trim(),
            PhoneNumber = request.PhoneNumber.Trim(),
            Email = normalizedEmail,
            PasswordHash = HashPassword(request.Password),
            CreatedAt = DateTime.UtcNow
        };

        _db.Caregivers.Add(caregiver);
        await _db.SaveChangesAsync(ct);

        var token = GenerateJwtToken(caregiver);
        _logger.LogInformation("[AUTH] Đăng ký thành công Người thân: {CaregiverId} ({Email})", caregiver.Id, caregiver.Email);

        return StatusCode(StatusCodes.Status201Created, new AuthResponse(token, caregiver.Id, caregiver.FullName, caregiver.Email));
    }

    /// <summary>
    /// Đăng nhập Người thân (Caregiver Login) - Cấp phát JWT mang Claim NameIdentifier
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Login([FromBody] LoginRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password))
        {
            return BadRequest(new { error = "Email và Mật khẩu không được để trống." });
        }

        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var caregiver = await _db.Caregivers.FirstOrDefaultAsync(c => c.Email == normalizedEmail, ct);

        if (caregiver == null || !VerifyPassword(request.Password, caregiver.PasswordHash))
        {
            _logger.LogWarning("[AUTH-FAIL] Đăng nhập thất bại cho Email: {Email}", request.Email);
            return Unauthorized(new { error = "Email hoặc mật khẩu không chính xác." });
        }

        var token = GenerateJwtToken(caregiver);
        _logger.LogInformation("[AUTH] Người thân {CaregiverId} ({Email}) đăng nhập thành công.", caregiver.Id, caregiver.Email);

        return Ok(new AuthResponse(token, caregiver.Id, caregiver.FullName, caregiver.Email));
    }

    private string GenerateJwtToken(Caregiver caregiver)
    {
        var jwtSecret = _config["Jwt:SecretKey"] ?? "CareAiSuperSecretKeyForDevelopment20261234567890!";
        var tokenHandler = new JwtSecurityTokenHandler();
        var key = Encoding.UTF8.GetBytes(jwtSecret);

        var tokenDescriptor = new SecurityTokenDescriptor
        {
            Subject = new ClaimsIdentity(new[]
            {
                new Claim(ClaimTypes.NameIdentifier, caregiver.Id),
                new Claim(ClaimTypes.Name, caregiver.FullName),
                new Claim(ClaimTypes.Email, caregiver.Email),
                new Claim(ClaimTypes.Role, "Caregiver")
            }),
            Expires = DateTime.UtcNow.AddDays(30),
            Issuer = "CareAI.Server",
            Audience = "CareAI.CaregiverApp",
            SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
        };

        var token = tokenHandler.CreateToken(tokenDescriptor);
        return tokenHandler.WriteToken(token);
    }

    public static string HashPassword(string password)
    {
        byte[] salt = RandomNumberGenerator.GetBytes(16);
        byte[] hash = Rfc2898DeriveBytes.Pbkdf2(
            Encoding.UTF8.GetBytes(password),
            salt,
            iterations: 600_000,
            HashAlgorithmName.SHA256,
            outputLength: 32);
        return $"{Convert.ToBase64String(salt)}:{Convert.ToBase64String(hash)}";
    }

    public static bool VerifyPassword(string password, string storedHash)
    {
        if (string.IsNullOrWhiteSpace(storedHash) || string.IsNullOrWhiteSpace(password))
            return false;

        var parts = storedHash.Split(':');
        if (parts.Length != 2)
        {
            using var sha = SHA256.Create();
            var h = Convert.ToBase64String(sha.ComputeHash(Encoding.UTF8.GetBytes(password)));
            return CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(h), Encoding.UTF8.GetBytes(storedHash));
        }

        try
        {
            byte[] salt = Convert.FromBase64String(parts[0]);
            byte[] expectedHash = Convert.FromBase64String(parts[1]);
            byte[] actualHash = Rfc2898DeriveBytes.Pbkdf2(
                Encoding.UTF8.GetBytes(password),
                salt,
                iterations: 600_000,
                HashAlgorithmName.SHA256,
                outputLength: 32);
            return CryptographicOperations.FixedTimeEquals(actualHash, expectedHash);
        }
        catch
        {
            return false;
        }
    }
}
