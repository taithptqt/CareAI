using System.Data;
using CareAI.Core.DTOs;
using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.Infrastructure.Feedback;

public sealed class FeedbackConflictException : Exception { }
public sealed class FeedbackRateLimitException : Exception { }

public sealed class FeedbackService(CareAiDbContext db)
{
    public async Task<CustomerFeedbackDto> SubmitAsync(string caregiverId, SubmitFeedbackRequest request, CancellationToken ct)
    {
        return await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            var requestId = request.RequestId.ToLowerInvariant();
            var subject = request.Subject.Trim();
            var message = request.Message.Trim();
            var existing = await db.Set<CustomerFeedback>().SingleOrDefaultAsync(x => x.CaregiverId == caregiverId && x.RequestId == requestId, ct);
            if (existing is not null)
            {
                if (existing.Category != request.Category || existing.Subject != subject || existing.Message != message)
                    throw new FeedbackConflictException();
                await tx.CommitAsync(ct);
                return ToDto(existing);
            }
            var since = DateTime.UtcNow.AddHours(-1);
            if (await db.Set<CustomerFeedback>().CountAsync(x => x.CaregiverId == caregiverId && x.CreatedAtUtc >= since, ct) >= 10)
                throw new FeedbackRateLimitException();
            var entry = new CustomerFeedback { CaregiverId = caregiverId, RequestId = requestId, Category = request.Category, Subject = subject, Message = message };
            db.Set<CustomerFeedback>().Add(entry);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return ToDto(entry);
        });
    }

    public async Task<AdminListResponse<CustomerFeedbackDto>> MineAsync(string caregiverId, int page, CancellationToken ct)
    {
        var query = db.Set<CustomerFeedback>().AsNoTracking().Where(x => x.CaregiverId == caregiverId);
        var count = await query.CountAsync(ct);
        page = ClampPage(page, count);
        var rows = await query.OrderByDescending(x => x.CreatedAtUtc).ThenBy(x => x.Id).Skip((page - 1) * 25).Take(25).ToArrayAsync(ct);
        return new(rows.Select(ToDto).ToArray(), count, page, 25, DateTimeOffset.UtcNow);
    }

    public async Task<AdminListResponse<AdminFeedbackDto>> InboxAsync(string? search, string? category, int page, CancellationToken ct)
    {
        var query = db.Set<CustomerFeedback>().AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(x => x.Subject.Contains(search) || x.Message.Contains(search));
        if (!string.IsNullOrEmpty(category)) query = query.Where(x => x.Category == category);
        var count = await query.CountAsync(ct);
        page = ClampPage(page, count);
        var rows = await query.OrderByDescending(x => x.CreatedAtUtc).ThenBy(x => x.Id).Skip((page - 1) * 25).Take(25)
            .Select(x => new { x.Id, x.CaregiverId, x.Caregiver.FullName, x.Category, x.Subject, x.Message, x.CreatedAtUtc, x.Status, x.AdminReply, x.RepliedAtUtc }).ToArrayAsync(ct);
        return new(rows.Select(x => new AdminFeedbackDto(x.Id, x.CaregiverId, x.FullName, x.Category, x.Subject, x.Message,
            new DateTimeOffset(DateTime.SpecifyKind(x.CreatedAtUtc, DateTimeKind.Utc)), x.Status, x.AdminReply,
            CareAI.Infrastructure.Admin.AdminOperationsReadService.Version(new { x.Status, x.AdminReply, x.RepliedAtUtc }))).ToArray(), count, page, 25, DateTimeOffset.UtcNow);
    }
    private static int ClampPage(int page, int count) => Math.Clamp(page, 1, Math.Max(1, (int)Math.Ceiling(count / 25d)));
    private static CustomerFeedbackDto ToDto(CustomerFeedback x) => new(x.Id, x.Category, x.Subject, x.Message,
        new DateTimeOffset(DateTime.SpecifyKind(x.CreatedAtUtc, DateTimeKind.Utc)), x.Status, x.AdminReply,
        x.RepliedAtUtc is DateTime t ? new DateTimeOffset(DateTime.SpecifyKind(t, DateTimeKind.Utc)) : null);
}
