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

    /// <summary>
    /// Số lần đăng nhập sai tối đa trước khi khóa tài khoản (Brute-Force Protection)
    /// </summary>
    private const int MaxFailedLoginAttempts = 5;

    /// <summary>
    /// Thời gian khóa tài khoản khi vượt quá ngưỡng sai (15 phút)
    /// </summary>
    private static readonly TimeSpan LockoutDuration = TimeSpan.FromMinutes(15);

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
            FailedLoginAttempts = 0,
            LockoutEnd = null,
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
    /// Tích hợp Khóa An Toàn Brute-Force: Đếm FailedLoginAttempts, khóa 15 phút sau 5 lần sai → HTTP 423 Locked
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status423Locked)]
    public async Task<IActionResult> Login([FromBody] LoginRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password))
        {
            return BadRequest(new { error = "Email và Mật khẩu không được để trống." });
        }

        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var caregiver = await _db.Caregivers.FirstOrDefaultAsync(c => c.Email == normalizedEmail, ct);

        if (caregiver == null)
        {
            _logger.LogWarning("[AUTH-FAIL] Đăng nhập thất bại - Email không tồn tại: {Email}", request.Email);
            return Unauthorized(new { error = "Email hoặc mật khẩu không chính xác." });
        }

        var adminState = _config.GetValue<bool>("AdminSecurity:EnforceCaregiverSessions")
            ? await _db.Set<CareAI.Core.Entities.Admin.CaregiverAdminState>().AsNoTracking().SingleOrDefaultAsync(x => x.CaregiverId == caregiver.Id, ct) : null;
        if (adminState?.IsSuspended == true) return StatusCode(403, new { error = "Tài khoản đang tạm ngưng. Vui lòng liên hệ hỗ trợ." });

        // KIỂM TRA KHÓA TÀI KHOẢN BRUTE-FORCE
        if (caregiver.LockoutEnd.HasValue && caregiver.LockoutEnd.Value > DateTime.UtcNow)
        {
            var remaining = caregiver.LockoutEnd.Value - DateTime.UtcNow;
            _logger.LogWarning("[AUTH-LOCKED] Tài khoản {Email} đang bị khóa. Còn {Minutes:F0} phút.", caregiver.Email, remaining.TotalMinutes);
            return StatusCode(StatusCodes.Status423Locked, new
            {
                error = $"Tài khoản đã bị khóa do nhập sai mật khẩu quá {MaxFailedLoginAttempts} lần. Vui lòng thử lại sau {Math.Ceiling(remaining.TotalMinutes)} phút.",
                lockoutEnd = caregiver.LockoutEnd.Value,
                remainingMinutes = Math.Ceiling(remaining.TotalMinutes)
            });
        }

        // Nếu hết thời gian khóa, tự động reset bộ đếm
        if (caregiver.LockoutEnd.HasValue && caregiver.LockoutEnd.Value <= DateTime.UtcNow)
        {
            caregiver.FailedLoginAttempts = 0;
            caregiver.LockoutEnd = null;
        }

        // XÁC THỰC MẬT KHẨU
        if (!VerifyPassword(request.Password, caregiver.PasswordHash))
        {
            caregiver.FailedLoginAttempts++;
            _logger.LogWarning("[AUTH-FAIL] Đăng nhập thất bại cho {Email} (Lần thứ {Attempt}/{Max})",
                caregiver.Email, caregiver.FailedLoginAttempts, MaxFailedLoginAttempts);

            // KHÓA TÀI KHOẢN khi đạt ngưỡng
            if (caregiver.FailedLoginAttempts >= MaxFailedLoginAttempts)
            {
                caregiver.LockoutEnd = DateTime.UtcNow.Add(LockoutDuration);
                await _db.SaveChangesAsync(ct);

                _logger.LogWarning("[AUTH-LOCKOUT] Tài khoản {Email} bị khóa {Minutes} phút do {Attempts} lần sai liên tiếp!",
                    caregiver.Email, LockoutDuration.TotalMinutes, caregiver.FailedLoginAttempts);

                return StatusCode(StatusCodes.Status423Locked, new
                {
                    error = $"Tài khoản đã bị khóa do nhập sai mật khẩu {MaxFailedLoginAttempts} lần. Vui lòng thử lại sau {LockoutDuration.TotalMinutes} phút.",
                    lockoutEnd = caregiver.LockoutEnd.Value,
                    remainingMinutes = LockoutDuration.TotalMinutes
                });
            }

            await _db.SaveChangesAsync(ct);
            return Unauthorized(new { error = "Email hoặc mật khẩu không chính xác." });
        }

        // ĐĂNG NHẬP THÀNH CÔNG → Reset bộ đếm
        caregiver.FailedLoginAttempts = 0;
        caregiver.LockoutEnd = null;
        await _db.SaveChangesAsync(ct);

        var token = GenerateJwtToken(caregiver, adminState?.SecurityVersion ?? 0);
        _logger.LogInformation("[AUTH] Người thân {CaregiverId} ({Email}) đăng nhập thành công.", caregiver.Id, caregiver.Email);

        return Ok(new AuthResponse(token, caregiver.Id, caregiver.FullName, caregiver.Email));
    }

    /// <summary>
    /// Quên mật khẩu - Sinh mã OTP 6 số gửi qua Email (TTL 10 phút)
    /// </summary>
    [HttpPost("forgot-password")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ForgotPasswordResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request, CancellationToken ct)
    {
        // Luôn trả về 200 OK để tránh tiết lộ sự tồn tại của email (Anti-Enumeration)
        if (string.IsNullOrWhiteSpace(request.Email))
        {
            return Ok(new ForgotPasswordResponse("Nếu email tồn tại trong hệ thống, mã OTP đã được gửi đến hộp thư của bạn."));
        }

        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var caregiver = await _db.Caregivers.FirstOrDefaultAsync(c => c.Email == normalizedEmail, ct);

        if (caregiver != null)
        {
            // Hủy tất cả OTP cũ chưa sử dụng
            var oldTokens = await _db.PasswordResetTokens
                .Where(t => t.CaregiverId == caregiver.Id && !t.IsUsed)
                .ToListAsync(ct);
            foreach (var old in oldTokens)
            {
                old.IsUsed = true;
            }

            // Sinh OTP 6 số mới
            var otpCode = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
            using var sha = SHA256.Create();
            var otpHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(otpCode))).ToLowerInvariant();

            var resetToken = new PasswordResetToken
            {
                Id = Guid.NewGuid().ToString(),
                CaregiverId = caregiver.Id,
                OtpCode = otpCode,
                OtpHash = otpHash,
                IsUsed = false,
                ExpiresAt = DateTime.UtcNow.AddMinutes(10),
                CreatedAt = DateTime.UtcNow
            };

            _db.PasswordResetTokens.Add(resetToken);
            await _db.SaveChangesAsync(ct);

            // TODO: Tích hợp gửi Email thực tế (SMTP / SendGrid / Azure Communication Services)
            _logger.LogInformation("[AUTH-OTP] Đã sinh mã OTP cho {Email}: {OTP} (Hết hạn: 10 phút)", caregiver.Email, otpCode);
        }

        return Ok(new ForgotPasswordResponse("Nếu email tồn tại trong hệ thống, mã OTP đã được gửi đến hộp thư của bạn."));
    }

    /// <summary>
    /// Đặt lại mật khẩu bằng mã OTP 6 số
    /// </summary>
    [HttpPost("reset-password")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ResetPasswordResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.OtpCode) ||
            string.IsNullOrWhiteSpace(request.NewPassword))
        {
            return BadRequest(new { error = "Email, mã OTP và mật khẩu mới không được để trống." });
        }

        if (request.NewPassword.Length < 8)
        {
            return BadRequest(new { error = "Mật khẩu mới phải có tối thiểu 8 ký tự." });
        }

        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var caregiver = await _db.Caregivers.FirstOrDefaultAsync(c => c.Email == normalizedEmail, ct);

        if (caregiver == null)
        {
            return BadRequest(new { error = "Mã OTP không hợp lệ hoặc đã hết hạn." });
        }

        using var sha = SHA256.Create();
        var otpHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(request.OtpCode.Trim()))).ToLowerInvariant();

        var resetToken = await _db.PasswordResetTokens
            .FirstOrDefaultAsync(t =>
                t.CaregiverId == caregiver.Id &&
                t.OtpHash == otpHash &&
                !t.IsUsed &&
                t.ExpiresAt > DateTime.UtcNow, ct);

        if (resetToken == null)
        {
            return BadRequest(new { error = "Mã OTP không hợp lệ hoặc đã hết hạn." });
        }

        // Cập nhật mật khẩu mới
        caregiver.PasswordHash = HashPassword(request.NewPassword);
        caregiver.FailedLoginAttempts = 0;
        caregiver.LockoutEnd = null;

        // Đánh dấu OTP đã sử dụng
        resetToken.IsUsed = true;

        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("[AUTH-RESET] Người thân {CaregiverId} ({Email}) đã đặt lại mật khẩu thành công.", caregiver.Id, caregiver.Email);

        return Ok(new ResetPasswordResponse("Mật khẩu đã được đặt lại thành công. Vui lòng đăng nhập với mật khẩu mới."));
    }

    private string GenerateJwtToken(Caregiver caregiver, int securityVersion = 0)
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
                new Claim(ClaimTypes.Role, "Caregiver"),
                new Claim("csv", securityVersion.ToString(System.Globalization.CultureInfo.InvariantCulture))
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
