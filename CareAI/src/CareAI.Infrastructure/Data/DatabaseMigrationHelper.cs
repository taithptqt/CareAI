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
            HomeAddress NVARCHAR(500) NULL,
            HomeLatitude FLOAT NULL,
            HomeLongitude FLOAT NULL,
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
            DeviceModel NVARCHAR(100) NULL,
            DisconnectReason NVARCHAR(50) NULL,
            IsWatchWorn BIT NULL,
            IsWatchCharging BIT NULL,
            WatchBatteryLevel INT NULL,
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
            HeartRateBpm FLOAT NULL,
            SpO2Percent FLOAT NULL,
            BpSystolic FLOAT NULL,
            BpDiastolic FLOAT NULL,
            VitalsMeasuredAt DATETIME2 NULL,
            GpsLocation NVARCHAR(100) NULL,
            CurrentGpsLocation NVARCHAR(100) NULL,
            CurrentGpsMeasuredAt DATETIME2 NULL,
            CurrentGpsIsSimulated BIT NULL,
            CurrentGpsAccuracyMeters FLOAT NULL,
            HomeAddressSnapshot NVARCHAR(500) NULL,
            AlertCycleNumber INT NOT NULL DEFAULT 1,
            AlertStartedAt DATETIME2 NULL,
            AlertDeadlineAt DATETIME2 NULL,
            SlaBreachedAt DATETIME2 NULL,
            ReminderCount INT NOT NULL DEFAULT 0,
            NextReminderAt DATETIME2 NULL,
            AcknowledgedAt DATETIME2 NULL,
            AcknowledgedByCaregiverId NVARCHAR(50) NULL,
            ResolvedAt DATETIME2 NULL,
            ResolvedByCaregiverId NVARCHAR(50) NULL,
            ResolutionNotes NVARCHAR(MAX) NULL,
            ConnectivityLostAt DATETIME2 NULL,
            LatestCriticalHeartRateBpm FLOAT NULL,
            LatestCriticalRuleCode NVARCHAR(50) NULL,
            AcknowledgedCriticalHeartRateBpm FLOAT NULL,
            AcknowledgedCriticalRuleCode NVARCHAR(50) NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            RowVersion ROWVERSION,
            CONSTRAINT FK_Incidents_Elder FOREIGN KEY (ElderProfileId) REFERENCES ElderProfiles(Id) ON DELETE NO ACTION
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
            ActorCaregiverId NVARCHAR(50) NULL,
            AlertCycleNumber INT NULL,
            CONSTRAINT FK_Timeline_Incident FOREIGN KEY (IncidentId) REFERENCES Incidents(Id) ON DELETE NO ACTION
        );
        CREATE INDEX IX_Timeline_IncidentId ON IncidentTimelineEvents(IncidentId);
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'IncidentPhotos')
    BEGIN
        CREATE TABLE IncidentPhotos (
            IncidentId NVARCHAR(50) NOT NULL PRIMARY KEY,
            DeviceId NVARCHAR(50) NOT NULL,
            JpegBytes VARBINARY(MAX) NOT NULL,
            Sha256 NVARCHAR(64) NOT NULL,
            CapturedAt DATETIME2 NOT NULL,
            ReceivedAt DATETIME2 NOT NULL,
            CONSTRAINT FK_IncidentPhotos_Incident FOREIGN KEY (IncidentId)
                REFERENCES Incidents(Id) ON DELETE NO ACTION
        );
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ProcessedTelemetryLedgers')
    BEGIN
        CREATE TABLE ProcessedTelemetryLedgers (
            DeviceId NVARCHAR(50) NOT NULL,
            PacketId NVARCHAR(100) NOT NULL,
            IncidentId NVARCHAR(50) NULL,
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
            AlertCycleNumber INT NOT NULL DEFAULT 1,
            PushToken NVARCHAR(500) NOT NULL,
            Title NVARCHAR(200) NOT NULL,
            Body NVARCHAR(MAX) NOT NULL,
            DataPayloadJson NVARCHAR(MAX) NOT NULL,
            Status NVARCHAR(20) NOT NULL DEFAULT 'PENDING',
            RetryCount INT NOT NULL DEFAULT 0,
            NextRetryAt DATETIME2 NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            SentAt DATETIME2 NULL,
            LeaseExpiresAt DATETIME2 NULL,
            ProviderMessageId NVARCHAR(200) NULL,
            LastErrorCode NVARCHAR(100) NULL,
            RowVersion ROWVERSION,
            CONSTRAINT FK_NotificationOutboxes_Incident FOREIGN KEY (IncidentId) REFERENCES Incidents(Id) ON DELETE CASCADE
        );
        CREATE INDEX IX_NotificationOutbox_Pending ON NotificationOutboxes(Status, NextRetryAt);
    END;
    -- Existing v111 databases need additive changes; nullable snapshots preserve old incidents.
    IF COL_LENGTH('dbo.ProcessedTelemetryLedgers', 'IncidentId') IS NULL
        ALTER TABLE dbo.ProcessedTelemetryLedgers ADD IncidentId NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.ElderProfiles', 'HomeAddress') IS NULL
        ALTER TABLE dbo.ElderProfiles ADD HomeAddress NVARCHAR(500) NULL;
    IF COL_LENGTH('dbo.ElderProfiles', 'HomeLatitude') IS NULL
        ALTER TABLE dbo.ElderProfiles ADD HomeLatitude FLOAT NULL;
    IF COL_LENGTH('dbo.ElderProfiles', 'HomeLongitude') IS NULL
        ALTER TABLE dbo.ElderProfiles ADD HomeLongitude FLOAT NULL;

    IF COL_LENGTH('dbo.Incidents', 'HeartRateBpm') IS NULL
        ALTER TABLE dbo.Incidents ADD HeartRateBpm FLOAT NULL;
    IF COL_LENGTH('dbo.Incidents', 'SpO2Percent') IS NULL
        ALTER TABLE dbo.Incidents ADD SpO2Percent FLOAT NULL;
    IF COL_LENGTH('dbo.Incidents', 'BpSystolic') IS NULL
        ALTER TABLE dbo.Incidents ADD BpSystolic FLOAT NULL;
    IF COL_LENGTH('dbo.Incidents', 'BpDiastolic') IS NULL
        ALTER TABLE dbo.Incidents ADD BpDiastolic FLOAT NULL;
    IF COL_LENGTH('dbo.Incidents', 'VitalsMeasuredAt') IS NULL
        ALTER TABLE dbo.Incidents ADD VitalsMeasuredAt DATETIME2 NULL;
    IF COL_LENGTH('dbo.Incidents', 'GpsLocation') IS NULL
        ALTER TABLE dbo.Incidents ADD GpsLocation NVARCHAR(100) NULL;
    IF COL_LENGTH('dbo.Incidents', 'CurrentGpsLocation') IS NULL
        ALTER TABLE dbo.Incidents ADD CurrentGpsLocation NVARCHAR(100) NULL;
    IF COL_LENGTH('dbo.Incidents', 'CurrentGpsMeasuredAt') IS NULL
        ALTER TABLE dbo.Incidents ADD CurrentGpsMeasuredAt DATETIME2 NULL;
    IF COL_LENGTH('dbo.Incidents', 'CurrentGpsIsSimulated') IS NULL
        ALTER TABLE dbo.Incidents ADD CurrentGpsIsSimulated BIT NULL;
    IF COL_LENGTH('dbo.Incidents', 'CurrentGpsAccuracyMeters') IS NULL
        ALTER TABLE dbo.Incidents ADD CurrentGpsAccuracyMeters FLOAT NULL;
    IF COL_LENGTH('dbo.Incidents', 'HomeAddressSnapshot') IS NULL
        ALTER TABLE dbo.Incidents ADD HomeAddressSnapshot NVARCHAR(500) NULL;
    IF COL_LENGTH('dbo.Incidents', 'AlertCycleNumber') IS NULL
        ALTER TABLE dbo.Incidents ADD AlertCycleNumber INT NOT NULL CONSTRAINT DF_Incidents_AlertCycleNumber DEFAULT 1;
    IF COL_LENGTH('dbo.Incidents', 'AlertStartedAt') IS NULL
        ALTER TABLE dbo.Incidents ADD AlertStartedAt DATETIME2 NULL;
    IF COL_LENGTH('dbo.Incidents', 'AlertDeadlineAt') IS NULL
        ALTER TABLE dbo.Incidents ADD AlertDeadlineAt DATETIME2 NULL;
    IF COL_LENGTH('dbo.Incidents', 'SlaBreachedAt') IS NULL
        ALTER TABLE dbo.Incidents ADD SlaBreachedAt DATETIME2 NULL;
    IF COL_LENGTH('dbo.Incidents', 'ReminderCount') IS NULL
        ALTER TABLE dbo.Incidents ADD ReminderCount INT NOT NULL CONSTRAINT DF_Incidents_ReminderCount DEFAULT 0;
    IF COL_LENGTH('dbo.Incidents', 'NextReminderAt') IS NULL
        ALTER TABLE dbo.Incidents ADD NextReminderAt DATETIME2 NULL;
    IF COL_LENGTH('dbo.Incidents', 'ConnectivityLostAt') IS NULL
        ALTER TABLE dbo.Incidents ADD ConnectivityLostAt DATETIME2 NULL;
    IF COL_LENGTH('dbo.Incidents', 'LatestCriticalHeartRateBpm') IS NULL
        ALTER TABLE dbo.Incidents ADD LatestCriticalHeartRateBpm FLOAT NULL;
    IF COL_LENGTH('dbo.Incidents', 'LatestCriticalRuleCode') IS NULL
        ALTER TABLE dbo.Incidents ADD LatestCriticalRuleCode NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.Incidents', 'AcknowledgedCriticalHeartRateBpm') IS NULL
        ALTER TABLE dbo.Incidents ADD AcknowledgedCriticalHeartRateBpm FLOAT NULL;
    IF COL_LENGTH('dbo.Incidents', 'AcknowledgedCriticalRuleCode') IS NULL
        ALTER TABLE dbo.Incidents ADD AcknowledgedCriticalRuleCode NVARCHAR(50) NULL;

    IF OBJECT_ID('dbo.ClinicalRuleCooldowns', 'U') IS NULL
        CREATE TABLE dbo.ClinicalRuleCooldowns (
            ElderProfileId NVARCHAR(50) NOT NULL,
            RuleCode NVARCHAR(50) NOT NULL,
            LastAlertAt DATETIME2 NOT NULL,
            LastIncidentId NVARCHAR(50) NOT NULL,
            CONSTRAINT PK_ClinicalRuleCooldowns PRIMARY KEY (ElderProfileId, RuleCode),
            CONSTRAINT FK_ClinicalRuleCooldowns_Elder FOREIGN KEY (ElderProfileId)
                REFERENCES dbo.ElderProfiles(Id) ON DELETE CASCADE
        );

    IF COL_LENGTH('dbo.IncidentTimelineEvents', 'ActorCaregiverId') IS NULL
        ALTER TABLE dbo.IncidentTimelineEvents ADD ActorCaregiverId NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.IncidentTimelineEvents', 'AlertCycleNumber') IS NULL
        ALTER TABLE dbo.IncidentTimelineEvents ADD AlertCycleNumber INT NULL;

    IF COL_LENGTH('dbo.NotificationOutboxes', 'AlertCycleNumber') IS NULL
        ALTER TABLE dbo.NotificationOutboxes ADD AlertCycleNumber INT NOT NULL CONSTRAINT DF_NotificationOutboxes_AlertCycleNumber DEFAULT 1;
    IF COL_LENGTH('dbo.NotificationOutboxes', 'LeaseExpiresAt') IS NULL
        ALTER TABLE dbo.NotificationOutboxes ADD LeaseExpiresAt DATETIME2 NULL;
    IF COL_LENGTH('dbo.NotificationOutboxes', 'ProviderMessageId') IS NULL
        ALTER TABLE dbo.NotificationOutboxes ADD ProviderMessageId NVARCHAR(200) NULL;
    IF COL_LENGTH('dbo.NotificationOutboxes', 'LastErrorCode') IS NULL
        ALTER TABLE dbo.NotificationOutboxes ADD LastErrorCode NVARCHAR(100) NULL;
    IF COL_LENGTH('dbo.NotificationOutboxes', 'RowVersion') IS NULL
        ALTER TABLE dbo.NotificationOutboxes ADD RowVersion ROWVERSION;

    -- Bỏ đường cascade có thể xóa lịch sử sự cố và timeline (Task 8 / Bước 8)
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Incidents_Elder' AND delete_referential_action = 1)
    BEGIN
        ALTER TABLE dbo.Incidents DROP CONSTRAINT FK_Incidents_Elder;
        ALTER TABLE dbo.Incidents ADD CONSTRAINT FK_Incidents_Elder FOREIGN KEY (ElderProfileId) REFERENCES dbo.ElderProfiles(Id) ON DELETE NO ACTION;
    END;

    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Timeline_Incident' AND delete_referential_action = 1)
    BEGIN
        ALTER TABLE dbo.IncidentTimelineEvents DROP CONSTRAINT FK_Timeline_Incident;
        ALTER TABLE dbo.IncidentTimelineEvents ADD CONSTRAINT FK_Timeline_Incident FOREIGN KEY (IncidentId) REFERENCES dbo.Incidents(Id) ON DELETE NO ACTION;
    END;

    -- Triggers bảo vệ lịch sử bất biến tại mức CSDL SQL Server (Task 8 / Bước 8)
    EXEC('
    CREATE OR ALTER TRIGGER dbo.TR_Incidents_PreventResolvedModification
    ON dbo.Incidents
    AFTER UPDATE, DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        IF CAST(SESSION_CONTEXT(N''ALLOW_ADMIN_HISTORICAL_OVERRIDE'') AS NVARCHAR(10)) = N''TRUE''
            RETURN;

        IF EXISTS (SELECT 1 FROM deleted WHERE [Status] = 3)
        BEGIN
            RAISERROR(''Incident history is immutable. Cannot update or delete a resolved incident.'', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;
    END;');

    EXEC('
    CREATE OR ALTER TRIGGER dbo.TR_IncidentTimelineEvents_PreventModification
    ON dbo.IncidentTimelineEvents
    AFTER UPDATE, DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        IF CAST(SESSION_CONTEXT(N''ALLOW_ADMIN_HISTORICAL_OVERRIDE'') AS NVARCHAR(10)) = N''TRUE''
            RETURN;

        RAISERROR(''Incident timeline events are append-only and cannot be updated or deleted.'', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;');

    EXEC('
    CREATE OR ALTER TRIGGER dbo.TR_IncidentPhotos_PreventModification
    ON dbo.IncidentPhotos
    AFTER UPDATE, DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        RAISERROR(''Incident photos are append-only.'', 16, 1);
        ROLLBACK TRANSACTION;
    END;');

    -- ============================================================================
    -- PHẦN 3: QUẢN TRỊ NHÓM GIA ĐÌNH, RBAC & VÒNG ĐỜI THIẾT BỊ
    -- ============================================================================

    -- Bổ sung cột Brute-Force Lockout cho Caregivers
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Caregivers') AND name = 'FailedLoginAttempts')
    BEGIN
        ALTER TABLE Caregivers ADD FailedLoginAttempts INT NOT NULL DEFAULT 0;
        ALTER TABLE Caregivers ADD LockoutEnd DATETIME2 NULL;
    END;

    -- Bổ sung cột cho ElderProfiles
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'IsDeleted')
    BEGIN
        ALTER TABLE ElderProfiles ADD IsDeleted BIT NOT NULL DEFAULT 0;
        ALTER TABLE ElderProfiles ADD PairingPinHash NVARCHAR(128) NULL;
    END;

    -- Bổ sung cột DeviceModel cho DeviceRegistrations
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('DeviceRegistrations') AND name = 'DeviceModel')
    BEGIN
        ALTER TABLE DeviceRegistrations ADD DeviceModel NVARCHAR(100) NULL;
    END;

    -- Bổ sung cột DisconnectReason cho DeviceRegistrations (phân biệt tắt Bluetooth chủ động vs mất sóng BLE)
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('DeviceRegistrations') AND name = 'DisconnectReason')
    BEGIN
        ALTER TABLE DeviceRegistrations ADD DisconnectReason NVARCHAR(50) NULL;
    END;

    -- Bổ sung các cột trạng thái đeo, sạc và pin đồng hồ cho DeviceRegistrations
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('DeviceRegistrations') AND name = 'IsWatchWorn')
    BEGIN
        ALTER TABLE DeviceRegistrations ADD IsWatchWorn BIT NULL;
    END;

    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('DeviceRegistrations') AND name = 'IsWatchCharging')
    BEGIN
        ALTER TABLE DeviceRegistrations ADD IsWatchCharging BIT NULL;
    END;

    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('DeviceRegistrations') AND name = 'WatchBatteryLevel')
    BEGIN
        ALTER TABLE DeviceRegistrations ADD WatchBatteryLevel INT NULL;
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'FamilyInvitations')
    BEGIN
        CREATE TABLE FamilyInvitations (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            ElderProfileId NVARCHAR(50) NOT NULL,
            InvitedByCaregiverId NVARCHAR(50) NOT NULL,
            InvitationCode NVARCHAR(10) NOT NULL,
            InvitationCodeHash NVARCHAR(128) NOT NULL,
            IsUsed BIT NOT NULL DEFAULT 0,
            AcceptedByCaregiverId NVARCHAR(50) NULL,
            AcceptedAt DATETIME2 NULL,
            ExpiresAt DATETIME2 NOT NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT FK_FamilyInvitations_Elder FOREIGN KEY (ElderProfileId) REFERENCES ElderProfiles(Id) ON DELETE CASCADE,
            CONSTRAINT FK_FamilyInvitations_Caregiver FOREIGN KEY (InvitedByCaregiverId) REFERENCES Caregivers(Id) ON DELETE NO ACTION
        );
        CREATE INDEX IX_FamilyInvitations_CodeHash ON FamilyInvitations(InvitationCodeHash);
        CREATE INDEX IX_FamilyInvitations_Expires ON FamilyInvitations(ExpiresAt);
    END;

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PasswordResetTokens')
    BEGIN
        CREATE TABLE PasswordResetTokens (
            Id NVARCHAR(50) NOT NULL PRIMARY KEY,
            CaregiverId NVARCHAR(50) NOT NULL,
            OtpCode NVARCHAR(10) NOT NULL,
            OtpHash NVARCHAR(128) NOT NULL,
            IsUsed BIT NOT NULL DEFAULT 0,
            ExpiresAt DATETIME2 NOT NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT FK_PasswordResetTokens_Caregiver FOREIGN KEY (CaregiverId) REFERENCES Caregivers(Id) ON DELETE CASCADE
        );
        CREATE INDEX IX_PasswordResetTokens_OtpHash ON PasswordResetTokens(OtpHash);
        CREATE INDEX IX_PasswordResetTokens_Expires ON PasswordResetTokens(ExpiresAt);
    END;

    -- ============================================================================
    -- PHẦN 4: TRÍ TUỆ NHÂN TẠO ML.NET & ZERO-PII GEMINI WEEKLY REPORT
    -- ============================================================================

    IF OBJECT_ID(N'dbo.HealthInsights', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.HealthInsights (
            Id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
            ElderProfileId NVARCHAR(50) NOT NULL,
            DeviceId NVARCHAR(50) NOT NULL,
            InsightType NVARCHAR(50) NOT NULL,
            WindowEndUtc DATETIME2 NOT NULL,
            ObservedValue FLOAT NOT NULL,
            BaselineValue FLOAT NOT NULL,
            PValue FLOAT NOT NULL,
            Description NVARCHAR(1000) NOT NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT FK_HealthInsights_Elder FOREIGN KEY (ElderProfileId)
                REFERENCES dbo.ElderProfiles(Id) ON DELETE CASCADE
        );
        CREATE UNIQUE INDEX UIX_HealthInsights_Window
            ON dbo.HealthInsights(ElderProfileId, DeviceId, InsightType, WindowEndUtc);
    END;

    IF OBJECT_ID(N'dbo.WeeklyHealthReports', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.WeeklyHealthReports (
            Id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
            ElderProfileId NVARCHAR(50) NOT NULL,
            WeekStartUtc DATETIME2 NOT NULL,
            WeekEndUtc DATETIME2 NOT NULL,
            Content NVARCHAR(MAX) NOT NULL,
            Source NVARCHAR(20) NOT NULL,
            CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT FK_WeeklyHealthReports_Elder FOREIGN KEY (ElderProfileId)
                REFERENCES dbo.ElderProfiles(Id) ON DELETE CASCADE
        );
        CREATE UNIQUE INDEX UIX_WeeklyHealthReports_Week ON dbo.WeeklyHealthReports(ElderProfileId, WeekEndUtc);
    END;

    IF OBJECT_ID(N'dbo.WeeklyReportNotifications', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.WeeklyReportNotifications (
            Id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
            WeeklyHealthReportId BIGINT NOT NULL,
            CaregiverPushTokenId NVARCHAR(50) NOT NULL,
            Status NVARCHAR(20) NOT NULL DEFAULT 'PENDING',
            RetryCount INT NOT NULL DEFAULT 0,
            NextAttemptUtc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            SentAt DATETIME2 NULL,
            RowVersion ROWVERSION NOT NULL,
            CONSTRAINT FK_WeeklyReportNotifications_Report FOREIGN KEY (WeeklyHealthReportId)
                REFERENCES dbo.WeeklyHealthReports(Id) ON DELETE CASCADE
        );
        CREATE UNIQUE INDEX UIX_WeeklyReportNotifications_Recipient
            ON dbo.WeeklyReportNotifications(WeeklyHealthReportId, CaregiverPushTokenId);
        CREATE INDEX IX_WeeklyReportNotifications_Status_NextAttemptUtc
            ON dbo.WeeklyReportNotifications(Status, NextAttemptUtc);
    END;

    -- 18. AdminUsers
    IF OBJECT_ID(N'dbo.AdminUsers', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.AdminUsers (
            Id NVARCHAR(36) NOT NULL CONSTRAINT PK_AdminUsers PRIMARY KEY,
            FullName NVARCHAR(100) NOT NULL,
            NormalizedEmail NVARCHAR(254) NOT NULL,
            PasswordHash NVARCHAR(256) NOT NULL,
            Role NVARCHAR(30) NOT NULL,
            IsActive BIT NOT NULL,
            SecurityVersion INT NOT NULL,
            FailedLoginAttempts INT NOT NULL,
            LockoutEndUtc DATETIME2 NULL,
            LastLoginAtUtc DATETIME2 NULL,
            RowVersion ROWVERSION NOT NULL,
            MfaEnabled BIT NOT NULL CONSTRAINT DF_AdminUsers_MfaEnabled DEFAULT 0,
            MfaSecretProtected NVARCHAR(2000) NULL,
            PendingMfaSecretProtected NVARCHAR(2000) NULL,
            LastTotpCounter BIGINT NOT NULL CONSTRAINT DF_AdminUsers_LastTotpCounter DEFAULT -1,
            CONSTRAINT CK_AdminUsers_Role CHECK (Role IN ('Owner','Operations','Support','Auditor'))
        );
        CREATE UNIQUE INDEX IX_AdminUsers_NormalizedEmail ON dbo.AdminUsers(NormalizedEmail);
    END;

    IF COL_LENGTH(N'dbo.AdminUsers',N'MfaEnabled') IS NULL
        ALTER TABLE dbo.AdminUsers ADD MfaEnabled BIT NOT NULL CONSTRAINT DF_AdminUsers_MfaEnabled DEFAULT 0;
    IF COL_LENGTH(N'dbo.AdminUsers',N'MfaSecretProtected') IS NULL
        ALTER TABLE dbo.AdminUsers ADD MfaSecretProtected NVARCHAR(2000) NULL;
    IF COL_LENGTH(N'dbo.AdminUsers',N'PendingMfaSecretProtected') IS NULL
        ALTER TABLE dbo.AdminUsers ADD PendingMfaSecretProtected NVARCHAR(2000) NULL;
    IF COL_LENGTH(N'dbo.AdminUsers',N'LastTotpCounter') IS NULL
        ALTER TABLE dbo.AdminUsers ADD LastTotpCounter BIGINT NOT NULL CONSTRAINT DF_AdminUsers_LastTotpCounter DEFAULT -1;

    -- 19. AdminSessions
    IF OBJECT_ID(N'dbo.AdminSessions', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.AdminSessions (
            Id NVARCHAR(36) NOT NULL CONSTRAINT PK_AdminSessions PRIMARY KEY,
            AdminUserId NVARCHAR(36) NOT NULL,
            SecurityVersion INT NOT NULL,
            CreatedAtUtc DATETIME2 NOT NULL,
            LastSeenAtUtc DATETIME2 NOT NULL,
            ExpiresAtUtc DATETIME2 NOT NULL,
            RevokedAtUtc DATETIME2 NULL,
            IsEnrollmentOnly BIT NOT NULL CONSTRAINT DF_AdminSessions_IsEnrollmentOnly DEFAULT 0,
            CONSTRAINT FK_AdminSessions_AdminUsers FOREIGN KEY(AdminUserId) REFERENCES dbo.AdminUsers(Id)
        );
        CREATE INDEX IX_AdminSessions_AdminUserId ON dbo.AdminSessions(AdminUserId);
        CREATE INDEX IX_AdminSessions_ExpiresAtUtc ON dbo.AdminSessions(ExpiresAtUtc);
    END;

    IF COL_LENGTH(N'dbo.AdminSessions',N'IsEnrollmentOnly') IS NULL
        ALTER TABLE dbo.AdminSessions ADD IsEnrollmentOnly BIT NOT NULL CONSTRAINT DF_AdminSessions_IsEnrollmentOnly DEFAULT 0;

    -- 20. AdminAuditEvents
    IF OBJECT_ID(N'dbo.AdminAuditEvents', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.AdminAuditEvents (
            Id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AdminAuditEvents PRIMARY KEY,
            ActorId NVARCHAR(36) NOT NULL,
            Action NVARCHAR(50) NOT NULL,
            TargetId NVARCHAR(50) NULL,
            Reason NVARCHAR(500) NOT NULL,
            Result NVARCHAR(20) NOT NULL,
            TraceId NVARCHAR(64) NOT NULL,
            OccurredAtUtc DATETIME2 NOT NULL,
            ChangesJson NVARCHAR(2000) NULL
        );
        CREATE INDEX IX_AdminAuditEvents_ActorId ON dbo.AdminAuditEvents(ActorId);
        CREATE INDEX IX_AdminAuditEvents_TargetId ON dbo.AdminAuditEvents(TargetId);
        CREATE INDEX IX_AdminAuditEvents_OccurredAtUtc ON dbo.AdminAuditEvents(OccurredAtUtc);
    END;

    IF COL_LENGTH(N'dbo.AdminAuditEvents',N'ChangesJson') IS NULL
        ALTER TABLE dbo.AdminAuditEvents ADD ChangesJson NVARCHAR(2000) NULL;

    -- 21. AdminCommandRecords
    IF OBJECT_ID(N'dbo.AdminCommandRecords', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.AdminCommandRecords (
            Id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AdminCommandRecords PRIMARY KEY,
            ActorId NVARCHAR(36) NOT NULL,
            RequestId NVARCHAR(36) NOT NULL,
            PayloadFingerprint NVARCHAR(64) NOT NULL,
            TargetId NVARCHAR(50) NOT NULL,
            ExecutedAtUtc DATETIME2 NOT NULL
        );
        CREATE UNIQUE INDEX IX_AdminCommandRecords_ActorId_RequestId ON dbo.AdminCommandRecords(ActorId, RequestId);
        CREATE INDEX IX_AdminCommandRecords_TargetId ON dbo.AdminCommandRecords(TargetId);
    END;

    -- 22. CaregiverAdminStates
    IF OBJECT_ID(N'dbo.CaregiverAdminStates', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.CaregiverAdminStates (
            CaregiverId NVARCHAR(50) NOT NULL PRIMARY KEY,
            IsSuspended BIT NOT NULL,
            SecurityVersion INT NOT NULL,
            Reason NVARCHAR(500) NOT NULL,
            UpdatedAtUtc DATETIME2 NOT NULL,
            RowVersion ROWVERSION NOT NULL
        );
    END;

    -- 23. CustomerFeedback
    IF OBJECT_ID(N'dbo.CustomerFeedback', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.CustomerFeedback (
            Id NVARCHAR(36) NOT NULL CONSTRAINT PK_CustomerFeedback PRIMARY KEY,
            CaregiverId NVARCHAR(50) NOT NULL,
            RequestId NVARCHAR(32) NOT NULL,
            Category NVARCHAR(20) NOT NULL,
            Subject NVARCHAR(120) NOT NULL,
            Message NVARCHAR(3000) NOT NULL,
            Status NVARCHAR(20) NOT NULL CONSTRAINT DF_CustomerFeedback_Status DEFAULT N'New',
            AdminReply NVARCHAR(3000) NULL,
            RepliedAtUtc DATETIME2 NULL,
            CreatedAtUtc DATETIME2 NOT NULL,
            CONSTRAINT FK_CustomerFeedback_Caregivers FOREIGN KEY(CaregiverId) REFERENCES dbo.Caregivers(Id),
            CONSTRAINT CK_CustomerFeedback_Category CHECK (Category IN ('Bug', 'Suggestion', 'Other'))
        );
        CREATE UNIQUE INDEX IX_CustomerFeedback_CaregiverId_RequestId ON dbo.CustomerFeedback(CaregiverId, RequestId);
        CREATE INDEX IX_CustomerFeedback_CaregiverId_CreatedAtUtc ON dbo.CustomerFeedback(CaregiverId, CreatedAtUtc);
        CREATE INDEX IX_CustomerFeedback_CreatedAtUtc ON dbo.CustomerFeedback(CreatedAtUtc);
    END;

    IF COL_LENGTH(N'dbo.CustomerFeedback',N'Status') IS NULL
        ALTER TABLE dbo.CustomerFeedback ADD Status NVARCHAR(20) NOT NULL CONSTRAINT DF_CustomerFeedback_Status DEFAULT N'New';
    IF COL_LENGTH(N'dbo.CustomerFeedback',N'AdminReply') IS NULL
        ALTER TABLE dbo.CustomerFeedback ADD AdminReply NVARCHAR(3000) NULL;
    IF COL_LENGTH(N'dbo.CustomerFeedback',N'RepliedAtUtc') IS NULL
        ALTER TABLE dbo.CustomerFeedback ADD RepliedAtUtc DATETIME2 NULL;

    -- 24. AdminWebTickets (Distributed SQL Server Session Cache)
    IF OBJECT_ID(N'dbo.AdminWebTickets', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.AdminWebTickets (
            Id NVARCHAR(449) COLLATE SQL_Latin1_General_CP1_CS_AS NOT NULL CONSTRAINT PK_AdminWebTickets PRIMARY KEY,
            Value VARBINARY(MAX) NOT NULL,
            ExpiresAtTime DATETIMEOFFSET NOT NULL,
            SlidingExpirationInSeconds BIGINT NULL,
            AbsoluteExpiration DATETIMEOFFSET NULL
        );
        CREATE INDEX Index_ExpiresAtTime ON dbo.AdminWebTickets(ExpiresAtTime);
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
