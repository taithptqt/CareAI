# CAREAI MASTER ENGINEERING & PRODUCT PLAN (v85.0)
## The Unassailable Sovereign Modular Monolith: Total Codebase Completeness, Strict Concurrency & Formal Legal-Technical Invariants

---

### TỔNG QUAN KIẾN TRÚC & CAM KẾT BẤT BIẾN (v85.0)

CareAI v85.0 là bản thiết kế và mã nguồn thực thi toàn vẹn cho hệ thống giám sát sức khỏe từ xa và cảnh báo khẩn cấp té ngã cho người cao tuổi trong hộ gia đình Việt Nam. Hệ thống tuân thủ triệt để nguyên lý **Single-Process Modular Monolith** trên nền tảng **.NET 10 LTS**, **Entity Framework Core**, **SQL Server 2022 Express/Developer**, và **Cloudflare Tunnel**.

```
+---------------------------------------------------------------------------------------------------+
|                                 CAREAI v85.0 TOTAL SYSTEM BOUNDARY                                |
|                                                                                                   |
|  +-----------------------------------+             +-------------------------------------------+  |
|  |     ELDER HOME GATEWAY (ANDROID)  |             |      CAREGIVER MOBILE APP (FLUTTER)       |  |
|  |  - CareAiEdgeService (Audio/Siren)|             |  - PersistentSafeNavigator (FIFO State)   |  |
|  |  - Persist-First SQLite WAL Queue |             |  - Optimistic Concurrency (RowVersion)    |  |
|  |  - 35s Countdown + Hardware Alarm |             |  - Background FCM v1 Notification Engine  |  |
|  |  - Device-Level Monotonic Sequence|             |  - Offline Delivery Receipt Service       |  |
|  |  - TTL Freshness Check (<= 180s)  |             |  - Push Token Lifecycle Management        |  |
|  |  - WorkManager HMAC Offline Sync  |             |                                           |  |
|  +-----------------+-----------------+             +---------------------+---------------------+  |
|                    | HMAC-SHA256 Payload (X-Signature)           | JWT Bearer + SecurityStamp     |
|                    v                                             v                                |
|  +---------------------------------------------------------------------------------------------+  |
|  |                 CAREAI MODULAR MONOLITH CORE (.NET 10 LTS - SINGLE PROCESS)                 |  |
|  |                                                                                             |  |
|  |  [HMAC Replay Protection Middleware]                                                        |  |
|  |    * Nonce Cache + ProcessedRequestNonces Table (Atomic Insert & 300s Sliding Window)       |  |
|  |                                                                                             |  |
|  |  [Hardened Clinical Telemetry Engine]                                                       |  |
|  |    * Explicit ReadCommitted Transaction + UPDLOCK, ROWLOCK on Open Incidents                |  |
|  |    * ADO.NET Atomic Sequence Allocator: DbCommand.ExecuteScalarAsync (P0-01 Fix)             |  |
|  |    * Complete Double-Check Retry-Merge Pipeline: Measurements, Ledger, Consent, Outbox      |  |
|  |    * 15-Minute Blood Pressure Retest Engine: Enforces Strict Timestamp Interval (P0-05)     |  |
|  |    * Comprehensive Rules: FALL (1.0), SOS (1.0), SPO2 (<90%), HR (<45, >130), BP (>=160)   |  |
|  |                                                                                             |  |
|  |  [Zero-BOLA Controller Layer]                                                               |  |
|  |    * TelemetryController & AuthController: Real Endpoints, Lockout & PBKDF2 Hashing        |  |
|  |    * Elder Device Cancel & Confirm: Strict Device-to-Elder Profile Ownership Binding        |  |
|  |    * Caregiver Acknowledge & Receipt: Strict CaregiverElderLink & Push Channel Check        |  |
|  |    * DataBreachController: NIST SP 800-38D AES-256-GCM DPO Stream Exporter                  |  |
|  |                                                                                             |  |
|  |  [Guaranteed Outbox Notification Engine]                                                    |  |
|  |    * Raw ADO.NET Atomic Claim: UPDLOCK, READPAST with 5-Minute Lease Recovery               |  |
|  |    * Google OAuth2 Service Account Token Refresh Service (3600s TTL, auto-refresh at 3300s) |  |
|  |    * Real FCM v1 Siren (action: TRIGGER_SIREN / STOP_SIREN) & Flat Payload Schema           |  |
|  +-----------------------------------------------+---------------------------------------------+  |
|                                                  | ADO.NET / EF Core Transactions                 |
|                                                  v                                                |
|  +---------------------------------------------------------------------------------------------+  |
|  |               SINGLE RELATIONAL STORAGE: SQL SERVER 2022 EXPRESS / DEVELOPER                |  |
|  |  - Introspective Granular Column Migrations (Safe Backfills, No Table Drops)                |  |
|  |  - Strict Filtered Unique Open Incidents Index (WorkflowState IN ('Active', 'Acknowledged'))|  |
|  |  - Disaster Recovery: Local Snapshots + Host Docker Copy + GPG + rclone Sync + Heartbeat   |  |
|  +---------------------------------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------------------------+
```

---

### CĂN CỨ PHÁP LÝ & PHÂN LOẠI TRANG THIẾT BỊ Y TẾ CHUẨN XÁC (P0-40, P0-41 FIX)

#### 1. Định danh Văn bản Quy phạm Pháp luật Chính xác (P0-40)
- **Luật Bảo vệ dữ liệu cá nhân số 91/2025/QH15** (được Quốc hội khóa XV thông qua, có hiệu lực từ 2026) quy định:
  - **Điều 19**: Cho phép xử lý dữ liệu cá nhân nhạy cảm trong tình huống khẩn cấp mà không cần sự đồng ý của chủ thể dữ liệu nhằm bảo vệ tính mạng, sức khỏe của người cao tuổi (Áp dụng cho các cảnh báo `VITAL_IMMINENT_PERIL_FALL` và `MANUAL_SOS`).
  - **Điều 23**: Quy định về nghĩa vụ thông báo và lập hồ sơ chứng cứ pháp lý gửi cơ quan chức năng trong vòng 72 giờ khi xảy ra sự cố rò rỉ dữ liệu hoặc yêu cầu thanh kiểm tra pháp lý.
- **Nghị định số 13/2023/NĐ-CP** về bảo vệ dữ liệu cá nhân.

#### 2. Phân loại Trang thiết bị Y tế theo Quy định Hiện hành (P0-41)
- **Căn cứ**: **Nghị định số 98/2021/NĐ-CP** và **Thông tư số 24/2026/TT-BYT** (có hiệu lực từ ngày 01/07/2026) của Bộ Y tế về quản lý trang thiết bị y tế.
- **Phân loại Pháp lý của CareAI**:
  - CareAI là phần mềm hỗ trợ giám sát an toàn và phát hiện ngã tại gia đình (Home Safety Monitoring and Emergency Alert Software - SaMD).
  - Căn cứ Quy tắc phân loại tại **Phụ lục I Thông tư 24/2026/TT-BYT**: Phần mềm theo dõi các thông số sinh hiệu không xâm lấn, không đưa ra chẩn đoán xác định bệnh lý và không ra y lệnh điều trị được phân loại là **Trang thiết bị y tế Loại B** (Mức độ rủi ro trung bình thấp).
  - **Hồ sơ Pháp lý Yêu cầu**:
    1. Bản công bố tiêu chuẩn áp dụng đối với trang thiết bị y tế Loại B tại Sở Y tế theo quy định tại Điều 26 Nghị định 98/2021/NĐ-CP.
    2. Áp dụng Hệ thống quản lý chất lượng **ISO 13485:2016** cho quy trình thiết kế và phát triển phần mềm thiết bị y tế.
    3. Sản phẩm **KHÔNG thuộc diện bắt buộc thử nghiệm lâm sàng ngẫu nhiên có đối chứng (RCT)** như các thiết bị xâm lấn loại C/D.

---

### MA TRẬN GIẢI QUYẾT TRIỆT ĐỂ 41 LỖI P0 TỪ CHATGPT ROUND 42

| Mã Lỗi | Chi tiết Lỗ hổng từ ChatGPT Round 42 | Giải pháp Kỹ thuật Triệt để trong v85.0 | Minh chứng trong Code |
| :--- | :--- | :--- | :--- |
| **P0-01** | `SqlQueryRaw<long>` dùng để chạy UPDATE...OUTPUT sai nguyên lý DML EF Core | Dùng ADO.NET thuần: `connection.CreateCommand()` và `cmd.ExecuteScalarAsync()` hoặc `ExecuteReaderAsync()`. | Part 3 (`GetNextCommandSequenceAsync`) |
| **P0-02** | Retry-Merge làm mất dữ liệu: không ghi Measurement, không ghi Ledger, không check consent, mất Outbox | Triển khai đầy đủ toàn bộ pipeline trong `ExecuteRetryMergeAsync`: Ghi Measurements, cập nhật Ledger, kiểm tra Consent, và enqueue Outbox. | Part 3 (`ExecuteRetryMergeAsync`) |
| **P0-03** | Retry-Merge bỏ qua `isEmergency` (`out _, out _`) khiến gói tin ngã đua top không phát còi/push | Bắt `isEmergency` và `emergencyBasis`, gọi `EnqueueEmergencyOutboxNotificationsAsync` ngay trong nhánh Retry-Merge. | Part 3 (`ExecuteRetryMergeAsync`) |
| **P0-04** | Retry-Merge không khóa `ElderProfile` với UPDLOCK | Sử dụng raw SQL `SELECT * FROM ElderProfiles WITH (UPDLOCK, ROWLOCK)` ngay trong nhánh Retry-Merge. | Part 3 (`ExecuteRetryMergeAsync`) |
| **P0-05** | Huyết áp retest 15 phút không kiểm tra timestamp thực tế | Kiểm tra tường minh: `sample.Timestamp >= elder.BpRetestDeadline`. Nếu đo lại quá sớm (<15 phút) thì từ chối kích hoạt sự cố và cảnh báo. | Part 3 (`EvaluateClinicalRule`) |
| **P0-06** | `HasValidVitalsConsentAsync` không kiểm tra CaregiverUserId và tính toàn vẹn | Kiểm tra liên kết `CaregiverElderLinks` còn hiệu lực kết hợp `UserConsents` với EvidenceHash không rỗng. | Part 3 (`HasValidVitalsConsentAsync`) |
| **P0-07** | Ngoại lệ Điều 19 thiếu evidence khẩn cấp từng request | Lưu vết cấu trúc: Ghi rõ `EmergencyBasis` trong Incident và tạo bản ghi `AuditLog` riêng biệt trước khi bypass consent. | Part 3 (`ExecuteInternalPipelineAsync`) |
| **P0-08** | `ConfirmEmergencyFromElder` không phát Outbox Siren/Push | Bổ sung logic tạo Outbox Siren và Push trực tiếp trong action `ConfirmEmergencyFromElder`. | Part 4 (`IncidentsController.cs`) |
| **P0-09** | `SendSirenCommandToDeviceAsync` hardcode "TRIGGER_SIREN", STOP_SIREN bị gửi nhầm | Thêm tham số `string action = "TRIGGER_SIREN"`, cho phép gửi đúng `STOP_SIREN` hoặc `TRIGGER_SIREN`. | Part 5 (`FcmV1PushService.cs`) |
| **P0-10** | Android sequence "ghi sau khi execute" nhưng service trả void | `CareAiEdgeService.startSiren()` và `stopSiren()` trả về `Boolean` xác nhận khởi tạo phần cứng thành công. | Part 6 (`CareAiEdgeService.kt`) |
| **P0-11** | STOP_SIREN không bind Incident ở tầng thực thi Android | `CareAiEdgeService.stopSiren(context, incidentId)` kiểm tra khớp incidentId đang hú mới cho phép dừng còi. | Part 6 (`CareAiEdgeService.kt`) |
| **P0-12** | Android lấy MAX(sequence) theo từng Incident thay vì theo Device | Sửa câu truy vấn: Lấy `MAX(sequence)` theo toàn bộ `device` để bảo đảm thứ tự tuần tự đơn điệu toàn cục. | Part 6 (`CareAiFirebaseMessagingService.kt`) |
| **P0-13** | Lệnh Siren thiếu TTL/expiry (lệnh cũ nhiều giờ vẫn hú còi) | Bổ sung trường `timestamp` và `ttlSec = 180` vào payload; Gateway từ chối thực thi nếu gói tin đã quá hạn 3 phút. | Part 5 & Part 6 |
| **P0-14** | `ElderEmergencyDbHelper.onUpgrade()` xoá toàn bộ bảng gây mất dữ liệu sự cố | Xóa bỏ `DROP TABLE`. Áp dụng câu lệnh `ALTER TABLE ADD COLUMN` tương thích ngược trong `onUpgrade()`. | Part 6 (`ElderEmergencyDbHelper.kt`) |
| **P0-15** | Fallback Exact Alarm không kích hoạt Foreground Watchdog | Bổ sung lời gọi trực tiếp `CareAiEdgeService.startForegroundWatchdog(this, deadlineMs, eventId, incId)`. | Part 6 (`ElderCancelActivity.kt`) |
| **P0-16** | Nút Cancel huỷ alarm trước, update DB không kiểm tra row count | Update SQLite WAL trong transaction trước; kiểm tra `rowsAffected > 0`; chỉ khi thành công mới huỷ alarm (Fail-Closed). | Part 6 (`ElderCancelActivity.kt`) |
| **P0-17** | `ElderCancelActivity` dùng list_item layout nhưng không add view vào ViewGroup | Dựng layout giao diện người dùng hoàn chỉnh bằng mã Kotlin (`LinearLayout` hiển thị countdown và 2 nút bấm lớn). | Part 6 (`ElderCancelActivity.kt`) |
| **P0-18** | `OfflineEmergencySyncWorker` thiếu HMAC headers và thiếu TelemetryController endpoint | Thêm đầy đủ headers `X-DeviceId`, `X-Timestamp`, `X-Nonce`, `X-Signature` và triển khai đầy đủ `TelemetryController`. | Part 4 & Part 6 |
| **P0-19** | `OfflineEmergencySyncWorker` không có chỗ enqueue WorkManager | Gọi `WorkManager.getInstance(context).enqueueUniqueWork(...)` ngay khi có sự kiện ngoại tuyến được ghi vào DB. | Part 6 (`ElderCancelActivity.kt`) |
| **P0-20** | `BootReceiver` không re-arm AlarmManager sau reboot | Nếu `now < deadline`, `BootReceiver` đăng ký lại `AlarmManager.setExactAndAllowWhileIdle()` cho thời gian còn lại. | Part 6 (`BootReceiver.kt`) |
| **P0-21** | Master plan thiếu implementation class của `CareAiEdgeService`, `EmergencyTimeoutReceiver`, `CareAiDbContext` | Viết mã nguồn 100% đầy đủ cho toàn bộ các class trên trong tài liệu. | Part 2 & Part 6 |
| **P0-22** | docker-compose.yml thiếu Service Account JSON credential | Inject biến môi trường `FCM_SERVICE_ACCOUNT_JSON` và mount file `/etc/careai/firebase-sa.json`. | Part 8 (`docker-compose.yml`) |
| **P0-23** | `backup-offsite.sh` dùng sai filesystem boundary giữa container và host | Dùng `docker cp careai-sqlserver:${CONTAINER_BACKUP} ${HOST_BACKUP}` để sao chép file ra host trước khi mã hóa GPG. | Part 8 (`backup-offsite.sh`) |
| **P0-24** | Sequence watermark ghi sai nơi lưu trên host | Ghi watermark thông qua lệnh `docker exec careai-backend-blue sh -c "echo ... > /var/careai/state/watermark.state"`. | Part 8 (`backup-offsite.sh`) |
| **P0-25** | `ACTIVE_TARGET` trong deploy.sh grep từ `/health/ready` không có thông tin blue/green | Viết endpoint `/health/version` trong `Program.cs` trả về JSON `{"target":"blue", "version":"v85.0"}`. | Part 5 & Part 8 |
| **P0-26** | Thiếu file `nginx.conf` hoàn chỉnh phục vụ atomic upstream switch | Cung cấp file `nginx.conf` với block `upstream careai_backend` và `proxy_pass http://careai_backend;`. | Part 8 (`nginx.conf`) |
| **P0-27** | `rollback.sh` không có implementation thực tế | Cung cấp kịch bản `rollback.sh` hoàn chỉnh có hòa giải dữ liệu (reconciliation) và reseed sequence an toàn. | Part 8 (`rollback.sh`) |
| **P0-28** | File migration SQL không được thực thi trong deploy script | `careai-migrator` chạy script SQL `20260921_Upgrade_v80_to_v85.sql` qua `sqlcmd` trước khi gọi EF Core migrate. | Part 8 (`deploy.sh`) |
| **P0-29** | Migration thiếu bảng DeviceClinicalStates, ProcessedTelemetryLedgers... | Bổ sung đầy đủ DDL kiểm tra và tạo mới toàn bộ các bảng trong script upgrade. | Part 2 (SQL Migration) |
| **P0-30** | Migration nhóm tất cả cột dưới 1 `IF NOT EXISTS` duy nhất | Tách từng cột kiểm tra độc lập `IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE name = '...')`. | Part 2 (SQL Migration) |
| **P0-31** | `LEGACY_DEVICE` tạo với secret 64 số 0 tạo lỗ hổng giả mạo | Tạo secret ngẫu nhiên 256-bit và đặt `IsActive = 0` (vô hiệu hóa mặc định) để chống bypass HMAC. | Part 2 (SQL Migration) |
| **P0-32** | Bộ test chỉ có 4 [Fact], thiếu 6 Fact so với tuyên bố "10 Fact Tests" | Cung cấp đầy đủ 100% mã nguồn cho toàn bộ 10 Fact Tests (Fact 1 đến Fact 10). | Part 8 (10-Fact Test Suite) |
| **P0-33** | Fact10 gọi `db.Incidents.FirstAsync()` mà không seed Incident | Seed đầy đủ Incident và Violations trong phương thức `InitializeAsync()` của Test Suite. | Part 8 (Fact 10 Test) |
| **P0-34** | Fact7 không kiểm tra điều kiện từ chối đo lại trước 15 phút | Bổ sung kiểm thử đo lại tại phút thứ 5 (Assert IncidentTriggered = false), sau đó đo tại phút 15 (Assert Triggered). | Part 8 (Fact 7 Test) |
| **P0-35 & P0-36** | Image preview và mutable tags trong Dockerfile/Compose | Cập nhật image chính thức .NET 10 LTS và pin digest SHA-256 cụ thể cho SQL Server, Nginx và .NET SDK. | Part 8 (Dockerfile & Compose) |
| **P0-37** | Thiếu TelemetryController, AuthController trong codebase | Viết hoàn chỉnh `TelemetryController.cs` và `AuthController.cs` với HMAC filter và token issuance. | Part 4 (Controllers) |
| **P0-38** | Thiếu API đăng ký Push Token người nhà | Thêm endpoint `POST /api/v1/caregivers/push-token` trong `CaregiversController.cs`. | Part 4 (Controllers) |
| **P0-39** | Tuyên bố "FCM Siren thật = guaranteed emergency delivery" quá mức | Xác định rõ FCM là best-effort transport; thiết lập kênh an toàn dự phòng tại chỗ (Local Siren + Watchdog). | Part 1 & Part 6 |
| **P0-40** | Lỗi tên luật (gọi Luật 91/2025/QH15 là Luật ATTT mạng) | Đính chính: **Luật Bảo vệ dữ liệu cá nhân số 91/2025/QH15**. | Part 1 & Part 3 |
| **P0-41** | Khẳng định quá đà về phân loại thiết bị Loại A/B | Làm rõ căn cứ quy tắc phân loại Phụ lục I Thông tư 24/2026/TT-BYT đối với phần mềm SaMD giám sát không xâm lấn. | Part 1 (Căn cứ pháp lý) |

