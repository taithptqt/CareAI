-- Seed demo data for CareAI Caregiver App demonstration
USE CareAiDb;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

-- Cho phép quyền ghi đè quản trị để cập nhật dữ liệu demo
EXEC sp_set_session_context N'ALLOW_ADMIN_HISTORICAL_OVERRIDE', N'TRUE';

-- 1. Caregiver
DECLARE @CaregiverId NVARCHAR(50) = 'a0e27e16-27ca-40e5-a235-385df5c28c77';
IF NOT EXISTS (SELECT 1 FROM Caregivers WHERE Id = @CaregiverId OR Email = 'con@careai.vn')
BEGIN
    INSERT INTO Caregivers (Id, FullName, Email, PasswordHash, PhoneNumber, CreatedAt)
    VALUES (@CaregiverId, N'Nguyễn Văn Con', 'con@careai.vn', 'AQAAAAIAAYagAAAAEO9...dummy', '0987654321', SYSUTCDATETIME());
END
ELSE
BEGIN
    UPDATE Caregivers 
    SET FullName = N'Nguyễn Văn Con' 
    WHERE Email = 'con@careai.vn';
END;

-- 2. Elder Profile
DECLARE @ElderId NVARCHAR(50) = 'elder_demo_an_01';
IF NOT EXISTS (SELECT 1 FROM ElderProfiles WHERE Id = @ElderId)
BEGIN
    INSERT INTO ElderProfiles (Id, FullName, DateOfBirth, MedicalNotes, EmergencyContact, HomeAddress, CreatedAt, UpdatedAt)
    VALUES (@ElderId, N'Cụ Nguyễn Văn An', '1944-05-12', N'Tiền sử cao huyết áp, rối loạn nhịp tim', '0901234567', N'128 Đường Hai Bà Trưng, Quận 1, TP.HCM', SYSUTCDATETIME(), SYSUTCDATETIME());
END
ELSE
BEGIN
    UPDATE ElderProfiles 
    SET FullName = N'Cụ Nguyễn Văn An',
        MedicalNotes = N'Tiền sử cao huyết áp, rối loạn nhịp tim',
        HomeAddress = N'128 Đường Hai Bà Trưng, Quận 1, TP.HCM'
    WHERE Id = @ElderId;
END;

-- 3. Elder - Caregiver Mapping
IF NOT EXISTS (SELECT 1 FROM ElderCaregivers WHERE CaregiverId = @CaregiverId AND ElderProfileId = @ElderId)
BEGIN
    INSERT INTO ElderCaregivers (Id, CaregiverId, ElderProfileId, Role, IsActive, AssignedAt)
    VALUES (NEWID(), @CaregiverId, @ElderId, 1, 1, SYSUTCDATETIME()); -- Role 1: Primary
END;

-- 4. Device Registration
DECLARE @DeviceId NVARCHAR(50) = 'DEV_DEMO_WATCH_01';
IF NOT EXISTS (SELECT 1 FROM DeviceRegistrations WHERE Id = @DeviceId)
BEGIN
    INSERT INTO DeviceRegistrations (Id, ElderProfileId, DeviceType, DeviceTokenHash, FirmwareVersion, IsActive, LastHeartbeat, RegisteredAt, CreatedAt, UpdatedAt)
    VALUES (@DeviceId, @ElderId, 'Smartwatch', 'dummy_hash', '1.0.0', 1, SYSUTCDATETIME(), SYSUTCDATETIME(), SYSUTCDATETIME(), SYSUTCDATETIME());
END;

-- 5. Resolved Incident with Heart Rate Spike (Task 8 & 9)
DECLARE @ResolvedIncidentId NVARCHAR(50) = 'incident_demo_hr_resolved';
DECLARE @T DATETIME2 = DATEADD(minute, -30, SYSUTCDATETIME());

IF NOT EXISTS (SELECT 1 FROM Incidents WHERE Id = @ResolvedIncidentId)
BEGIN
    INSERT INTO Incidents (
        Id, ElderProfileId, TriggeredByDeviceId, EmergencyType, Severity, [Status],
        TriggeredAt, HeartRateBpm, SpO2Percent, GpsLocation, HomeAddressSnapshot,
        AlertCycleNumber, AcknowledgedAt, AcknowledgedByCaregiverId,
        ResolvedAt, ResolvedByCaregiverId, ResolutionNotes,
        CreatedAt, UpdatedAt
    )
    VALUES (
        @ResolvedIncidentId, @ElderId, @DeviceId, 'CRITICAL_HEART_RATE', 2, 3, -- Severity 2: Critical, Status 3: Resolved
        @T, 185.0, 92.0, '10.7769,106.7009', N'128 Đường Hai Bà Trưng, Quận 1, TP.HCM',
        1, DATEADD(minute, 1, @T), @CaregiverId,
        DATEADD(minute, 15, @T), @CaregiverId, N'Đã cho cụ uống thuốc hạ áp theo đơn bác sĩ, nghỉ ngơi tại giường, nhịp tim đã trở về mức ổn định 76 bpm.',
        @T, DATEADD(minute, 15, @T)
    );
END
ELSE
BEGIN
    UPDATE Incidents
    SET HomeAddressSnapshot = N'128 Đường Hai Bà Trưng, Quận 1, TP.HCM',
        ResolutionNotes = N'Đã cho cụ uống thuốc hạ áp theo đơn bác sĩ, nghỉ ngơi tại giường, nhịp tim đã trở về mức ổn định 76 bpm.'
    WHERE Id = @ResolvedIncidentId;
