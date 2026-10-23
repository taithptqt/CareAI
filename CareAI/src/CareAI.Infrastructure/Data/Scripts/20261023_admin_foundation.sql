-- REVIEW/APPLY MANUALLY against the explicitly selected database.
-- This script is not called by DatabaseMigrationHelper or application startup.
-- Additive schema only. Does not modify caregiver/device/incident data.
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.AdminUsers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminUsers (
        Id nvarchar(36) NOT NULL CONSTRAINT PK_AdminUsers PRIMARY KEY,
        FullName nvarchar(100) NOT NULL,
        NormalizedEmail nvarchar(254) NOT NULL,
        PasswordHash nvarchar(256) NOT NULL,
        Role nvarchar(30) NOT NULL,
        IsActive bit NOT NULL,
        SecurityVersion int NOT NULL,
        FailedLoginAttempts int NOT NULL,
        LockoutEndUtc datetime2 NULL,
        LastLoginAtUtc datetime2 NULL,
        RowVersion rowversion NOT NULL,
        CONSTRAINT CK_AdminUsers_Role CHECK (Role IN ('Owner','Operations','Support','Auditor'))
    );
    CREATE UNIQUE INDEX IX_AdminUsers_NormalizedEmail ON dbo.AdminUsers(NormalizedEmail);
END;

IF OBJECT_ID(N'dbo.AdminSessions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminSessions (
        Id nvarchar(36) NOT NULL CONSTRAINT PK_AdminSessions PRIMARY KEY,
        AdminUserId nvarchar(36) NOT NULL,
        SecurityVersion int NOT NULL,
        CreatedAtUtc datetime2 NOT NULL,
        LastSeenAtUtc datetime2 NOT NULL,
        ExpiresAtUtc datetime2 NOT NULL,
        RevokedAtUtc datetime2 NULL,
        CONSTRAINT FK_AdminSessions_AdminUsers FOREIGN KEY(AdminUserId) REFERENCES dbo.AdminUsers(Id)
    );
    CREATE INDEX IX_AdminSessions_AdminUserId ON dbo.AdminSessions(AdminUserId);
    CREATE INDEX IX_AdminSessions_ExpiresAtUtc ON dbo.AdminSessions(ExpiresAtUtc);
END;

IF OBJECT_ID(N'dbo.AdminAuditEvents', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminAuditEvents (
        Id nvarchar(36) NOT NULL CONSTRAINT PK_AdminAuditEvents PRIMARY KEY,
        ActorId nvarchar(36) NOT NULL,
        Action nvarchar(80) NOT NULL,
        TargetId nvarchar(100) NOT NULL,
        Result nvarchar(30) NOT NULL,
        Reason nvarchar(500) NOT NULL,
        TraceId nvarchar(128) NOT NULL,
        OccurredAtUtc datetime2 NOT NULL
    );
    CREATE INDEX IX_AdminAuditEvents_OccurredAtUtc ON dbo.AdminAuditEvents(OccurredAtUtc);
END;

-- Standard Microsoft.Extensions.Caching.SqlServer schema. It may instead be
-- created in a separate session-store database, using just this block.
IF OBJECT_ID(N'dbo.AdminWebTickets', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminWebTickets (
        Id nvarchar(449) COLLATE SQL_Latin1_General_CP1_CS_AS NOT NULL CONSTRAINT PK_AdminWebTickets PRIMARY KEY,
        Value varbinary(max) NOT NULL,
        ExpiresAtTime datetimeoffset NOT NULL,
        SlidingExpirationInSeconds bigint NULL,
        AbsoluteExpiration datetimeoffset NULL
    );
    CREATE INDEX Index_ExpiresAtTime ON dbo.AdminWebTickets(ExpiresAtTime);
END;

COMMIT TRANSACTION;
GO
CREATE OR ALTER TRIGGER dbo.TR_AdminAuditEvents_AppendOnly ON dbo.AdminAuditEvents
INSTEAD OF UPDATE, DELETE AS
BEGIN
    THROW 51001, 'Admin audit events are append-only.', 1;
END;
GO