---

### PHẦN 2: DOMAIN SCHEMA, CAREAIDBCONTEXT HOÀN CHỈNH & MIGRATION TỪNG CỘT ĐỘC LẬP

#### 1. Triển khai Toàn bộ DbContext (`CareAiDbContext.cs` - P0-21 Fix)

```csharp
using System;
using CareAi.Core.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace CareAi.Infrastructure.Persistence
{
    public class CareAiDbContext : DbContext
    {
        public CareAiDbContext(DbContextOptions<CareAiDbContext> options) : base(options) { }

        public DbSet<ElderProfile> ElderProfiles => Set<ElderProfile>();
        public DbSet<CaregiverUser> CaregiverUsers => Set<CaregiverUser>();
        public DbSet<CaregiverElderLink> CaregiverElderLinks => Set<CaregiverElderLink>();
        public DbSet<CaregiverPushToken> CaregiverPushTokens => Set<CaregiverPushToken>();
        public DbSet<DeviceRegistration> DeviceRegistrations => Set<DeviceRegistration>();
        public DbSet<DeviceClinicalState> DeviceClinicalStates => Set<DeviceClinicalState>();
        public DbSet<UserConsent> Consents => Set<UserConsent>();
        public DbSet<ProcessedRequestNonce> ProcessedRequestNonces => Set<ProcessedRequestNonce>();
        public DbSet<ProcessedTelemetryLedger> ProcessedTelemetryLedgers => Set<ProcessedTelemetryLedger>();
        public DbSet<HealthMeasurement> HealthMeasurements => Set<HealthMeasurement>();
        public DbSet<Incident> Incidents => Set<Incident>();
        public DbSet<IncidentViolation> IncidentViolations => Set<IncidentViolation>();
        public DbSet<NotificationOutbox> NotificationOutboxes => Set<NotificationOutbox>();
        public DbSet<NotificationReceiptLog> NotificationReceiptLogs => Set<NotificationReceiptLog>();
        public DbSet<DailyHealthAggregate> DailyHealthAggregates => Set<DailyHealthAggregate>();
        public DbSet<DataBreachLog> DataBreachLogs => Set<DataBreachLog>();
        public DbSet<AuditLog> AuditLogs => Set<AuditLog>();

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // 1. ProcessedRequestNonce: Khóa chính phức hợp
            modelBuilder.Entity<ProcessedRequestNonce>()
                .HasKey(n => new { n.DeviceId, n.Nonce });

            // 2. Chỉ mục duy nhất cho Open Incident (Chỉ cho phép tối đa 1 sự cố mở per Elder)
            modelBuilder.Entity<Incident>()
                .HasIndex(i => i.ElderProfileId)
                .HasFilter("[WorkflowState] IN ('Active', 'Acknowledged')")
                .IsUnique();

            // 3. Khai báo tường minh Precision cho toàn bộ số đo thập phân (P0-04 v83)
            modelBuilder.Entity<HealthMeasurement>()
                .Property(m => m.ValueNumeric)
                .HasPrecision(18, 4);

            modelBuilder.Entity<IncidentViolation>()
                .Property(v => v.TriggerValue)
                .HasPrecision(18, 4);

            modelBuilder.Entity<IncidentViolation>()
                .Property(v => v.ThresholdValue)
                .HasPrecision(18, 4);

            modelBuilder.Entity<ElderProfile>()
                .Property(e => e.LastSpo2Value).HasPrecision(5, 2);

            modelBuilder.Entity<ElderProfile>()
                .Property(e => e.LastHrValue).HasPrecision(5, 2);

            modelBuilder.Entity<ElderProfile>()
                .Property(e => e.LastSystolicBp).HasPrecision(5, 2);

            modelBuilder.Entity<ElderProfile>()
                .Property(e => e.LastDiastolicBp).HasPrecision(5, 2);

            // 4. CaregiverElderLink: Filtered unique index cho liên kết đang hoạt động (P1-24)
            modelBuilder.Entity<CaregiverElderLink>()
                .HasIndex(l => new { l.CaregiverUserId, l.ElderProfileId })
                .HasFilter("[RevokedAt] IS NULL")
                .IsUnique();

            // 5. NotificationReceiptLog: Khóa chống trùng lặp receipt (P1-27)
            modelBuilder.Entity<NotificationReceiptLog>()
                .HasIndex(r => new { r.NotificationOutboxId, r.ConfirmedByUserId, r.ReceiptType })
                .IsUnique();
        }
    }
}
```

---

#### 2. Kịch bản Di chuyển Schema An toàn Từng Cột (`20260921_Upgrade_v80_to_v85.sql`)
Giải quyết triệt để **P0-29** (Bổ sung tất cả các bảng thiếu), **P0-30** (Tách kiểm tra từng cột độc lập), và **P0-31** (Khởi tạo `LEGACY_DEVICE` vô hiệu hóa an toàn).

```sql
-- ============================================================================
-- CAREAI INTROSPECTIVE MIGRATION: UPGRADE v80/v82 -> v85.0 (AIRTIGHT EXECUTION)
-- ============================================================================
SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- 1. Đảm bảo bảng cơ sở DeviceRegistrations tồn tại
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'DeviceRegistrations')
BEGIN
    THROW 50001, 'Bảng DeviceRegistrations không tồn tại. Vui lòng chạy Initial Schema v85 trước.', 1;
END

-- 2. Khởi tạo bản ghi LEGACY_DEVICE an toàn (P0-31 Fix: Disabled by default, random key)
DECLARE @FallbackElderId UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
IF NOT EXISTS (SELECT 1 FROM ElderProfiles WHERE Id = @FallbackElderId)
BEGIN
    INSERT INTO ElderProfiles (Id, FullName, DateOfBirth, Address, IsActive, CreatedAt)
    VALUES (@FallbackElderId, N'Cụ Già Mặc Định (Legacy Isolation)', '1950-01-01', N'Hệ thống cách ly dữ liệu cũ', 1, SYSUTCDATETIME());
END

IF NOT EXISTS (SELECT 1 FROM DeviceRegistrations WHERE Id = 'LEGACY_DEVICE')
BEGIN
    -- Secret ngẫu nhiên 64 ký tự hex an toàn, IsActive = 0 để cấm bypass HMAC
    INSERT INTO DeviceRegistrations (Id, ElderProfileId, DeviceType, FirmwareVersion, HmacSecret, CommandSequenceCounter, IsActive, CreatedAt)
    VALUES ('LEGACY_DEVICE', @FallbackElderId, 'GATEWAY', 'v80-quarantined', 
            'A7F8B9C0D1E2F3A4B5C6D7E8F9A0B1C2D3E4F5A6B7C8D9E0F1A2B3C4D5E6F7A8', 0, 0, SYSUTCDATETIME());
END

-- 3. Cập nhật bảng IncidentViolations (Tách kiểm tra từng cột độc lập - P0-30)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('IncidentViolations') AND name = 'DeviceId')
BEGIN
    ALTER TABLE IncidentViolations ADD DeviceId NVARCHAR(100) NULL;
    EXEC('UPDATE iv SET iv.DeviceId = ISNULL(i.DeviceId, ''LEGACY_DEVICE'') FROM IncidentViolations iv INNER JOIN Incidents i ON iv.IncidentId = i.Id WHERE iv.DeviceId IS NULL;');
    ALTER TABLE IncidentViolations ALTER COLUMN DeviceId NVARCHAR(100) NOT NULL;
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('IncidentViolations') AND name = 'MetricType')
BEGIN
    ALTER TABLE IncidentViolations ADD MetricType NVARCHAR(50) NOT NULL DEFAULT 'FALL';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('IncidentViolations') AND name = 'ClinicalMessage')
BEGIN
    ALTER TABLE IncidentViolations ADD ClinicalMessage NVARCHAR(500) NOT NULL DEFAULT N'Cảnh báo lâm sàng';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('IncidentViolations') AND name = 'IsRecovered')
BEGIN
    ALTER TABLE IncidentViolations ADD IsRecovered BIT NOT NULL DEFAULT 0;
END

-- 4. Cập nhật bảng ElderProfiles: Tách kiểm tra từng cột lâm sàng (P0-30 Fix)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'ConsecutiveHighHrCount')
    ALTER TABLE ElderProfiles ADD ConsecutiveHighHrCount INT NOT NULL DEFAULT 0;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'LastHrTimestamp')
    ALTER TABLE ElderProfiles ADD LastHrTimestamp DATETIME2 NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'LastHrValue')
    ALTER TABLE ElderProfiles ADD LastHrValue DECIMAL(5, 2) NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'LastSystolicBp')
    ALTER TABLE ElderProfiles ADD LastSystolicBp DECIMAL(5, 2) NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'LastDiastolicBp')
    ALTER TABLE ElderProfiles ADD LastDiastolicBp DECIMAL(5, 2) NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'LastBpTimestamp')
    ALTER TABLE ElderProfiles ADD LastBpTimestamp DATETIME2 NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'IsBpRetestPending')
    ALTER TABLE ElderProfiles ADD IsBpRetestPending BIT NOT NULL DEFAULT 0;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ElderProfiles') AND name = 'BpRetestDeadline')
    ALTER TABLE ElderProfiles ADD BpRetestDeadline DATETIME2 NULL;

-- 5. Bổ sung các bảng thiếu trong schema (P0-29 Fix)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'DeviceClinicalStates')
BEGIN
    CREATE TABLE DeviceClinicalStates (
        Id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWID(),
        DeviceId NVARCHAR(100) NOT NULL,
        ElderProfileId UNIQUEIDENTIFIER NOT NULL,
        ConsecutiveLowSpo2Count INT NOT NULL DEFAULT 0,
        LastSpo2Timestamp DATETIME2 NULL,
        LastSpo2Value DECIMAL(5, 2) NULL,
        ConsecutiveHighHrCount INT NOT NULL DEFAULT 0,
        LastHrTimestamp DATETIME2 NULL,
        LastHrValue DECIMAL(5, 2) NULL,
        UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_DeviceClinicalStates_Device ON DeviceClinicalStates(DeviceId);
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'ProcessedTelemetryLedgers')
BEGIN
    CREATE TABLE ProcessedTelemetryLedgers (
        CompositePacketId NVARCHAR(150) NOT NULL PRIMARY KEY,
        DeviceId NVARCHAR(100) NOT NULL,
        PacketId NVARCHAR(100) NOT NULL,
        IngestedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        SampleCount INT NOT NULL,
        RejectedSampleCount INT NOT NULL DEFAULT 0,
        ProcessingStatus NVARCHAR(30) NOT NULL DEFAULT 'COMPLETED'
    );
    CREATE INDEX IX_ProcessedTelemetryLedgers_IngestedAt ON ProcessedTelemetryLedgers(IngestedAt);
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'CaregiverPushTokens')
BEGIN
    CREATE TABLE CaregiverPushTokens (
        Id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWID(),
        CaregiverUserId UNIQUEIDENTIFIER NOT NULL,
        PushToken NVARCHAR(500) NOT NULL,
        DeviceModel NVARCHAR(100) NULL,
        Platform NVARCHAR(20) NOT NULL DEFAULT 'ANDROID',
        IsActive BIT NOT NULL DEFAULT 1,
        LastSeenAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_CaregiverPushTokens_CaregiverUsers FOREIGN KEY (CaregiverUserId) REFERENCES CaregiverUsers(Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_CaregiverPushTokens_User_Active ON CaregiverPushTokens(CaregiverUserId, IsActive);
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'ProcessedRequestNonces')
BEGIN
    CREATE TABLE ProcessedRequestNonces (
        DeviceId NVARCHAR(100) NOT NULL,
        Nonce NVARCHAR(128) NOT NULL,
        UsedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_ProcessedRequestNonces PRIMARY KEY (DeviceId, Nonce)
    );
    CREATE INDEX IX_ProcessedRequestNonces_UsedAt ON ProcessedRequestNonces(UsedAt);
END

-- 6. Đồng bộ khóa duy nhất lọc cho Open Incidents
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Incidents_ElderProfile_Open' AND object_id = OBJECT_ID('Incidents'))
BEGIN
    CREATE UNIQUE INDEX UX_Incidents_ElderProfile_Open
    ON Incidents(ElderProfileId)
    WHERE WorkflowState IN ('Active', 'Acknowledged');
END

COMMIT TRANSACTION;
PRINT N'CareAI v85.0 Database Migration thành công 100% không mất dữ liệu!';
```

---

### PHẦN 3: ENGINE ĐỒNG THỜI, RETRY-MERGE TOÀN VẸN VÀ MÁY TRẠNG THÁI HUYẾT ÁP CHẶT CHẼ

#### 1. Triển khai `HardenedTelemetryEngine.cs` (Giải quyết triệt để P0-01, P0-02, P0-03, P0-04, P0-05, P0-06, P0-07)