END;

-- Timeline events cho incident resolved
DELETE FROM IncidentTimelineEvents WHERE IncidentId = @ResolvedIncidentId;

INSERT INTO IncidentTimelineEvents (Id, IncidentId, EventType, Description, RecordedAt, ActorCaregiverId, AlertCycleNumber)
VALUES 
(NEWID(), @ResolvedIncidentId, 'INCIDENT_OPENED', N'Phát hiện nhịp tim nguy kịch 185 bpm (Vượt ngưỡng an toàn 180 bpm)', @T, NULL, 1),
(NEWID(), @ResolvedIncidentId, 'INCIDENT_ACKNOWLEDGED', N'Người thân Nguyễn Văn Con đã tiếp nhận xử lý sự cố', DATEADD(minute, 1, @T), @CaregiverId, 1),
(NEWID(), @ResolvedIncidentId, 'INCIDENT_RESOLVED', N'Đã giải quyết sự cố. Ghi chú: Đã cho cụ uống thuốc hạ áp theo đơn bác sĩ, nhịp tim ổn định 76 bpm.', DATEADD(minute, 15, @T), @CaregiverId, 1);

-- Health Measurements around T (T-15m to T+15m) for the Heart Rate Chart
DELETE FROM HealthMeasurements WHERE ElderProfileId = @ElderId;

INSERT INTO HealthMeasurements (ElderProfileId, DeviceId, PacketId, MetricType, Value, Unit, [Timestamp], RecordedAt)
VALUES
(@ElderId, @DeviceId, 'PKT_HR_1', 'HEART_RATE', 78.0, 'bpm', DATEADD(minute, -15, @T), DATEADD(minute, -15, @T)),
(@ElderId, @DeviceId, 'PKT_HR_2', 'HEART_RATE', 82.0, 'bpm', DATEADD(minute, -10, @T), DATEADD(minute, -10, @T)),
(@ElderId, @DeviceId, 'PKT_HR_3', 'HEART_RATE', 115.0, 'bpm', DATEADD(minute, -5, @T), DATEADD(minute, -5, @T)),
(@ElderId, @DeviceId, 'PKT_HR_4', 'HEART_RATE', 185.0, 'bpm', @T, @T),
(@ElderId, @DeviceId, 'PKT_HR_5', 'HEART_RATE', 152.0, 'bpm', DATEADD(minute, 5, @T), DATEADD(minute, 5, @T)),
(@ElderId, @DeviceId, 'PKT_HR_6', 'HEART_RATE', 98.0, 'bpm', DATEADD(minute, 10, @T), DATEADD(minute, 10, @T)),
(@ElderId, @DeviceId, 'PKT_HR_7', 'HEART_RATE', 76.0, 'bpm', DATEADD(minute, 15, @T), DATEADD(minute, 15, @T));

-- 6. Active Open Incident (Té ngã khẩn cấp để trải nghiệm còi và ACK)
DECLARE @OpenIncidentId NVARCHAR(50) = 'incident_demo_fall_open';
DECLARE @Now DATETIME2 = SYSUTCDATETIME();

IF NOT EXISTS (SELECT 1 FROM Incidents WHERE Id = @OpenIncidentId)
BEGIN
    INSERT INTO Incidents (
        Id, ElderProfileId, TriggeredByDeviceId, EmergencyType, Severity, [Status],
        TriggeredAt, HeartRateBpm, SpO2Percent, GpsLocation, HomeAddressSnapshot,
        AlertCycleNumber, AlertStartedAt, AlertDeadlineAt,
        CreatedAt, UpdatedAt
    )
    VALUES (
        @OpenIncidentId, @ElderId, @DeviceId, 'HARDWARE_FALL_DETECTED', 2, 1, -- Status 1: Open, Severity 2: Critical
        @Now, 122.0, 95.0, '10.7769,106.7009', N'128 Đường Hai Bà Trưng, Quận 1, TP.HCM',
        1, @Now, DATEADD(second, 60, @Now),
        @Now, @Now
    );
END
ELSE
BEGIN
    UPDATE Incidents
    SET [Status] = 1, -- Đưa về Open
        AcknowledgedAt = NULL,
        AcknowledgedByCaregiverId = NULL,
        ResolvedAt = NULL,
        ResolvedByCaregiverId = NULL,
        ResolutionNotes = NULL,
        AlertStartedAt = @Now,
        AlertDeadlineAt = DATEADD(second, 60, @Now),
        HomeAddressSnapshot = N'128 Đường Hai Bà Trưng, Quận 1, TP.HCM',
        UpdatedAt = @Now
    WHERE Id = @OpenIncidentId;
END;

DELETE FROM IncidentTimelineEvents WHERE IncidentId = @OpenIncidentId;

INSERT INTO IncidentTimelineEvents (Id, IncidentId, EventType, Description, RecordedAt, ActorCaregiverId, AlertCycleNumber)
VALUES 
(NEWID(), @OpenIncidentId, 'INCIDENT_OPENED', N'Phát hiện ngã phần cứng từ đồng hồ thông minh (Impact: 3.8G). Cảnh báo khẩn cấp đang kích hoạt!', @Now, NULL, 1);

-- Tắt quyền ghi đè quản trị
EXEC sp_set_session_context N'ALLOW_ADMIN_HISTORICAL_OVERRIDE', N'FALSE';

PRINT 'SEEDED DEMO DATA SUCCESSFULLY WITH UNICODE';
GO
