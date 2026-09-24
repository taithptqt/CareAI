namespace CareAI.Core.DTOs;

public record GeneratePinResponse(string Pin, DateTime ExpiresAt);
public record PairDeviceRequest(string DeviceId, string PairingPin, string DeviceType, string? FirmwareVersion);
public record PairDeviceResponse(string DeviceId, string DeviceToken, string ElderProfileId, string FullName);
public record CreateElderRequest(string FullName, DateTime DateOfBirth, string? MedicalNotes, string? EmergencyContact);
public record ElderItemDto(string Id, string FullName, DateTime DateOfBirth, string? MedicalNotes, string? EmergencyContact, string? PairingPin, DateTime? PinExpiresAt, int DeviceCount, string DeviceStatus);
