SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF COL_LENGTH(N'dbo.AdminSessions',N'IsEnrollmentOnly') IS NULL
    ALTER TABLE dbo.AdminSessions ADD IsEnrollmentOnly bit NOT NULL CONSTRAINT DF_AdminSessions_IsEnrollmentOnly DEFAULT 0;
IF COL_LENGTH(N'dbo.AdminUsers',N'MfaEnabled') IS NULL
    ALTER TABLE dbo.AdminUsers ADD MfaEnabled bit NOT NULL CONSTRAINT DF_AdminUsers_MfaEnabled DEFAULT 0;
IF COL_LENGTH(N'dbo.AdminUsers',N'MfaSecretProtected') IS NULL
    ALTER TABLE dbo.AdminUsers ADD MfaSecretProtected nvarchar(2000) NULL;
IF COL_LENGTH(N'dbo.AdminUsers',N'PendingMfaSecretProtected') IS NULL
    ALTER TABLE dbo.AdminUsers ADD PendingMfaSecretProtected nvarchar(2000) NULL;
IF COL_LENGTH(N'dbo.AdminUsers',N'LastTotpCounter') IS NULL
    ALTER TABLE dbo.AdminUsers ADD LastTotpCounter bigint NOT NULL CONSTRAINT DF_AdminUsers_LastTotpCounter DEFAULT -1;
IF COL_LENGTH(N'dbo.AdminAuditEvents',N'ChangesJson') IS NULL
    ALTER TABLE dbo.AdminAuditEvents ADD ChangesJson nvarchar(2000) NULL;
IF OBJECT_ID(N'dbo.CaregiverAdminStates', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CaregiverAdminStates (
        CaregiverId nvarchar(50) NOT NULL PRIMARY KEY,
        IsSuspended bit NOT NULL,
        SecurityVersion int NOT NULL,
        Reason nvarchar(500) NOT NULL,
        UpdatedAtUtc datetime2 NOT NULL,
        RowVersion rowversion NOT NULL
    );
END;
IF OBJECT_ID(N'dbo.AdminCommandRecords', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminCommandRecords (
        Id nvarchar(36) NOT NULL PRIMARY KEY,
        ActorId nvarchar(36) NOT NULL,
        RequestId nvarchar(36) NOT NULL,
        PayloadFingerprint nvarchar(64) NOT NULL,
        TargetId nvarchar(100) NOT NULL,
        CreatedAtUtc datetime2 NOT NULL
    );
    CREATE UNIQUE INDEX IX_AdminCommandRecords_ActorId_RequestId ON dbo.AdminCommandRecords(ActorId,RequestId);
END;
IF COL_LENGTH(N'dbo.CustomerFeedback',N'Status') IS NULL
    ALTER TABLE dbo.CustomerFeedback ADD Status nvarchar(20) NOT NULL CONSTRAINT DF_CustomerFeedback_Status DEFAULT N'New';
IF COL_LENGTH(N'dbo.CustomerFeedback',N'AdminReply') IS NULL
    ALTER TABLE dbo.CustomerFeedback ADD AdminReply nvarchar(3000) NULL;
IF COL_LENGTH(N'dbo.CustomerFeedback',N'RepliedAtUtc') IS NULL
    ALTER TABLE dbo.CustomerFeedback ADD RepliedAtUtc datetime2 NULL;
COMMIT TRANSACTION;
