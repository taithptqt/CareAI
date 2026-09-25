using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using CareAI.API.Controllers;
using CareAI.API.Middlewares;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using Xunit;

namespace CareAI.UnitTests;

/// <summary>
/// Bộ kiểm thử Unit Test toàn diện cho PHẦN 3:
/// Trục Quản Trị Nhóm Gia Đình, Mã Mời 6 Số, RBAC & Vòng Đời Thiết Bị
/// (UC-01, UC-02, UC-03, UC-12, UC-13)
/// </summary>
public class Part3FamilyAndRbacTests : IDisposable
{
    private readonly CareAiDbContext _db;
    private readonly IMemoryCache _memoryCache;
    private readonly IConfiguration _config;

    private readonly string _elderId = "ELDER_PART3_TEST";
    private readonly string _primaryCaregiverId = "PRIMARY_CG_01";
    private readonly string _secondaryCaregiverId = "SECONDARY_CG_02";
    private readonly string _strangerCaregiverId = "STRANGER_CG_03";
    private readonly string _deviceId = "DEVICE_PART3_01";

    public Part3FamilyAndRbacTests()
    {
        var options = new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(databaseName: $"CareAiDb_Part3_{Guid.NewGuid()}")
            .Options;

        _db = new CareAiDbContext(options);
        _memoryCache = new MemoryCache(new MemoryCacheOptions());

        var configValues = new Dictionary<string, string?>
        {
            {"Jwt:SecretKey", "SuperSecretKeyForCareAITestingMustBeAtLeast32BytesLong!"},
            {"Jwt:Issuer", "CareAI.Server"},
            {"Jwt:Audience", "CareAI.CaregiverApp"}
        };
        _config = new ConfigurationBuilder().AddInMemoryCollection(configValues).Build();

        SeedTestData();
    }

    private void SeedTestData()
    {
        // 1. Elder Profile
        var elder = new ElderProfile
        {
            Id = _elderId,
            FullName = "Cụ Hoàng Thị Mai",
            DateOfBirth = new DateTime(1940, 5, 20),
            MedicalNotes = "Cao huyết áp giai đoạn 2",
            EmergencyContact = "0912345678",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        _db.ElderProfiles.Add(elder);

        // 2. Primary Caregiver
        var primaryCg = new Caregiver
        {
            Id = _primaryCaregiverId,
            FullName = "Hoàng Tuấn Anh",
            Email = "tuananh@careai.vn",
            PhoneNumber = "0901111111",
            PasswordHash = AuthController.HashPassword("SecurePass123!"),
            FailedLoginAttempts = 0,
            CreatedAt = DateTime.UtcNow
        };
        _db.Caregivers.Add(primaryCg);

        // 3. Secondary Caregiver
        var secondaryCg = new Caregiver
        {
            Id = _secondaryCaregiverId,
            FullName = "Hoàng Mai Linh",
            Email = "mailinh@careai.vn",
            PhoneNumber = "0902222222",
            PasswordHash = AuthController.HashPassword("SecurePass123!"),
            FailedLoginAttempts = 0,
            CreatedAt = DateTime.UtcNow
        };
        _db.Caregivers.Add(secondaryCg);

        // 4. Stranger Caregiver
        var strangerCg = new Caregiver
        {
            Id = _strangerCaregiverId,
            FullName = "Người Lạ",
            Email = "stranger@careai.vn",
            PhoneNumber = "0903333333",
            PasswordHash = AuthController.HashPassword("SecurePass123!"),
            FailedLoginAttempts = 0,
            CreatedAt = DateTime.UtcNow
        };
        _db.Caregivers.Add(strangerCg);

        // 5. Relations
        _db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = Guid.NewGuid().ToString(),
            ElderProfileId = _elderId,
            CaregiverId = _primaryCaregiverId,
            Role = CaregiverRole.Primary,
            IsActive = true,
            AssignedAt = DateTime.UtcNow
        });