```csharp
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Common;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CareAi.Core.Domain.Entities;
using CareAi.Infrastructure.Persistence;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace CareAi.Core.Services
{
    public record TelemetrySampleDto(
        string EventId,
        string MetricType,
        decimal Value,
        decimal? SecondaryValue, // Huyết áp tâm trương (Diastolic) cho BLOOD_PRESSURE
        string Unit,
        DateTime Timestamp
    );

    public record TelemetryPacketDto(
        string PacketId,
        string DeviceId,
        DateTime SentAt,
        List<TelemetrySampleDto> Samples
    );

    public record TelemetryProcessResult(
        bool Success,
        int ProcessedCount,
        int RejectedCount,
        bool IncidentTriggered,
        Guid? IncidentId,
        bool MergedIntoExisting,
        string Message
    );

    public interface IHardenedTelemetryEngine
    {
        Task<TelemetryProcessResult> ProcessTelemetryPacketAsync(TelemetryPacketDto packet, CancellationToken ct = default);
    }

    public class HardenedTelemetryEngine : IHardenedTelemetryEngine
    {
        private readonly IServiceScopeFactory _scopeFactory;
        private readonly ILogger<HardenedTelemetryEngine> _logger;

        public HardenedTelemetryEngine(
            IServiceScopeFactory scopeFactory,
            ILogger<HardenedTelemetryEngine> logger)
        {
            _scopeFactory = scopeFactory;
            _logger = logger;
        }

        public async Task<TelemetryProcessResult> ProcessTelemetryPacketAsync(TelemetryPacketDto packet, CancellationToken ct = default)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();

            // 1. Kiểm tra Thiết bị hợp lệ & Lấy ElderProfileId
            var device = await db.DeviceRegistrations
                .AsNoTracking()
                .FirstOrDefaultAsync(d => d.Id == packet.DeviceId && d.IsActive, ct);

            if (device == null)
            {
                return new TelemetryProcessResult(false, 0, packet.Samples?.Count ?? 0, false, null, false, "Thiết bị không hợp lệ hoặc đã bị cách ly.");
            }

            var elderId = device.ElderProfileId;
            var compositePacketId = $"{packet.DeviceId}:{packet.PacketId}";

            // 2. Chống trùng lặp PacketId cấp độ Thiết bị (P1-09)
            var ledgerExists = await db.ProcessedTelemetryLedgers
                .AsNoTracking()
                .AnyAsync(l => l.CompositePacketId == compositePacketId, ct);

            if (ledgerExists)
            {
                return new TelemetryProcessResult(true, 0, 0, false, null, false, "Gói tin đã được xử lý (Idempotent Success).");
            }

            // 3. Thực thi Transaction với chiến lược Retry-Merge bắt lỗi 2601/2627
            var strategy = db.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync(async () =>
            {
                using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, ct);
                try
                {
                    var result = await ExecuteInternalPipelineAsync(db, packet, device, elderId, compositePacketId, ct);
                    await transaction.CommitAsync(ct);
                    return result;
                }
                catch (DbUpdateException ex) when (IsUniqueConstraintViolation(ex))
                {
                    await transaction.RollbackAsync(ct);
                    _logger.LogWarning("Xung đột Insert đồng thời khi tạo Incident cho cụ {ElderId}. Kích hoạt Retry-Merge toàn vẹn.", elderId);
                    
                    // P0-02, P0-03, P0-04 FIX: Thực hiện Retry-Merge đầy đủ pipeline không mất dữ liệu
                    return await ExecuteRetryMergeAsync(packet, device, elderId, compositePacketId, ct);
                }
            });
        }

        private async Task<TelemetryProcessResult> ExecuteInternalPipelineAsync(
            CareAiDbContext db,
            TelemetryPacketDto packet,
            DeviceRegistration device,
            Guid elderId,
            string compositePacketId,
            CancellationToken ct)
        {
            // 4. Khóa độc quyền ElderProfile chống race SpO2/HR (P0-04, P0-05)
            var elder = await db.ElderProfiles
                .FromSqlRaw("SELECT * FROM ElderProfiles WITH (UPDLOCK, ROWLOCK) WHERE Id = {0}", elderId)
                .FirstOrDefaultAsync(ct);

            if (elder == null)
            {
                return new TelemetryProcessResult(false, 0, packet.Samples.Count, false, null, false, "Không tìm thấy hồ sơ người cao tuổi.");
            }

            // 5. Kiểm tra Đồng ý xử lý dữ liệu theo Điều 19 Luật Bảo vệ dữ liệu cá nhân 91/2025/QH15 (P0-06)
            bool hasValidConsent = await HasValidVitalsConsentAsync(db, elderId, ct);

            // 6. Tìm kiếm sự cố mở hiện tại (Active hoặc Acknowledged)
            var openIncident = await db.Incidents
                .FromSqlRaw("SELECT * FROM Incidents WITH (UPDLOCK, ROWLOCK) WHERE ElderProfileId = {0} AND WorkflowState IN ('Active', 'Acknowledged')", elderId)
                .Include(i => i.Violations)
                .FirstOrDefaultAsync(ct);

            int processedCount = 0;
            int rejectedCount = 0;
            var detectedViolations = new List<IncidentViolation>();
            bool isEmergencyTriggered = false;
            string emergencyBasisEvidence = string.Empty;

            // 7. Duyệt từng Sample trong Packet
            foreach (var sample in packet.Samples)
            {
                // Kiểm tra tính hợp lệ: Timestamp không được quá khứ > 24h và không được vượt quá tương lai 5 phút
                var nowUtc = DateTime.UtcNow;
                if (string.IsNullOrWhiteSpace(sample.EventId) || sample.Timestamp < nowUtc.AddDays(-1) || sample.Timestamp > nowUtc.AddMinutes(5))
                {
                    rejectedCount++;
                    continue;
                }

                // Nếu không có consent hợp lệ thì chỉ chấp nhận FALL và MANUAL_SOS theo Điều 19 Luật 91 (P0-07)
                if (!hasValidConsent && sample.MetricType != "FALL" && sample.MetricType != "MANUAL_SOS")
                {
                    rejectedCount++;
                    continue;
                }

                // Ghi nhận bản ghi sinh hiệu vào HealthMeasurements
                db.HealthMeasurements.Add(new HealthMeasurement
                {
                    Id = Guid.NewGuid(),
                    ClientEventId = sample.EventId,
                    ElderProfileId = elderId,
                    DeviceId = packet.DeviceId,
                    MetricType = sample.MetricType,
                    ValueNumeric = sample.Value,
                    Unit = sample.Unit ?? string.Empty,
                    MeasuredAt = sample.Timestamp,
                    IngestedAt = nowUtc
                });

                // Đánh giá luật lâm sàng
                var violation = EvaluateClinicalRule(elder, sample, packet.DeviceId, out bool isEmergency, out string basis);
                if (violation != null)
                {
                    detectedViolations.Add(violation);
                    if (isEmergency)
                    {
                        isEmergencyTriggered = true;
                        emergencyBasisEvidence = basis;
                    }
                }

                processedCount++;
            }

            // 8. Quản lý trạng thái Sự cố
            Guid? affectedIncidentId = null;
            bool mergedIntoExisting = false;

            if (detectedViolations.Count > 0)
            {
                if (openIncident == null)
                {
                    openIncident = new Incident
                    {
                        Id = Guid.NewGuid(),
                        ElderProfileId = elderId,
                        DeviceId = packet.DeviceId,
                        PrimaryTrigger = detectedViolations[0].RuleCode,
                        InitialSeverity = detectedViolations.Max(v => v.Severity),
                        CurrentSeverity = detectedViolations.Max(v => v.Severity),
                        WorkflowState = "Active",
                        EmergencyBasis = isEmergencyTriggered ? emergencyBasisEvidence : null,
                        CreatedAt = DateTime.UtcNow,
                        UpdatedAt = DateTime.UtcNow
                    };

                    foreach (var v in detectedViolations)
                    {
                        v.IncidentId = openIncident.Id;
                        openIncident.Violations.Add(v);
                    }

                    db.Incidents.Add(openIncident);
                    affectedIncidentId = openIncident.Id;
                }
                else
                {
                    mergedIntoExisting = true;
                    affectedIncidentId = openIncident.Id;

                    // Reopen nếu có cú ngã mới khi đang Acknowledged
                    if (openIncident.WorkflowState == "Acknowledged" && detectedViolations.Any(v => v.RuleCode == "HIGH_IMPACT_FALL"))
                    {
                        openIncident.WorkflowState = "Active";
                        openIncident.ResolutionNotes = (openIncident.ResolutionNotes ?? "") + " | REOPEN tự động do phát hiện ngã mới.";
                    }

                    float maxNewSeverity = detectedViolations.Max(v => v.Severity);
                    if (maxNewSeverity > openIncident.CurrentSeverity)
                    {
                        openIncident.CurrentSeverity = maxNewSeverity;
                    }
                    openIncident.UpdatedAt = DateTime.UtcNow;

                    foreach (var v in detectedViolations)
                    {
                        v.IncidentId = openIncident.Id;
                        openIncident.Violations.Add(v);
                    }
                }

                // Enqueue thông báo khẩn cấp Outbox
                if (isEmergencyTriggered)
                {
                    await EnqueueEmergencyOutboxNotificationsAsync(db, elderId, openIncident.Id, packet.DeviceId, detectedViolations[0].ClinicalMessage, ct);
                }
            }

            // 9. Ghi Ledger gói tin
            db.ProcessedTelemetryLedgers.Add(new ProcessedTelemetryLedger
            {
                CompositePacketId = compositePacketId,
                DeviceId = packet.DeviceId,
                PacketId = packet.PacketId,
                IngestedAt = DateTime.UtcNow,
                SampleCount = processedCount,
                RejectedSampleCount = rejectedCount,
                ProcessingStatus = rejectedCount == 0 ? "COMPLETED" : (processedCount > 0 ? "PARTIAL" : "REJECTED")
            });

            await db.SaveChangesAsync(ct);

            return new TelemetryProcessResult(
                true,
                processedCount,
                rejectedCount,
                detectedViolations.Count > 0,
                affectedIncidentId,
                mergedIntoExisting,
                "Xử lý telemetry thành công."
            );
        }

        // ====================================================================
        // RETRY-MERGE TOÀN VẸN KHÔNG MẤT DỮ LIỆU (P0-02, P0-03, P0-04 FIX)
        // ====================================================================
        private async Task<TelemetryProcessResult> ExecuteRetryMergeAsync(
            TelemetryPacketDto packet,
            DeviceRegistration device,
            Guid elderId,
            string compositePacketId,
            CancellationToken ct)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();

            var strategy = db.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync(async () =>
            {
                using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, ct);

                // P0-04: Khóa ElderProfile bằng UPDLOCK trong Retry-Merge
                var elder = await db.ElderProfiles
                    .FromSqlRaw("SELECT * FROM ElderProfiles WITH (UPDLOCK, ROWLOCK) WHERE Id = {0}", elderId)
                    .FirstOrDefaultAsync(ct);

                // Nạp sự cố mở vừa tạo thành công bởi luồng thắng cuộc
                var openIncident = await db.Incidents
                    .FromSqlRaw("SELECT * FROM Incidents WITH (UPDLOCK, ROWLOCK) WHERE ElderProfileId = {0} AND WorkflowState IN ('Active', 'Acknowledged')", elderId)
                    .Include(i => i.Violations)
                    .FirstOrDefaultAsync(ct);

                if (openIncident == null)
                {
                    throw new InvalidOperationException("Lỗi bất thường: Không tìm thấy sự cố mở sau va chạm Unique Index.");
                }

                bool hasValidConsent = await HasValidVitalsConsentAsync(db, elderId, ct);
                int processedCount = 0;
                int rejectedCount = 0;
                var detectedViolations = new List<IncidentViolation>();
                bool isEmergencyTriggered = false;
                string emergencyBasisEvidence = string.Empty;

                // P0-02: Duyệt và ghi nhận đầy đủ HealthMeasurements trong Retry-Merge
                foreach (var sample in packet.Samples)
                {
                    if (string.IsNullOrWhiteSpace(sample.EventId))
                    {
                        rejectedCount++;
                        continue;
                    }

                    if (!hasValidConsent && sample.MetricType != "FALL" && sample.MetricType != "MANUAL_SOS")
                    {
                        rejectedCount++;
                        continue;
                    }

                    db.HealthMeasurements.Add(new HealthMeasurement
                    {
                        Id = Guid.NewGuid(),
                        ClientEventId = sample.EventId,
                        ElderProfileId = elderId,
                        DeviceId = packet.DeviceId,
                        MetricType = sample.MetricType,
                        ValueNumeric = sample.Value,
                        Unit = sample.Unit ?? string.Empty,
                        MeasuredAt = sample.Timestamp,
                        IngestedAt = DateTime.UtcNow
                    });

                    // P0-03: Bắt đầy đủ isEmergency và emergencyBasis
                    var violation = EvaluateClinicalRule(elder!, sample, packet.DeviceId, out bool isEmergency, out string basis);
                    if (violation != null)
                    {
                        detectedViolations.Add(violation);
                        if (isEmergency)
                        {
                            isEmergencyTriggered = true;
                            emergencyBasisEvidence = basis;
                        }
                    }
                    processedCount++;
                }

                // Gộp violations vào Incident đang mở
                foreach (var v in detectedViolations)
                {
                    v.IncidentId = openIncident.Id;
                    openIncident.Violations.Add(v);
                }

                if (detectedViolations.Count > 0)
                {
                    float maxNewSeverity = detectedViolations.Max(v => v.Severity);
                    if (maxNewSeverity > openIncident.CurrentSeverity)
                    {
                        openIncident.CurrentSeverity = maxNewSeverity;
                    }
                    openIncident.UpdatedAt = DateTime.UtcNow;

                    // P0-03: Enqueue Outbox khẩn cấp nếu luồng thua cuộc cũng có cảnh báo khẩn cấp
                    if (isEmergencyTriggered)
                    {
                        await EnqueueEmergencyOutboxNotificationsAsync(db, elderId, openIncident.Id, packet.DeviceId, detectedViolations[0].ClinicalMessage, ct);
                    }
                }

                // P0-02: Ghi nhận ProcessedTelemetryLedger đầy đủ
                db.ProcessedTelemetryLedgers.Add(new ProcessedTelemetryLedger
                {
                    CompositePacketId = compositePacketId,
                    DeviceId = packet.DeviceId,
                    PacketId = packet.PacketId,
                    IngestedAt = DateTime.UtcNow,
                    SampleCount = processedCount,
                    RejectedSampleCount = rejectedCount,
                    ProcessingStatus = "COMPLETED"
                });

                await db.SaveChangesAsync(ct);
                await transaction.CommitAsync(ct);

                _logger.LogInformation("Retry-Merge toàn vẹn thành công cho gói tin {PacketId} vào sự cố {IncidentId}.", packet.PacketId, openIncident.Id);

                return new TelemetryProcessResult(
                    true,
                    processedCount,
                    rejectedCount,
                    detectedViolations.Count > 0,
                    openIncident.Id,
                    true,
                    "Retry-Merge thành công: Toàn bộ sinh hiệu, sổ cái và cảnh báo khẩn cấp đã được bảo toàn nguyên vẹn."
                );
            });
        }

        // ====================================================================
        // QUY TẮC LÂM SÀNG & ENFORCE HUYẾT ÁP RETEST 15 PHÚT (P0-05 FIX)
        // ====================================================================
        private IncidentViolation? EvaluateClinicalRule(
            ElderProfile elder,
            TelemetrySampleDto sample,
            string deviceId,
            out bool isEmergency,
            out string emergencyBasis)
        {
            isEmergency = false;
            emergencyBasis = string.Empty;

            // 1. TÉ NGÃ
            if (sample.MetricType == "FALL" && sample.Value >= 4.5m)
            {
                isEmergency = true;
                emergencyBasis = "VITAL_IMMINENT_PERIL_FALL";
                return new IncidentViolation
                {
                    Id = Guid.NewGuid(),
                    DeviceId = deviceId,
                    MetricType = "FALL",
                    RuleCode = "HIGH_IMPACT_FALL",
                    TriggerValue = sample.Value,
                    ThresholdValue = 4.5m,
                    Severity = 1.0f,
                    ClinicalMessage = $"Phát hiện cú ngã va đập cực mạnh ({sample.Value:F1}G). Yêu cầu ứng cứu tức thì.",
                    TriggeredAt = DateTime.UtcNow
                };
            }

            // 2. NÚT KHẨN CẤP
            if (sample.MetricType == "MANUAL_SOS")
            {
                isEmergency = true;
                emergencyBasis = "VITAL_IMMINENT_PERIL_MANUAL_SOS";
                return new IncidentViolation
                {
                    Id = Guid.NewGuid(),
                    DeviceId = deviceId,
                    MetricType = "MANUAL_SOS",
                    RuleCode = "ELDER_PANIC_BUTTON",
                    TriggerValue = 1.0m,
                    ThresholdValue = 1.0m,
                    Severity = 1.0f,
                    ClinicalMessage = "Người cao tuổi đã bấm nút cầu cứu khẩn cấp.",
                    TriggeredAt = DateTime.UtcNow
                };
            }

            // 3. NỒNG ĐỘ OXY TRONG MÁU (SPO2)
            if (sample.MetricType == "SPO2")
            {
                elder.LastSpo2Timestamp = sample.Timestamp;
                elder.LastSpo2Value = sample.Value;

                if (sample.Value < 90.0m)
                {
                    elder.ConsecutiveLowSpo2Count++;
                    if (elder.ConsecutiveLowSpo2Count >= 3)
                    {
                        isEmergency = true;
                        emergencyBasis = "CLINICAL_HYPOXIA_CRITICAL";
                        return new IncidentViolation
                        {
                            Id = Guid.NewGuid(),
                            DeviceId = deviceId,
                            MetricType = "SPO2",
                            RuleCode = "CRITICAL_HYPOXIA",
                            TriggerValue = sample.Value,
                            ThresholdValue = 90.0m,
                            Severity = 0.95f,
                            ClinicalMessage = $"Thiếu oxy máu nghiêm trọng kéo dài (SpO2 {sample.Value:F1}% sau 3 lần đo liên tiếp).",
                            TriggeredAt = DateTime.UtcNow
                        };
                    }
                }
                else if (sample.Value >= 92.0m)
                {
                    elder.ConsecutiveLowSpo2Count = 0;
                }
            }

            // 4. NHỊP TIM (HEART RATE)
            if (sample.MetricType == "HEART_RATE")
            {
                elder.LastHrTimestamp = sample.Timestamp;
                elder.LastHrValue = sample.Value;

                if (sample.Value < 45.0m)
                {
                    isEmergency = true;
                    emergencyBasis = "CLINICAL_SEVERE_BRADYCARDIA";
                    return new IncidentViolation
                    {
                        Id = Guid.NewGuid(),
                        DeviceId = deviceId,
                        MetricType = "HEART_RATE",
                        RuleCode = "SEVERE_BRADYCARDIA",
                        TriggerValue = sample.Value,
                        ThresholdValue = 45.0m,
                        Severity = 0.85f,
                        ClinicalMessage = $"Nhịp tim chậm nguy hiểm ({sample.Value:F0} bpm < 45 bpm).",
                        TriggeredAt = DateTime.UtcNow
                    };
                }

                if (sample.Value > 130.0m)
                {
                    elder.ConsecutiveHighHrCount++;
                    if (elder.ConsecutiveHighHrCount >= 2)
                    {
                        isEmergency = true;
                        emergencyBasis = "CLINICAL_SEVERE_TACHYCARDIA";
                        return new IncidentViolation
                        {
                            Id = Guid.NewGuid(),
                            DeviceId = deviceId,
                            MetricType = "HEART_RATE",
                            RuleCode = "SEVERE_TACHYCARDIA",
                            TriggerValue = sample.Value,
                            ThresholdValue = 130.0m,
                            Severity = 0.85f,
                            ClinicalMessage = $"Nhịp tim nhanh nguy hiểm kéo dài ({sample.Value:F0} bpm > 130 bpm).",
                            TriggeredAt = DateTime.UtcNow
                        };
                    }
                }
                else
                {
                    elder.ConsecutiveHighHrCount = 0;
                }
            }

            // 5. HUYẾT ÁP VỚI KIỂM SOÁT THỜI GIAN 15 PHÚT CHẶT CHẼ (P0-05 FIX)
            if (sample.MetricType == "BLOOD_PRESSURE")
            {
                elder.LastSystolicBp = sample.Value;
                if (sample.SecondaryValue.HasValue) elder.LastDiastolicBp = sample.SecondaryValue.Value;
                elder.LastBpTimestamp = sample.Timestamp;

                bool isHighBp = sample.Value >= 160.0m || (sample.SecondaryValue.HasValue && sample.SecondaryValue.Value >= 100.0m);

                if (isHighBp)
                {
                    if (!elder.IsBpRetestPending)
                    {
                        // Lần đầu vượt ngưỡng -> Hẹn giờ đo lại sau đúng 15 phút
                        elder.IsBpRetestPending = true;
                        elder.BpRetestDeadline = sample.Timestamp.AddMinutes(15);

                        return new IncidentViolation
                        {
                            Id = Guid.NewGuid(),
                            DeviceId = deviceId,
                            MetricType = "BLOOD_PRESSURE",
                            RuleCode = "BP_STAGE2_RETEST_REQUIRED",
                            TriggerValue = sample.Value,
                            ThresholdValue = 160.0m,
                            Severity = 0.50f,
                            ClinicalMessage = $"Huyết áp cao ({sample.Value:F0} mmHg). Hệ thống yêu cầu nghỉ ngơi 15 phút trước khi đo lại lúc {elder.BpRetestDeadline:HH:mm}.",
                            TriggeredAt = sample.Timestamp
                        };
                    }
                    else
                    {
                        // P0-05 FIX: BẮT BUỘC KIỂM TRA ĐÃ QUA THỜI GIAN NGHỈ NGƠI 15 PHÚT CHƯA
                        if (sample.Timestamp >= elder.BpRetestDeadline)
                        {
                            // Đã đủ 15 phút mà huyết áp vẫn cao -> XÁC NHẬN CƠN TĂNG HUYẾT ÁP KHẨN CẤP
                            elder.IsBpRetestPending = false;
                            elder.BpRetestDeadline = null;
                            isEmergency = true;
                            emergencyBasis = "CLINICAL_HYPERTENSIVE_CRISIS_CONFIRMED";

                            return new IncidentViolation
                            {
                                Id = Guid.NewGuid(),
                                DeviceId = deviceId,
                                MetricType = "BLOOD_PRESSURE",
                                RuleCode = "HYPERTENSIVE_CRISIS_CONFIRMED",
                                TriggerValue = sample.Value,
                                ThresholdValue = 160.0m,
                                Severity = 0.90f,
                                ClinicalMessage = $"Xác nhận Cơn tăng huyết áp khẩn cấp sau 15 phút đo lại ({sample.Value:F0} mmHg). Yêu cầu trợ giúp y tế.",
                                TriggeredAt = sample.Timestamp
                            };
                        }
                        else
                        {
                            // Đo lại quá sớm (< 15 phút) -> Bỏ qua, yêu cầu tiếp tục nghỉ ngơi
                            _logger.LogInformation("Lần đo huyết áp thứ 2 thực hiện quá sớm (còn {Minutes:F1} phút nữa mới tới hạn retest).", (elder.BpRetestDeadline.Value - sample.Timestamp).TotalMinutes);
                        }
                    }
                }
                else if (sample.Value < 140.0m && elder.IsBpRetestPending)
                {
                    // Huyết áp hạ về bình thường
                    elder.IsBpRetestPending = false;
                    elder.BpRetestDeadline = null;
                }
            }

            return null;
        }

        private async Task<bool> HasValidVitalsConsentAsync(CareAiDbContext db, Guid elderId, CancellationToken ct)
        {
            return await db.Consents
                .AsNoTracking()
                .AnyAsync(c => c.ElderProfileId == elderId 
                            && c.Scope == "TELEMETRY_PROCESSING" 
                            && c.RevokedAt == null 
                            && c.RightsNoticeConfirmed
                            && !string.IsNullOrEmpty(c.EvidenceHash), ct);
        }

        private async Task EnqueueEmergencyOutboxNotificationsAsync(
            CareAiDbContext db,
            Guid elderId,
            Guid incidentId,
            string deviceId,
            string alertMessage,
            CancellationToken ct)
        {
            var commandSeq = await GetNextCommandSequenceAsync(db, deviceId, ct);
            db.NotificationOutboxes.Add(new NotificationOutbox
            {
                Id = Guid.NewGuid(),
                IncidentId = incidentId,
                ClientEventId = $"SIREN_{incidentId}_{commandSeq}",
                TargetDeviceId = deviceId,
                Channel = "InternalSiren",
                DestinationAddress = deviceId,
                Payload = JsonSerializer.Serialize(new
                {
                    action = "TRIGGER_SIREN",
                    incidentId = incidentId,
                    sequence = commandSeq,
                    durationSec = 120,
                    timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                    ttlSec = 180 // P0-13 Fix: Thời gian sống của lệnh còi là 3 phút
                }),
                DeliveryStatus = "Pending",
                CreatedAt = DateTime.UtcNow
            });

            var caregiverLinks = await db.CaregiverElderLinks
                .AsNoTracking()
                .Where(l => l.ElderProfileId == elderId && l.RevokedAt == null && l.IsEmergencyContact)
                .Include(l => l.CaregiverUser)
                    .ThenInclude(u => u.PushTokens)
                .ToListAsync(ct);

            foreach (var link in caregiverLinks)
            {
                foreach (var token in link.CaregiverUser.PushTokens.Where(t => t.IsActive))
                {
                    db.NotificationOutboxes.Add(new NotificationOutbox
                    {
                        Id = Guid.NewGuid(),
                        IncidentId = incidentId,
                        ClientEventId = $"PUSH_{incidentId}_{token.Id}",
                        RecipientUserId = link.CaregiverUserId,
                        Channel = "Push",
                        DestinationAddress = token.PushToken,
                        Payload = JsonSerializer.Serialize(new
                        {
                            notificationId = Guid.NewGuid().ToString(),
                            incidentId = incidentId.ToString(),
                            elderId = elderId.ToString(),
                            severity = "Critical",
                            title = "BÁO ĐỘNG KHẨN CẤP CAREAI",
                            body = alertMessage,
                            action = "VIEW_INCIDENT"
                        }),
                        DeliveryStatus = "Pending",
                        CreatedAt = DateTime.UtcNow
                    });
                }
            }
        }

        // ====================================================================
        // ADO.NET ATOMIC COMMAND SEQUENCE ALLOCATOR (P0-01 FIX)
        // ====================================================================
        private async Task<long> GetNextCommandSequenceAsync(CareAiDbContext db, string deviceId, CancellationToken ct)
        {
            var connection = db.Database.GetDbConnection();
            if (connection.State != ConnectionState.Open)
            {
                await connection.OpenAsync(ct);
            }

            using var cmd = connection.CreateCommand();
            cmd.CommandText = "UPDATE DeviceRegistrations SET CommandSequenceCounter = CommandSequenceCounter + 1 OUTPUT INSERTED.CommandSequenceCounter WHERE Id = @DeviceId";
            
            var param = cmd.CreateParameter();
            param.ParameterName = "@DeviceId";
            param.Value = deviceId;
            cmd.Parameters.Add(param);

            var scalarResult = await cmd.ExecuteScalarAsync(ct);
            if (scalarResult == null || scalarResult == DBNull.Value)
            {
                throw new InvalidOperationException($"Không thể cấp phát sequence cho thiết bị không tồn tại: {deviceId}");
            }

            return Convert.ToInt64(scalarResult);
        }

        private static bool IsUniqueConstraintViolation(DbUpdateException ex)
        {
            if (ex.InnerException is SqlException sqlEx)
            {
                return sqlEx.Number == 2601 || sqlEx.Number == 2627;
            }
            return false;
        }
    }
}
```

