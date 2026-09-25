namespace CareAI.Core.DTOs;

// ===== FAMILY INVITATION DTOs =====
public record CreateInvitationResponse(string InvitationCode, DateTime ExpiresAt);
public record AcceptInvitationRequest(string InvitationCode);
public record AcceptInvitationResponse(string ElderProfileId, string ElderName, string Role);

// ===== FAMILY MEMBER DTOs =====
public record FamilyMemberDto(
    string CaregiverId,
    string FullName,
    string Email,
    string PhoneNumber,
    string Role,
    bool IsActive,
    DateTime AssignedAt
);

// ===== ELDER PROFILE EDIT DTOs =====
public record UpdateElderRequest(
    string? FullName,
    DateTime? DateOfBirth,
    string? MedicalNotes,
    string? EmergencyContact
);

// ===== DEVICE UNPAIR DTOs =====
public record UnpairDeviceResponse(string DeviceId, string Status, string Message);

// ===== DELETE ELDER DTOs =====
public record DeleteElderRequest(string Password);
public record DeleteElderResponse(string ElderProfileId, string Status, string Message);

// ===== PASSWORD RESET DTOs =====
public record ForgotPasswordRequest(string Email);
public record ForgotPasswordResponse(string Message);
public record ResetPasswordRequest(string Email, string OtpCode, string NewPassword);
public record ResetPasswordResponse(string Message);
