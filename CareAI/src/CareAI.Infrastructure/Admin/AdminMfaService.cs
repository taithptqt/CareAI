using System.Buffers.Binary;
using System.Data;
using System.Globalization;
using System.Security.Cryptography;
using CareAI.Core.Entities.Admin;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.Infrastructure.Admin;

public interface IAdminMfaProtector
{
    string Protect(string value);
    string Unprotect(string value);
}
public sealed record AdminMfaOptions(bool Required);
public static class AdminTotp
{
    private const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    public static string NewSecret()
    {
        var bytes = RandomNumberGenerator.GetBytes(20);
        var output = new System.Text.StringBuilder();
        var buffer = 0; var bits = 0;
        foreach (var value in bytes)
        {
            buffer = (buffer << 8) | value; bits += 8;
            while (bits >= 5) { bits -= 5; output.Append(Alphabet[(buffer >> bits) & 31]); }
        }
        return output.ToString();
    }
    public static string Code(string secret, long counter)
    {
        var bytes = new List<byte>(); var buffer = 0; var bits = 0;
        foreach (var character in secret)
        {
            var value = Alphabet.IndexOf(character);
            if (value < 0) throw new FormatException("Invalid TOTP secret.");
            buffer = (buffer << 5) | value; bits += 5;
            if (bits >= 8) { bits -= 8; bytes.Add((byte)(buffer >> bits)); }
        }
        Span<byte> step = stackalloc byte[8]; BinaryPrimitives.WriteInt64BigEndian(step, counter);
        var hash = HMACSHA1.HashData(bytes.ToArray(), step);
        var offset = hash[^1] & 15;
        var value32 = BinaryPrimitives.ReadInt32BigEndian(hash.AsSpan(offset, 4)) & 0x7fffffff;
        return (value32 % 1_000_000).ToString("D6", CultureInfo.InvariantCulture);
    }
    public static long? Verify(string secret, string? code, DateTimeOffset now, long lastCounter)
    {
        if (code?.Length != 6 || code.Any(c => c is < '0' or > '9')) return null;
        var step = now.ToUnixTimeSeconds() / 30;
        foreach (var offset in new[] { 0, -1, 1 })
        {
            var counter = step + offset;
            if (counter <= lastCounter) continue;
            if (CryptographicOperations.FixedTimeEquals(System.Text.Encoding.ASCII.GetBytes(Code(secret, counter)), System.Text.Encoding.ASCII.GetBytes(code))) return counter;
        }
        return null;
    }
}

public sealed class AdminMfaService(CareAiDbContext db, IAdminMfaProtector protector)
{
    public long? Verify(AdminUser user, string? code) => user.MfaSecretProtected is null ? null
        : AdminTotp.Verify(protector.Unprotect(user.MfaSecretProtected), code, DateTimeOffset.UtcNow, user.LastTotpCounter);

    public async Task<string?> EnrollAsync(string actorId, string password, string? code, string trace, CancellationToken ct)
    {
        return await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            var user = await db.Set<AdminUser>().SingleAsync(x => x.Id == actorId, ct);
            if (!user.IsActive || !AdminPasswords.Verify(password, user.PasswordHash)) throw new AdminBusinessException("Xác thực lại không thành công.", 403);
            if (user.MfaEnabled) throw new AdminBusinessException("Tài khoản đã bật MFA. Không thay khóa qua luồng đăng ký lại.");
            string? result = null;
            if (code is null)
            {
                result = AdminTotp.NewSecret(); user.PendingMfaSecretProtected = protector.Protect(result);
            }
            else
            {
                if (user.PendingMfaSecretProtected is null) throw new AdminBusinessException("Hãy tạo khóa thiết lập trước.");
                var counter = AdminTotp.Verify(protector.Unprotect(user.PendingMfaSecretProtected), code, DateTimeOffset.UtcNow, -1);
                if (counter is null) throw new AdminBusinessException("Mã TOTP không hợp lệ. Kiểm tra đồng hồ và thử lại.");
                user.MfaSecretProtected = user.PendingMfaSecretProtected; user.PendingMfaSecretProtected = null;
                user.MfaEnabled = true; user.LastTotpCounter = counter.Value;
                user.SecurityVersion++;
                var now = DateTime.UtcNow;
                await db.Set<AdminSession>().Where(x => x.AdminUserId == user.Id && x.RevokedAtUtc == null)
                    .ExecuteUpdateAsync(set => set.SetProperty(x => x.RevokedAtUtc, now), ct);
            }
            db.Set<AdminAuditEvent>().Add(new() { ActorId = user.Id, Action = code is null ? "auth.mfa.begin" : "auth.mfa.enabled", TargetId = user.Id, Result = "Success", TraceId = trace });
            await db.SaveChangesAsync(ct); await tx.CommitAsync(ct);
            return result;
        });
    }
}