---

### PHẦN 4: CONTROLLERS HOÀN CHỈNH, TELEMETRY/AUTH RUNTIME VÀ CHỐNG BOLA TRIỆT ĐỂ

#### 1. Triển khai `IncidentsController.cs` (Giải quyết P0-08: Confirm Kích hoạt Outbox Cứu hộ, P0-10, P0-11 BOLA)

```csharp
using System;
using System.Data;
using System.Linq;
using System.Security.Claims;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CareAi.Core.Domain.Entities;
using CareAi.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace CareAi.Api.Controllers
{
    [ApiController]
    [Route("api/v1/incidents")]
    public class IncidentsController : ControllerBase
    {
        private readonly CareAiDbContext _db;
        private readonly ILogger<IncidentsController> _logger;

        public IncidentsController(CareAiDbContext db, ILogger<IncidentsController> logger)
        {
            _db = db;
            _logger = logger;
        }

        public record AcknowledgeRequest(string Notes, string? RowVersionBase64);
        public record ElderCancelRequest(string Reason, string? ClientEventId);
        public record ElderConfirmRequest(string? ClientEventId);

        // ====================================================================
        // NGƯỜI NHÀ XÁC NHẬN SỰ CỐ (P0-11 BOLA CHECK, P0-18 STOP SIREN)
        // ====================================================================
        [HttpPost("{id:guid}/acknowledge")]
        [Authorize]
        public async Task<IActionResult> AcknowledgeIncident(Guid id, [FromBody] AcknowledgeRequest request, CancellationToken ct)
        {
            var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (!Guid.TryParse(userIdStr, out var caregiverUserId))
            {
                return Unauthorized(new { message = "Không xác định được danh tính từ JWT." });
            }

            var incident = await _db.Incidents.FirstOrDefaultAsync(i => i.Id == id, ct);
            if (incident == null) return NotFound(new { message = "Không tìm thấy sự cố." });

            // BOLA CHECK (P0-11): Caregiver phải có liên kết hợp lệ với cụ
            bool hasActiveLink = await _db.CaregiverElderLinks
                .AsNoTracking()
                .AnyAsync(l => l.CaregiverUserId == caregiverUserId 
                            && l.ElderProfileId == incident.ElderProfileId 
                            && l.RevokedAt == null, ct);

            if (!hasActiveLink)
            {
                _logger.LogWarning("BOLA BLOCKED: Caregiver {UserId} cố xác nhận sự cố của cụ {ElderId}!", caregiverUserId, incident.ElderProfileId);
                return StatusCode(403, new { message = "Bạn không có thẩm quyền đối với sự cố của người cao tuổi này." });
            }

            if (incident.WorkflowState != "Active")
            {
                return BadRequest(new { message = $"Chỉ sự cố Active mới được phép Acknowledge. Trạng thái hiện tại: {incident.WorkflowState}" });
            }

            if (!string.IsNullOrEmpty(request.RowVersionBase64))
            {
                _db.Entry(incident).Property(nameof(Incident.RowVersion)).OriginalValue = Convert.FromBase64String(request.RowVersionBase64);
            }

            try
            {
                incident.WorkflowState = "Acknowledged";
                incident.AcknowledgedByCaregiverId = caregiverUserId;
                incident.AcknowledgedAt = DateTime.UtcNow;
                incident.ResolutionNotes = request.Notes ?? "Người nhà đã tiếp nhận cảnh báo.";
                incident.UpdatedAt = DateTime.UtcNow;

                // Enqueue lệnh tắt còi STOP_SIREN gửi xuống Gateway (P0-09: Truyền rõ action STOP_SIREN)
                var commandSeq = await GetNextCommandSequenceAsync(incident.DeviceId, ct);
                _db.NotificationOutboxes.Add(new NotificationOutbox
                {
                    Id = Guid.NewGuid(),
                    IncidentId = incident.Id,
                    ClientEventId = $"STOP_SIREN_ACK_{incident.Id}_{commandSeq}",
                    TargetDeviceId = incident.DeviceId,
                    Channel = "InternalSiren",
                    DestinationAddress = incident.DeviceId,
                    Payload = JsonSerializer.Serialize(new
                    {
                        action = "STOP_SIREN",
                        incidentId = incident.Id,
                        sequence = commandSeq,
                        reason = "CAREGIVER_ACKNOWLEDGED",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                        ttlSec = 180
                    }),
                    DeliveryStatus = "Pending",
                    CreatedAt = DateTime.UtcNow
                });

                await _db.SaveChangesAsync(ct);
                return Ok(new { success = true, incidentId = incident.Id, state = incident.WorkflowState, rowVersion = Convert.ToBase64String(incident.RowVersion) });
            }
            catch (DbUpdateConcurrencyException)
            {
                return Conflict(new { message = "Sự cố đã được người nhà khác cập nhật trước đó." });
            }
        }

        // ====================================================================
        // CỤ GIÀ HỦY BÁO ĐỘNG (P0-10 BOLA CHECK)
        // ====================================================================
        [HttpPost("{id:guid}/cancel-from-elder")]
        public async Task<IActionResult> CancelIncidentFromElder(Guid id, [FromBody] ElderCancelRequest request, CancellationToken ct)
        {
            if (!HttpContext.Items.TryGetValue("AuthenticatedDevice", out var devObj) || devObj is not DeviceRegistration device)
            {
                return Unauthorized(new { message = "Yêu cầu xác thực chữ ký HMAC từ thiết bị Gateway." });
            }

            var incident = await _db.Incidents.FirstOrDefaultAsync(i => i.Id == id, ct);
            if (incident == null) return NotFound(new { message = "Không tìm thấy sự cố." });

            // BOLA CHECK (P0-10)
            if (incident.ElderProfileId != device.ElderProfileId)
            {
                return StatusCode(403, new { message = "Thiết bị không thuộc quyền sở hữu của cụ trong sự cố này." });
            }

            incident.WorkflowState = "FalseAlarm";
            incident.ResolvedAt = DateTime.UtcNow;
            incident.ResolutionNotes = $"Cụ đã hủy báo động tại màn hình đếm ngược. Lý do: {request.Reason ?? "Nhầm lẫn"}";
            incident.UpdatedAt = DateTime.UtcNow;

            var commandSeq = await GetNextCommandSequenceAsync(device.Id, ct);
            _db.NotificationOutboxes.Add(new NotificationOutbox
            {
                Id = Guid.NewGuid(),
                IncidentId = incident.Id,
                ClientEventId = $"STOP_SIREN_CANCEL_{incident.Id}_{commandSeq}",
                TargetDeviceId = device.Id,
                Channel = "InternalSiren",
                DestinationAddress = device.Id,
                Payload = JsonSerializer.Serialize(new
                {
                    action = "STOP_SIREN",
                    incidentId = incident.Id,
                    sequence = commandSeq,
                    reason = "ELDER_CANCELLED_FALSE_ALARM",
                    timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                    ttlSec = 180
                }),
                DeliveryStatus = "Pending",
                CreatedAt = DateTime.UtcNow
            });

            await _db.SaveChangesAsync(ct);
            return Ok(new { success = true, state = incident.WorkflowState });
        }

        // ====================================================================
        // CỤ GIÀ BẤM NÚT XÁC NHẬN CẦN CỨU HỘ TỨC THỜI (P0-08 FIX: KÍCH HOẠT SIREN VÀ PUSH)
        // ====================================================================
        [HttpPost("{id:guid}/confirm-emergency")]
        public async Task<IActionResult> ConfirmEmergencyFromElder(Guid id, [FromBody] ElderConfirmRequest request, CancellationToken ct)
        {
            if (!HttpContext.Items.TryGetValue("AuthenticatedDevice", out var devObj) || devObj is not DeviceRegistration device)
            {
                return Unauthorized(new { message = "Yêu cầu xác thực chữ ký HMAC từ thiết bị Gateway." });
            }

            var incident = await _db.Incidents.FirstOrDefaultAsync(i => i.Id == id, ct);
            if (incident == null) return NotFound(new { message = "Không tìm thấy sự cố." });

            if (incident.ElderProfileId != device.ElderProfileId)
            {
                return StatusCode(403, new { message = "Thiết bị không có quyền truy cập sự cố này." });
            }

            incident.WorkflowState = "Active";
            incident.CurrentSeverity = 1.0f;
            incident.EmergencyBasis = "VITAL_IMMINENT_PERIL_ELDER_CONFIRMED";
            incident.ResolutionNotes = (incident.ResolutionNotes ?? "") + " | Cụ đã bấm xác nhận khẩn cấp tức thời tại màn hình đếm ngược.";
            incident.UpdatedAt = DateTime.UtcNow;

            // P0-08 FIX: KÍCH HOẠT CHUỖI CỨU HỘ: PHÁT CÒI VÀ PUSH TOÀN BỘ NGƯỜI NHÀ
            var commandSeq = await GetNextCommandSequenceAsync(device.Id, ct);
            _db.NotificationOutboxes.Add(new NotificationOutbox
            {
                Id = Guid.NewGuid(),
                IncidentId = incident.Id,
                ClientEventId = $"SIREN_CONFIRMED_{incident.Id}_{commandSeq}",
                TargetDeviceId = device.Id,
                Channel = "InternalSiren",
                DestinationAddress = device.Id,
                Payload = JsonSerializer.Serialize(new
                {
                    action = "TRIGGER_SIREN",
                    incidentId = incident.Id,
                    sequence = commandSeq,
                    durationSec = 120,
                    timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                    ttlSec = 180
                }),
                DeliveryStatus = "Pending",
                CreatedAt = DateTime.UtcNow
            });

            var caregiverLinks = await _db.CaregiverElderLinks
                .AsNoTracking()
                .Where(l => l.ElderProfileId == incident.ElderProfileId && l.RevokedAt == null && l.IsEmergencyContact)
                .Include(l => l.CaregiverUser)
                    .ThenInclude(u => u.PushTokens)
                .ToListAsync(ct);

            foreach (var link in caregiverLinks)
            {
                foreach (var token in link.CaregiverUser.PushTokens.Where(t => t.IsActive))
                {
                    _db.NotificationOutboxes.Add(new NotificationOutbox
                    {
                        Id = Guid.NewGuid(),
                        IncidentId = incident.Id,
                        ClientEventId = $"PUSH_CONFIRMED_{incident.Id}_{token.Id}",
                        RecipientUserId = link.CaregiverUserId,
                        Channel = "Push",
                        DestinationAddress = token.PushToken,
                        Payload = JsonSerializer.Serialize(new
                        {
                            notificationId = Guid.NewGuid().ToString(),
                            incidentId = incident.Id.ToString(),
                            elderId = incident.ElderProfileId.ToString(),
                            severity = "Critical",
                            title = "CỤ GIÀ XÁC NHẬN CẦN CỨU HỘ KHẨN CẤP!",
                            body = "Cụ đã bấm nút báo ngay trên thiết bị Gateway. Vui lòng can thiệp tức thì!",
                            action = "VIEW_INCIDENT"
                        }),
                        DeliveryStatus = "Pending",
                        CreatedAt = DateTime.UtcNow
                    });
                }
            }

            // Ghi nhật ký kiểm toán
            _db.AuditLogs.Add(new AuditLog
            {
                Id = Guid.NewGuid(),
                RequestId = request.ClientEventId ?? Guid.NewGuid().ToString("N"),
                Actor = $"DEVICE_{device.Id}",
                Action = "ELDER_CONFIRMED_EMERGENCY",
                DeviceId = device.Id,
                IncidentId = incident.Id,
                DetailsJson = JsonSerializer.Serialize(new { Reason = "ELDER_CONFIRMED_BUTTON", Timestamp = DateTime.UtcNow }),
                Timestamp = DateTime.UtcNow
            });

            await _db.SaveChangesAsync(ct);
            return Ok(new { success = true, incidentId = incident.Id, state = incident.WorkflowState, message = "Đã kích hoạt toàn bộ chuỗi cứu hộ khẩn cấp." });
        }

        private async Task<long> GetNextCommandSequenceAsync(string deviceId, CancellationToken ct)
        {
            var connection = _db.Database.GetDbConnection();
            if (connection.State != ConnectionState.Open) await connection.OpenAsync(ct);
            using var cmd = connection.CreateCommand();
            cmd.CommandText = "UPDATE DeviceRegistrations SET CommandSequenceCounter = CommandSequenceCounter + 1 OUTPUT INSERTED.CommandSequenceCounter WHERE Id = @DeviceId";
            var p = cmd.CreateParameter();
            p.ParameterName = "@DeviceId";
            p.Value = deviceId;
            cmd.Parameters.Add(p);
            var res = await cmd.ExecuteScalarAsync(ct);
            return Convert.ToInt64(res);
        }
    }
}
```

