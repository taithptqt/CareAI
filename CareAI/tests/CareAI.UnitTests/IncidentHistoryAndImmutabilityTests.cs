using System.Security.Claims;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit.Sdk;

namespace CareAI.UnitTests;

[Collection("SqlServerIntegration")]
public class IncidentHistoryAndImmutabilityTests
{
    private static CareAiDbContext CreateDb(string? name = null)
    {
        var options = new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(name ?? $"HistoryTests_{Guid.NewGuid():N}")
            .Options;
        return new CareAiDbContext(options);
    }

    private static IncidentsController CreateController(CareAiDbContext db, string? caregiverId)
    {
        var controller = new IncidentsController(db, new TelemetryEngine(db, NullLogger<TelemetryEngine>.Instance), NullLogger<IncidentsController>.Instance);
        var httpContext = new DefaultHttpContext();
        if (!string.IsNullOrEmpty(caregiverId))
        {
            var identity = new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, caregiverId)], "TestAuth");
            httpContext.User = new ClaimsPrincipal(identity);
        }
        controller.ControllerContext = new ControllerContext { HttpContext = httpContext };
        return controller;
    }

    [Fact]
    public async Task Bola_ElderIncidentHistory_RejectsUnauthorizedCaregiver()
    {
        await using var db = CreateDb();
        db.ElderProfiles.Add(new ElderProfile { Id = "elder-1", FullName = "Cụ Nguyễn Văn An" });
        db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = "ec-1",
            ElderProfileId = "elder-1",
            CaregiverId = "caregiver-authorized",
            IsActive = true
        });
        db.Incidents.Add(new Incident
        {
            Id = "inc-1",
            ElderProfileId = "elder-1",
            TriggeredByDeviceId = "dev-1",
            EmergencyType = "FALL",
            Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Resolved
        });
        await db.SaveChangesAsync();

        // 1. Không xác thực (Unauthenticated) -> 401
        var anonController = CreateController(db, null);
        var anonResult = await anonController.GetElderIncidentHistory("elder-1");
        Assert.IsType<UnauthorizedObjectResult>(anonResult);

        // 2. Người thân không được phân quyền (BOLA unauthorized) -> 403
        var strangerController = CreateController(db, "caregiver-stranger");
        var forbidResult = await strangerController.GetElderIncidentHistory("elder-1");
        var forbidObj = Assert.IsType<ObjectResult>(forbidResult);
        Assert.Equal(403, forbidObj.StatusCode);

        // 3. Người cao tuổi không tồn tại -> 404
        var authorizedController = CreateController(db, "caregiver-authorized");
        var notFoundResult = await authorizedController.GetElderIncidentHistory("non-existent-elder");
        Assert.IsType<NotFoundObjectResult>(notFoundResult);

        // 4. Người thân hợp lệ -> 200 OK
        var okResult = await authorizedController.GetElderIncidentHistory("elder-1");
        var okObj = Assert.IsType<OkObjectResult>(okResult);
        var paged = Assert.IsType<PagedResult<IncidentResponseDto>>(okObj.Value);
        Assert.Equal(1, paged.TotalCount);
        Assert.Single(paged.Items);
        Assert.Equal("inc-1", paged.Items[0].Id);
    }

    [Fact]
    public async Task PaginationAndFiltering_ReturnsStableOrderedPage_AndFiltersCorrectly()
    {
        await using var db = CreateDb();
        db.ElderProfiles.Add(new ElderProfile { Id = "elder-1", FullName = "Cụ An" });
        db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = "ec-1", ElderProfileId = "elder-1", CaregiverId = "cg-1", IsActive = true
        });

        var baseTime = new DateTime(2026, 9, 25, 10, 0, 0, DateTimeKind.Utc);

        // Seed 5 incidents với các đặc tính khác nhau
        db.Incidents.AddRange(
            new Incident
            {
                Id = "inc-1", ElderProfileId = "elder-1", TriggeredByDeviceId = "dev-1",
                EmergencyType = "FALL", Severity = IncidentSeverity.Critical, Status = IncidentStatus.Resolved,
                TriggeredAt = baseTime.AddMinutes(10)
            },
            new Incident
            {
                Id = "inc-2", ElderProfileId = "elder-1", TriggeredByDeviceId = "dev-1",
                EmergencyType = "MANUAL_SOS", Severity = IncidentSeverity.Critical, Status = IncidentStatus.Acknowledged,
                TriggeredAt = baseTime.AddMinutes(20)
            },
            new Incident
            {
                Id = "inc-3", ElderProfileId = "elder-1", TriggeredByDeviceId = "dev-1",
                EmergencyType = "TACHYCARDIA", Severity = IncidentSeverity.Critical, Status = IncidentStatus.Open,
                TriggeredAt = baseTime.AddMinutes(30)
            },
            new Incident
            {
                Id = "inc-4", ElderProfileId = "elder-1", TriggeredByDeviceId = "dev-1",
                EmergencyType = "FALL", Severity = IncidentSeverity.High, Status = IncidentStatus.Resolved,
                TriggeredAt = baseTime.AddMinutes(40)
            },
            new Incident
            {
                Id = "inc-5", ElderProfileId = "elder-1", TriggeredByDeviceId = "dev-1",
                EmergencyType = "FALL", Severity = IncidentSeverity.Critical, Status = IncidentStatus.Resolved,
                TriggeredAt = baseTime.AddMinutes(50)
            }
        );
        await db.SaveChangesAsync();

        var controller = CreateController(db, "cg-1");

        // Test phân trang: page 1, pageSize = 2 -> trả về inc-5, inc-4 (mới nhất trước)
        var p1Result = Assert.IsType<OkObjectResult>(await controller.GetElderIncidentHistory("elder-1", page: 1, pageSize: 2));
        var p1 = Assert.IsType<PagedResult<IncidentResponseDto>>(p1Result.Value);
        Assert.Equal(5, p1.TotalCount);
        Assert.Equal(3, p1.TotalPages);
        Assert.Equal(2, p1.Items.Count);
        Assert.Equal("inc-5", p1.Items[0].Id);
        Assert.Equal("inc-4", p1.Items[1].Id);

        // Test page 2 -> inc-3, inc-2
        var p2Result = Assert.IsType<OkObjectResult>(await controller.GetElderIncidentHistory("elder-1", page: 2, pageSize: 2));
        var p2 = Assert.IsType<PagedResult<IncidentResponseDto>>(p2Result.Value);
        Assert.Equal(2, p2.Items.Count);
        Assert.Equal("inc-3", p2.Items[0].Id);
        Assert.Equal("inc-2", p2.Items[1].Id);

        // Test Lọc theo EmergencyType = "FALL" (inc-5, inc-4, inc-1)
        var fallResult = Assert.IsType<OkObjectResult>(await controller.GetElderIncidentHistory("elder-1", emergencyType: "FALL"));
        var fallPaged = Assert.IsType<PagedResult<IncidentResponseDto>>(fallResult.Value);
        Assert.Equal(3, fallPaged.TotalCount);
        Assert.All(fallPaged.Items, i => Assert.Equal("FALL", i.EmergencyType));

        // Test Lọc theo Severity = "High" (chỉ inc-4)
        var warnResult = Assert.IsType<OkObjectResult>(await controller.GetElderIncidentHistory("elder-1", severity: "High"));
        var warnPaged = Assert.IsType<PagedResult<IncidentResponseDto>>(warnResult.Value);
        Assert.Single(warnPaged.Items);
        Assert.Equal("inc-4", warnPaged.Items[0].Id);

        // Test Lọc theo Status = "Resolved" (inc-5, inc-4, inc-1)
        var resolvedResult = Assert.IsType<OkObjectResult>(await controller.GetElderIncidentHistory("elder-1", status: "Resolved"));
        var resolvedPaged = Assert.IsType<PagedResult<IncidentResponseDto>>(resolvedResult.Value);
        Assert.Equal(3, resolvedPaged.TotalCount);

        // Test Lọc theo Khoảng thời gian UTC (từ phút 15 đến phút 35: inc-3, inc-2)
        var timeResult = Assert.IsType<OkObjectResult>(await controller.GetElderIncidentHistory(
            "elder-1",
            fromUtc: baseTime.AddMinutes(15),
            toUtc: baseTime.AddMinutes(35)));
        var timePaged = Assert.IsType<PagedResult<IncidentResponseDto>>(timeResult.Value);
        Assert.Equal(2, timePaged.TotalCount);
        Assert.Equal("inc-3", timePaged.Items[0].Id);
        Assert.Equal("inc-2", timePaged.Items[1].Id);
    }

    [Fact]
    public async Task IncidentDetail_ReturnsTimelineAndHeartRateSeries_Within15MinutesWindow()
    {
        await using var db = CreateDb();
        db.ElderProfiles.Add(new ElderProfile { Id = "elder-1", FullName = "Cụ An" });
        db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = "ec-1", ElderProfileId = "elder-1", CaregiverId = "cg-1", IsActive = true
        });

        var triggerTime = new DateTime(2026, 9, 25, 12, 0, 0, DateTimeKind.Utc);
        var incident = new Incident
        {
            Id = "inc-detail-1",
            ElderProfileId = "elder-1",
            TriggeredByDeviceId = "dev-1",
            EmergencyType = "FALL",
            Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Open,
            TriggeredAt = triggerTime
        };
        db.Incidents.Add(incident);

        db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            Id = "tl-1",
            IncidentId = "inc-detail-1",
            EventType = "TRIGGERED",
            Description = "Phát hiện ngã",
            RecordedAt = triggerTime
        });

        // Seed các mẫu nhịp tim quanh mốc T = 12:00:
        db.HealthMeasurements.AddRange(
            // T - 20m (11:40) -> NGOÀI cửa sổ (quá 15 phút trước)
            new HealthMeasurement { ElderProfileId = "elder-1", DeviceId = "dev-1", PacketId = "p-1", MetricType = "HEART_RATE", Value = 72, Unit = "bpm", Timestamp = triggerTime.AddMinutes(-20) },
            // T - 10m (11:50) -> TRONG cửa sổ
            new HealthMeasurement { ElderProfileId = "elder-1", DeviceId = "dev-1", PacketId = "p-2", MetricType = "HEART_RATE", Value = 78, Unit = "bpm", Timestamp = triggerTime.AddMinutes(-10) },
            // T - 1m (11:59) -> TRONG cửa sổ (tăng vọt)
            new HealthMeasurement { ElderProfileId = "elder-1", DeviceId = "dev-1", PacketId = "p-3", MetricType = "HEART_RATE", Value = 182, Unit = "bpm", Timestamp = triggerTime.AddMinutes(-1) },
            // T + 5m (12:05) -> TRONG cửa sổ
            new HealthMeasurement { ElderProfileId = "elder-1", DeviceId = "dev-1", PacketId = "p-4", MetricType = "HEART_RATE", Value = 160, Unit = "bpm", Timestamp = triggerTime.AddMinutes(5) },
            // T + 20m (12:20) -> NGOÀI cửa sổ (quá 15 phút sau)
            new HealthMeasurement { ElderProfileId = "elder-1", DeviceId = "dev-1", PacketId = "p-5", MetricType = "HEART_RATE", Value = 85, Unit = "bpm", Timestamp = triggerTime.AddMinutes(20) },
            // Mẫu của Cụ khác tại T -> Không được lọt vào
            new HealthMeasurement { ElderProfileId = "elder-other", DeviceId = "dev-2", PacketId = "p-6", MetricType = "HEART_RATE", Value = 100, Unit = "bpm", Timestamp = triggerTime },
            // Mẫu sinh hiệu khác (SPO2) -> Không được lọt vào
            new HealthMeasurement { ElderProfileId = "elder-1", DeviceId = "dev-1", PacketId = "p-7", MetricType = "SPO2", Value = 95, Unit = "%", Timestamp = triggerTime }
        );
        await db.SaveChangesAsync();

        var controller = CreateController(db, "cg-1");

        // 1. Gọi chi tiết qua GET /api/v1/incidents/{id}
        var detailResult = Assert.IsType<OkObjectResult>(await controller.GetIncident("inc-detail-1", CancellationToken.None));
        var detail = Assert.IsType<IncidentResponseDto>(detailResult.Value);

        Assert.Equal("inc-detail-1", detail.Id);
        Assert.Single(detail.Timeline);
        Assert.NotNull(detail.HeartRateSeries);
        Assert.Equal(triggerTime, detail.HeartRateSeries.IncidentTriggeredAt);
        Assert.Equal(triggerTime.AddMinutes(-15), detail.HeartRateSeries.WindowStartUtc);
        Assert.Equal(triggerTime.AddMinutes(15), detail.HeartRateSeries.WindowEndUtc);

        // Chỉ chứa đúng 3 mẫu hợp lệ nằm trong khoảng [T-15, T+15], sắp xếp tăng dần theo thời gian
        Assert.Equal(3, detail.HeartRateSeries.Samples.Count);
        Assert.Equal(78, detail.HeartRateSeries.Samples[0].Value);
        Assert.Equal(182, detail.HeartRateSeries.Samples[1].Value);
        Assert.Equal(160, detail.HeartRateSeries.Samples[2].Value);

        // 2. Gọi API chuyên biệt GET /api/v1/incidents/{id}/heart-rate-series
        var seriesResult = Assert.IsType<OkObjectResult>(await controller.GetIncidentHeartRateSeries("inc-detail-1", CancellationToken.None));
        var series = Assert.IsType<IncidentHeartRateWindowDto>(seriesResult.Value);
        Assert.Equal(3, series.Samples.Count);
        Assert.Equal(182, series.Samples[1].Value);
    }

    [Fact]
    public async Task Immutability_ResolvedIncident_CannotBeModifiedOrDeleted()
    {
        await using var db = CreateDb();
        var incident = new Incident
        {
            Id = "inc-resolved-1",
            ElderProfileId = "elder-1",
            TriggeredByDeviceId = "dev-1",
            EmergencyType = "FALL",
            Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Resolved,
            ResolutionNotes = "Đã xử lý xong",
            ResolvedAt = DateTime.UtcNow
        };
        db.Incidents.Add(incident);
        await db.SaveChangesAsync();

        // 1. Thử sửa Incident đã Resolved -> Ném ngoại lệ InvalidOperationException
        incident.EmergencyType = "TAMPERED_TYPE";
        var updateEx = await Assert.ThrowsAsync<InvalidOperationException>(() => db.SaveChangesAsync());
        Assert.Contains("Cannot update an already resolved incident", updateEx.Message);

        // Khôi phục change tracker
        db.ChangeTracker.Clear();

        // 2. Thử xóa Incident đã Resolved -> Ném ngoại lệ InvalidOperationException
        var toDelete = await db.Incidents.FirstAsync(i => i.Id == "inc-resolved-1");
        db.Incidents.Remove(toDelete);
        var deleteEx = await Assert.ThrowsAsync<InvalidOperationException>(() => db.SaveChangesAsync());
        Assert.Contains("Cannot delete a resolved incident", deleteEx.Message);

        // Khôi phục change tracker
        db.ChangeTracker.Clear();

        // 3. Nếu bật cờ ngoại lệ quản trị AllowAdminHistoricalOverride -> Cho phép thực hiện
        db.AllowAdminHistoricalOverride = true;
        var adminTarget = await db.Incidents.FirstAsync(i => i.Id == "inc-resolved-1");
        adminTarget.ResolutionNotes = "Ghi chú điều chỉnh bởi quản trị viên tuân thủ";
        await db.SaveChangesAsync(); // Thành công!
        Assert.Equal("Ghi chú điều chỉnh bởi quản trị viên tuân thủ", adminTarget.ResolutionNotes);
    }

    [Fact]
    public async Task Immutability_TimelineEvents_AreAppendOnly_CannotBeModifiedOrDeleted()
    {
        await using var db = CreateDb();
        var timelineEvent = new IncidentTimelineEvent
        {
            Id = "tl-immutable-1",
            IncidentId = "inc-1",
            EventType = "ACKNOWLEDGED",
            Description = "Người thân đã tiếp nhận",
            RecordedAt = DateTime.UtcNow
        };
        db.IncidentTimelineEvents.Add(timelineEvent);
        await db.SaveChangesAsync();

        // 1. Thử sửa TimelineEvent -> Throws
        timelineEvent.Description = "Sửa mô tả gian lận";
        var modEx = await Assert.ThrowsAsync<InvalidOperationException>(() => db.SaveChangesAsync());
        Assert.Contains("Incident timeline events are append-only and cannot be updated", modEx.Message);

        db.ChangeTracker.Clear();

        // 2. Thử xóa TimelineEvent -> Throws
        var toDelete = await db.IncidentTimelineEvents.FirstAsync(t => t.Id == "tl-immutable-1");
        db.IncidentTimelineEvents.Remove(toDelete);
        var delEx = await Assert.ThrowsAsync<InvalidOperationException>(() => db.SaveChangesAsync());
        Assert.Contains("Incident timeline events are append-only and cannot be deleted", delEx.Message);

        db.ChangeTracker.Clear();

        // 3. Ngoại lệ quản trị
        db.AllowAdminHistoricalOverride = true;
        var adminTarget = await db.IncidentTimelineEvents.FirstAsync(t => t.Id == "tl-immutable-1");
        adminTarget.Description = "Điều chỉnh hợp lệ bởi kiểm toán";
        await db.SaveChangesAsync();
        Assert.Equal("Điều chỉnh hợp lệ bởi kiểm toán", adminTarget.Description);
    }

    [Fact]
    public async Task Immutability_TransitioningToResolved_IsAllowed()
    {
        await using var db = CreateDb();
        var incident = new Incident
        {
            Id = "inc-open-to-resolve",
            ElderProfileId = "elder-1",
            TriggeredByDeviceId = "dev-1",
            EmergencyType = "MANUAL_SOS",
            Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Acknowledged
        };
        db.Incidents.Add(incident);
        await db.SaveChangesAsync();

        // Chuyển từ Acknowledged sang Resolved là luồng hợp pháp, phải thành công!
        incident.Status = IncidentStatus.Resolved;
        incident.ResolvedAt = DateTime.UtcNow;
        incident.ResolutionNotes = "Đã đến nhà hỗ trợ cụ";
        await db.SaveChangesAsync();

        Assert.Equal(IncidentStatus.Resolved, incident.Status);
    }

    [Fact]
    public async Task SqlServer_Triggers_RejectDirectSqlModificationsOnClosedHistory()
    {
        var configuredConnection = Environment.GetEnvironmentVariable("CAREAI_TEST_SQL_CONNECTION_STRING");
        if (string.IsNullOrWhiteSpace(configuredConnection))
            return;


        var databaseName = $"CareAI_Immutability_{Guid.NewGuid():N}";
        var master = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = "master" };
        var testDb = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = databaseName };

        await using (var conn = new SqlConnection(master.ConnectionString))
        {
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = $"CREATE DATABASE [{databaseName}];";
            cmd.CommandTimeout = 120;
            await cmd.ExecuteNonQueryAsync();
        }

        try
        {
            await DatabaseMigrationHelper.InitializeDatabaseAsync(testDb.ConnectionString);

            await using var conn = new SqlConnection(testDb.ConnectionString);
            await conn.OpenAsync();

            // Seed elder, incident resolved, timeline event qua direct SQL
            await using (var seedCmd = conn.CreateCommand())
            {
                seedCmd.CommandText = """
                INSERT INTO dbo.ElderProfiles (Id, FullName, DateOfBirth) VALUES ('elder-sql', 'Cụ SQL', '1945-01-01');
                INSERT INTO dbo.Incidents (Id, ElderProfileId, TriggeredByDeviceId, EmergencyType, Severity, Status, TriggeredAt, ResolutionNotes, ResolvedAt)
                VALUES ('inc-sql-1', 'elder-sql', 'dev-1', 'FALL', 2, 3, SYSUTCDATETIME(), 'Đã giải quyết', SYSUTCDATETIME());
                INSERT INTO dbo.IncidentTimelineEvents (Id, IncidentId, EventType, Description, RecordedAt)
                VALUES ('tl-sql-1', 'inc-sql-1', 'RESOLVED', 'Sự cố đã được giải quyết', SYSUTCDATETIME());
                INSERT INTO dbo.Incidents (Id, ElderProfileId, TriggeredByDeviceId, EmergencyType, Severity, Status, TriggeredAt, ResolutionNotes, ResolvedAt)
                VALUES ('inc-standalone', 'elder-sql', 'dev-1', 'MANUAL_SOS', 2, 3, SYSUTCDATETIME(), 'Đã giải quyết độc lập', SYSUTCDATETIME());
                """;
                await seedCmd.ExecuteNonQueryAsync();
            }

            // 1. Thử DELETE trực tiếp incident đã Resolved (không có timeline con) qua T-SQL -> Trigger phải chặn và ném SqlException
            await using (var deleteCmd = conn.CreateCommand())
            {
                deleteCmd.CommandText = "DELETE FROM dbo.Incidents WHERE Id = 'inc-standalone';";
                var ex = await Assert.ThrowsAsync<SqlException>(() => deleteCmd.ExecuteNonQueryAsync());
                Assert.Contains("Incident history is immutable", ex.Message);
            }

            // 2. Thử UPDATE trực tiếp incident đã Resolved qua T-SQL -> Trigger phải chặn
            await using (var updateCmd = conn.CreateCommand())
            {
                updateCmd.CommandText = "UPDATE dbo.Incidents SET EmergencyType = 'TAMPERED' WHERE Id = 'inc-sql-1';";
                var ex = await Assert.ThrowsAsync<SqlException>(() => updateCmd.ExecuteNonQueryAsync());
                Assert.Contains("Incident history is immutable", ex.Message);
            }

            // 3. Thử DELETE hoặc UPDATE timeline event qua T-SQL -> Trigger phải chặn
            await using (var timelineCmd = conn.CreateCommand())
            {
                timelineCmd.CommandText = "DELETE FROM dbo.IncidentTimelineEvents WHERE Id = 'tl-sql-1';";
                var ex = await Assert.ThrowsAsync<SqlException>(() => timelineCmd.ExecuteNonQueryAsync());
                Assert.Contains("Incident timeline events are append-only", ex.Message);
            }

            // 4. Kiểm tra SESSION_CONTEXT ngoại lệ quản trị
            await using (var adminCmd = conn.CreateCommand())
            {
                adminCmd.CommandText = """
                EXEC sp_set_session_context N'ALLOW_ADMIN_HISTORICAL_OVERRIDE', N'TRUE';
                UPDATE dbo.Incidents SET ResolutionNotes = 'Ghi chú cập nhật qua override hợp pháp' WHERE Id = 'inc-sql-1';
                """;
                await adminCmd.ExecuteNonQueryAsync();
            }

            // 5. Kiểm tra bỏ cascade delete: Xóa Incident khi còn TimelineEvents con -> SQL Server từ chối do FK NO ACTION
            await using (var incDeleteCmd = conn.CreateCommand())
            {
                incDeleteCmd.CommandText = "DELETE FROM dbo.Incidents WHERE Id = 'inc-sql-1';";
                var ex = await Assert.ThrowsAsync<SqlException>(() => incDeleteCmd.ExecuteNonQueryAsync());
                // Vi phạm FK_Timeline_Incident
                Assert.Contains("REFERENCE constraint", ex.Message);
            }

            // 6. Kiểm tra bỏ cascade delete: Xóa Elder khi còn Incident có status = 3 -> SQL Server từ chối do FK NO ACTION
            await using (var elderDeleteCmd = conn.CreateCommand())
            {
                elderDeleteCmd.CommandText = "DELETE FROM dbo.ElderProfiles WHERE Id = 'elder-sql';";
                var ex = await Assert.ThrowsAsync<SqlException>(() => elderDeleteCmd.ExecuteNonQueryAsync());
                // Vi phạm FK_Incidents_Elder
                Assert.Contains("REFERENCE constraint", ex.Message);
            }

            // 7. Ảnh đã nhận là chứng cứ bất biến kể cả khi có kết nối SQL trực tiếp.
            await using (var photoCmd = conn.CreateCommand())
            {
                photoCmd.CommandText = """
                INSERT INTO dbo.IncidentPhotos (IncidentId, DeviceId, JpegBytes, Sha256, CapturedAt, ReceivedAt)
                VALUES ('inc-sql-1', 'dev-1', 0xFFD8FFD9, REPLICATE('a', 64), SYSUTCDATETIME(), SYSUTCDATETIME());
                """;
                await photoCmd.ExecuteNonQueryAsync();
                photoCmd.CommandText = "UPDATE dbo.IncidentPhotos SET Sha256 = REPLICATE('b', 64) WHERE IncidentId = 'inc-sql-1';";
                var changed = await Assert.ThrowsAsync<SqlException>(() => photoCmd.ExecuteNonQueryAsync());
                Assert.Contains("Incident photos are append-only", changed.Message);
                photoCmd.CommandText = "DELETE FROM dbo.IncidentPhotos WHERE IncidentId = 'inc-sql-1';";
                var deleted = await Assert.ThrowsAsync<SqlException>(() => photoCmd.ExecuteNonQueryAsync());
                Assert.Contains("Incident photos are append-only", deleted.Message);
            }
        }
        finally
        {
            SqlConnection.ClearAllPools();
            await using var conn = new SqlConnection(master.ConnectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = $"IF DB_ID('{databaseName}') IS NOT NULL BEGIN ALTER DATABASE [{databaseName}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{databaseName}]; END;";
            cmd.CommandTimeout = 120;
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
