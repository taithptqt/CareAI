using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.Infrastructure.Engines;

public record UrgentHeartRateResult(string Status, string? IncidentId, bool Duplicate);

public class UrgentTelemetryEngine
{
    private readonly CareAiDbContext _db;
    private readonly ClinicalDiagnosticEngine _clinicalEngine;

    public UrgentTelemetryEngine(CareAiDbContext db, ClinicalDiagnosticEngine clinicalEngine)
    {
        _db = db;
        _clinicalEngine = clinicalEngine;
    }

    public async Task<UrgentHeartRateResult> ProcessHeartRateAsync(
        string deviceId, UrgentHeartRateRequest packet, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var measuredAt = packet.Timestamp.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(packet.Timestamp, DateTimeKind.Utc)
            : packet.Timestamp.ToUniversalTime();

        var device = await _db.DeviceRegistrations
            .FirstOrDefaultAsync(d => d.Id == deviceId && d.IsActive, ct);
        if (device == null)
            return new UrgentHeartRateResult("DEVICE_INACTIVE", null, false);

        if (await _db.ProcessedTelemetryLedgers.AnyAsync(
            p => p.DeviceId == deviceId && p.PacketId == packet.PacketId, ct))
            return new UrgentHeartRateResult("ALREADY_PROCESSED", null, true);

        _db.ProcessedTelemetryLedgers.Add(new ProcessedTelemetryLedger
        {
            DeviceId = deviceId,
            PacketId = packet.PacketId,
            ReceivedAt = now
        });
        device.LastHeartbeat = now;
        device.UpdatedAt = now;

        var sampleExists = await _db.HealthMeasurements.AnyAsync(m =>
            m.ElderProfileId == device.ElderProfileId &&
            m.DeviceId == deviceId &&
            m.Timestamp == measuredAt &&
            m.MetricType == "HEART_RATE", ct);
        if (!sampleExists)
        {
            _db.HealthMeasurements.Add(new HealthMeasurement
            {
                ElderProfileId = device.ElderProfileId,
                DeviceId = deviceId,
                PacketId = packet.PacketId,
                MetricType = "HEART_RATE",
                Value = packet.HeartRateBpm,
                Unit = "bpm",
                Timestamp = measuredAt,
                RecordedAt = now
            });
        }

        // Delayed offline samples are retained for history, but must not sound a stale alarm.
        var isFresh = measuredAt >= now.AddMinutes(-2) && measuredAt <= now.AddMinutes(1);
        var incident = isFresh && !sampleExists
            ? await _clinicalEngine.EvaluateHeartRateSampleAsync(
                device.ElderProfileId, deviceId, packet.HeartRateBpm,
                ct: ct, saveChanges: false, measuredAtUtc: measuredAt)
            : null;
        var alertQueued = _db.ChangeTracker.Entries<NotificationOutbox>()
            .Any(e => e.State == EntityState.Added);

        try
        {
            // One SaveChanges keeps ledger, sample, incident, timeline and outbox atomic on SQL Server.
            await _db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            _db.ChangeTracker.Clear();
            if (await _db.ProcessedTelemetryLedgers.AnyAsync(
                p => p.DeviceId == deviceId && p.PacketId == packet.PacketId, ct))
                return new UrgentHeartRateResult("ALREADY_PROCESSED", null, true);
            throw;
        }

        return new UrgentHeartRateResult(
            !isFresh ? "STORED_STALE" : alertQueued ? "ALERT_QUEUED" : "INCIDENT_UPDATED",
            incident?.Id,
            false);
    }
}