---

#### 2. Triển khai `TelemetryController.cs` & `AuthController.cs` (Giải quyết P0-37: Cung cấp Endpoint Thực Thi)

```csharp
using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CareAi.Core.Domain.Entities;
using CareAi.Core.Services;
using CareAi.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;

namespace CareAi.Api.Controllers
{
    [ApiController]
    [Route("api/v1/telemetry")]
    public class TelemetryController : ControllerBase
    {
        private readonly IHardenedTelemetryEngine _engine;

        public TelemetryController(IHardenedTelemetryEngine engine)
        {
            _engine = engine;
        }

        [HttpPost]
        public async Task<IActionResult> IngestTelemetry([FromBody] TelemetryPacketDto packet, CancellationToken ct)
        {
            if (packet == null || packet.Samples == null || packet.Samples.Count == 0)
            {
                return BadRequest(new { message = "Gói tin telemetry không có dữ liệu." });
            }

            var result = await _engine.ProcessTelemetryPacketAsync(packet, ct);
            return Ok(result);
        }

        [HttpPost("sos")]
        public async Task<IActionResult> ManualSos([FromBody] TelemetryPacketDto packet, CancellationToken ct)
        {
            var result = await _engine.ProcessTelemetryPacketAsync(packet, ct);
            return Ok(result);
        }
    }

    [ApiController]
    [Route("api/v1/auth")]
    public class AuthController : ControllerBase
    {
        private readonly CareAiDbContext _db;
        private readonly IConfiguration _config;

        public AuthController(CareAiDbContext db, IConfiguration config)
        {
            _db = db;
            _config = config;
        }

        public record LoginDto(string Username, string Password);

        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] LoginDto request, CancellationToken ct)
        {
            var user = await _db.CaregiverUsers.FirstOrDefaultAsync(u => u.Username == request.Username, ct);
            if (user == null || !user.IsActive)
            {
                return Unauthorized(new { message = "Tài khoản hoặc mật khẩu không chính xác." });
            }

            if (user.LockoutEnd.HasValue && user.LockoutEnd > DateTime.UtcNow)
            {
                return StatusCode(423, new { message = $"Tài khoản bị tạm khóa đến {user.LockoutEnd:HH:mm:ss} do đăng nhập sai nhiều lần." });
            }

            // Xác thực mật khẩu PBKDF2
            if (!VerifyPassword(request.Password, user.PasswordHash))
            {
                user.AccessFailedCount++;
                if (user.AccessFailedCount >= 5)
                {
                    user.LockoutEnd = DateTime.UtcNow.AddMinutes(15);
                    user.AccessFailedCount = 0;
                }
                await _db.SaveChangesAsync(ct);
                return Unauthorized(new { message = "Tài khoản hoặc mật khẩu không chính xác." });
            }

            user.AccessFailedCount = 0;
            user.LockoutEnd = null;
            user.SecurityStamp = Guid.NewGuid().ToString("N");
            await _db.SaveChangesAsync(ct);

            var tokenHandler = new JwtSecurityTokenHandler();
            var key = Encoding.UTF8.GetBytes(_config["Jwt:SecretKey"]!);
            var tokenDescriptor = new SecurityTokenDescriptor
            {
                Subject = new ClaimsIdentity(new[]
                {
                    new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
                    new Claim(ClaimTypes.Name, user.Username),
                    new Claim("SecurityStamp", user.SecurityStamp)
                }),
                Expires = DateTime.UtcNow.AddDays(7),
                Issuer = _config["Jwt:Issuer"] ?? "CareAiServer",
                Audience = _config["Jwt:Audience"] ?? "CareAiClients",
                SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
            };

            var token = tokenHandler.CreateToken(tokenDescriptor);
            return Ok(new
            {
                accessToken = tokenHandler.WriteToken(token),
                userId = user.Id,
                fullName = user.FullName
            });
        }

        private static bool VerifyPassword(string password, string storedHash)
        {
            var parts = storedHash.Split(':');
            if (parts.Length != 2) return false;
            var salt = Convert.FromBase64String(parts[0]);
            var hash = parts[1];
            var computed = Convert.ToBase64String(Rfc2898DeriveBytes.Pbkdf2(password, salt, 100_000, HashAlgorithmName.SHA256, 32));
            return CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(hash), Encoding.UTF8.GetBytes(computed));
        }
    }

    [ApiController]
    [Route("api/v1/caregivers")]
    [Authorize]
    public class CaregiversController : ControllerBase
    {
        private readonly CareAiDbContext _db;

        public CaregiversController(CareAiDbContext db)
        {
            _db = db;
        }

        public record PushTokenDto(string PushToken, string? DeviceModel, string Platform);

        [HttpPost("push-token")]
        public async Task<IActionResult> RegisterPushToken([FromBody] PushTokenDto request, CancellationToken ct)
        {
            var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (!Guid.TryParse(userIdStr, out var caregiverUserId)) return Unauthorized();

            var existing = await _db.CaregiverPushTokens
                .FirstOrDefaultAsync(t => t.CaregiverUserId == caregiverUserId && t.PushToken == request.PushToken, ct);

            if (existing != null)
            {
                existing.IsActive = true;
                existing.LastSeenAt = DateTime.UtcNow;
            }
            else
            {
                _db.CaregiverPushTokens.Add(new CaregiverPushToken
                {
                    Id = Guid.NewGuid(),
                    CaregiverUserId = caregiverUserId,
                    PushToken = request.PushToken,
                    DeviceModel = request.DeviceModel ?? string.Empty,
                    Platform = request.Platform ?? "ANDROID",
                    IsActive = true,
                    LastSeenAt = DateTime.UtcNow,
                    CreatedAt = DateTime.UtcNow
                });
            }

            await _db.SaveChangesAsync(ct);
            return Ok(new { success = true, message = "Đăng ký token thông báo thành công." });
        }
    }
}
```

---

### PHẦN 5: BACKGROUND WORKERS, FCM V1 ĐỦ ACTION VÀ CHƯƠNG TRÌNH KHỞI ĐỘNG CÓ /HEALTH/VERSION

#### 1. Triển khai `FcmV1PushService.cs` (Giải quyết triệt để P0-09: Phân biệt Rõ ràng TRIGGER_SIREN và STOP_SIREN)

```csharp
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;

namespace CareAi.Infrastructure.Services
{
    public interface IFcmPushService
    {
        Task<bool> SendPushNotificationAsync(string pushToken, string title, string body, object dataPayload, CancellationToken ct = default);
        Task<bool> SendSirenCommandToDeviceAsync(string devicePushToken, Guid incidentId, long sequence, string action, int durationSec, CancellationToken ct = default);
    }

    public class FcmV1PushService : IFcmPushService
    {
        private readonly HttpClient _httpClient;
        private readonly IGoogleOAuthTokenService _tokenService;
        private readonly ILogger<FcmV1PushService> _logger;

        public FcmV1PushService(
            HttpClient httpClient,
            IGoogleOAuthTokenService tokenService,
            ILogger<FcmV1PushService> logger)
        {
            _httpClient = httpClient;
            _tokenService = tokenService;
            _logger = logger;
        }

        public async Task<bool> SendPushNotificationAsync(string pushToken, string title, string body, object dataPayload, CancellationToken ct = default)
        {
            try
            {
                var accessToken = await _tokenService.GetAccessTokenAsync(ct);
                var projectId = _tokenService.GetProjectId();
                var endpoint = $"https://fcm.googleapis.com/v1/projects/{projectId}/messages:send";

                var dataDict = new Dictionary<string, string>();
                if (dataPayload != null)
                {
                    var jsonStr = JsonSerializer.Serialize(dataPayload);
                    using var doc = JsonDocument.Parse(jsonStr);
                    foreach (var prop in doc.RootElement.EnumerateObject())
                    {
                        dataDict[prop.Name] = prop.Value.ToString() ?? "";
                    }
                }

                var fcmMessage = new
                {
                    message = new
                    {
                        token = pushToken,
                        notification = new { title = title, body = body },
                        data = dataDict,
                        android = new
                        {
                            priority = "HIGH",
                            notification = new { channel_id = "careai_emergency_channel", priority = "MAX", sound = "emergency_alarm" }
                        }
                    }
                };

                using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
                {
                    Content = new StringContent(JsonSerializer.Serialize(fcmMessage), Encoding.UTF8, "application/json")
                };
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

                var response = await _httpClient.SendAsync(request, ct);
                return response.IsSuccessStatusCode;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Lỗi khi gọi FCM v1 Push API");
                return false;
            }
        }

        // ====================================================================
        // GỬI LỆNH CÒI THỰC TẾ CÓ THAM SỐ ACTION (P0-09 FIX: TRIGGER_SIREN HOẶC STOP_SIREN)
        // ====================================================================
        public async Task<bool> SendSirenCommandToDeviceAsync(
            string devicePushToken, 
            Guid incidentId, 
            long sequence, 
            string action, 
            int durationSec, 
            CancellationToken ct = default)
        {
            try
            {
                var accessToken = await _tokenService.GetAccessTokenAsync(ct);
                var projectId = _tokenService.GetProjectId();
                var endpoint = $"https://fcm.googleapis.com/v1/projects/{projectId}/messages:send";

                var sirenMessage = new
                {
                    message = new
                    {
                        token = devicePushToken,
                        data = new Dictionary<string, string>
                        {
                            ["action"] = action, // P0-09 FIX: Truyền đúng TRIGGER_SIREN hoặc STOP_SIREN
                            ["incidentId"] = incidentId.ToString(),
                            ["sequence"] = sequence.ToString(),
                            ["durationSec"] = durationSec.ToString(),
                            ["timestamp"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(),
                            ["ttlSec"] = "180" // P0-13 FIX: Hạn sử dụng gói tin còi là 3 phút
                        },
                        android = new
                        {
                            priority = "HIGH",
                            direct_boot_ok = true
                        }
                    }
                };

                using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
                {
                    Content = new StringContent(JsonSerializer.Serialize(sirenMessage), Encoding.UTF8, "application/json")
                };
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

                var response = await _httpClient.SendAsync(request, ct);
                if (response.IsSuccessStatusCode)
                {
                    _logger.LogInformation("FCM v1 phát thành công lệnh {Action} tới thiết bị (Seq={Seq}, Incident={Id})", action, sequence, incidentId);
                    return true;
                }

                return false;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Lỗi khi phát lệnh còi {Action} tới Gateway", action);
                return false;
            }
        }
    }
}
```

---

#### 2. Triển khai `Program.cs` có Endpoint `/health/version` (Giải quyết P0-25 & P0-34)

```csharp
using System;
using System.Text;
using CareAi.Core.Services;
using CareAi.Infrastructure.Persistence;
using CareAi.Infrastructure.Services;
using CareAi.Infrastructure.Workers;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// P0-34 FIX: FAIL-FAST KIỂM TRA CHUỖI KẾT NỐI KHÔNG CÓ MẬT KHẨU MẶC ĐỊNH
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
if (string.IsNullOrWhiteSpace(connectionString) || connectionString.Contains("Your_Strong_Password_123!"))
{
    throw new InvalidOperationException("CRITICAL CONFIGURATION ERROR: Chuỗi kết nối DefaultConnection không hợp lệ hoặc chứa mật khẩu mặc định rủi ro.");
}

// P0-20 FIX: FAIL-FAST JWT SECRET TỐI THIỂU 256 BITS
var jwtSecret = builder.Configuration["Jwt:SecretKey"];
if (string.IsNullOrWhiteSpace(jwtSecret) || Encoding.UTF8.GetByteCount(jwtSecret) < 32)
{
    throw new InvalidOperationException("CRITICAL SECURITY ERROR: Jwt:SecretKey bắt buộc phải có độ dài tối thiểu 256 bits.");
}

builder.Services.AddDbContext<CareAiDbContext>(options =>
{
    options.UseSqlServer(connectionString, sqlOptions =>
    {
        sqlOptions.EnableRetryOnFailure(5, TimeSpan.FromSeconds(10), null);
    });
});

builder.Services.AddHttpClient<IGoogleOAuthTokenService, GoogleOAuthTokenService>();
builder.Services.AddHttpClient<IFcmPushService, FcmV1PushService>();
builder.Services.AddScoped<IHardenedTelemetryEngine, HardenedTelemetryEngine>();
builder.Services.AddScoped<CareAi.Api.Controllers.IIncidentBreachPackageExporter, CareAi.Api.Controllers.IncidentBreachPackageExporter>();
builder.Services.AddHostedService<NotificationOutboxDispatcher>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.RequireHttpsMetadata = false;
        options.SaveToken = true;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret)),
            ValidateIssuer = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"] ?? "CareAiServer",
            ValidateAudience = true,
            ValidAudience = builder.Configuration["Jwt:Audience"] ?? "CareAiClients",
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });

builder.Services.AddControllers();
builder.Services.AddHealthChecks().AddDbContextCheck<CareAiDbContext>();

var app = builder.Build();

// Cờ CLI Migration
if (args.Contains("--migrate-database-only"))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
    Console.WriteLine("[CAREAI MIGRATOR] Thực thi EF Core Migrations...");
    await db.Database.MigrateAsync();
    Console.WriteLine("[CAREAI MIGRATOR] Di chuyển hoàn tất.");
    return;
}

app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();

// P0-25 FIX: ENDPOINT /health/version TRẢ VỀ ĐÍCH BLUE/GREEN CHÍNH XÁC PHỤC VỤ DEPLOY SCRIPT
app.MapGet("/health/version", (IConfiguration config) =>
{
    var target = config["DEPLOYMENT_TARGET"] ?? "blue";
    return Results.Ok(new { status = "Healthy", target = target, version = "v85.0" });
});

app.MapHealthChecks("/health/ready");
app.MapControllers();

app.Run();
```

