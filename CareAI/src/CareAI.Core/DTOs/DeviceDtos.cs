namespace CareAI.Core.DTOs;

public record GeneratePinResponse(string Pin, DateTime ExpiresAt);
public record PairDeviceRequest(string DeviceId, string PairingPin, string DeviceType, string? FirmwareVersion, string? DeviceModel = null);
public record SyncWatchRequest(string WatchModel);
public record PairDeviceResponse(string DeviceId, string DeviceToken, string ElderProfileId, string FullName);
public record CreateElderRequest(string FullName, DateTime DateOfBirth, string? MedicalNotes, string? EmergencyContact, string? HomeAddress = null, double? HomeLatitude = null, double? HomeLongitude = null);
public record UpdateElderHomeAddressRequest(string? HomeAddress, double? HomeLatitude = null, double? HomeLongitude = null);
public record ElderItemDto(string Id, string FullName, DateTime DateOfBirth, string? MedicalNotes, string? EmergencyContact, string? PairingPin, DateTime? PinExpiresAt, int DeviceCount, string DeviceStatus, string? HomeAddress = null, double? HomeLatitude = null, double? HomeLongitude = null);
