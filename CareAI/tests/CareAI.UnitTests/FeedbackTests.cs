using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities;
using CareAI.Core.Entities.Admin;
using CareAI.Infrastructure.Admin;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Feedback;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CareAI.UnitTests;

public sealed class FeedbackTests
{
    private static CareAiDbContext CreateDb() => new(new DbContextOptionsBuilder<CareAiDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
        .Options);

    [Fact]
    public async Task CaregiverHistoryDoesNotExposeAnotherCaregiversMessages()
    {
        await using var db = CreateDb();
        db.Set<CustomerFeedback>().AddRange(
            new CustomerFeedback { CaregiverId = "fictional-a", RequestId = new string('a', 32), Subject = "A's feedback", Message = "Fictional feedback A" },
            new CustomerFeedback { CaregiverId = "fictional-b", RequestId = new string('b', 32), Subject = "B's feedback", Message = "Fictional feedback B" });
        await db.SaveChangesAsync();
        var result = await new FeedbackService(db).MineAsync("fictional-a", int.MaxValue, default);
        Assert.Equal(1, result.TotalCount);
        Assert.Equal(1, result.Page);
        Assert.Equal("A's feedback", Assert.Single(result.Items).Subject);
    }

    [Fact]
    public void SubmissionRejectsInvalidCategoryAndRequestId()
    {
        var invalid = new SubmitFeedbackRequest("invalid", "Unexpected", "Valid title", "Valid fictional message");
        var errors = new List<ValidationResult>();
        Assert.False(Validator.TryValidateObject(invalid, new ValidationContext(invalid), errors, true));
        Assert.Contains(errors, e => e.MemberNames.Contains(nameof(SubmitFeedbackRequest.Category)));
        Assert.Contains(errors, e => e.MemberNames.Contains(nameof(SubmitFeedbackRequest.RequestId)));
    }

    [Fact]
    public void FeedbackPermissionIsSeparateFromAuditAndCaregiverRoles()
    {
        Assert.Contains(AdminPermissions.Feedback, AdminPermissions.ForRole("Support"));
        Assert.Contains(AdminPermissions.Feedback, AdminPermissions.ForRole("Operations"));
        Assert.DoesNotContain(AdminPermissions.Feedback, AdminPermissions.ForRole("Auditor"));
        Assert.DoesNotContain(AdminPermissions.Feedback, AdminPermissions.ForRole("Caregiver"));
    }

    [Fact]
    public async Task SubmitAsync_IdempotentReplayReturnsExistingRecord()
    {
        await using var db = CreateDb();
        var service = new FeedbackService(db);
        var req = new SubmitFeedbackRequest(new string('c', 32), "Bug", "Tiêu đề hợp lệ", "Nội dung phản hồi chi tiết hợp lệ.");
        
        var first = await service.SubmitAsync("cg-1", req, default);
        var second = await service.SubmitAsync("cg-1", req, default);

        Assert.Equal(first.Id, second.Id);
        Assert.Equal(1, await db.Set<CustomerFeedback>().CountAsync());
    }

    [Fact]
    public async Task SubmitAsync_ConflictingPayloadThrowsFeedbackConflictException()
    {
        await using var db = CreateDb();
        var service = new FeedbackService(db);
        var req1 = new SubmitFeedbackRequest(new string('d', 32), "Bug", "Tiêu đề ban đầu", "Nội dung phản hồi ban đầu hợp lệ.");
        var req2 = new SubmitFeedbackRequest(new string('d', 32), "Bug", "Tiêu đề khác", "Nội dung phản hồi ban đầu hợp lệ.");

        await service.SubmitAsync("cg-1", req1, default);
        await Assert.ThrowsAsync<FeedbackConflictException>(() => service.SubmitAsync("cg-1", req2, default));
    }

