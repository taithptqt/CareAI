namespace CareAI.Core.Entities;

public class ElderProfile
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string FullName { get; set; } = string.Empty;
    public DateTime DateOfBirth { get; set; }
    public string? MedicalNotes { get; set; }
    public string? EmergencyContact { get; set; }
    public string? PairingPin { get; set; }
    public DateTime? PinExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    // Navigation properties
    public ICollection<DeviceRegistration> Devices { get; set; } = new List<DeviceRegistration>();
    public ICollection<ElderCaregiver> ElderCaregivers { get; set; } = new List<ElderCaregiver>();
    public ICollection<Incident> Incidents { get; set; } = new List<Incident>();
    public ICollection<HealthMeasurement> Measurements { get; set; } = new List<HealthMeasurement>();
}
