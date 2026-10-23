-- Apply manually to the explicitly selected CareAI database. Not run at startup.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF OBJECT_ID(N'dbo.CustomerFeedback', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CustomerFeedback (
        Id nvarchar(36) NOT NULL CONSTRAINT PK_CustomerFeedback PRIMARY KEY,
        CaregiverId nvarchar(50) NOT NULL,
        RequestId nvarchar(32) NOT NULL,
        Category nvarchar(20) NOT NULL,
        Subject nvarchar(120) NOT NULL,
        Message nvarchar(3000) NOT NULL,
        CreatedAtUtc datetime2 NOT NULL,
        CONSTRAINT FK_CustomerFeedback_Caregivers FOREIGN KEY(CaregiverId) REFERENCES dbo.Caregivers(Id),
        CONSTRAINT CK_CustomerFeedback_Category CHECK (Category IN ('Bug', 'Suggestion', 'Other'))
    );
    CREATE UNIQUE INDEX IX_CustomerFeedback_CaregiverId_RequestId ON dbo.CustomerFeedback(CaregiverId, RequestId);
    CREATE INDEX IX_CustomerFeedback_CaregiverId_CreatedAtUtc ON dbo.CustomerFeedback(CaregiverId, CreatedAtUtc);
    CREATE INDEX IX_CustomerFeedback_CreatedAtUtc ON dbo.CustomerFeedback(CreatedAtUtc);
END;
COMMIT TRANSACTION;
