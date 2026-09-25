using System.Collections.Concurrent;
using System.Security.Claims;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using CareAI.Infrastructure.Notifications;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Xunit.Sdk;

namespace CareAI.UnitTests;

[Collection("SqlServerIntegration")]
public class Part2EndToEndIntegrationTests
{
    private sealed class E2eFakeSender : IPushSender
    {
        public ConcurrentBag<string> SentOutboxIds { get; } = new();

        public Task<PushSendResult> SendAsync(NotificationOutbox item, CancellationToken ct)
        {
            SentOutboxIds.Add(item.Id);
            return Task.FromResult(new PushSendResult(PushSendDisposition.Accepted, MessageId: $"fcm-msg-{Guid.NewGuid():N}"));
        }
    }

    [Fact]
    public async Task SqlServer_FullLifecycle_Quorum_OCC_Reescalation_SLA_Immutability_And_FilteredIndex()
    {
        var configuredConnection = Environment.GetEnvironmentVariable("CAREAI_TEST_SQL_CONNECTION_STRING");
        if (string.IsNullOrWhiteSpace(configuredConnection))
            throw SkipException.ForSkip("Set CAREAI_TEST_SQL_CONNECTION_STRING to run the SQL Server end-to-end integration test.");

        var databaseName = $"CareAI_E2E_{Guid.NewGuid():N}";
        var master = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = "master" };
        var testDb = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = databaseName };

        // 1. Tạo database độc lập trên SQL Server LocalDB
        await using (var connection = new SqlConnection(master.ConnectionString))
        {
            await connection.OpenAsync();
            await using var create = connection.CreateCommand();
            create.CommandText = $"CREATE DATABASE [{databaseName}]";
            create.CommandTimeout = 120;
            await create.ExecuteNonQueryAsync();
        }

        try
        {
            // 2. Khởi tạo schema DDL, indexes, và triggers chống can thiệp lịch sử
            await DatabaseMigrationHelper.InitializeDatabaseAsync(testDb.ConnectionString);

            const string elderId = "elder_e2e_01";
            const string deviceId = "device_e2e_01";
            const string cgWinnerId = "cg_winner";
            const string cgLoserId = "cg_loser";

            // 3. Khởi tạo dữ liệu người cao tuổi, 2 người thân liên kết (Quorum) và thiết bị
            await using (var seedDb = CreateContext(testDb.ConnectionString))
            {
                var elder = new ElderProfile
                {
                    Id = elderId,
                    FullName = "Cụ Hoàng Văn Thọ",
                    DateOfBirth = new DateTime(1942, 5, 12),
                    EmergencyContact = "0912345678",
                    HomeAddress = "100 Trần Hưng Đạo, Hoàn Kiếm, Hà Nội"
                };
                seedDb.ElderProfiles.Add(elder);

                var device = new DeviceRegistration
                {
                    Id = deviceId,
                    ElderProfileId = elderId,
                    DeviceTokenHash = "testhash",
                    DeviceType = "WearOS_Watch",
                    FirmwareVersion = "2.1.0",
                    LastHeartbeat = DateTime.UtcNow
                };
                seedDb.DeviceRegistrations.Add(device);

                var cg1 = new Caregiver
                {
                    Id = cgWinnerId,
                    FullName = "Người Thân 1",
                    PhoneNumber = "0901111111",
                    Email = "winner@careai.vn",
                    PasswordHash = "hashed_pw_1"
                };
                var cg2 = new Caregiver
                {
                    Id = cgLoserId,
                    FullName = "Người Thân 2",
                    PhoneNumber = "0902222222",
                    Email = "loser@careai.vn",
                    PasswordHash = "hashed_pw_2"
                };
                seedDb.Caregivers.AddRange(cg1, cg2);

                seedDb.ElderCaregivers.AddRange(
                    new ElderCaregiver { Id = "link_1", ElderProfileId = elderId, CaregiverId = cgWinnerId, IsActive = true },
                    new ElderCaregiver { Id = "link_2", ElderProfileId = elderId, CaregiverId = cgLoserId, IsActive = true }
                );

                seedDb.CaregiverPushTokens.AddRange(
                    new CaregiverPushToken { Id = "token_1", CaregiverId = cgWinnerId, PushToken = "fcm_token_1", IsActive = true },
                    new CaregiverPushToken { Id = "token_2", CaregiverId = cgLoserId, PushToken = "fcm_token_2", IsActive = true }
                );

                await seedDb.SaveChangesAsync();
            }

            string incidentId;
            string initialRowVersionBase64;

            // -------------------------------------------------------------
            // BƯỚC 1: LUỒNG 1 - QUORUM ALERTING & PHÁT HIỆN SỰ CỐ NGUY KỊCH
            // -------------------------------------------------------------
            await using (var db = CreateContext(testDb.ConnectionString))
            {
                var engine = new ClinicalDiagnosticEngine(db, NullLogger<ClinicalDiagnosticEngine>.Instance);
                var incident = await engine.EvaluateHeartRateSampleAsync(elderId, deviceId, 185.0);

                Assert.NotNull(incident);
                Assert.Equal(IncidentSeverity.Critical, incident.Severity);
                Assert.Equal(IncidentStatus.Open, incident.Status);
                Assert.Equal(1, incident.AlertCycleNumber);
                Assert.Equal(0, incident.ReminderCount);

                incidentId = incident.Id;
                Assert.NotNull(incident.RowVersion);
                initialRowVersionBase64 = Convert.ToBase64String(incident.RowVersion);

                // Xác minh Quorum: Tạo Outbox cho CẢ 2 người thân liên kết
                var outboxes = await db.NotificationOutboxes.Where(n => n.IncidentId == incidentId).ToListAsync();
                Assert.Equal(2, outboxes.Count);
                Assert.Contains(outboxes, n => n.RecipientCaregiverId == cgWinnerId);
                Assert.Contains(outboxes, n => n.RecipientCaregiverId == cgLoserId);

                // Dispatch qua NotificationDispatchEngine
                var fakeSender = new E2eFakeSender();
                var dispatcher = new NotificationDispatchEngine(
                    db,
                    fakeSender,
                    NullLogger<NotificationDispatchEngine>.Instance);

                await dispatcher.DispatchDueAsync(DateTime.UtcNow);
                Assert.Equal(2, fakeSender.SentOutboxIds.Count);

                var dispatched = await db.NotificationOutboxes.Where(n => n.IncidentId == incidentId).ToListAsync();
                Assert.All(dispatched, n => Assert.Equal("SENT", n.Status));
            }

            // -------------------------------------------------------------
            // BƯỚC 2: LUỒNG 2 - OPTIMISTIC CONCURRENCY CONTROL (OCC)
            // -------------------------------------------------------------
            // Hai người thân đồng thời tiếp nhận sự cố với cùng RowVersion ban đầu.
            // Kết quả bắt buộc: đúng 1 người thắng (200 OK), 1 người xung đột (409 Conflict).
            await using (var dbWinner = CreateContext(testDb.ConnectionString))
            await using (var dbLoser = CreateContext(testDb.ConnectionString))
            {
                var ctrlWinner = CreateController(dbWinner, cgWinnerId);
                var ctrlLoser = CreateController(dbLoser, cgLoserId);

                var taskWinner = ctrlWinner.AcknowledgeIncident(
                    incidentId,
                    new AcknowledgeIncidentRequest("Đang tới nhà cụ", initialRowVersionBase64),
                    CancellationToken.None);

                var taskLoser = ctrlLoser.AcknowledgeIncident(
                    incidentId,
                    new AcknowledgeIncidentRequest("Tôi đang gần đó sẽ qua", initialRowVersionBase64),
                    CancellationToken.None);

                var results = await Task.WhenAll(taskWinner, taskLoser);
                var okResult = results.OfType<OkObjectResult>().SingleOrDefault();
                var conflictResult = results.OfType<ConflictObjectResult>().SingleOrDefault();

                Assert.NotNull(okResult);
                Assert.NotNull(conflictResult);

                // Người thua nhận 409 Conflict có thông tin người đã tiếp nhận trước
                Assert.Equal(409, conflictResult.StatusCode);
            }

            // Kiểm tra trạng thái sự cố sau ACK
            string ackedRowVersionBase64;
            await using (var db = CreateContext(testDb.ConnectionString))
            {
                var inc = await db.Incidents.Include(i => i.TimelineEvents).SingleAsync(i => i.Id == incidentId);
                Assert.Equal(IncidentStatus.Acknowledged, inc.Status);
                Assert.NotNull(inc.AcknowledgedAt);
                Assert.Contains(inc.TimelineEvents, t => t.EventType == "ACKNOWLEDGED");

                Assert.NotNull(inc.RowVersion);
                ackedRowVersionBase64 = Convert.ToBase64String(inc.RowVersion);
                Assert.NotEqual(initialRowVersionBase64, ackedRowVersionBase64); // RowVersion đã thay đổi
            }

            // -------------------------------------------------------------
            // BƯỚC 3: KIỂM TRA BỘ ĐẾM SLA - KHÔNG NHẮC LẠI KHI ĐÃ ĐƯỢC ACK
            // -------------------------------------------------------------
            await using (var db = CreateContext(testDb.ConnectionString))
            {
                var slaEngine = new AlertSlaEngine(
                    db,
                    Options.Create(new AlertingOptions { ReminderIntervalSeconds = 60, MaxReminders = 3 }),
                    NullLogger<AlertSlaEngine>.Instance);

                // Quét SLA tại mốc 75s sau kích hoạt
                var futureUtc = DateTime.UtcNow.AddSeconds(75);
                await slaEngine.CheckDueAsync(futureUtc);

                var inc = await db.Incidents.SingleAsync(i => i.Id == incidentId);
                Assert.Equal(0, inc.ReminderCount); // Không bị tăng reminder vì đã ACK
                Assert.DoesNotContain(db.IncidentTimelineEvents, t => t.IncidentId == incidentId && t.EventType == "SLA_BREACHED");
            }

            // -------------------------------------------------------------
            // BƯỚC 4: LUỒNG 3 - RE-ESCALATION (TÁI MỞ KHI BỆNH TRẠNG XẤU ĐI)
            // -------------------------------------------------------------
            // Sau khi ACK, cụ tiếp tục có mẫu nhịp tim nguy kịch xấu đi (195 bpm)
            await using (var db = CreateContext(testDb.ConnectionString))
            {
                var engine = new ClinicalDiagnosticEngine(db, NullLogger<ClinicalDiagnosticEngine>.Instance);
                var reescalatedIncident = await engine.EvaluateHeartRateSampleAsync(elderId, deviceId, 195.0);

                Assert.NotNull(reescalatedIncident);
                Assert.Equal(incidentId, reescalatedIncident.Id); // Cùng sự cố đang xử lý
                Assert.Equal(IncidentStatus.Open, reescalatedIncident.Status); // Tái mở về Open
                Assert.Equal(2, reescalatedIncident.AlertCycleNumber); // Lên chu kỳ 2

                // Kiểm tra timeline giữ nguyên lịch sử ACK trước đó và thêm mốc RE_ESCALATED
                var timeline = await db.IncidentTimelineEvents
                    .Where(t => t.IncidentId == incidentId)
                    .OrderBy(t => t.RecordedAt)
                    .ToListAsync();

                Assert.Contains(timeline, t => t.EventType == "ACKNOWLEDGED");
                Assert.Contains(timeline, t => t.EventType == "CLINICAL_REESCALATION");

                // Outbox chu kỳ 2 được tạo cho 2 caregivers
                var cycle2Outbox = await db.NotificationOutboxes
                    .Where(n => n.IncidentId == incidentId && n.AlertCycleNumber == 2)
                    .ToListAsync();
                Assert.Equal(2, cycle2Outbox.Count);
            }

            // -------------------------------------------------------------
            // BƯỚC 5: VI PHẠM SLA CHU KỲ 2 KHI QUÁ 60 GIÂY CHƯA AI ACK
            // -------------------------------------------------------------
            await using (var db = CreateContext(testDb.ConnectionString))
            {
                var slaEngine = new AlertSlaEngine(
                    db,
                    Options.Create(new AlertingOptions { ReminderIntervalSeconds = 60, MaxReminders = 3 }),
                    NullLogger<AlertSlaEngine>.Instance);

                // Quét SLA ở chu kỳ 2 tại thời điểm vượt 65 giây
                var cycle2BreachTime = DateTime.UtcNow.AddSeconds(65);
                await slaEngine.CheckDueAsync(cycle2BreachTime);

                var inc = await db.Incidents.SingleAsync(i => i.Id == incidentId);
                Assert.Equal(1, inc.ReminderCount); // Đã ghi nhận 1 lần nhắc nhở

                var timeline = await db.IncidentTimelineEvents.Where(t => t.IncidentId == incidentId).ToListAsync();
                Assert.Contains(timeline, t => t.EventType == "SLA_BREACHED");
            }

            // -------------------------------------------------------------
            // BƯỚC 6: ACK CHU KỲ 2 VÀ GIẢI QUYẾT AN TOÀN (RESOLVE)
            // -------------------------------------------------------------
            await using (var db = CreateContext(testDb.ConnectionString))
            {
                var inc = await db.Incidents.SingleAsync(i => i.Id == incidentId);
                Assert.NotNull(inc.RowVersion);
                var currentVersion = Convert.ToBase64String(inc.RowVersion);

                // Caregiver 2 tiếp nhận chu kỳ 2
                var ctrlLoser = CreateController(db, cgLoserId);
                var ackRes = await ctrlLoser.AcknowledgeIncident(
                    incidentId,
                    new AcknowledgeIncidentRequest("Người thân 2 đã có mặt tại nhà", currentVersion),
                    CancellationToken.None);
                Assert.IsType<OkObjectResult>(ackRes);

                // Cập nhật lại phiên bản sau khi ACK chu kỳ 2
                await db.Entry(inc).ReloadAsync();
                Assert.NotNull(inc.RowVersion);
                currentVersion = Convert.ToBase64String(inc.RowVersion);

                // Thử resolve với ghi chú rỗng -> Bắt buộc bị từ chối 400 Bad Request
                var emptyNotesRes = await ctrlLoser.ResolveIncident(
                    incidentId,
                    new ResolveIncidentRequest("   ", currentVersion),
                    CancellationToken.None);
                Assert.IsType<BadRequestObjectResult>(emptyNotesRes);

                // Thử resolve với RowVersion cũ -> Bị từ chối 409 Conflict
                var staleVersionRes = await ctrlLoser.ResolveIncident(
                    incidentId,
                    new ResolveIncidentRequest("Đã ổn định", initialRowVersionBase64),
                    CancellationToken.None);
                Assert.IsType<ConflictObjectResult>(staleVersionRes);

                // Resolve hợp lệ với ghi chú lâm sàng đầy đủ
                var resolveRes = await ctrlLoser.ResolveIncident(
                    incidentId,
                    new ResolveIncidentRequest("Cụ đã ngồi nghỉ, uống thuốc, nhịp tim đo lại 76 bpm ổn định.", currentVersion),
                    CancellationToken.None);
                Assert.IsType<OkObjectResult>(resolveRes);

                await db.Entry(inc).ReloadAsync();
                Assert.Equal(IncidentStatus.Resolved, inc.Status);
                Assert.NotNull(inc.ResolvedAt);
                Assert.Equal(cgLoserId, inc.ResolvedByCaregiverId);
                Assert.Equal("Cụ đã ngồi nghỉ, uống thuốc, nhịp tim đo lại 76 bpm ổn định.", inc.ResolutionNotes);
            }

            // -------------------------------------------------------------
            // BƯỚC 7: TÍNH BẤT BIẾN - TRIGGER CSDL SQL SERVER CHẶN SỬA/XÓA
            // -------------------------------------------------------------
            await using (var connection = new SqlConnection(testDb.ConnectionString))
            {
                await connection.OpenAsync();

                // 7.1 Cấm UPDATE trực tiếp vào incident đã Resolved
                await using (var cmd = connection.CreateCommand())
                {
                    cmd.CommandText = $"UPDATE Incidents SET EmergencyType = 'TAMPERED' WHERE Id = '{incidentId}'";
                    var ex = await Assert.ThrowsAsync<SqlException>(() => cmd.ExecuteNonQueryAsync());
                    Assert.Contains("immutable", ex.Message, StringComparison.OrdinalIgnoreCase);
                }

                // 7.2 Cấm UPDATE/DELETE trực tiếp vào bảng IncidentTimelineEvents (Append-only)
                await using (var cmd = connection.CreateCommand())
                {
                    cmd.CommandText = $"UPDATE IncidentTimelineEvents SET Description = 'TAMPERED' WHERE IncidentId = '{incidentId}'";
                    var ex = await Assert.ThrowsAsync<SqlException>(() => cmd.ExecuteNonQueryAsync());
                    Assert.Contains("append-only", ex.Message, StringComparison.OrdinalIgnoreCase);
                }

                // 7.3 Cấm DELETE trực tiếp incident đã Resolved
                await using (var cmd = connection.CreateCommand())
                {
                    cmd.CommandText = $"DELETE FROM Incidents WHERE Id = '{incidentId}'";
                    await Assert.ThrowsAsync<SqlException>(() => cmd.ExecuteNonQueryAsync());
                }
            }

            // -------------------------------------------------------------
            // BƯỚC 8: FILTERED UNIQUE INDEX UIX_Incidents_SingleActiveElder
            // -------------------------------------------------------------
            // Vì sự cố thứ nhất đã Resolved (Status = 3), hệ thống PHẢI cho phép tạo sự cố mới
            // cho cụ đó mà không bị xung đột chỉ mục lọc [Status] IN (1, 2)
            await using (var db = CreateContext(testDb.ConnectionString))
            {
                var newIncident = new Incident
                {
                    Id = "incident_fall_new_02",
                    ElderProfileId = elderId,
                    TriggeredByDeviceId = deviceId,
                    EmergencyType = "FALL",
                    Severity = IncidentSeverity.Critical,
                    Status = IncidentStatus.Open,
                    TriggeredAt = DateTime.UtcNow,
                    AlertCycleNumber = 1
                };

                db.Incidents.Add(newIncident);
                await db.SaveChangesAsync(); // Thành công, không bị lỗi UIX_Incidents_SingleActiveElder

                // Xác minh trong DB có 2 incidents: 1 Resolved, 1 Open
                var allIncidents = await db.Incidents.Where(i => i.ElderProfileId == elderId).ToListAsync();
                Assert.Equal(2, allIncidents.Count);
                Assert.Single(allIncidents, i => i.Status == IncidentStatus.Resolved);
                Assert.Single(allIncidents, i => i.Status == IncidentStatus.Open);

                // Thử tạo một sự cố thứ 3 cũng Open/Acknowledged -> Bắt buộc bị SQL Server chặn bởi Filtered Index
                var thirdIncident = new Incident
                {
                    Id = "incident_fall_conflict_03",
                    ElderProfileId = elderId,
                    TriggeredByDeviceId = deviceId,
                    EmergencyType = "MANUAL_SOS",
                    Severity = IncidentSeverity.Critical,
                    Status = IncidentStatus.Open,
                    TriggeredAt = DateTime.UtcNow,
                    AlertCycleNumber = 1
                };
                db.Incidents.Add(thirdIncident);
                var dbEx = await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
                Assert.Contains("UIX_Incidents_SingleActiveElder", dbEx.InnerException?.Message ?? "");
            }
        }
        finally
        {
            // Dọn dẹp database thử nghiệm trên LocalDB
            try
            {
                await using var connection = new SqlConnection(master.ConnectionString);
                await connection.OpenAsync();
                await using var drop = connection.CreateCommand();
                drop.CommandText = $@"
                    ALTER DATABASE [{databaseName}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                    DROP DATABASE [{databaseName}];";
                drop.CommandTimeout = 120;
                await drop.ExecuteNonQueryAsync();
            }
            catch { /* Bỏ qua lỗi xóa nếu đã dọn dẹp */ }
        }
    }

    private static CareAiDbContext CreateContext(string connectionString)
    {
        var options = new DbContextOptionsBuilder<CareAiDbContext>()
            .UseSqlServer(connectionString)
            .Options;
        return new CareAiDbContext(options);
    }

    private static IncidentsController CreateController(CareAiDbContext db, string caregiverId)
    {
        var controller = new IncidentsController(
            db,
            new TelemetryEngine(db, NullLogger<TelemetryEngine>.Instance),
            NullLogger<IncidentsController>.Instance);

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(
                [
                    new Claim(ClaimTypes.NameIdentifier, caregiverId),
                    new Claim("role", "Caregiver")
                ], "TestAuth"))
            }
        };
        return controller;
    }
}
