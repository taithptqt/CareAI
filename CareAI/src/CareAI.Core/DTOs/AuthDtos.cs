namespace CareAI.Core.DTOs;

public record RegisterCaregiverRequest(string FullName, string PhoneNumber, string Email, string Password);
public record LoginRequest(string Email, string Password);
public record AuthResponse(string Token, string CaregiverId, string FullName, string Email);
public record RegisterPushTokenRequest(string PushToken, string? DeviceModel);