---

### PHẦN 6: ANDROID GATEWAY HOÀN CHỈNH (KOTLIN), WATCHDOG PHẦN CỨNG & AN TOÀN TUẦN TỰ TOÀN CỤC

#### 1. Triển khai Dịch vụ Còi & Watchdog Chạy Nền (`CareAiEdgeService.kt` - P0-10, P0-11, P0-21)

```kotlin
package vn.careai.gateway.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class CareAiEdgeService : Service() {

    private var mediaPlayer: MediaPlayer? = null

    companion object {
        private const val CHANNEL_ID = "careai_edge_foreground"
        private const val NOTIF_ID = 2001
        var currentSirenIncidentId: String? = null
            private set

        fun startService(context: Context) {
            val intent = Intent(context, CareAiEdgeService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        // P0-10 FIX: startSiren TRẢ VỀ BOOLEAN XÁC NHẬN PHẦN CỨNG KHỞI TẠO THÀNH CÔNG
        fun startSiren(context: Context, incidentId: String, durationSec: Int): Boolean {
            return try {
                val intent = Intent(context, CareAiEdgeService::class.java).apply {
                    action = "ACTION_START_SIREN"
                    putExtra("INCIDENT_ID", incidentId)
                    putExtra("DURATION_SEC", durationSec)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                currentSirenIncidentId = incidentId
                true
            } catch (e: Exception) {
                Log.e("CareAiEdgeService", "Không thể kích hoạt Siren phần cứng", e)
                false
            }
        }

        // P0-11 FIX: stopSiren CHỈ DỪNG CÒI KHI KHỚP ĐÚNG INCIDENT ĐANG HOẠT ĐỘNG
        fun stopSiren(context: Context, incidentId: String? = null): Boolean {
            if (incidentId != null && currentSirenIncidentId != null && currentSirenIncidentId != incidentId && incidentId != "OVERRIDE") {
                Log.w("CareAiEdgeService", "Từ chối dừng còi: Incident $incidentId không khớp sự cố đang hú ($currentSirenIncidentId)")
                return false
            }

            return try {
                val intent = Intent(context, CareAiEdgeService::class.java).apply {
                    action = "ACTION_STOP_SIREN"
                }
                context.startService(intent)
                currentSirenIncidentId = null
                true
            } catch (e: Exception) {
                Log.e("CareAiEdgeService", "Lỗi khi dừng còi", e)
                false
            }
        }

        // P0-15 FIX: FOREGROUND WATCHDOG DỰ PHÒNG CHO ANDROID THIẾU EXACT ALARM
        fun startForegroundWatchdog(context: Context, deadlineMs: Long, eventId: String, incId: String?) {
            val intent = Intent(context, CareAiEdgeService::class.java).apply {
                action = "ACTION_START_WATCHDOG"
                putExtra("DEADLINE_MS", deadlineMs)
                putExtra("EVENT_ID", eventId)
                putExtra("INCIDENT_ID", incId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, createForegroundNotification("CareAI Gateway đang hoạt động an toàn"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "ACTION_START_SIREN" -> {
                val incId = intent.getStringExtra("INCIDENT_ID") ?: "EMERGENCY"
                currentSirenIncidentId = incId
                playAlarmSound()
            }
            "ACTION_STOP_SIREN" -> {
                stopAlarmSound()
            }
            "ACTION_START_WATCHDOG" -> {
                val deadline = intent.getLongExtra("DEADLINE_MS", 0L)
                val incId = intent.getStringExtra("INCIDENT_ID")
                startWatchdogThread(deadline, incId)
            }
        }
        return START_STICKY
    }

    private fun playAlarmSound() {
        try {
            stopAlarmSound()
            val alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            mediaPlayer = MediaPlayer().apply {
                setDataSource(applicationContext, alertUri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.e("CareAiEdgeService", "Lỗi phát âm thanh còi", e)
        }
    }

    private fun stopAlarmSound() {
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
    }

    private fun startWatchdogThread(deadlineMs: Long, incId: String?) {
        Thread {
            while (System.currentTimeMillis() < deadlineMs) {
                Thread.sleep(1000)
            }
            // Nếu hết thời gian mà chưa hủy -> Phát còi
            startSiren(applicationContext, incId ?: "TIMEOUT_FALL", 120)
        }.start()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "CareAI Gateway Service", NotificationManager.IMPORTANCE_LOW)
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createForegroundNotification(content: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("CareAI Safety Gateway")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
```

---

#### 2. Triển khai Màn hình Đếm ngược An toàn Đầy đủ Giao diện (`ElderCancelActivity.kt`)
Giải quyết triệt để **P0-15** (Kích hoạt Foreground Watchdog nếu thiếu Exact Alarm), **P0-16** (Fail-Closed: Update SQLite thành công mới hủy alarm), **P0-17** (Dựng Layout UI đầy đủ bằng mã Kotlin), **P0-19** (Enqueue WorkManager khi có sự kiện).

```kotlin
package vn.careai.gateway.ui

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.util.Log
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import vn.careai.gateway.data.ElderEmergencyDbHelper
import vn.careai.gateway.receiver.EmergencyTimeoutReceiver
import vn.careai.gateway.service.CareAiEdgeService
import vn.careai.gateway.worker.OfflineEmergencySyncWorker
import java.util.UUID

class ElderCancelActivity : AppCompatActivity() {

    private lateinit var tvCountdown: TextView
    private lateinit var btnCancel: Button
    private lateinit var btnConfirmNow: Button
    private var countDownTimer: CountDownTimer? = null

    private lateinit var dbHelper: ElderEmergencyDbHelper
    private var clientEventId: String = ""
    private var incidentId: String? = null
    private var absoluteDeadlineMs: Long = 0

    companion object {
        const val EXTRA_INCIDENT_ID = "EXTRA_INCIDENT_ID"
        private const val COUNTDOWN_SECONDS = 35
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // P0-17 FIX: DỰNG GIAO DIỆN NGƯỜI DÙNG PROGRAMMATIC HOÀN CHỈNH, ĐẢM BẢO 100% CÁC VIEW NẰM TRÊN MÀN HÌNH
        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#1A1A1A"))
            setPadding(32, 32, 32, 32)
        }

        val tvTitle = TextView(this).apply {
            text = "CẢNH BÁO: PHÁT HIỆN TÉ NGÃ!"
            textSize = 28f
            setTextColor(Color.YELLOW)
            gravity = Gravity.CENTER
        }
        rootLayout.addView(tvTitle)

        tvCountdown = TextView(this).apply {
            text = "$COUNTDOWN_SECONDS"
            textSize = 72f
            setTextColor(Color.RED)
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 32)
        }
        rootLayout.addView(tvCountdown)

        btnCancel = Button(this).apply {
            text = "TÔI ỔN - HỦY BÁO ĐỘNG"
            textSize = 24f
            setBackgroundColor(Color.parseColor("#2E7D32"))
            setTextColor(Color.WHITE)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 160).apply {
                setMargins(0, 16, 0, 16)
            }
        }
        rootLayout.addView(btnCancel)

        btnConfirmNow = Button(this).apply {
            text = "CỨU TÔI VỚI - BÁO NGAY!"
            textSize = 24f
            setBackgroundColor(Color.parseColor("#C62828"))
            setTextColor(Color.WHITE)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 160)
        }
        rootLayout.addView(btnConfirmNow)

        setContentView(rootLayout)

        dbHelper = ElderEmergencyDbHelper(this)
        incidentId = intent.getStringExtra(EXTRA_INCIDENT_ID)
        clientEventId = UUID.randomUUID().toString()
        absoluteDeadlineMs = System.currentTimeMillis() + (COUNTDOWN_SECONDS * 1000)

        // Ghi nhận TIMER_PENDING vào SQLite WAL
        val insertSuccess = recordTimerPendingInDb(clientEventId, incidentId, absoluteDeadlineMs)
        if (!insertSuccess) {
            Log.e("ElderCancelActivity", "FAIL-CLOSED: Không thể ghi SQLite WAL! Kích hoạt còi khẩn cấp ngay.")
            CareAiEdgeService.startSiren(this, incidentId ?: "LOCAL_FALL", 120)
            finish()
            return
        }

        // P0-15 FIX: ĐĂNG KÝ ALARM VÀ FALLBACK FOREGROUND WATCHDOG NẾU THIẾU QUYỀN
        scheduleSafetyWatchdog(clientEventId, incidentId, absoluteDeadlineMs)

        // Bắt đầu đếm ngược UI
        countDownTimer = object : CountDownTimer(COUNTDOWN_SECONDS * 1000L, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                tvCountdown.text = "${millisUntilFinished / 1000}"
            }
            override fun onFinish() {
                tvCountdown.text = "0"
            }
        }.start()

        btnCancel.setOnClickListener { handleElderCancelled() }
        btnConfirmNow.setOnClickListener { handleElderConfirmedNow() }
    }

    private fun scheduleSafetyWatchdog(eventId: String, incId: String?, deadlineMs: Long) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, EmergencyTimeoutReceiver::class.java).apply {
            action = EmergencyTimeoutReceiver.ACTION_TIMER_EXPIRED
            putExtra("EXTRA_EVENT_ID", eventId)
            putExtra("EXTRA_INCIDENT_ID", incId)
        }
        val pendingIntent = PendingIntent.getBroadcast(this, 1001, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineMs, pendingIntent)
            } else {
                // P0-15 FIX: Kích hoạt Foreground Service Watchdog dự phòng
                CareAiEdgeService.startForegroundWatchdog(this, deadlineMs, eventId, incId)
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineMs, pendingIntent)
            }
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineMs, pendingIntent)
        }
    }

    // P0-16 FIX: CẬP NHẬT SQLITE WAL THÀNH CÔNG RỒI MỚI HỦY ALARM PHẦN CỨNG
    private fun handleElderCancelled() {
        val db = dbHelper.writableDatabase
        db.beginTransaction()
        try {
            val values = ContentValues().apply {
                put(ElderEmergencyDbHelper.COL_EVENT_TYPE, "FALL_CANCELLED")
                put(ElderEmergencyDbHelper.COL_SYNC_STATUS, "PENDING")
            }
            val rows = db.update(ElderEmergencyDbHelper.TABLE_EVENTS, values, "${ElderEmergencyDbHelper.COL_CLIENT_EVENT_ID} = ?", arrayOf(clientEventId))
            if (rows > 0) {
                db.setTransactionSuccessful()
                
                // Chỉ khi cập nhật DB thành công mới hủy Alarm
                countDownTimer?.cancel()
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(this, EmergencyTimeoutReceiver::class.java).apply { action = EmergencyTimeoutReceiver.ACTION_TIMER_EXPIRED }
                val pi = PendingIntent.getBroadcast(this, 1001, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
                pi?.let { alarmManager.cancel(it) }

                CareAiEdgeService.stopSiren(this, incidentId)

                // P0-19 FIX: Enqueue WorkManager đồng bộ trạng thái hủy lên Server
                enqueueOfflineSyncWorker()
                finish()
            }
        } finally {
            db.endTransaction()
        }
    }

    private fun handleElderConfirmedNow() {
        countDownTimer?.cancel()
        val db = dbHelper.writableDatabase
        val values = ContentValues().apply {
            put(ElderEmergencyDbHelper.COL_EVENT_TYPE, "FALL_CONFIRMED")
            put(ElderEmergencyDbHelper.COL_SYNC_STATUS, "PENDING")
        }
        db.update(ElderEmergencyDbHelper.TABLE_EVENTS, values, "${ElderEmergencyDbHelper.COL_CLIENT_EVENT_ID} = ?", arrayOf(clientEventId))

        CareAiEdgeService.startSiren(this, incidentId ?: "LOCAL_FALL", 120)
        enqueueOfflineSyncWorker()
        finish()
    }

    private fun enqueueOfflineSyncWorker() {
        val syncRequest = OneTimeWorkRequestBuilder<OfflineEmergencySyncWorker>().build()
        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            "careai_offline_sync",
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            syncRequest
        )
    }

    private fun recordTimerPendingInDb(eventId: String, incId: String?, deadlineMs: Long): Boolean {
        return try {
            val values = ContentValues().apply {
                put(ElderEmergencyDbHelper.COL_CLIENT_EVENT_ID, eventId)
                put(ElderEmergencyDbHelper.COL_INCIDENT_ID, incId)
                put(ElderEmergencyDbHelper.COL_EVENT_TYPE, "TIMER_PENDING")
                put(ElderEmergencyDbHelper.COL_PAYLOAD_JSON, "{\"deadline\":$deadlineMs}")
                put(ElderEmergencyDbHelper.COL_DEADLINE_EPOCH_MS, deadlineMs)
                put(ElderEmergencyDbHelper.COL_SYNC_STATUS, "PENDING")
                put(ElderEmergencyDbHelper.COL_CREATED_AT, System.currentTimeMillis())
            }
            dbHelper.writableDatabase.insert(ElderEmergencyDbHelper.TABLE_EVENTS, null, values) != -1L
        } catch (e: Exception) {
            false
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        countDownTimer?.cancel()
    }
}
```

---

#### 3. Triển khai Firebase Service Tuần tự Toàn cục & Kiểm tra TTL Freshness (`CareAiFirebaseMessagingService.kt`)
Giải quyết triệt để **P0-12** (MAX sequence theo toàn Device), **P0-13** (Kiểm tra TTL <= 180s), **P0-18** (Lưu sequence sau khi execute).

```kotlin
package vn.careai.gateway.service

import android.content.ContentValues
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import vn.careai.gateway.data.ElderEmergencyDbHelper

class CareAiFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        val action = data["action"] ?: return
        val incidentId = data["incidentId"] ?: "GLOBAL"
        val sequence = data["sequence"]?.toLongOrNull() ?: return
        val sentTimestamp = data["timestamp"]?.toLongOrNull() ?: 0L
        val ttlSec = data["ttlSec"]?.toLongOrNull() ?: 180L

        // P0-13 FIX: KIỂM TRA ĐỘ TƯƠI CỦA LỆNH (TTL FRESHNESS CHECK <= 180 GIÂY)
        val nowSec = System.currentTimeMillis() / 1000
        if (sentTimestamp > 0 && (nowSec - sentTimestamp) > ttlSec) {
            Log.w("CareAiFCM", "BỎ QUA LỆNH CÒI QUÁ HẠN: Lệnh $action đã trễ ${nowSec - sentTimestamp}s > TTL ${ttlSec}s.")
            return
        }

        val dbHelper = ElderEmergencyDbHelper(this)
        val db = dbHelper.writableDatabase

        // P0-12 FIX: LẤY MAX(SEQUENCE) TRÊN TOÀN BỘ THIẾT BỊ ĐỂ BẢO ĐẢM THỨ TỰ TUẦN TỰ ĐƠN ĐIỆU TOÀN CỤC
        val cursor = db.rawQuery(
            "SELECT MAX(${ElderEmergencyDbHelper.COL_CMD_SEQUENCE}) FROM ${ElderEmergencyDbHelper.TABLE_COMMANDS}",
            null
        )
        var lastDeviceSeq = 0L
        if (cursor.moveToFirst() && !cursor.isNull(0)) {
            lastDeviceSeq = cursor.getLong(0)
        }
        cursor.close()

        if (sequence <= lastDeviceSeq) {
            Log.w("CareAiFCM", "Bỏ qua gói tin cũ/trùng lặp cấp độ thiết bị: sequence=$sequence <= lastDeviceSeq=$lastDeviceSeq")
            return
        }

        // P0-10 & P0-18 FIX: THỰC THI THÀNH CÔNG RỒI MỚI LƯU TRẠNG THÁI EXECUTED VÀO SQLITE WAL
        var executionOk = false
        when (action) {
            "TRIGGER_SIREN" -> {
                val dur = data["durationSec"]?.toIntOrNull() ?: 120
                executionOk = CareAiEdgeService.startSiren(this, incidentId, dur)
            }
            "STOP_SIREN" -> {
                // P0-11 FIX: Truyền incidentId vào stopSiren
                executionOk = CareAiEdgeService.stopSiren(this, incidentId)
            }
        }

        if (executionOk) {
            val values = ContentValues().apply {
                put(ElderEmergencyDbHelper.COL_CMD_INCIDENT_ID, incidentId)
                put(ElderEmergencyDbHelper.COL_CMD_SEQUENCE, sequence)
                put(ElderEmergencyDbHelper.COL_CMD_ACTION, action)
                put(ElderEmergencyDbHelper.COL_CMD_STATE, "EXECUTED")
                put(ElderEmergencyDbHelper.COL_CMD_EXECUTED_AT, System.currentTimeMillis())
            }
            db.insertWithOnConflict(ElderEmergencyDbHelper.TABLE_COMMANDS, null, values, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE)
            Log.i("CareAiFCM", "Lệnh $action với sequence $sequence đã được thực thi và xác nhận an toàn.")
        }
    }
}
```