    [Fact]
    public async Task SubmitAsync_RateLimitEnforced_10PerHour()
    {
        await using var db = CreateDb();
        var service = new FeedbackService(db);

        for (int i = 0; i < 10; i++)
        {
            var req = new SubmitFeedbackRequest(i.ToString("x32"), "Suggestion", $"Đề xuất số {i}", "Nội dung đề xuất cải tiến dịch vụ.");
            await service.SubmitAsync("cg-rate-limit", req, default);
        }

        var req11 = new SubmitFeedbackRequest("f".PadLeft(32, '0'), "Suggestion", "Đề xuất thứ 11", "Nội dung phản hồi thứ 11 vượt quá giới hạn.");
        await Assert.ThrowsAsync<FeedbackRateLimitException>(() => service.SubmitAsync("cg-rate-limit", req11, default));
    }

    [Fact]
    public async Task FeedbackController_RejectsSuspendedCaregiverWith403()
    {
        await using var db = CreateDb();
        db.Caregivers.Add(new Caregiver { Id = "cg-suspended", Email = "sus@test.com", FullName = "Suspended User", PasswordHash = "hash" });
        db.Set<CaregiverAdminState>().Add(new CaregiverAdminState { CaregiverId = "cg-suspended", IsSuspended = true });
        await db.SaveChangesAsync();

        var service = new FeedbackService(db);
        var controller = new FeedbackController(service, db)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "cg-suspended")]))
                }
            }
        };

        var mineResult = await controller.Mine(1, default) as ObjectResult;
        Assert.NotNull(mineResult);
        Assert.Equal(StatusCodes.Status403Forbidden, mineResult.StatusCode);

        var req = new SubmitFeedbackRequest(new string('e', 32), "Other", "Tiêu đề hợp lệ", "Nội dung góp ý hợp lệ.");
        var submitResult = await controller.Submit(req, default) as ObjectResult;
        Assert.NotNull(submitResult);
        Assert.Equal(StatusCodes.Status403Forbidden, submitResult.StatusCode);
    }

    [Fact]
    public async Task FeedbackController_RejectsOverlyLongSubjectOrMessageWith400()
    {
        await using var db = CreateDb();
        db.Caregivers.Add(new Caregiver { Id = "cg-valid", Email = "val@test.com", FullName = "Valid User", PasswordHash = "hash" });
        await db.SaveChangesAsync();

        var service = new FeedbackService(db);
        var controller = new FeedbackController(service, db)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "cg-valid")]))
                }
            }
        };

        var longSubjectReq = new SubmitFeedbackRequest(new string('1', 32), "Bug", new string('a', 121), "Nội dung hợp lệ 10 ký tự.");
        var longSubjectResult = await controller.Submit(longSubjectReq, default) as ObjectResult;
        Assert.NotNull(longSubjectResult);
        Assert.Equal(StatusCodes.Status400BadRequest, longSubjectResult.StatusCode);

        var longMsgReq = new SubmitFeedbackRequest(new string('2', 32), "Bug", "Tiêu đề hợp lệ", new string('m', 3001));
        var longMsgResult = await controller.Submit(longMsgReq, default) as ObjectResult;
        Assert.NotNull(longMsgResult);
        Assert.Equal(StatusCodes.Status400BadRequest, longMsgResult.StatusCode);
    }

    [Fact]
    public async Task AdminCommandService_FeedbackReply_LifecycleAndConcurrency()
    {
        await using var db = CreateDb();
        var cg = new Caregiver { Id = "cg-feedback", Email = "cg@test.com", FullName = "Người Thân Test", PasswordHash = "hash" };
        var fb = new CustomerFeedback { Id = "fb-01", CaregiverId = cg.Id, RequestId = new string('9', 32), Category = "Suggestion", Subject = "Cần tăng cỡ chữ", Message = "Chữ trên app hơi nhỏ." };
        var admin = new AdminUser { Id = "admin-op", NormalizedEmail = "OP@CAREAI.TEST", Role = "Operations", PasswordHash = AdminPasswords.Hash("AdminPass123!") };
        var sess = new AdminSession { Id = "sess-01", AdminUserId = admin.Id, SecurityVersion = admin.SecurityVersion, ExpiresAtUtc = DateTime.UtcNow.AddHours(2), LastSeenAtUtc = DateTime.UtcNow };

        db.Caregivers.Add(cg);
        db.Set<CustomerFeedback>().Add(fb);
        db.Set<AdminUser>().Add(admin);
        db.Set<AdminSession>().Add(sess);
        await db.SaveChangesAsync();

        var cmdOptions = new AdminCommandOptions("test-fingerprint-key-32-bytes-long!");
        var readService = new AdminOperationsReadService(db, cmdOptions);
        var record = await readService.RecordAsync("feedback", fb.Id, default);
        Assert.NotNull(record);
        Assert.Contains(record.Fields, f => f.Label == "Người gửi" && f.Value.Contains("Người Thân Test"));

        var commandService = new AdminCommandService(db, cmdOptions);
        var req = new AdminCommandRequest
        {
            Action = "feedback.reply",
            TargetId = fb.Id,
            ExpectedVersion = record.Version,
            Reason = "Đã cập nhật giao diện tăng cỡ chữ",
            ReauthPassword = "AdminPass123!",
            RequestId = Guid.NewGuid().ToString(),
            Values = new Dictionary<string, string>
            {
                ["Status"] = "Resolved",
                ["Reply"] = "CareAI đã bổ sung tùy chọn cỡ chữ lớn trong cài đặt."
            }
        };

        var result = await commandService.ExecuteAsync(admin.Id, sess.Id, req, "trace-fb-reply", default);
        Assert.Equal(fb.Id, result.TargetId);

        var updatedFb = await db.Set<CustomerFeedback>().SingleAsync(x => x.Id == fb.Id);
        Assert.Equal("Resolved", updatedFb.Status);
        Assert.Equal("CareAI đã bổ sung tùy chọn cỡ chữ lớn trong cài đặt.", updatedFb.AdminReply);
        Assert.NotNull(updatedFb.RepliedAtUtc);

        var audit = await db.Set<AdminAuditEvent>().SingleAsync(x => x.TargetId == fb.Id);
        Assert.Equal("feedback.reply", audit.Action);
        Assert.Equal("Success", audit.Result);
        Assert.Equal("admin-op", audit.ActorId);

        // Replay idempotency
        var replay = await commandService.ExecuteAsync(admin.Id, sess.Id, req, "trace-fb-replay", default);
        Assert.Contains("trước đó", replay.Message);

        // Concurrency conflict check
        var reqConflict = new AdminCommandRequest
        {
            Action = "feedback.reply",
            TargetId = fb.Id,
            ExpectedVersion = record.Version, // Stale version
            Reason = "Cố tình gửi version cũ",
            ReauthPassword = "AdminPass123!",
            RequestId = Guid.NewGuid().ToString(),
            Values = new Dictionary<string, string>
            {
                ["Status"] = "InProgress",
                ["Reply"] = "Nội dung phản hồi xung đột."
            }
        };
        await Assert.ThrowsAsync<CareAI.Infrastructure.Admin.AdminBusinessException>(() => commandService.ExecuteAsync(admin.Id, sess.Id, reqConflict, "trace-conflict", default));
    }

    [Fact]
    public async Task FeedbackService_InboxAsync_FilteringAndPagination()
    {
        await using var db = CreateDb();
        var cg1 = new Caregiver { Id = "cg-inbox-1", Email = "cg1@test.com", FullName = "Nguyễn Văn A", PasswordHash = "hash" };
        var cg2 = new Caregiver { Id = "cg-inbox-2", Email = "cg2@test.com", FullName = "Trần Thị B", PasswordHash = "hash" };
        db.Caregivers.AddRange(cg1, cg2);

        db.Set<CustomerFeedback>().AddRange(
            new CustomerFeedback { Id = "fb-sug-1", CaregiverId = cg1.Id, RequestId = "1".PadLeft(32, '0'), Category = "Suggestion", Subject = "Cải tiến giao diện SOS", Message = "Cần nút to hơn.", CreatedAtUtc = DateTime.UtcNow.AddMinutes(-30) },
            new CustomerFeedback { Id = "fb-bug-1", CaregiverId = cg2.Id, RequestId = "2".PadLeft(32, '0'), Category = "Bug", Subject = "Lỗi mất kết nối đồng hồ", Message = "Bluetooth tự ngắt vào ban đêm.", CreatedAtUtc = DateTime.UtcNow.AddMinutes(-20) },
            new CustomerFeedback { Id = "fb-other-1", CaregiverId = cg1.Id, RequestId = "3".PadLeft(32, '0'), Category = "Other", Subject = "Cảm ơn đội ngũ bác sĩ", Message = "Gia đình rất an tâm.", CreatedAtUtc = DateTime.UtcNow.AddMinutes(-10) }
        );
        await db.SaveChangesAsync();

        var service = new FeedbackService(db);

        // 1. Filter by category
        var bugs = await service.InboxAsync(null, "Bug", 1, default);
        Assert.Equal(1, bugs.TotalCount);
        Assert.Equal("fb-bug-1", bugs.Items[0].Id);
        Assert.Equal("Trần Thị B", bugs.Items[0].SenderName);

        // 2. Search in subject or message
        var searchResult = await service.InboxAsync("Bluetooth", null, 1, default);
        Assert.Equal(1, searchResult.TotalCount);
        Assert.Equal("fb-bug-1", searchResult.Items[0].Id);

        // 3. Search in subject
        var searchSubject = await service.InboxAsync("giao diện", null, 1, default);
        Assert.Equal(1, searchSubject.TotalCount);
        Assert.Equal("fb-sug-1", searchSubject.Items[0].Id);

        // 4. Default inbox all (sorted newest first)
        var all = await service.InboxAsync(null, null, 1, default);
        Assert.Equal(3, all.TotalCount);
        Assert.Equal("fb-other-1", all.Items[0].Id); // Most recent
    }

    [Fact]
    public async Task AdminFeedbackController_Inbox_ValidatesAndReturnsList()
    {
        await using var db = CreateDb();
        var cg = new Caregiver { Id = "cg-admin-inbox", Email = "cg@inbox.test", FullName = "Người Dùng Admin Inbox", PasswordHash = "hash" };
        db.Caregivers.Add(cg);
        db.Set<CustomerFeedback>().Add(new CustomerFeedback
        {
            Id = "fb-admin-1",
            CaregiverId = cg.Id,
            RequestId = "7".PadLeft(32, '0'),
            Category = "Bug",
            Subject = "Lỗi hiển thị",
            Message = "Biểu đồ nhịp tim bị lệch.",
            CreatedAtUtc = DateTime.UtcNow
        });
        await db.SaveChangesAsync();

        var service = new FeedbackService(db);
        var controller = new CareAI.API.Controllers.Admin.AdminFeedbackController(service)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() }
        };

        // Case 1: Empty string category (like from HTML select "Tất cả")
        var resEmptyCat = await controller.Inbox(null, "", 1, default) as OkObjectResult;
        Assert.NotNull(resEmptyCat);
        var listEmptyCat = Assert.IsAssignableFrom<AdminListResponse<AdminFeedbackDto>>(resEmptyCat.Value);
        Assert.Equal(1, listEmptyCat.TotalCount);

        // Case 2: Matching category
        var resMatchCat = await controller.Inbox(null, "Bug", 1, default) as OkObjectResult;
        Assert.NotNull(resMatchCat);
        var listMatchCat = Assert.IsAssignableFrom<AdminListResponse<AdminFeedbackDto>>(resMatchCat.Value);
        Assert.Equal(1, listMatchCat.TotalCount);

        // Case 3: Non-matching category
        var resOtherCat = await controller.Inbox(null, "Suggestion", 1, default) as OkObjectResult;
        Assert.NotNull(resOtherCat);
        var listOtherCat = Assert.IsAssignableFrom<AdminListResponse<AdminFeedbackDto>>(resOtherCat.Value);
        Assert.Equal(0, listOtherCat.TotalCount);
    }
}
