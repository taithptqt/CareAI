using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace CareAI.Infrastructure.Data;

public static class DatabaseMigrationHelper
{
    public const string DdlScript = """
    -- ============================================================================
    -- CAREAI v111.0 IDEMPOTENT DATABASE INITIALIZATION (AZURE SQL / T-SQL)
    -- ============================================================================

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ElderProfiles')
    BEGIN
        CREATE TABLE ElderProfiles (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            FullName NVARCHAR(100) NOT NULL,
            DateOfBirth DATETIME2 NOT NULL,
            MedicalNotes NVARCHAR(MAX) NULL,
            EmergencyContact NVARCHAR(50) NULL,
            PairingPin NVARCHAR(10) NULL,
            PinExpiresAt DATETIME2 NULL,
            RestingHeartRateMin FLOAT NOT NULL DEFAULT 40.0,
            RestingHeartRateMax FLOAT NOT NULL DEFAULT 120.0,
            ThresholdsUpdatedAt DATETIME2 NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
    END;

    -- ĐẢM BẢO IDEMPOTENT: Bổ sung các cột ngưỡng nếu bảng đã tồn tại từ phiên bản trước
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'RestingHeartRateMin')
    BEGIN
        ALTER TABLE ElderProfiles ADD RestingHeartRateMin FLOAT NOT NULL DEFAULT 40.0;
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'RestingHeartRateMax')
    BEGIN
        ALTER TABLE ElderProfiles ADD RestingHeartRateMax FLOAT NOT NULL DEFAULT 120.0;
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'ThresholdsUpdatedAt')
    BEGIN
        ALTER TABLE ElderProfiles ADD ThresholdsUpdatedAt DATETIME2 NULL;
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'NightHeartRateMin')
    BEGIN
        ALTER TABLE ElderProfiles ADD NightHeartRateMin FLOAT NOT NULL DEFAULT 40.0;
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'NightHeartRateMax')
    BEGIN
        ALTER TABLE ElderProfiles ADD NightHeartRateMax FLOAT NOT NULL DEFAULT 90.0;
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'SleepWindowStart')
    BEGIN
        ALTER TABLE ElderProfiles ADD SleepWindowStart NVARCHAR(10) NOT NULL DEFAULT '22:00';
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'SleepWindowEnd')
    BEGIN
        ALTER TABLE ElderProfiles ADD SleepWindowEnd NVARCHAR(10) NOT NULL DEFAULT '06:00';
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'DeviceRegistrations')
    BEGIN
        CREATE TABLE DeviceRegistrations (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            ElderProfileId NVARCHAR(50) NOT NULL,
            DeviceTokenHash NVARCHAR(128) NOT NULL,
            DeviceType NVARCHAR(50) NOT NULL,
            FirmwareVersion NVARCHAR(50) NOT NULL DEFAULT '1.0.0',
            IsActive BIT NOT NULL DEFAULT 1,
            LastHeartbeat DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            RegisteredAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT FK_Devices_Elder FOREIGN KEY (ElderProfileId) REFERENCES ElderProfiles(Id) ON DELETE CASCADE
        );
        CREATE INDEX IX_DeviceRegistrations_ElderId ON DeviceRegistrations(ElderProfileId);
        CREATE INDEX IX_DeviceRegistrations_Heartbeat ON DeviceRegistrations(LastHeartbeat);
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Caregivers')
    BEGIN
        CREATE TABLE Caregivers (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            FullName NVARCHAR(100) NOT NULL,
            PhoneNumber NVARCHAR(20) NOT NULL,
            Email NVARCHAR(100) NOT NULL,
            PasswordHash NVARCHAR(256) NOT NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        CREATE UNIQUE INDEX IX_Caregivers_Email ON Caregivers(Email);
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ElderCaregivers')
    BEGIN
        CREATE TABLE ElderCaregivers (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            ElderProfileId NVARCHAR(50) NOT NULL,
            CaregiverId NVARCHAR(50) NOT NULL,
            Role INT NOT NULL DEFAULT 2, -- Primary = 1, Secondary = 2
            IsActive BIT NOT NULL DEFAULT 1,
            AssignedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT FK_ElderCaregiver_Elder FOREIGN KEY (ElderProfileId) REFERENCES ElderProfiles(Id) ON DELETE CASCADE,
            CONSTRAINT FK_ElderCaregiver_Caregiver FOREIGN KEY (CaregiverId) REFERENCES Caregivers(Id) ON DELETE CASCADE,
            CONSTRAINT UQ_ElderCaregiver UNIQUE (ElderProfileId, CaregiverId)
        );
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'CaregiverPushTokens')
    BEGIN
        CREATE TABLE CaregiverPushTokens (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            CaregiverId NVARCHAR(50) NOT NULL,
            PushToken NVARCHAR(500) NOT NULL,
            DeviceModel NVARCHAR(100) NULL,
            IsActive BIT NOT NULL DEFAULT 1,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            LastUsedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            DeactivatedAt DATETIME2 NULL,
            DeactivationReason NVARCHAR(200) NULL,
            CONSTRAINT FK_CaregiverPushTokens_Caregiver FOREIGN KEY (CaregiverId) REFERENCES Caregivers(Id) ON DELETE CASCADE
        );
        CREATE INDEX IX_CaregiverPushTokens_Caregiver ON CaregiverPushTokens(CaregiverId, IsActive);
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Incidents')
    BEGIN
        CREATE TABLE Incidents (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            ElderProfileId NVARCHAR(50) NOT NULL,
            TriggeredByDeviceId NVARCHAR(50) NOT NULL,
            EmergencyType NVARCHAR(50) NOT NULL,
            Severity INT NOT NULL,
            Status INT NOT NULL DEFAULT 1, -- Open = 1, Acknowledged = 2, Resolved = 3
            TriggeredAt DATETIME2 NOT NULL,
            AcknowledgedAt DATETIME2 NULL,
            AcknowledgedByCaregiverId NVARCHAR(50) NULL,
            ResolvedAt DATETIME2 NULL,
            ResolvedByCaregiverId NVARCHAR(50) NULL,
            ResolutionNotes NVARCHAR(MAX) NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            RowVersion ROWVERSION,
            CONSTRAINT FK_Incidents_Elder FOREIGN KEY (ElderProfileId) REFERENCES ElderProfiles(Id) ON DELETE CASCADE
        );
        CREATE UNIQUE NONCLUSTERED INDEX UIX_Incidents_SingleActiveElder 
        ON Incidents (ElderProfileId) 
        WHERE [Status] IN (1, 2);
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'IncidentTimelineEvents')
    BEGIN
        CREATE TABLE IncidentTimelineEvents (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            IncidentId NVARCHAR(50) NOT NULL,
            EventType NVARCHAR(50) NOT NULL,
            Description NVARCHAR(MAX) NOT NULL,
            RecordedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT FK_Timeline_Incident FOREIGN KEY (IncidentId) REFERENCES Incidents(Id) ON DELETE CASCADE
        );
        CREATE INDEX IX_Timeline_IncidentId ON IncidentTimelineEvents(IncidentId);
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ProcessedTelemetryLedgers')
    BEGIN
        CREATE TABLE ProcessedTelemetryLedgers (
            DeviceId NVARCHAR(50) NOT NULL,
            PacketId NVARCHAR(100) NOT NULL,
            ReceivedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT PK_ProcessedTelemetryLedgers PRIMARY KEY (DeviceId, PacketId)
        );
        CREATE INDEX IX_ProcessedLedgers_Received ON ProcessedTelemetryLedgers(ReceivedAt);
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'HealthMeasurements')
    BEGIN
        CREATE TABLE HealthMeasurements (
            Id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
            ElderProfileId NVARCHAR(50) NOT NULL,
            DeviceId NVARCHAR(50) NOT NULL,
            PacketId NVARCHAR(100) NOT NULL,
            MetricType NVARCHAR(50) NOT NULL,
            Value FLOAT NOT NULL,
            Unit NVARCHAR(20) NOT NULL,
            Timestamp DATETIME2 NOT NULL,
            RecordedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT FK_HealthMeasurements_Elder FOREIGN KEY (ElderProfileId) REFERENCES ElderProfiles(Id) ON DELETE CASCADE
        );
        CREATE UNIQUE INDEX UIX_HealthMeasurements_Deduplication 
        ON HealthMeasurements(ElderProfileId, DeviceId, Timestamp, MetricType);
        CREATE INDEX IX_HealthMeasurements_ClinicalQuery 
        ON HealthMeasurements(ElderProfileId, MetricType, Timestamp DESC);
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'NotificationOutboxes')
    BEGIN
        CREATE TABLE NotificationOutboxes (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            IncidentId NVARCHAR(50) NOT NULL,
            RecipientCaregiverId NVARCHAR(50) NULL,
            PushToken NVARCHAR(500) NOT NULL,
            Title NVARCHAR(200) NOT NULL,
            Body NVARCHAR(MAX) NOT NULL,
            DataPayloadJson NVARCHAR(MAX) NOT NULL,
            Status NVARCHAR(20) NOT NULL DEFAULT 'PENDING',
            RetryCount INT NOT NULL DEFAULT 0,
            NextRetryAt DATETIME2 NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            SentAt DATETIME2 NULL,
            CONSTRAINT FK_NotificationOutboxes_Incident FOREIGN KEY (IncidentId) REFERENCES Incidents(Id) ON DELETE CASCADE
        );
        CREATE INDEX IX_NotificationOutbox_Pending ON NotificationOutboxes(Status, NextRetryAt);
    END;
    """;

    public static async Task InitializeDatabaseAsync(string connectionString, ILogger? logger = null, CancellationToken ct = default)
    {
        try
        {
            await using var conn = new SqlConnection(connectionString);
            await conn.OpenAsync(ct);
            logger?.LogInformation("[DB-INIT] Kết nối CSDL thành công. Đang thực thi DDL Idempotent...");

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = DdlScript;
            cmd.CommandTimeout = 60;
            await cmd.ExecuteNonQueryAsync(ct);

            logger?.LogInformation("[DB-INIT] Khởi tạo toàn bộ bảng và chỉ mục CSDL CareAI thành công!");
        }
        catch (Exception ex)
        {
            logger?.LogError(ex, "[DB-INIT-ERROR] Lỗi khi thực thi khởi tạo CSDL: {Message}", ex.Message);
            throw;
        }
    }
}