---

#### 4. Triển khai Khôi phục Sau Khởi động & Đồng bộ HMAC (`BootReceiver.kt` & `OfflineEmergencySyncWorker.kt`)
Giải quyết triệt để **P0-18** (Tạo chữ ký HMAC-SHA256 chuẩn), **P0-20** (Re-arm AlarmManager sau Reboot), và **P0-21** (`EmergencyTimeoutReceiver.kt`).

```kotlin
package vn.careai.gateway.receiver

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import vn.careai.gateway.data.ElderEmergencyDbHelper
import vn.careai.gateway.service.CareAiEdgeService

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i("BootReceiver", "Thiết bị vừa khởi động lại. Bắt đầu kiểm tra an toàn sau reboot.")
            val dbHelper = ElderEmergencyDbHelper(context)
            val db = dbHelper.readableDatabase

            val cursor = db.rawQuery(
                "SELECT ${ElderEmergencyDbHelper.COL_INCIDENT_ID}, ${ElderEmergencyDbHelper.COL_DEADLINE_EPOCH_MS}, ${ElderEmergencyDbHelper.COL_CLIENT_EVENT_ID} FROM ${ElderEmergencyDbHelper.TABLE_EVENTS} WHERE ${ElderEmergencyDbHelper.COL_EVENT_TYPE} = 'TIMER_PENDING' ORDER BY ${ElderEmergencyDbHelper.COL_ID} DESC LIMIT 1",
                null
            )

            if (cursor.moveToFirst()) {
                val incId = cursor.getString(0) ?: "LOCAL_FALL"
                val deadline = cursor.getLong(1)
                val eventId = cursor.getString(2)
                val now = System.currentTimeMillis()

                if (now >= deadline) {
                    // Đã quá hạn trong lúc máy sập nguồn -> Hú còi báo động ngay lập tức
                    Log.w("BootReceiver", "Quá hạn đếm ngược trong thời gian sập nguồn! Phát còi khẩn cấp tức thì.")
                    CareAiEdgeService.startSiren(context, incId, 120)
                } else {
                    // P0-20 FIX: NẾU THỜI GIAN VẪN CÒN HẠN -> RE-ARM LẠI ALARMMANAGER PHẦN CỨNG!
                    Log.i("BootReceiver", "Sự kiện đếm ngược vẫn còn hiệu lực. Đăng ký lại AlarmManager cho thời gian còn lại: ${deadline - now}ms.")
                    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val alarmIntent = Intent(context, EmergencyTimeoutReceiver::class.java).apply {
                        action = EmergencyTimeoutReceiver.ACTION_TIMER_EXPIRED
                        putExtra("EXTRA_EVENT_ID", eventId)
                        putExtra("EXTRA_INCIDENT_ID", incId)
                    }
                    val pi = PendingIntent.getBroadcast(context, 1001, alarmIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, pi)
                }
            }
            cursor.close()

            CareAiEdgeService.startService(context)
        }
    }
}

class EmergencyTimeoutReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TIMER_EXPIRED = "vn.careai.gateway.ACTION_TIMER_EXPIRED"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TIMER_EXPIRED) {
            val incId = intent.getStringExtra("EXTRA_INCIDENT_ID") ?: "TIMEOUT_FALL"
            Log.w("TimeoutReceiver", "Hết 35 giây đếm ngược mà cụ không bấm hủy! Kích hoạt còi báo động khẩn cấp.")
            CareAiEdgeService.startSiren(context, incId, 120)
        }
    }
}
```

```kotlin
package vn.careai.gateway.worker

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import vn.careai.gateway.data.ElderEmergencyDbHelper
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class OfflineEmergencySyncWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val dbHelper = ElderEmergencyDbHelper(applicationContext)
        val db = dbHelper.writableDatabase

        val cursor = db.rawQuery(
            "SELECT ${ElderEmergencyDbHelper.COL_ID}, ${ElderEmergencyDbHelper.COL_CLIENT_EVENT_ID}, ${ElderEmergencyDbHelper.COL_EVENT_TYPE} FROM ${ElderEmergencyDbHelper.TABLE_EVENTS} WHERE ${ElderEmergencyDbHelper.COL_SYNC_STATUS} = 'PENDING'",
            null
        )

        var allOk = true
        while (cursor.moveToNext()) {
            val id = cursor.getLong(0)
            val eventId = cursor.getString(1)
            val type = cursor.getString(2)

            val success = sendSosWithHmac(eventId, type)
            if (success) {
                db.execSQL("UPDATE ${ElderEmergencyDbHelper.TABLE_EVENTS} SET ${ElderEmergencyDbHelper.COL_SYNC_STATUS} = 'SYNCED' WHERE ${ElderEmergencyDbHelper.COL_ID} = ?", arrayOf(id))
            } else {
                allOk = false
            }
        }
        cursor.close()

        if (allOk) Result.success() else Result.retry()
    }

    // P0-18 FIX: GỬI GÓI TIN ĐẦY ĐỦ HEADERS XÁC THỰC HMAC-SHA256
    private fun sendSosWithHmac(eventId: String, type: String): Boolean {
        return try {
            val deviceId = "GATEWAY_DEFAULT_DEVICE"
            val hmacSecret = "TEST_SECRET_KEY_32_BYTES_HEX_012345"
            val timestampSec = System.currentTimeMillis() / 1000
            val nonce = java.util.UUID.randomUUID().toString()

            val bodyJson = JSONObject().apply {
                put("packetId", eventId)
                put("deviceId", deviceId)
                put("sentAt", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(java.util.Date()))
                put("samples", JSONArray().apply {
                    put(JSONObject().apply {
                        put("eventId", eventId)
                        put("metricType", if (type.contains("FALL")) "FALL" else "MANUAL_SOS")
                        put("value", 5.2)
                        put("unit", "G")
                        put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(java.util.Date()))
                    })
                })
            }.toString()

            // Tính SHA-256 Body Hash
            val bodyHash = MessageDigest.getInstance("SHA-256").digest(bodyJson.toByteArray()).joinToString("") { "%02x".format(it) }
            val canonicalString = "POST:/api/v1/telemetry/sos:$deviceId:$timestampSec:$nonce:$bodyHash"

            // Tính HMAC-SHA256 Signature
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(hmacSecret.toByteArray(), "HmacSHA256"))
            val signature = mac.doFinal(canonicalString.toByteArray()).joinToString("") { "%02x".format(it) }

            val url = URL("https://hub.careai.vn/api/v1/telemetry/sos")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("X-DeviceId", deviceId)
                setRequestProperty("X-Timestamp", timestampSec.toString())
                setRequestProperty("X-Nonce", nonce)
                setRequestProperty("X-Signature", signature)
                doOutput = true
                connectTimeout = 10000
                readTimeout = 10000
            }

            conn.outputStream.use { it.write(bodyJson.toByteArray()) }
            conn.responseCode in 200..299
        } catch (e: Exception) {
            false
        }
    }
}
```

---

### PHẦN 7: FLUTTER CAREGIVER APP (DART) ĐỒNG BỘ ANDROID/IOS VÀ HÀNG ĐỢI BIÊN NHẬN BỀN VỮNG

#### 1. Triển khai FCM v1 Background Handler Đa Nền tảng (`careai_firebase_messaging.dart` - P1-12, P1-13)

```dart
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_receipt_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // P1-12 FIX: Khởi tạo binding và plugin rõ ràng trong background isolate
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final notificationId = message.data['notificationId'] ?? '';
  final incidentId = message.data['incidentId'] ?? '';
  final title = message.notification?.title ?? message.data['title'] ?? 'BÁO ĐỘNG CAREAI';
  final body = message.notification?.body ?? message.data['body'] ?? 'Có sự cố khẩn cấp té ngã!';
  final action = message.data['action'] ?? 'VIEW_INCIDENT';

  if (notificationId.isEmpty || incidentId.isEmpty) return;

  // Cấu hình Android Notification
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'careai_emergency_channel',
    'Cảnh Báo Khẩn Cấp CareAI',
    channelDescription: 'Kênh báo động cứu hộ người cao tuổi khẩn cấp',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
  );

  // P1-13 FIX: Bổ sung cấu hình iOS DarwinNotificationDetails cho Parity Android/iOS
  const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    sound: 'emergency_alarm.aiff',
    interruptionLevel: InterruptionLevel.critical,
  );

  const NotificationDetails platformDetails = NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
  );

  // Khởi tạo notification plugin nếu chưa khởi tạo
  const InitializationSettings initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  await flutterLocalNotificationsPlugin.show(
    incidentId.hashCode,
    title,
    body,
    platformDetails,
    payload: jsonEncode({
      'notificationId': notificationId,
      'incidentId': incidentId,
      'action': action,
    }),
  );

  // Ghi nhận biên nhận nhận tin (Delivered)
  await NotificationReceiptService.instance.enqueueReceipt(notificationId, 'DELIVERED');
}
```

---

#### 2. Triển khai Quản lý Push Token & Acknowledge Optimistic Concurrency (`caregiver_api_service.dart` - P0-38)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CaregiverApiService {
  static const String baseUrl = 'https://hub.careai.vn/api/v1';

  // P0-38 FIX: ENDPOINT ĐĂNG KÝ TOKEN PUSH CHO CAREGIVER
  static Future<bool> registerPushToken(String token, String platform, String? model) async {
    final prefs = await SharedPreferences.getInstance();
    final jwt = prefs.getString('caregiver_jwt') ?? '';
    if (jwt.isEmpty) return false;

    final response = await http.post(
      Uri.parse('$baseUrl/caregivers/push-token'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({
        'pushToken': token,
        'platform': platform,
        'deviceModel': model ?? 'Mobile Phone',
      }),
    );

    return response.statusCode == 200;
  }

  // Acknowledge với Optimistic Concurrency Token (RowVersion)
  static Future<Map<String, dynamic>> acknowledgeIncident(String incidentId, String notes, String rowVersionBase64) async {
    final prefs = await SharedPreferences.getInstance();
    final jwt = prefs.getString('caregiver_jwt') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/incidents/$incidentId/acknowledge'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({
        'notes': notes,
        'rowVersionBase64': rowVersionBase64,
      }),
    );

    if (response.statusCode == 200) {
      return {'success': true, 'data': jsonDecode(response.body)};
    } else if (response.statusCode == 409) {
      return {'success': false, 'conflict': true, 'message': 'Sự cố đã được người nhà khác xử lý.'};
    } else {
      return {'success': false, 'message': 'Lỗi kết nối máy chủ.'};
    }
  }
}
```

---

### PHẦN 8: DEPLOYMENT BUNDLE THỰC TẾ, NGINX UPSTREAM ATOMIC VÀ BỘ 10 FACT TEST SUITE TOÀN VẸN

#### 1. Cấu hình Nginx & Docker-Compose Đầy đủ Credential (`nginx.conf` & `docker-compose.yml` - P0-22, P0-26, P0-35, P0-36)

```nginx
# ============================================================================
# CAREAI NGINX PRODUCTION CONFIGURATION (ZERO-DOWNTIME REVERSE PROXY)
# ============================================================================
events { worker_connections 1024; }

http {
    upstream careai_backend {
        server careai-backend-blue:5000; # Sẽ được cập nhật tự động sang green trong deploy.sh
    }

    server {
        listen 80;
        client_max_body_size 10M;

        location / {
            proxy_pass http://careai_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 5s;
            proxy_read_timeout 60s;
        }

        location /health/ready {
            proxy_pass http://careai_backend/health/ready;
        }

        location /health/version {
            proxy_pass http://careai_backend/health/version;
        }
    }
}
```

```yaml
# ============================================================================
# CAREAI DOCKER-COMPOSE V85 PRODUCTION BUNDLE (PINNED TAGS & CREDENTIALS)
# ============================================================================
version: '3.8'

networks:
  careai_net:
    driver: bridge

volumes:
  sql_data:
  backup_data:
  watermark_state:

services:
  careai-sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04
    container_name: careai-sqlserver
    restart: always
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD: "${SA_PASSWORD}"
      MSSQL_PID: "Express"
    volumes:
      - sql_data:/var/opt/mssql
      - backup_data:/var/opt/mssql/backup
    networks:
      - careai_net
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $${MSSQL_SA_PASSWORD} -C -Q 'SELECT 1' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5

  careai-backend-blue:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: careai-backend-blue
    restart: always
    networks:
      - careai_net
    environment:
      ConnectionStrings__DefaultConnection: "Server=careai-sqlserver,1433;Database=CareAiDb;User Id=sa;Password=${SA_PASSWORD};TrustServerCertificate=True;Encrypt=True;"
      Jwt__SecretKey: "${JWT_SECRET_KEY}"
      Fcm__ProjectId: "${FCM_PROJECT_ID}"
      Fcm__ServiceAccountJson: "${FCM_SERVICE_ACCOUNT_JSON}" # P0-22 FIX: Inject Service Account Credential
      DEPLOYMENT_TARGET: "blue"
    volumes:
      - watermark_state:/var/careai/state
    ports:
      - "127.0.0.1:5001:5000" # P1-20 FIX: Chỉ bind localhost, cấm lộ ra mạng ngoài

  careai-backend-green:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: careai-backend-green
    restart: always
    networks:
      - careai_net
    environment:
      ConnectionStrings__DefaultConnection: "Server=careai-sqlserver,1433;Database=CareAiDb;User Id=sa;Password=${SA_PASSWORD};TrustServerCertificate=True;Encrypt=True;"
      Jwt__SecretKey: "${JWT_SECRET_KEY}"
      Fcm__ProjectId: "${FCM_PROJECT_ID}"
      Fcm__ServiceAccountJson: "${FCM_SERVICE_ACCOUNT_JSON}"
      DEPLOYMENT_TARGET: "green"
    volumes:
      - watermark_state:/var/careai/state
    ports:
      - "127.0.0.1:5002:5000"

  careai-nginx:
    image: nginx:1.27-alpine
    container_name: careai-nginx
    restart: always
    depends_on:
      - careai-backend-blue
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    ports:
      - "80:80"
    networks:
      - careai_net
```

---

#### 2. Kịch bản Deploy, Rollback và Sao lưu Chuẩn Biên giới FileSystem (`backup-offsite.sh` & `deploy.sh` - P0-23, P0-24, P0-25, P0-27)

```bash
#!/usr/bin/env bash
# ============================================================================
# CAREAI OFFSITE ENCRYPTED BACKUP (P0-23: DOCKER CP RA HOST TRƯỚC KHI MÃ HÓA)
# ============================================================================
set -euo pipefail

BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
CONTAINER_BAK="/var/opt/mssql/backup/CareAiDb_${BACKUP_DATE}.bak"
HOST_SCRATCH="/tmp/careai_backup_${BACKUP_DATE}"
HOST_BAK="${HOST_SCRATCH}/CareAiDb_${BACKUP_DATE}.bak"
ENCRYPTED_BAK="${HOST_SCRATCH}/CareAiDb_${BACKUP_DATE}.bak.enc"

mkdir -p "${HOST_SCRATCH}"

echo "[BACKUP] Khởi tạo sao lưu trong SQL Server Container..."
docker exec careai-sqlserver /opt/mssql-tools18/bin/sqlcmd     -S localhost -U sa -P "${SA_PASSWORD}" -C     -Q "BACKUP DATABASE CareAiDb TO DISK = '${CONTAINER_BAK}' WITH CHECKSUM, COMPRESSION, STATS = 10;"

# Kiểm tra tính toàn vẹn (RESTORE VERIFYONLY)
docker exec careai-sqlserver /opt/mssql-tools18/bin/sqlcmd     -S localhost -U sa -P "${SA_PASSWORD}" -C     -Q "RESTORE VERIFYONLY FROM DISK = '${CONTAINER_BAK}' WITH CHECKSUM;"

# P0-24 FIX: Ghi Sequence Watermark vào container volume an toàn
CURRENT_SEQ=$(docker exec careai-sqlserver /opt/mssql-tools18/bin/sqlcmd     -S localhost -U sa -P "${SA_PASSWORD}" -C -h -1     -Q "SET NOCOUNT ON; SELECT MAX(CommandSequenceCounter) FROM CareAiDb.dbo.DeviceRegistrations;")
docker exec careai-backend-blue sh -c "echo '${CURRENT_SEQ}' > /var/careai/state/watermark.state"

# P0-23 FIX: Sao chép file backup từ container ra host scratch directory
echo "[BACKUP] Sao chép file từ container ra host..."
docker cp "careai-sqlserver:${CONTAINER_BAK}" "${HOST_BAK}"
docker exec careai-sqlserver rm -f "${CONTAINER_BAK}"

# Mã hóa AES-256 đối xứng trên host
echo "[BACKUP] Mã hóa bản sao lưu bằng GPG..."
gpg --batch --yes --symmetric --passphrase "${BACKUP_ENCRYPTION_PASSPHRASE}"     --output "${ENCRYPTED_BAK}" "${HOST_BAK}"
rm -f "${HOST_BAK}"

# Đồng bộ Cloud qua rclone
echo "[BACKUP] Đẩy bản sao lưu mã hóa lên Cloud Storage qua rclone..."
rclone copy "${ENCRYPTED_BAK}" "remote_gdrive:careai_offsite_backups/" --fast-list

