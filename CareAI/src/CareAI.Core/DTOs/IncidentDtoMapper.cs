using CareAI.Core.Entities;

namespace CareAI.Core.DTOs;

public static class IncidentDtoMapper
{
    public static IncidentResponseDto ToResponse(
        Incident incident,
        string elderName,
        IncidentHeartRateWindowDto? heartRateSeries = null) => new(
        incident.Id,
        incident.ElderProfileId,
        elderName,
        incident.TriggeredByDeviceId,
        incident.EmergencyType,
        incident.Severity.ToString(),
        incident.Status.ToString(),
        incident.TriggeredAt,
        incident.AcknowledgedAt,
        incident.AcknowledgedByCaregiverId,
        incident.ResolvedAt,
        incident.ResolvedByCaregiverId,
        incident.ResolutionNotes,
        incident.TimelineEvents
            .OrderBy(t => t.RecordedAt)
            .ThenBy(t => t.Id)
            .Select(t => new IncidentTimelineDto(t.EventType, t.Description, t.RecordedAt,
                t.ActorCaregiverId, t.AlertCycleNumber))
            .ToList(),
        incident.RowVersion is { Length: > 0 } ? Convert.ToBase64String(incident.RowVersion) : null,
        new IncidentSnapshotDto(incident.HeartRateBpm, incident.SpO2Percent,
            incident.BpSystolic, incident.BpDiastolic, incident.VitalsMeasuredAt,
            incident.GpsLocation, incident.HomeAddressSnapshot,
            incident.CurrentGpsLocation, incident.CurrentGpsMeasuredAt,
            incident.CurrentGpsIsSimulated, incident.CurrentGpsAccuracyMeters),
        new IncidentAlertStateDto(incident.AlertCycleNumber, incident.AlertStartedAt,
            incident.AlertDeadlineAt, incident.SlaBreachedAt),
        heartRateSeries);
}
