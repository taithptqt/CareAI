using System.ComponentModel.DataAnnotations;
using CareAI.Core.DTOs;
using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Feedback;
using Microsoft.EntityFrameworkCore;

namespace CareAI.UnitTests;

public sealed class FeedbackTests
{
    [Fact]
    public async Task CaregiverHistoryDoesNotExposeAnotherCaregiversMessages()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
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
}
