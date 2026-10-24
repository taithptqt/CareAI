namespace CareAI.Core.DTOs;

public record GeneratePinResponse(string Pin, DateTime ExpiresAt);
public record PairDeviceRequest(string DeviceId, string PairingPin, string DeviceType, string? FirmwareVersion, string? DeviceModel = null);
public record SyncWatchRequest(
    string WatchModel,
    bool? IsConnected = true,
    string? DisconnectReason = null,
    bool? IsWorn = null,
    bool? IsCharging = null,
    int? BatteryLevel = null,
    int? TodaySteps = null,
    double? HeartRate = null,
    double? Spo2 = null,
    double? BpSystolic = null,
    double? BpDiastolic = null,
    int? SleepMinutes = null,
    List<string>? SupportedMetrics = null,
    int? DeepSleepMinutes = null,
    int? CoreSleepMinutes = null,
    int? RemSleepMinutes = null,
    int? AwakeMinutes = null,
    int? WakeCount = null,
    double? MinSleepingHeartRate = null,
    double? AvgSleepingHeartRate = null,
    double? MinNightSpo2 = null,
    int? NightSpo2DipsCount = null,
    string? BreathingDisturbances = null
);
public record PairDeviceResponse(string DeviceId, string DeviceToken, string ElderProfileId, string FullName);
public record CreateElderRequest(string FullName, DateTime DateOfBirth, string? MedicalNotes, string? EmergencyContact, string? HomeAddress = null, double? HomeLatitude = null, double? HomeLongitude = null);
public record UpdateElderHomeAddressRequest(string? HomeAddress, double? HomeLatitude = null, double? HomeLongitude = null);
public record ElderItemDto(string Id, string FullName, DateTime DateOfBirth, string? MedicalNotes, string? EmergencyContact, string? PairingPin, DateTime? PinExpiresAt, int DeviceCount, string DeviceStatus, string? HomeAddress = null, double? HomeLatitude = null, double? HomeLongitude = null);
public record DeviceActiveIncidentResponse(
    bool HasActiveIncident,
    string? IncidentId,
    string Status,
    string? EmergencyType,
    DateTime? TriggeredAt,
    DateTime? AcknowledgedAt,
    string? AcknowledgedByName,
    string? AcknowledgedNote,
    DateTime? ResolvedAt,
    string? ResolvedByName,
    string? ResolutionNotes,
    bool RequiresForceSync = false
);