        _db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = Guid.NewGuid().ToString(),
            ElderProfileId = _elderId,
            CaregiverId = _secondaryCaregiverId,
            Role = CaregiverRole.Secondary,
            IsActive = true,
            AssignedAt = DateTime.UtcNow
        });

        // 6. Device
        using var sha = SHA256.Create();
        var rawToken = "DeviceInitialTokenPart3";
        var tokenHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(rawToken))).ToLowerInvariant();

        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = _deviceId,
            ElderProfileId = _elderId,
            DeviceTokenHash = tokenHash,
            DeviceType = "Smartwatch",
            FirmwareVersion = "1.0.0",
            IsActive = true,
            LastHeartbeat = DateTime.UtcNow,
            RegisteredAt = DateTime.UtcNow,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        });

        _db.SaveChanges();
    }

    private static ControllerContext CreateContextWithUser(string userId, string role = "Caregiver")
    {
        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, userId),
            new Claim(ClaimTypes.Role, role)
        };
        var identity = new ClaimsIdentity(claims, "TestAuth");
        var principal = new ClaimsPrincipal(identity);
        return new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = principal }
        };
    }

    // =========================================================================
    // NHIỆM VỤ 3.1: XÁC THỰC DANH TÍNH & KHÓA BRUTE-FORCE
    // =========================================================================

    [Fact]
    public async Task Fact_37_BruteForceLockout_LocksAccount_After5FailedAttempts_Returns423()
    {
        var controller = new AuthController(_db, _config, NullLogger<AuthController>.Instance);

        // Thử sai 4 lần -> trả về 401 Unauthorized
        for (int i = 1; i <= 4; i++)
        {
            var res = await controller.Login(new LoginRequest("tuananh@careai.vn", "WrongPassword!"), CancellationToken.None);
            var unauthorized = Assert.IsType<UnauthorizedObjectResult>(res);
            Assert.Equal(StatusCodes.Status401Unauthorized, unauthorized.StatusCode);
        }

        // Lần thứ 5 sai -> Kích hoạt khóa tài khoản và trả về HTTP 423 Locked
        var res5 = await controller.Login(new LoginRequest("tuananh@careai.vn", "WrongPassword!"), CancellationToken.None);
        var lockedRes = Assert.IsType<ObjectResult>(res5);
        Assert.Equal(StatusCodes.Status423Locked, lockedRes.StatusCode);

        // Kiểm tra trong CSDL: FailedLoginAttempts = 5 và LockoutEnd được thiết lập
        var caregiver = await _db.Caregivers.FirstOrDefaultAsync(c => c.Email == "tuananh@careai.vn");
        Assert.NotNull(caregiver);
        Assert.Equal(5, caregiver.FailedLoginAttempts);
        Assert.NotNull(caregiver.LockoutEnd);
        Assert.True(caregiver.LockoutEnd > DateTime.UtcNow);

        // Lần thứ 6 dù nhập ĐÚNG mật khẩu vẫn bị chặn HTTP 423 Locked do đang trong thời gian phạt 15 phút
        var res6 = await controller.Login(new LoginRequest("tuananh@careai.vn", "SecurePass123!"), CancellationToken.None);
        var lockedAgain = Assert.IsType<ObjectResult>(res6);
        Assert.Equal(StatusCodes.Status423Locked, lockedAgain.StatusCode);
    }

    [Fact]
    public async Task Fact_38_PasswordReset_GeneratesOtp_And_AllowsReset()
    {
        var controller = new AuthController(_db, _config, NullLogger<AuthController>.Instance);

        // 1. Quên mật khẩu: Gửi email -> Sinh OTP 6 số
        var forgotRes = await controller.ForgotPassword(new ForgotPasswordRequest("mailinh@careai.vn"), CancellationToken.None);
        var okForgot = Assert.IsType<OkObjectResult>(forgotRes);
        Assert.Equal(StatusCodes.Status200OK, okForgot.StatusCode);

        // Lấy token OTP vừa tạo trong CSDL
        var resetToken = await _db.PasswordResetTokens
            .Where(t => t.Caregiver.Email == "mailinh@careai.vn" && !t.IsUsed)
            .OrderByDescending(t => t.CreatedAt)
            .FirstOrDefaultAsync();

        Assert.NotNull(resetToken);
        Assert.Equal(6, resetToken.OtpCode.Length);
        Assert.NotNull(resetToken.OtpHash);
        Assert.True(resetToken.ExpiresAt > DateTime.UtcNow);

        // 2. Nhập sai OTP -> Báo lỗi
        var failReset = await controller.ResetPassword(new ResetPasswordRequest("mailinh@careai.vn", "000000", "NewPass999!"), CancellationToken.None);
        Assert.IsType<BadRequestObjectResult>(failReset);

        // 3. Nhập đúng OTP -> Đổi mật khẩu thành công và vô hiệu hóa OTP
        var successReset = await controller.ResetPassword(new ResetPasswordRequest("mailinh@careai.vn", resetToken.OtpCode, "NewPass999!"), CancellationToken.None);
        Assert.IsType<OkObjectResult>(successReset);

        var updatedToken = await _db.PasswordResetTokens.FindAsync(resetToken.Id);
        Assert.NotNull(updatedToken);
        Assert.True(updatedToken.IsUsed);

        // 4. Đăng nhập bằng mật khẩu mới thành công
        var loginRes = await controller.Login(new LoginRequest("mailinh@careai.vn", "NewPass999!"), CancellationToken.None);
        var okLogin = Assert.IsType<OkObjectResult>(loginRes);
        Assert.Equal(StatusCodes.Status200OK, okLogin.StatusCode);
    }

    // =========================================================================
    // NHIỆM VỤ 3.2: QUẢN LÝ HỒ SƠ & GHÉP NỐI THIẾT BỊ (PIN 6 SỐ / SHA-256)
    // =========================================================================

    [Fact]
    public async Task Fact_39_PairingPin_Generates_15MinTTL_And_SHA256_Hash()
    {
        var devicesController = new DevicesController(_db, NullLogger<DevicesController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_primaryCaregiverId)
        };

        var res = await devicesController.GeneratePairingPin(_elderId, CancellationToken.None);
        var okRes = Assert.IsType<OkObjectResult>(res);
        var pinData = Assert.IsType<GeneratePinResponse>(okRes.Value);

        Assert.Equal(6, pinData.Pin.Length);
        Assert.True(pinData.ExpiresAt > DateTime.UtcNow.AddMinutes(14));

        var elder = await _db.ElderProfiles.FindAsync(_elderId);
        Assert.NotNull(elder);
        Assert.Equal(pinData.Pin, elder.PairingPin);
        Assert.NotNull(elder.PairingPinHash);

        // Bất biến: Mã băm SHA-256 phải là chữ thường
        using var sha = SHA256.Create();
        var expectedHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(pinData.Pin))).ToLowerInvariant();
        Assert.Equal(expectedHash, elder.PairingPinHash);
    }

    [Fact]
    public async Task Fact_40_PairDevice_Validates_SHA256_Pin_And_Invalidates_Pin()
    {
        // 1. Sinh PIN trước
        var devicesController = new DevicesController(_db, NullLogger<DevicesController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_primaryCaregiverId)
        };
        var pinRes = await devicesController.GeneratePairingPin(_elderId, CancellationToken.None);
        var pinData = Assert.IsType<GeneratePinResponse>(((OkObjectResult)pinRes).Value);

        // 2. Thiết bị phần cứng gọi Pair bằng mã PIN vừa sinh
        var pairRequest = new PairDeviceRequest("NEW_DEVICE_999", pinData.Pin, "Smartwatch", "1.1.0");
        var pairRes = await devicesController.PairDevice(pairRequest, CancellationToken.None);
        var pairOk = Assert.IsType<OkObjectResult>(pairRes);
        var pairData = Assert.IsType<PairDeviceResponse>(pairOk.Value);

        Assert.Equal("NEW_DEVICE_999", pairData.DeviceId);
        Assert.NotEmpty(pairData.DeviceToken);

        // 3. Bất biến One-Time PIN: Mã PIN và Băm PIN phải bị xóa sạch khỏi hồ sơ Cụ
        var elder = await _db.ElderProfiles.FindAsync(_elderId);
        Assert.NotNull(elder);
        Assert.Null(elder.PairingPin);
        Assert.Null(elder.PairingPinHash);
        Assert.Null(elder.PinExpiresAt);

        // 4. Thử ghép nối lại bằng mã PIN cũ -> Thất bại
        var retryPair = await devicesController.PairDevice(pairRequest, CancellationToken.None);
        Assert.IsType<BadRequestObjectResult>(retryPair);
    }

    // =========================================================================
    // NHIỆM VỤ 3.3 & 3.4: MÃ MỜI GIA ĐÌNH 6 KÝ TỰ (24H) & MA TRẬN RBAC
    // =========================================================================

    [Fact]
    public async Task Fact_41_FamilyInvitation_PrimaryCanCreate_24HourTTL_SecondaryForbidden()
    {
        var familyControllerPrimary = new FamilyController(_db, NullLogger<FamilyController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_primaryCaregiverId)
        };

        // Primary tạo mã mời -> 201 Created
        var createRes = await familyControllerPrimary.CreateInvitation(_elderId, CancellationToken.None);
        var created = Assert.IsType<ObjectResult>(createRes);
        Assert.Equal(StatusCodes.Status201Created, created.StatusCode);
        var inviteData = Assert.IsType<CreateInvitationResponse>(created.Value);

        Assert.Equal(6, inviteData.InvitationCode.Length);
        Assert.True(inviteData.ExpiresAt > DateTime.UtcNow.AddHours(23));

        // Secondary Caregiver cố tạo mã mời -> 403 Forbidden
        var familyControllerSecondary = new FamilyController(_db, NullLogger<FamilyController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_secondaryCaregiverId)
        };
        var forbiddenRes = await familyControllerSecondary.CreateInvitation(_elderId, CancellationToken.None);
        var forbidden = Assert.IsType<ObjectResult>(forbiddenRes);
        Assert.Equal(StatusCodes.Status403Forbidden, forbidden.StatusCode);
    }

    [Fact]
    public async Task Fact_42_FamilyInvitation_Accept_JoinsAsSecondaryCaregiver()
    {
        // 1. Primary tạo mã mời
        var familyControllerPrimary = new FamilyController(_db, NullLogger<FamilyController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_primaryCaregiverId)
        };
        var createRes = await familyControllerPrimary.CreateInvitation(_elderId, CancellationToken.None);
        var inviteData = (CreateInvitationResponse)((ObjectResult)createRes).Value!;

        // 2. Người lạ (Stranger) dùng mã mời tham gia
        var familyControllerStranger = new FamilyController(_db, NullLogger<FamilyController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_strangerCaregiverId)
        };
        var acceptRes = await familyControllerStranger.AcceptInvitation(new AcceptInvitationRequest(inviteData.InvitationCode), CancellationToken.None);
        var okAccept = Assert.IsType<OkObjectResult>(acceptRes);
        var acceptData = Assert.IsType<AcceptInvitationResponse>(okAccept.Value);

        Assert.Equal(_elderId, acceptData.ElderProfileId);
        Assert.Equal(CaregiverRole.Secondary.ToString(), acceptData.Role);

        // Kiểm tra trong CSDL quan hệ được tạo với vai trò Secondary
        var relation = await _db.ElderCaregivers
            .FirstOrDefaultAsync(ec => ec.ElderProfileId == _elderId && ec.CaregiverId == _strangerCaregiverId);
        Assert.NotNull(relation);
        Assert.True(relation.IsActive);
        Assert.Equal(CaregiverRole.Secondary, relation.Role);

        // Mã mời bị vô hiệu hóa, không dùng lại được
        var retryAccept = await familyControllerStranger.AcceptInvitation(new AcceptInvitationRequest(inviteData.InvitationCode), CancellationToken.None);
        Assert.IsType<BadRequestObjectResult>(retryAccept);
    }

    [Fact]
    public async Task Fact_43_RBAC_Matrix_SecondaryForbidden_From_Update_Revoke_Unpair_Delete()
    {
        // 1. Secondary thử Sửa hồ sơ -> 403 Forbidden
        var caregiversController = new CaregiversController(_db, NullLogger<CaregiversController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_secondaryCaregiverId)
        };
        var updateRes = await caregiversController.UpdateElder(_elderId, new UpdateElderRequest("Tên mới", null, null, null), CancellationToken.None);
        var forbiddenUpdate = Assert.IsType<ObjectResult>(updateRes);
        Assert.Equal(StatusCodes.Status403Forbidden, forbiddenUpdate.StatusCode);

        // 2. Secondary thử Thu hồi thành viên -> 403 Forbidden
        var familyController = new FamilyController(_db, NullLogger<FamilyController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_secondaryCaregiverId)
        };
        var revokeRes = await familyController.RevokeFamilyMember(_elderId, _primaryCaregiverId, CancellationToken.None);
        var forbiddenRevoke = Assert.IsType<ObjectResult>(revokeRes);
        Assert.Equal(StatusCodes.Status403Forbidden, forbiddenRevoke.StatusCode);

        // 3. Secondary thử Hủy ghép nối thiết bị -> 403 Forbidden
        var devicesController = new DevicesController(_db, NullLogger<DevicesController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_secondaryCaregiverId)
        };
        var unpairRes = await devicesController.UnpairDevice(_deviceId, _memoryCache, CancellationToken.None);
        var forbiddenUnpair = Assert.IsType<ObjectResult>(unpairRes);
        Assert.Equal(StatusCodes.Status403Forbidden, forbiddenUnpair.StatusCode);

        // 4. Secondary thử Xóa hồ sơ Cụ -> 403 Forbidden
        var eldersController = new EldersController(_db, NullLogger<EldersController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_secondaryCaregiverId)
        };
        var deleteRes = await eldersController.DeleteElder(_elderId, new DeleteElderRequest("SecurePass123!"), _memoryCache, CancellationToken.None);
        var forbiddenDelete = Assert.IsType<ObjectResult>(deleteRes);
        Assert.Equal(StatusCodes.Status403Forbidden, forbiddenDelete.StatusCode);
    }

    // =========================================================================
    // NHIỆM VỤ 3.5: VÒNG ĐỜI THIẾT BỊ & XÓA DỮ LIỆU AN TOÀN (PII REMOVAL)
    // =========================================================================

    [Fact]
    public async Task Fact_44_DeviceUnpair_SetsInactive_ClearsToken_BlacklistsDevice()
    {
        var devicesController = new DevicesController(_db, NullLogger<DevicesController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_primaryCaregiverId)
        };

        var unpairRes = await devicesController.UnpairDevice(_deviceId, _memoryCache, CancellationToken.None);
        var okUnpair = Assert.IsType<OkObjectResult>(unpairRes);
        var data = Assert.IsType<UnpairDeviceResponse>(okUnpair.Value);

        Assert.Equal("WIPE_DEVICE_CREDENTIALS", data.Status);

        var device = await _db.DeviceRegistrations.FindAsync(_deviceId);
        Assert.NotNull(device);
        Assert.False(device.IsActive);
        Assert.Empty(device.DeviceTokenHash);

        // Kiểm tra Blacklist trong cache
        Assert.True(_memoryCache.TryGetValue($"blacklist:dev:{_deviceId}", out bool isBlacklisted));
        Assert.True(isBlacklisted);
    }

    [Fact]
    public async Task Fact_45_DeleteElder_Level2Password_SoftDeletes_And_AnonymizesPII()
    {
        var eldersController = new EldersController(_db, NullLogger<EldersController>.Instance)
        {
            ControllerContext = CreateContextWithUser(_primaryCaregiverId)
        };

        // 1. Nhập sai mật khẩu cấp 2 -> Bị từ chối
        var wrongPwdRes = await eldersController.DeleteElder(_elderId, new DeleteElderRequest("WrongPassword!"), _memoryCache, CancellationToken.None);
        Assert.IsType<BadRequestObjectResult>(wrongPwdRes);

        // 2. Nhập đúng mật khẩu cấp 2 -> Soft delete và ẩn danh hóa PII
        var deleteRes = await eldersController.DeleteElder(_elderId, new DeleteElderRequest("SecurePass123!"), _memoryCache, CancellationToken.None);
        var okDelete = Assert.IsType<OkObjectResult>(deleteRes);
        var deleteData = Assert.IsType<DeleteElderResponse>(okDelete.Value);

        Assert.Equal("DELETED_ANONYMIZED", deleteData.Status);

        var elder = await _db.ElderProfiles.IgnoreQueryFilters().FirstOrDefaultAsync(e => e.Id == _elderId);
        Assert.NotNull(elder);
        Assert.True(elder.IsDeleted);
        Assert.Equal("NGƯỜI DÙNG ĐÃ XÓA (ANONYMIZED)", elder.FullName);
        Assert.Null(elder.MedicalNotes);
        Assert.Null(elder.EmergencyContact);

        // Thiết bị gắn với Cụ bị ngắt quyền
        var device = await _db.DeviceRegistrations.FindAsync(_deviceId);
        Assert.NotNull(device);
        Assert.False(device.IsActive);

        // Thành viên gia đình bị ngắt kích hoạt
        var relations = await _db.ElderCaregivers.Where(ec => ec.ElderProfileId == _elderId).ToListAsync();
        Assert.All(relations, r => Assert.False(r.IsActive));
    }

    public void Dispose()
    {
        _db.Dispose();
        _memoryCache.Dispose();
    }
}
