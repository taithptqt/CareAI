using CareAI.API.Middlewares;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using System.Security.Claims;
using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities;
using CareAI.Core.Entities.Admin;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Admin;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace CareAI.UnitTests;

public sealed class CaregiverAdminSessionTests
{
    [Theory]
    [InlineData(false, 0, null, true)]
    [InlineData(false, 1, null, false)]
    [InlineData(false, 2, "1", false)]
    [InlineData(false, 2, "2", true)]
    [InlineData(true, 2, "2", false)]
    public async Task RevocationCutoverPreservesOnlyMatchingNonSuspendedSessions(bool suspended, int version, string? tokenVersion, bool expected)
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Set<CaregiverAdminState>().Add(new() { CaregiverId = "fictional", IsSuspended = suspended, SecurityVersion = version });
        await db.SaveChangesAsync();
        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, "fictional") };
        if (tokenVersion is not null) claims.Add(new("csv", tokenVersion));
        Assert.Equal(expected, await CaregiverSessionValidator.IsValidAsync(db, new(new ClaimsIdentity(claims, "test")), default));
    }

    [Fact]
    public async Task UnrevokedLegacyAccountRemainsValid()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var user = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "fictional")], "test"));
        Assert.True(await CaregiverSessionValidator.IsValidAsync(db, user, default));
    }

    [Fact]
    public async Task CaregiverSessionValidator_CachesResultInMemory()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        using var cache = new MemoryCache(new MemoryCacheOptions { SizeLimit = 50_000 });
        const string caregiverId = "CG_CACHE_TEST";

        db.Set<CaregiverAdminState>().Add(new() { CaregiverId = caregiverId, IsSuspended = false, SecurityVersion = 1 });
        await db.SaveChangesAsync();

        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, caregiverId), new("csv", "1") };
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, "test"));

        // First call: Populates cache
        var firstResult = await CaregiverSessionValidator.IsValidAsync(db, principal, default, cache);
        Assert.True(firstResult);
        Assert.True(cache.TryGetValue($"auth:caregiver:{caregiverId}", out CaregiverCachedState? cached));
        Assert.NotNull(cached);
        Assert.Equal(1, cached.SecurityVersion);

        // Modify DB directly (simulate out-of-band change without cache clear)
        var state = await db.Set<CaregiverAdminState>().SingleAsync(x => x.CaregiverId == caregiverId);
        state.IsSuspended = true;
        await db.SaveChangesAsync();

        // Second call: Returns true because cache is still active (protects DB from burst)
        var cachedResult = await CaregiverSessionValidator.IsValidAsync(db, principal, default, cache);
        Assert.True(cachedResult);

        // Evict cache: Next call must reflect suspended DB state immediately
        cache.Remove($"auth:caregiver:{caregiverId}");
        var freshResult = await CaregiverSessionValidator.IsValidAsync(db, principal, default, cache);
        Assert.False(freshResult);
    }

    [Fact]
    public async Task AdminCommand_AccountRevocationEvictsAuthCacheImmediately()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
            .Options);
        using var cache = new MemoryCache(new MemoryCacheOptions { SizeLimit = 50_000 });

        const string caregiverId = "CG_REVOKE_TARGET";
        cache.Set($"auth:caregiver:{caregiverId}", new CaregiverCachedState(true, false, 1));
        Assert.True(cache.TryGetValue($"auth:caregiver:{caregiverId}", out _));

        var caregiver = new Caregiver { Id = caregiverId, FullName = "Nguyá»…n VÄƒn Test", Email = "cg@test.com", PasswordHash = "hash" };
        var admin = new AdminUser { Id = "ADMIN_01", NormalizedEmail = "ADMIN@TEST.COM", Role = "Owner", PasswordHash = AdminPasswords.Hash("AdminPassword123!") };
        var session = new AdminSession { Id = "SESS_01", AdminUserId = admin.Id, SecurityVersion = admin.SecurityVersion, ExpiresAtUtc = DateTime.UtcNow.AddHours(1), LastSeenAtUtc = DateTime.UtcNow };

        db.Caregivers.Add(caregiver);
        db.Set<AdminUser>().Add(admin);
        db.Set<AdminSession>().Add(session);
        await db.SaveChangesAsync();

        var service = new AdminCommandService(db, new AdminCommandOptions("test-fingerprint-key-32-bytes-long!", CaregiverApiEnforcementReady: true), cache);
        var req = new AdminCommandRequest
        {
            Action = "account.revoke",
            TargetId = caregiverId,
            ExpectedVersion = AdminOperationsReadService.AccountVersion(caregiver, null),
            Reason = "Thu há»“i quyá»n truy cáº­p kháº©n cáº¥p",
            ReauthPassword = "AdminPassword123!",
            RequestId = Guid.NewGuid().ToString()
        };

        var result = await service.ExecuteAsync("ADMIN_01", "SESS_01", req, "trace-test", default);
        Assert.NotNull(result);

        // Verification: Cache key must be gone immediately!
        Assert.False(cache.TryGetValue($"auth:caregiver:{caregiverId}", out _));
    }
    [Fact]
    public async Task FastLaneSos_NeverRoutesAlertToSuspendedCaregiver()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
            .Options);

        const string elderId = "ELDER_ALERT_TEST";
        const string activeCaregiverId = "CG_ACTIVE";
        const string suspendedCaregiverId = "CG_SUSPENDED";
        const string deviceId = "DEV_SOS_TEST";

        var elder = new ElderProfile { Id = elderId, FullName = "Cụ Huỳnh Thị Test" };
        var device = new DeviceRegistration { Id = deviceId, ElderProfileId = elderId, IsActive = true, DeviceTokenHash = "hash" };

        var cgActive = new Caregiver { Id = activeCaregiverId, FullName = "Người Nhà Hoạt Động", Email = "active@test.com", PasswordHash = "h" };
        var cgSuspended = new Caregiver { Id = suspendedCaregiverId, FullName = "Người Nhà Bị Khóa", Email = "suspended@test.com", PasswordHash = "h" };

        var linkActive = new ElderCaregiver { Id = "LINK_1", ElderProfileId = elderId, CaregiverId = activeCaregiverId, IsActive = true, Role = CaregiverRole.Primary };
        var linkSuspended = new ElderCaregiver { Id = "LINK_2", ElderProfileId = elderId, CaregiverId = suspendedCaregiverId, IsActive = true, Role = CaregiverRole.Secondary };

        var tokenActive = new CaregiverPushToken { Id = "TOK_1", CaregiverId = activeCaregiverId, PushToken = "FCM_ACTIVE", IsActive = true };
        var tokenSuspended = new CaregiverPushToken { Id = "TOK_2", CaregiverId = suspendedCaregiverId, PushToken = "FCM_SUSPENDED", IsActive = true };

        var suspendedState = new CaregiverAdminState { CaregiverId = suspendedCaregiverId, IsSuspended = true, Reason = "Bị khóa do nghi ngờ gian lận", SecurityVersion = 1 };

        db.ElderProfiles.Add(elder);
        db.DeviceRegistrations.Add(device);
        db.Caregivers.AddRange(cgActive, cgSuspended);
        db.ElderCaregivers.AddRange(linkActive, linkSuspended);
        db.CaregiverPushTokens.AddRange(tokenActive, tokenSuspended);
        db.Set<CaregiverAdminState>().Add(suspendedState);
        await db.SaveChangesAsync();

        var engine = new CareAI.Infrastructure.Engines.TelemetryEngine(db, Microsoft.Extensions.Logging.Abstractions.NullLogger<CareAI.Infrastructure.Engines.TelemetryEngine>.Instance);
        var sosPacket = new CareAI.Core.DTOs.SosPacketRequest("PACKET_SOS_1", null, "SOS_MANUAL", "Critical", DateTime.UtcNow, "10.762622,106.660172", null);

        var result = await engine.ProcessFastLaneAsync(deviceId, sosPacket);
        Assert.True(result.Success);

        // Verification: Outbox must ONLY contain active caregiver, NEVER the suspended one!
        var outboxes = await db.NotificationOutboxes.ToListAsync();
        Assert.Single(outboxes);
        Assert.Equal(activeCaregiverId, outboxes[0].RecipientCaregiverId);
        Assert.Equal("FCM_ACTIVE", outboxes[0].PushToken);
    }

    [Fact]
    public async Task DeleteElder_WithActiveIncident_ReturnsConflict409()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
            .Options);

        const string caregiverId = "CG_PRIMARY";
        const string elderId = "ELDER_ACTIVE_INCIDENT";

        var caregiver = new Caregiver
        {
            Id = caregiverId,
            FullName = "Primary Caregiver",
            Email = "primary@test.com",
            PasswordHash = AuthController.HashPassword("SecretPassword123!")
        };
        var elder = new ElderProfile { Id = elderId, FullName = "Cụ Đang Có Sự Cố", IsDeleted = false };
        var relation = new ElderCaregiver
        {
            Id = "REL_1",
            CaregiverId = caregiverId,
            ElderProfileId = elderId,
            Role = CaregiverRole.Primary,
            IsActive = true
        };
        var incident = new Incident
        {
            Id = "INC_1001",
            ElderProfileId = elderId,
            Status = IncidentStatus.Open,
            Severity = IncidentSeverity.Critical,
            TriggeredAt = DateTime.UtcNow
        };

        db.Caregivers.Add(caregiver);
        db.ElderProfiles.Add(elder);
        db.ElderCaregivers.Add(relation);
        db.Incidents.Add(incident);
        await db.SaveChangesAsync();

        var controller = new EldersController(db, Microsoft.Extensions.Logging.Abstractions.NullLogger<EldersController>.Instance);
        var httpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext();
        httpContext.User = new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity(new[]
        {
            new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.NameIdentifier, caregiverId)
        }, "TestAuth"));
        controller.ControllerContext = new Microsoft.AspNetCore.Mvc.ControllerContext { HttpContext = httpContext };

        var cache = new MemoryCache(new MemoryCacheOptions());
        var result = await controller.DeleteElder(elderId, new DeleteElderRequest("SecretPassword123!"), cache, default);

        var conflictResult = Assert.IsType<Microsoft.AspNetCore.Mvc.ObjectResult>(result);
        Assert.Equal(Microsoft.AspNetCore.Http.StatusCodes.Status409Conflict, conflictResult.StatusCode);

        // Verification: Elder must NOT be deleted!
        var reloadedElder = await db.ElderProfiles.FindAsync(elderId);
        Assert.NotNull(reloadedElder);
        Assert.False(reloadedElder.IsDeleted);
    }

    [Fact]
    public async Task SecondaryCaregiver_CanSelfLeave_FamilyGroup()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
            .Options);

        const string primaryId = "CG_PRIMARY";
        const string secondaryId = "CG_SECONDARY";
        const string elderId = "ELDER_FAMILY_TEST";

        var elder = new ElderProfile { Id = elderId, FullName = "Cụ Gia Đình" };
        var relPrimary = new ElderCaregiver { Id = "REL_P", CaregiverId = primaryId, ElderProfileId = elderId, Role = CaregiverRole.Primary, IsActive = true };
        var relSecondary = new ElderCaregiver { Id = "REL_S", CaregiverId = secondaryId, ElderProfileId = elderId, Role = CaregiverRole.Secondary, IsActive = true };

        db.ElderProfiles.Add(elder);
        db.ElderCaregivers.AddRange(relPrimary, relSecondary);
        await db.SaveChangesAsync();

        var controller = new FamilyController(db, Microsoft.Extensions.Logging.Abstractions.NullLogger<FamilyController>.Instance);
        var httpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext();
        httpContext.User = new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity(new[]
        {
            new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.NameIdentifier, secondaryId)
        }, "TestAuth"));
        controller.ControllerContext = new Microsoft.AspNetCore.Mvc.ControllerContext { HttpContext = httpContext };

        // Secondary self-leaves: targetCaregiverId == secondaryId
        var result = await controller.RevokeFamilyMember(elderId, secondaryId, default);

        var okResult = Assert.IsType<Microsoft.AspNetCore.Mvc.OkObjectResult>(result);
        Assert.Equal(Microsoft.AspNetCore.Http.StatusCodes.Status200OK, okResult.StatusCode);

        // Verification: Secondary relationship is now inactive
        var updatedRel = await db.ElderCaregivers.FindAsync("REL_S");
        Assert.NotNull(updatedRel);
        Assert.False(updatedRel.IsActive);
    }

    [Fact]
    public async Task CaregiversController_RegisterPushToken_RejectsSuspendedCaregiver()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
            .Options);

        const string suspendedId = "CG_SUSPENDED_TOKEN";
        var caregiver = new Caregiver { Id = suspendedId, FullName = "Người Bị Khóa", Email = "lock@test.com", PasswordHash = "h" };
        var suspendedState = new CaregiverAdminState { CaregiverId = suspendedId, IsSuspended = true, Reason = "Bị khóa", SecurityVersion = 1 };

        db.Caregivers.Add(caregiver);
        db.Set<CaregiverAdminState>().Add(suspendedState);
        await db.SaveChangesAsync();

        var controller = new CaregiversController(db, Microsoft.Extensions.Logging.Abstractions.NullLogger<CaregiversController>.Instance);
        var httpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext();
        httpContext.User = new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity(new[]
        {
            new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.NameIdentifier, suspendedId)
        }, "TestAuth"));
        controller.ControllerContext = new Microsoft.AspNetCore.Mvc.ControllerContext { HttpContext = httpContext };

        var result = await controller.RegisterPushToken(new RegisterPushTokenRequest("NEW_TOKEN", "Galaxy Phone"), default);

        var forbiddenResult = Assert.IsType<Microsoft.AspNetCore.Mvc.ObjectResult>(result);
        Assert.Equal(Microsoft.AspNetCore.Http.StatusCodes.Status403Forbidden, forbiddenResult.StatusCode);

        // Verification: No token was saved!
        var tokenCount = await db.CaregiverPushTokens.CountAsync();
        Assert.Equal(0, tokenCount);
    }

    [Fact]
    public async Task FeedbackController_Rejects_Oversized_Subject_Or_Message()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
            .Options);

        const string caregiverId = "CG_FEEDBACK_TEST";
        var caregiver = new Caregiver { Id = caregiverId, FullName = "Người Dùng", Email = "fb@test.com", PasswordHash = "h" };
        db.Caregivers.Add(caregiver);
        await db.SaveChangesAsync();

        var service = new CareAI.Infrastructure.Feedback.FeedbackService(db);
        var controller = new FeedbackController(service, db);
        var httpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext();
        httpContext.User = new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity(new[]
        {
            new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.NameIdentifier, caregiverId),
            new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.Role, "Caregiver")
        }, "TestAuth"));
        controller.ControllerContext = new Microsoft.AspNetCore.Mvc.ControllerContext { HttpContext = httpContext };

        // 1. Oversized Subject (> 200 chars)
        var oversizedSubjectReq = new SubmitFeedbackRequest("REQ_1", "Suggestion", new string('A', 201), "Nội dung phản hồi hợp lệ dài hơn 10 ký tự.");
        var badSubjectResult = await controller.Submit(oversizedSubjectReq, default);
        var problem1 = Assert.IsType<Microsoft.AspNetCore.Mvc.ObjectResult>(badSubjectResult);
        Assert.Equal(Microsoft.AspNetCore.Http.StatusCodes.Status400BadRequest, problem1.StatusCode);

        // 2. Oversized Message (> 4000 chars)
        var oversizedMessageReq = new SubmitFeedbackRequest("REQ_2", "Suggestion", "Tiêu đề hợp lệ", new string('B', 4001));
        var badMessageResult = await controller.Submit(oversizedMessageReq, default);
        var problem2 = Assert.IsType<Microsoft.AspNetCore.Mvc.ObjectResult>(badMessageResult);
        Assert.Equal(Microsoft.AspNetCore.Http.StatusCodes.Status400BadRequest, problem2.StatusCode);
    }

    [Fact]
    public async Task PairDevice_InvalidatesOldDeviceAndCurrentDeviceCache()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
            .Options);

        var cache = new MemoryCache(new MemoryCacheOptions());
        const string elderId = "ELDER_PAIR_CACHE";
        const string oldDeviceId = "WATCH_OLD_001";
        const string newDeviceId = "WATCH_NEW_002";
        const string pin = "123456";

        var elder = new ElderProfile
        {
            Id = elderId,
            FullName = "Cụ Thử Nghiệm Cache",
            PairingPin = pin,
            PinExpiresAt = DateTime.UtcNow.AddMinutes(10),
            IsDeleted = false
        };
        var oldDevice = new DeviceRegistration
        {
            Id = oldDeviceId,
            ElderProfileId = elderId,
            DeviceType = "Smartwatch",
            IsActive = true,
            RegisteredAt = DateTime.UtcNow.AddDays(-10),
            CreatedAt = DateTime.UtcNow.AddDays(-10),
            UpdatedAt = DateTime.UtcNow.AddDays(-10)
        };

        db.ElderProfiles.Add(elder);
        db.DeviceRegistrations.Add(oldDevice);
        await db.SaveChangesAsync();

        cache.Set($"auth:dev:{oldDeviceId}", new CachedDeviceAuthInfo("old_hash", true));
        cache.Set($"auth:dev:{newDeviceId}", new CachedDeviceAuthInfo("stale_hash", true));

        var controller = new DevicesController(db, Microsoft.Extensions.Logging.Abstractions.NullLogger<DevicesController>.Instance);
        var result = await controller.PairDevice(new PairDeviceRequest(newDeviceId, pin, "Smartwatch", "1.0.0"), CancellationToken.None, cache);

        Assert.IsType<Microsoft.AspNetCore.Mvc.OkObjectResult>(result);

        Assert.False(cache.TryGetValue($"auth:dev:{oldDeviceId}", out _));
        Assert.False(cache.TryGetValue($"auth:dev:{newDeviceId}", out _));

        var reloadedOld = await db.DeviceRegistrations.FindAsync(oldDeviceId);
        Assert.False(reloadedOld!.IsActive);
    }

}