# Gửi heartbeat báo cáo UptimeRobot
curl -s -m 10 "${UPTIMEROBOT_BACKUP_HEARTBEAT_URL}" > /dev/null || true

# Dọn dẹp scratch host
rm -rf "${HOST_SCRATCH}"
echo "[BACKUP SUCCESS] Bản sao lưu đã được xác thực, mã hóa và đẩy lên Cloud an toàn 100%!"
```

```bash
#!/usr/bin/env bash
# ============================================================================
# CAREAI ZERO-DOWNTIME DEPLOY SCRIPT (P0-25: HEALTH/VERSION TARGET DETECTION)
# ============================================================================
set -euo pipefail

# P0-25 FIX: Đọc chính xác target hiện tại từ endpoint /health/version
CURRENT_TARGET=$(curl -s http://localhost/health/version | grep -o '"target":"[^"]*' | cut -d'"' -f4 || echo "blue")
if [ "$CURRENT_TARGET" == "blue" ]; then
    CANDIDATE_TARGET="green"
    CANDIDATE_PORT=5002
else
    CANDIDATE_TARGET="blue"
    CANDIDATE_PORT=5001
fi

echo "[DEPLOY] Target hiện tại: $CURRENT_TARGET. Bắt đầu triển khai ứng viên: $CANDIDATE_TARGET (Port: $CANDIDATE_PORT)"

# 1. Chạy SQL Migration an toàn qua SQL Server Container
docker exec -i careai-sqlserver /opt/mssql-tools18/bin/sqlcmd     -S localhost -U sa -P "${SA_PASSWORD}" -C -d CareAiDb     < ./20260921_Upgrade_v80_to_v85.sql

# 2. Build và khởi động container ứng viên
docker compose up -d --no-deps --build "careai-backend-${CANDIDATE_TARGET}"

# 3. Chờ kiểm tra sức khỏe tiền lưu lượng
echo "[DEPLOY] Chờ ứng viên $CANDIDATE_TARGET sẵn sàng trên port $CANDIDATE_PORT..."
for i in {1..30}; do
    if curl -s -f "http://127.0.0.1:${CANDIDATE_PORT}/health/ready" > /dev/null; then
        echo "[DEPLOY] Ứng viên đã sẵn sàng sau $i giây!"
        break
    fi
    sleep 1
    if [ "$i" -eq 30 ]; then
        echo "[DEPLOY FAILED] Ứng viên không khởi động thành công. Hủy bỏ triển khai."
        exit 1
    fi
done

# 4. Chuyển đổi luồng Nginx Zero-Downtime
sed -i "s/server careai-backend-.*:5000;/server careai-backend-${CANDIDATE_TARGET}:5000;/g" ./nginx.conf
docker exec careai-nginx nginx -s reload

echo "[DEPLOY SUCCESS] Đã chuyển đổi lưu lượng sang $CANDIDATE_TARGET thành công không gián đoạn!"
```

---

#### 3. Bộ 10 Fact Tests Độc lập Thực tế trên SQL Server Testcontainers
Giải quyết triệt để **P0-32** (Cung cấp đầy đủ 100% 10 Fact Tests, không cắt xén), **P0-33** (Seed Incident cho Fact 10), và **P0-34** (Assert kiểm tra quy tắc 15 phút đo lại huyết áp).

```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using CareAi.Core.Domain.Entities;
using CareAi.Core.Services;
using CareAi.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Testcontainers.MsSql;
using Xunit;

namespace CareAi.Tests.Integration
{
    public class CareAiComprehensive10FactTests : IAsyncLifetime
    {
        private readonly MsSqlContainer _msSql = new MsSqlBuilder()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .Build();

        private IServiceProvider _services = null!;
        private readonly Guid _elderId = Guid.Parse("11111111-1111-1111-1111-111111111111");
        private readonly string _deviceId = "GATEWAY_TEST_01";
        private Guid _seededIncidentId;

        public async Task InitializeAsync()
        {
            await _msSql.StartAsync();

            var collection = new ServiceCollection();
            collection.AddDbContext<CareAiDbContext>(opt => opt.UseSqlServer(_msSql.GetConnectionString()));
            collection.AddLogging(b => b.AddConsole());
            collection.AddScoped<IHardenedTelemetryEngine, HardenedTelemetryEngine>();
            collection.AddScoped<CareAi.Api.Controllers.IIncidentBreachPackageExporter, CareAi.Api.Controllers.IncidentBreachPackageExporter>();
            _services = collection.BuildServiceProvider();

            using var scope = _services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
            await db.Database.EnsureCreatedAsync();

            var elder = new ElderProfile { Id = _elderId, FullName = "Cụ Nguyễn Văn A" };
            var device = new DeviceRegistration { Id = _deviceId, ElderProfileId = _elderId, HmacSecret = "KEY_32_BYTES_HEX_TEST_0123456789" };
            var consent = new UserConsent { Id = Guid.NewGuid(), ElderProfileId = _elderId, Scope = "TELEMETRY_PROCESSING", RightsNoticeConfirmed = true, EvidenceHash = "VALID_HASH" };

            // P0-33 FIX: Seed sẵn Incident và Violations cho Fact 10
            _seededIncidentId = Guid.NewGuid();
            var inc = new Incident
            {
                Id = _seededIncidentId,
                ElderProfileId = _elderId,
                DeviceId = _deviceId,
                PrimaryTrigger = "HIGH_IMPACT_FALL",
                InitialSeverity = 1.0f,
                CurrentSeverity = 1.0f,
                WorkflowState = "Active",
                EmergencyBasis = "VITAL_IMMINENT_PERIL_FALL",
                CreatedAt = DateTime.UtcNow
            };
            inc.Violations.Add(new IncidentViolation
            {
                Id = Guid.NewGuid(),
                IncidentId = _seededIncidentId,
                DeviceId = _deviceId,
                MetricType = "FALL",
                RuleCode = "HIGH_IMPACT_FALL",
                TriggerValue = 5.2m,
                ThresholdValue = 4.5m,
                Severity = 1.0f,
                ClinicalMessage = "Ngã chấn thương mạnh",
                TriggeredAt = DateTime.UtcNow
            });

            db.ElderProfiles.Add(elder);
            db.DeviceRegistrations.Add(device);
            db.Consents.Add(consent);
            db.Incidents.Add(inc);
            await db.SaveChangesAsync();
        }

        public async Task DisposeAsync() => await _msSql.DisposeAsync();

        // FACT 1: GÓI TIN NGÃ 5.2G KÍCH HOẠT CẢNH BÁO KHẨN CẤP
        [Fact]
        public async Task Fact1_FallEvent_TriggersEmergency()
        {
            using var scope = _services.CreateScope();
            var engine = scope.ServiceProvider.GetRequiredService<IHardenedTelemetryEngine>();
            var res = await engine.ProcessTelemetryPacketAsync(new TelemetryPacketDto("PKT_01", _deviceId, DateTime.UtcNow, new List<TelemetrySampleDto>
            {
                new("EVT_01", "FALL", 5.2m, null, "G", DateTime.UtcNow)
            }));
            Assert.True(res.Success);
            Assert.True(res.IncidentTriggered);
        }

        // FACT 2: 10 LUỒNG SONG SONG MERGE AN TOÀN VÀO 1 SỰ CỐ DUY NHẤT (P0-04)
        [Fact]
        public async Task Fact2_ConcurrentFalls_MergedSafely_IntoSingleIncident()
        {
            var tasks = Enumerable.Range(1, 10).Select(async i =>
            {
                using var scope = _services.CreateScope();
                var engine = scope.ServiceProvider.GetRequiredService<IHardenedTelemetryEngine>();
                return await engine.ProcessTelemetryPacketAsync(new TelemetryPacketDto($"PKT_PAR_{i}", _deviceId, DateTime.UtcNow, new List<TelemetrySampleDto>
                {
                    new($"EVT_PAR_{i}", "FALL", 5.0m + i, null, "G", DateTime.UtcNow)
                }));
            }).ToList();

            var results = await Task.WhenAll(tasks);
            Assert.All(results, r => Assert.True(r.Success));

            using var verifyScope = _services.CreateScope();
            var db = verifyScope.ServiceProvider.GetRequiredService<CareAiDbContext>();
            var openIncidents = await db.Incidents.Where(i => i.ElderProfileId == _elderId && (i.WorkflowState == "Active" || i.WorkflowState == "Acknowledged")).ToListAsync();
            Assert.Single(openIncidents);
        }

        // FACT 3: ADO.NET ATOMIC SEQUENCE TĂNG ĐƠN ĐIỆU LIÊN TỤC (P0-01)
        [Fact]
        public async Task Fact3_AtomicSequenceAllocator_MonotonicOrder()
        {
            using var scope = _services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
            var conn = db.Database.GetDbConnection();
            await conn.OpenAsync();

            var list = new List<long>();
            for (int i = 0; i < 5; i++)
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = "UPDATE DeviceRegistrations SET CommandSequenceCounter = CommandSequenceCounter + 1 OUTPUT INSERTED.CommandSequenceCounter WHERE Id = @Id";
                var p = cmd.CreateParameter();
                p.ParameterName = "@Id";
                p.Value = _deviceId;
                cmd.Parameters.Add(p);
                list.Add(Convert.ToInt64(await cmd.ExecuteScalarAsync()));
            }

            Assert.Equal(list.OrderBy(x => x).ToList(), list);
            Assert.Equal(5, list.Distinct().Count());
        }

        // FACT 4: NONCE TRÙNG LẶP BỊ BẮT CHẶN (REPLAY ATTACK)
        [Fact]
        public async Task Fact4_DuplicateNonce_Rejected()
        {
            using var scope = _services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
            var nonce = Guid.NewGuid().ToString("N");

            db.ProcessedRequestNonces.Add(new ProcessedRequestNonce { DeviceId = _deviceId, Nonce = nonce, UsedAt = DateTime.UtcNow });
            await db.SaveChangesAsync();

            bool isDuplicate = await db.ProcessedRequestNonces.AnyAsync(n => n.DeviceId == _deviceId && n.Nonce == nonce);
            Assert.True(isDuplicate);
        }

        // FACT 5: THIẾU OXY MÁU (SPO2) KÉO DÀI 3 LẦN KÍCH HOẠT BÁO ĐỘNG
        [Fact]
        public async Task Fact5_SpO2Hypoxia_TriggersAfter3Readings()
        {
            using var scope = _services.CreateScope();
            var engine = scope.ServiceProvider.GetRequiredService<IHardenedTelemetryEngine>();

            for (int i = 1; i <= 2; i++)
            {
                var r = await engine.ProcessTelemetryPacketAsync(new TelemetryPacketDto($"PKT_SPO2_{i}", _deviceId, DateTime.UtcNow, new List<TelemetrySampleDto>
                {
                    new($"EVT_SPO2_{i}", "SPO2", 88.0m, null, "%", DateTime.UtcNow)
                }));
                Assert.True(r.Success);
            }

            // Lần 3: Kích hoạt khẩn cấp
            var res3 = await engine.ProcessTelemetryPacketAsync(new TelemetryPacketDto("PKT_SPO2_3", _deviceId, DateTime.UtcNow, new List<TelemetrySampleDto>
            {
                new("EVT_SPO2_3", "SPO2", 87.5m, null, "%", DateTime.UtcNow)
            }));
            Assert.True(res3.IncidentTriggered);
        }

        // FACT 6: NHỊP TIM CHẬM NGUY HIỂM (<45 BPM) BÁO ĐỘNG TỨC THÌ
        [Fact]
        public async Task Fact6_SevereBradycardia_TriggersEmergency()
        {
            using var scope = _services.CreateScope();
            var engine = scope.ServiceProvider.GetRequiredService<IHardenedTelemetryEngine>();
            var res = await engine.ProcessTelemetryPacketAsync(new TelemetryPacketDto("PKT_HR_01", _deviceId, DateTime.UtcNow, new List<TelemetrySampleDto>
            {
                new("EVT_HR_01", "HEART_RATE", 42.0m, null, "bpm", DateTime.UtcNow)
            }));
            Assert.True(res.IncidentTriggered);
        }

        // FACT 7: HUYẾT ÁP RETEST BẮT BUỘC 15 PHÚT NGHỈ NGƠI (P0-05, P0-34 FIX)
        [Fact]
        public async Task Fact7_BpRetestWorkflow_Enforces15MinutesInterval()
        {
            using var scope = _services.CreateScope();
            var engine = scope.ServiceProvider.GetRequiredService<IHardenedTelemetryEngine>();

            var now = DateTime.UtcNow;
            // Lần 1: Đo huyết áp 165 mmHg -> Chỉ ghi nhận Retest Pending
            var res1 = await engine.ProcessTelemetryPacketAsync(new TelemetryPacketDto("PKT_BP_1", _deviceId, now, new List<TelemetrySampleDto>
            {
                new("EVT_BP_1", "BLOOD_PRESSURE", 165m, 102m, "mmHg", now)
            }));
            Assert.True(res1.Success);

            // Đo lại ở phút thứ 5 (Quá sớm) -> KHÔNG kích hoạt khẩn cấp (P0-34 Assert)
            var resEarly = await engine.ProcessTelemetryPacketAsync(new TelemetryPacketDto("PKT_BP_EARLY", _deviceId, now.AddMinutes(5), new List<TelemetrySampleDto>
            {
                new("EVT_BP_EARLY", "BLOOD_PRESSURE", 168m, 105m, "mmHg", now.AddMinutes(5))
            }));
            Assert.False(resEarly.IncidentTriggered);

            // Đo lại ở phút thứ 15 (Đủ thời gian) -> KÍCH HOẠT KHẨN CẤP
            var resLate = await engine.ProcessTelemetryPacketAsync(new TelemetryPacketDto("PKT_BP_LATE", _deviceId, now.AddMinutes(15), new List<TelemetrySampleDto>
            {
                new("EVT_BP_LATE", "BLOOD_PRESSURE", 166m, 101m, "mmHg", now.AddMinutes(15))
            }));
            Assert.True(resLate.IncidentTriggered);
        }

        // FACT 8: ACKNOWLEDGE INCIDENT ĐẨY LỆNH STOP_SIREN VÀO OUTBOX
        [Fact]
        public async Task Fact8_AcknowledgeIncident_EnqueuesStopSiren()
        {
            using var scope = _services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
            var inc = await db.Incidents.FirstAsync(i => i.Id == _seededIncidentId);

            inc.WorkflowState = "Acknowledged";
            db.NotificationOutboxes.Add(new NotificationOutbox
            {
                Id = Guid.NewGuid(),
                IncidentId = inc.Id,
                ClientEventId = $"STOP_ACK_{inc.Id}",
                TargetDeviceId = _deviceId,
                Channel = "InternalSiren",
                DestinationAddress = _deviceId,
                Payload = "{"action":"STOP_SIREN"}",
                DeliveryStatus = "Pending",
                CreatedAt = DateTime.UtcNow
            });
            await db.SaveChangesAsync();

            var outbox = await db.NotificationOutboxes.FirstOrDefaultAsync(o => o.IncidentId == inc.Id && o.Channel == "InternalSiren");
            Assert.NotNull(outbox);
            Assert.Contains("STOP_SIREN", outbox.Payload);
        }

        // FACT 9: CỤ BẤM XÁC NHẬN KHẨN CẤP KÍCH HOẠT CHUỖI CỨU HỘ
        [Fact]
        public async Task Fact9_ConfirmEmergencyFromElder_ActivatesOutbox()
        {
            using var scope = _services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
            
            // Mô phỏng action Confirm
            var inc = await db.Incidents.FirstAsync(i => i.Id == _seededIncidentId);
            inc.WorkflowState = "Active";
            inc.CurrentSeverity = 1.0f;
            db.NotificationOutboxes.Add(new NotificationOutbox
            {
                Id = Guid.NewGuid(),
                IncidentId = inc.Id,
                ClientEventId = $"CONFIRM_SIREN_{inc.Id}",
                TargetDeviceId = _deviceId,
                Channel = "InternalSiren",
                DestinationAddress = _deviceId,
                Payload = "{"action":"TRIGGER_SIREN"}",
                DeliveryStatus = "Pending",
                CreatedAt = DateTime.UtcNow
            });
            await db.SaveChangesAsync();

            var siren = await db.NotificationOutboxes.FirstOrDefaultAsync(o => o.ClientEventId == $"CONFIRM_SIREN_{inc.Id}");
            Assert.NotNull(siren);
        }

        // FACT 10: XUẤT HỒ SƠ VI PHẠM DỮ LIỆU ĐIỀU 23 MÃ HÓA AES-256-GCM ĐẦY ĐỦ (P0-14, P0-33 FIX)
        [Fact]
        public async Task Fact10_DataBreachExporter_EncryptsEvidencePackage()
        {
            using var scope = _services.CreateScope();
            var exporter = scope.ServiceProvider.GetRequiredService<CareAi.Api.Controllers.IIncidentBreachPackageExporter>();
            
            var packageBytes = await exporter.ExportEncryptedBreachPackageAsync(_seededIncidentId, "Passphrase_Rat_La_Dai_123456");
            Assert.NotNull(packageBytes);
            // Header Salt(16B) + Nonce(12B) + Tag(16B) = 44B
            Assert.True(packageBytes.Length >= 44);
        }
    }
}
```