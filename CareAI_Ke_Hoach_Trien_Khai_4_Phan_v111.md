# KẾ HOẠCH TRIỂN KHAI TOÀN DIỆN HỆ THỐNG CAREAI v111.0
## BẢN KẾ HOẠCH BỐN PHẦN ĐỘC LẬP & CÂN BẰNG NGHIỆP VỤ (BALANCED & DECOUPLED ROADMAP)

- **Dự án**: Hệ thống Y tế Từ xa & Cảnh báo Cấp cứu Gia đình CareAI
- **Phiên bản kiến trúc chuẩn**: v111.0 (Definitive Production-Hardened Edition)
- **Định vị pháp lý**: Nền tảng Hỗ trợ Cảnh báo Chăm sóc Người cao tuổi (Caregiver Assistive Alerting Platform - Non-SaMD)
- **Mô hình kiến trúc**: Sovereign Modular Monolith (.NET 9 LTS · Azure SQL · Kotlin Direct Boot · Flutter Single Unified App)
- **Ngày ban hành**: 24/09/2026
- **Trạng thái**: Kế hoạch chuẩn chính thức (Approved Execution Baseline)

---

## 1. TỔNG QUAN HIỆN TRẠNG & NỀN TẢNG ĐÃ ĐẠT ĐƯỢC (BASELINE ACHIEVEMENTS)

Tính đến ngày 24/09/2026, dự án CareAI đã hoàn thành 100% các cột mốc nền tảng sống còn:

1. **Backend Sovereign Modular Monolith (.NET 9 LTS)**:
   - Cơ sở dữ liệu Azure SQL Database (`***REMOVED***`) đã khởi tạo trọn vẹn 10 bảng DDL Idempotent, các ràng buộc toàn vẹn, cờ OCC `ROWVERSION` và Filtered Unique Index `UIX_Incidents_SingleActiveElder`.
   - Authentication Middleware chuẩn hóa băm SHA-256 chữ thường (`DeviceTokenHash.ToLowerInvariant()`), Header `X-DeviceId`.
   - Toàn bộ **36/36 Facts Unit Tests đều đạt 100% Passed** (`dotnet test CareAI/CareAI.slnx`).
2. **Ứng Dụng Di Động Hợp Nhất (Single Unified Mobile App - `vn.careai.companion`)**:
   - Hợp nhất hoàn toàn phân hệ Người cao tuổi (Companion SOS & Fall) và phân hệ Người thân (Caregiver Monitoring) vào một ứng dụng duy nhất, điều hướng qua `RoleSelectionScreen` và lưu trạng thái vào `SharedPreferences`.
   - Bảo toàn 100% các thành phần Native Android Direct Boot (`PhoneBootReceiver`), Device Protected Storage (`CareAiFallStore`), còi hú y tế ICU 1350Hz phần cứng (`SoundPool` 0ms latency), `AlarmManager.RTC_WAKEUP` và Full-Screen Intent.
   - **8/8 Kịch bản Phần cứng HIL (HIL-01 đến HIL-08)** đã nghiệm thu thực địa 100% thành công trên điện thoại thật Samsung Galaxy A55 5G (`R5CY10M8BZN`).
3. **Module Galaxy Watch (Wear OS)**:
   - Module Native Kotlin `:wearos` biên dịch thành công APK `wearos-debug.apk`, tích hợp Google Health Services, chạy mượt mà trên màn hình OLED tròn của Wear OS Virtual Watch (`emulator-5554`).
4. **Mã Nguồn & Git Repository**:
   - Toàn bộ mã nguồn đã tinh gọn, phân định rõ ràng trong thư mục `CareAI/`, commit và đẩy thành công lên GitHub `https://github.com/taithptqt/CareAI.git` (nhánh `main`).

---

## 2. MA TRẬN PHÂN CHIA 4 PHẦN NHIỆM VỤ CÂN BẰNG & ĐỘC LẬP (THE 4-PART BALANCED ROADMAP)

Để đảm bảo khối lượng công việc được phân bổ đồng đều, không có phần nào quá nặng hay quá nhẹ, và các phần **hoàn toàn độc lập 100% không bị phụ thuộc vòng tròn**, toàn bộ các Use Case và tính năng còn lại của hệ thống CareAI được cấu trúc thành 4 phần chuyên biệt:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                   CAREAI ARCHITECTURE                                  │
├────────────────────────────┬────────────────────────────┬──────────────────────────────┤
│ PHẦN 1: VIỄN TRẮC &        │ PHẦN 2: TRUNG TÂM PHẢN ỨNG │ PHẦN 3: QUẢN TRỊ GIA ĐÌNH,   │
│ THÍCH NGHI NGƯỠNG          │ CẤP CỨU & KIỂM TOÁN PHÁP Y │ PHÂN QUYỀN & THIẾT BỊ        │
│ (UC-04, UC-05, UC-10, 11)  │ (UC-06, UC-07, UC-08, 14)  │ (UC-01+, UC-02, UC-12, 13)   │
├────────────────────────────┴────────────────────────────┴──────────────────────────────┤
│ PHẦN 4: TRÍ TUỆ NHÂN TẠO (AI/ML) PHÂN TÍCH DỊ BIỆT SINH HOẠT & BÁO CÁO Y TẾ TUẦN      │
│ (UC-15: ML.NET Anomaly Detection · UC-16: LLM GenAI Weekly Report · Safe Fallback)     │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### Bảng Ma Trận So Sánh Độ Nặng & Tính Độc Lập Giữa 4 Phần:

| Chỉ Số Đánh Giá | **Phần 1** | **Phần 2** | **Phần 3** | **Phần 4** |
| :--- | :--- | :--- | :--- | :--- |
| **Phạm vi Use Case** | UC-04, UC-05, UC-10 (Sinh hiệu & GPS), UC-11 (Thích nghi ngưỡng) | UC-06, UC-07, UC-08, UC-14 | UC-01 (Nâng cao), UC-02, UC-03 (Nâng cao), UC-12, UC-13 | UC-15, UC-16, Module AI Analytics |
| **Độ nặng nghiệp vụ** | **25%** (Cân bằng) | **25%** (Cân bằng) | **25%** (Cân bằng) | **25%** (Cân bằng) |
| **Thành phần Di động** | Đồng bộ Health Connect, SQLite WAL 7 ngày, Live Charts, Map | Giao diện Quorum Alerting, Còi hú, Nút gọi 115, Nút Tiếp nhận ACK | Màn hình Quản lý thành viên, Mã mời 6 ký tự, Quét mã QR ghép nối, Đổi quyền | Thẻ nhận định thông minh AI, Màn hình xem Báo cáo sức khỏe tuần |
| **Thành phần Backend** | Telemetry Batch Ingestion, Transient Retry, Adaptive Engine | Clinical Rule Engine, Multi-Device Watchdog 60s, OCC Concurrency | Family RBAC Service, Pairing PIN Service, Token Revocation, Safe Erasure | In-Process ML.NET Time-Series Worker, LLM Prompt Engine, Deterministic Template |
| **Cơ sở dữ liệu** | `HealthMeasurements`, `ProcessedTelemetryLedgers`, `DeviceClinicalStates` | `Incidents`, `IncidentTimelineEvents`, `NotificationOutbox` | `ElderProfiles`, `ElderCaregivers`, `DevicePairingTokens`, `FamilyInvitations` | `HealthInsights`, `WeeklyHealthReports`, `HealthMeasurements` (Read-only) |
| **Tính Độc Lập** | **100% Độc lập**: Chỉ ghi nhận sinh hiệu và tính toán ngưỡng. | **100% Độc lập**: Vận hành trên bảng sự cố và quy trình cấp cứu. | **100% Độc lập**: Quản trị tài khoản, nhóm gia đình và thiết bị. | **100% Độc lập**: Chạy phân tích offline trên dữ liệu lịch sử. |

---

## 3. CHI TIẾT TRIỂN KHAI PHẦN 1: TRỤC VIỄN TRẮC, ĐỒNG BỘ SMARTWATCH, GPS & TỰ ĐIỀU CHỈNH NGƯỠNG THÍCH NGHI THEO THỜI GIAN

### 3.1 Mục Tiêu & Phạm Vi Nghiệp Vụ
- **Mã Use Case phụ trách**: UC-04, UC-05, UC-10 (chức năng Sinh hiệu & Bản đồ GPS), UC-11 (Mở rộng Thuật toán Thích nghi Ngưỡng).
- **Mục tiêu cốt lõi**:
  1. Thiết lập luồng thu thập dữ liệu sinh hiệu thụ động định kỳ từ Samsung Galaxy Watch qua Google Health Connect.
  2. Cơ chế lưu đệm ngoại tuyến SQLite WAL 7 ngày trên điện thoại, truyền mẻ Batch-Lane (`/api/v1/telemetry/batch`) phản hồi `< 15ms` (HTTP 202 Accepted).
  3. Xử lý nền Bulk Ingestion tại Backend Kestrel với mạch Retry 5 lần chống quá tải 5 DTU và cầu dao bảo vệ RAM máy chủ.
  4. Trực quan hóa dữ liệu sinh hiệu thời gian thực: Biểu đồ nhịp tim 24 giờ, bước chân, và định vị GPS của cụ trên bản đồ.
  5. **Chức năng Tự Động Thu Thập Dữ Liệu & Tự Điều Chỉnh Ngưỡng Thích Nghi Theo Thời Gian (Adaptive Threshold Tuning)**: Phân tích phân phối xác suất dữ liệu lịch sử 14 ngày của cụ để tự động tính toán và điều chỉnh dải ngưỡng an toàn phù hợp với thể trạng thực tế, kết hợp cơ chế Zero-Downtime Cache Invalidation.

### 3.2 Các Hạng Mục Nhiệm Vụ Cụ Thể (Actionable Tasks)
1. **Nhiệm vụ 1.1 - Tích hợp Google Health Connect & Android WorkManager (`companion_app`)**:
   - Triển khai `TelemetrySyncWorker` chạy ngầm định kỳ 15 phút.
   - Trích xuất dữ liệu từ Health Connect: Nhịp tim từng phút (`HeartRateRecord`), Số bước chân (`StepsRecord`), `OxygenSaturationRecord`, `BloodPressureRecord`.
   - Lưu trữ an toàn vào SQLite cục bộ (`careai_local_spool.db`) với chế độ WAL và cờ `Synced = 0`.
   - Cơ chế dọn dẹp an toàn `purgeOldSyncedPackets`: Chỉ xóa các bản ghi đã đồng bộ (`Synced = 1`) có tuổi thọ lớn hơn 7 ngày.
2. **Nhiệm vụ 1.2 - API Batch Ingestion & Hàng Đợi Bộ Nhớ (`CareAI.API`)**:
   - Xây dựng endpoint `POST /api/v1/telemetry/batch` xác thực Bearer Token thiết bị, nạp vào `Channel<HealthMeasurementPacket>` và trả về ngay HTTP 202 Accepted.
   - Endpoint `POST /api/v1/telemetry/heartbeat` cập nhật mốc `LastHeartbeat` phục vụ giám sát đường truyền.
3. **Nhiệm vụ 1.3 - TelemetryBatchProcessor & Mạch Cầu Dao Bảo Vệ RAM (`CareAI.Infrastructure`)**:
   - Triển khai Background Worker tiêu thụ Channel theo mẻ 100 gói hoặc timeout 1.000ms.
   - Tiền lọc Idempotency qua bảng `ProcessedTelemetryLedgers`.
   - Bulk Insert vào `HealthMeasurements` trên Azure SQL.
   - Mạch Transient Retry 5 lần (delay 5s) và Dead Letter Batch khi lỗi lặp lại.
   - Cầu dao giới hạn RAM máy chủ không vượt quá 700MB trên môi trường Azure B1s 1GB RAM.
4. **Nhiệm vụ 1.4 - Trực Quan Hóa Dashboard Sinh Hiệu & Bản Đồ GPS (`companion_app/lib/caregiver`)**:
   - Màn hình Bảng điều khiển người thân: Thẻ màu sức khỏe (Xanh, Vàng, Đỏ, Xám), Biểu đồ đường biến thiên nhịp tim 24 giờ qua (fl_chart), Thanh tiến độ bước chân so với mục tiêu vận động.
   - Tích hợp Bản đồ GPS tương tác (OpenStreetMap / flutter_map) hiển thị tọa độ gần nhất và thời điểm đo.
5. **Nhiệm vụ 1.5 - Thuật Toán Tự Điều Chỉnh Ngưỡng Thích Nghi Theo Thời Gian (`CareAI.Core`)**:
   - Xây dựng dịch vụ `AdaptiveThresholdService`: Định kỳ phân tích dữ liệu nhịp tim nghỉ ngơi 14 ngày gần nhất của cụ theo bách phân vị (Percentile 5th và 95th).
   - Tự động đề xuất dải ngưỡng mới: `RecommendedMin` (>= 40 bpm) và `RecommendedMax` (<= 160 bpm).
   - Cung cấp API cập nhật ngưỡng `PUT /api/v1/elders/{id}/thresholds` với cơ chế làm mới `IMemoryCache` tức thì (Zero-Downtime Cache Invalidation).
   - Chế độ tự động điều chỉnh an toàn (Safe Auto-Tuning): Giới hạn biên độ dịch chuyển tối đa 3 bpm/tuần.

### 3.3 Tiêu Chí Nghiệm Thu (Definition of Done - DoD)
- [ ] Gửi mẻ 500 mẫu viễn trắc từ điện thoại lên server, phản hồi HTTP 202 Accepted trong `< 15ms`.
- [ ] Dữ liệu sinh hiệu lưu trữ bền vững vào Azure SQL, không mất mát khi ngắt kết nối mạng tạm thời (thử lại thành công từ SQLite sau 7 ngày).
- [ ] Biểu đồ nhịp tim 24 giờ và bản đồ GPS hiển thị trực quan, mượt mà trên Chế độ Người thân.
- [ ] Thuật toán Adaptive Thresholds tự động tính toán chính xác dải ngưỡng mới dựa trên dữ liệu 14 ngày và cập nhật Cache trong 0ms.
- [ ] Bổ sung xUnit Fact Tests mới cho luồng Batch-Lane và Adaptive Tuning, bảo đảm 100% test pass.

---

## 4. CHI TIẾT TRIỂN KHAI PHẦN 2: TRỤC TRUNG TÂM PHẢN ỨNG CẤP CỨU, ĐIỀU PHỐI QUORUM SLA 60S & DẤU VẾT KIỂM TOÁN PHÁP Y

### 4.1 Mục Tiêu & Phạm Vi Nghiệp Vụ
- **Mã Use Case phụ trách**: UC-06, UC-07, UC-08, UC-14.
- **Mục tiêu cốt lõi**:
  1. Hoàn thiện Engine thẩm định lâm sàng thời gian thực (HardenedTelemetryEngine): Bắt chuẩn xác cơn rung thất (`>= 180 bpm`), vô tâm thu (`<= 35 bpm`) và tăng nhịp đột ngột (`>= 15 bpm` khi ngồi nghỉ).
  2. Giám sát mất kết nối đa thiết bị (Multi-Device Watchdog 60s) với quy tắc ức chế cảnh báo khi đang có cấp cứu (Emergency Suppression Rule) và tự động phục hồi độc lập.
  3. Trung tâm điều phối cấp cứu Quorum Alerting đa người thân với SLA phản hồi khắt khe `< 60 giây`.
  4. Quy trình Tiếp nhận sự cố (Acknowledge) và Đóng sự cố (Resolve) kiểm soát tương tranh lạc quan OCC (`ROWVERSION`), chống tấn công BOLA và tích hợp nút gọi khẩn cấp 115.
  5. Dấu vết kiểm toán pháp y y tế bất biến (Append-Only Medical Forensic Audit Trail) và tái hiện biểu đồ nhịp tim 15 phút trước và sau sự cố.

### 4.2 Các Hạng Mục Nhiệm Vụ Cụ Thể (Actionable Tasks)
1. **Nhiệm vụ 2.1 - Clinical Rule Engine & Tự Động Tái Kích Hoạt (`CareAI.Core`)**:
   - Thẩm định mẫu đo nhịp tim: Bình thường (50-110), Cảnh báo (nhịp chậm/nhanh), Nguy kịch (Rung thất >= 180 hoặc Vô tâm thu <= 35 bpm).
   - Cơ chế Cửa sổ Khử trùng lặp (Debounce Cooldown Window 10 phút) chống spam thông báo.
   - Bất biến Tái mở sự cố (Re-escalation Invariant): Tự động chuyển từ `Acknowledged` về `Open` và nâng mức `Critical` nếu tình trạng cụ chuyển biến xấu nguy kịch sau khi người thân đã tiếp nhận.
2. **Nhiệm vụ 2.2 - Multi-Device Watchdog 60s & Ức Chế Cấp Cứu (`CareAI.Infrastructure`)**:
   - Hoàn thiện `DeviceStaleWorker` quét định kỳ 60 giây/lần.
   - Gom nhóm đa thiết bị theo cụ: Chỉ cảnh báo mất mạng khi TẤT CẢ các thiết bị của cụ mất tín hiệu quá 5 phút.
   - Triệt để tuân thủ Quy tắc Ức chế Cấp cứu: Nếu cụ đang có sự cố SOS hoặc Ngã, cấm tạo sự cố mất mạng rác, chỉ ghi chú bổ sung vào sự cố hiện tại.
   - Pha 2: Tự động phục hồi đóng sự cố sang `Resolved` độc lập khi thiết bị có tín hiệu trở lại.
3. **Nhiệm vụ 2.3 - Quorum Alerting SLA 60s & Giao Diện Cứu Hộ Khẩn Cấp (`companion_app`)**:
   - Khi có sự cố `Critical`, gửi còi hú đồng thời tới toàn bộ người thân trong gia đình qua Google FCM High Priority.
   - Màn hình Chi tiết Sự cố khẩn cấp trên app người thân: Còi hú y tế, thông tin chỉ số sinh hiệu lúc xảy ra sự cố, vị trí GPS.
   - Nút hành động nhanh: Bấm gọi trực tiếp cho cụ, Bấm gọi Cấp cứu 115 (kèm hiển thị nhanh địa chỉ nhà của cụ để đọc cho tổng đài viên).
4. **Nhiệm vụ 2.4 - Quy Trình Tiếp Nhận (ACK) & Giải Quyết (Resolve) Chuẩn OCC (`CareAI.API`)**:
   - Triển khai endpoint `POST /api/v1/incidents/{id}/acknowledge`: Kiểm tra BOLA, kiểm tra OCC `RowVersion`, chuyển trạng thái `Acknowledged`, tắt còi hú và thông báo cho các người thân khác biết đã có người xử lý.
   - Triển khai endpoint `POST /api/v1/incidents/{id}/resolve`: Yêu cầu ghi chú y tế lâm sàng (`ResolutionNotes`), chuyển trạng thái `Resolved`.
5. **Nhiệm vụ 2.5 - Tra Cứu Lịch Sử Sự Cố & Dấu Vết Pháp Y Bất Biến (`CareAI.API` & `companion_app`)**:
   - Endpoint `GET /api/v1/elders/{id}/incidents` phân trang, hỗ trợ lọc theo loại sự cố, mức độ nghiêm trọng và khoảng thời gian.
   - Giao diện Timeline lịch sử sự cố trực quan trên app người thân: Thể hiện rõ ai tiếp nhận lúc mấy giờ, ai giải quyết và ghi chú y tế.
   - Biểu đồ chi tiết nhịp tim trong khoảng 15 phút trước và 15 phút sau sự cố phục vụ bác sĩ giám định thể trạng phục hồi.
   - Bất biến CSDL: Bản ghi Incident là Append-Only, cấm xóa hoặc sửa các trường lịch sử.

### 4.3 Tiêu Chí Nghiệm Thu (Definition of Done - DoD)
- [ ] Mô phỏng nhịp tim 185 bpm: Hệ thống kích hoạt còi hú khẩn cấp và đẩy thông báo Quorum tới người thân trong `< 3 giây`.
- [ ] Hai người thân cùng bấm tiếp nhận đồng thời: Người bấm sau nhận HTTP 409 Conflict với thông báo rõ ràng người trước đã tiếp nhận, triệt tiêu lỗi ghi đè Lost Update nhờ OCC `RowVersion`.
- [ ] Ngắt tín hiệu thiết bị khi đang có SOS: Watchdog không tạo sự cố rác đè lên sự cố SOS đang mở.
- [ ] Ghi chú y tế và dấu vết người tiếp nhận/giải quyết được lưu trữ bất biến và hiển thị đầy đủ trên Timeline lịch sử.
- [ ] Bổ sung xUnit Fact Tests cho luồng Quorum, OCC Concurrency Collision và Forensic Audit.

---

## 5. CHI TIẾT TRIỂN KHAI PHẦN 3: TRỤC QUẢN TRỊ NHÓM GIA ĐÌNH, MÃ MỜI 6 SỐ, PHÂN QUYỀN RBAC & VÒNG ĐỜI THIẾT BỊ

### 5.1 Mục Tiêu & Phạm Vi Nghiệp Vụ
- **Mã Use Case phụ trách**: UC-01 (Mở rộng bảo mật), UC-02, UC-03 (Mở rộng ghép nối), UC-12, UC-13.
- **Mục tiêu cốt lõi**:
  1. Quản lý danh tính người chăm sóc: Đăng ký, đăng nhập an toàn với mật khẩu băm BCrypt, cơ chế phòng thủ vật lý khóa tài khoản 15 phút khi nhập sai quá 5 lần (Brute-force Lockout).
  2. Khởi tạo hồ sơ người cao tuổi và quản lý thông tin bệnh án nền.
  3. Ghép nối thiết bị phần cứng thông minh qua Mã PIN 6 chữ số dùng 1 lần (Single-Use PIN, hiệu lực 15 phút) kết hợp tạo mã QR Code quét nhanh từ màn hình.
  4. Quản trị nhóm gia đình qua Mã mời 6 ký tự (hiệu lực 24 giờ) và thực thi ma trận phân quyền dựa trên vai trò nghiêm ngặt (RBAC Matrix): Người thân chính (Primary Caregiver - Đại diện pháp lý) vs Người thân phụ (Secondary Caregiver).
  5. Quản trị vòng đời thiết bị và dữ liệu: Hủy ghép nối từ xa (gửi Silent Push xóa sạch token), Quyền xóa dữ liệu (Right to Erasure) và Ẩn danh hóa dữ liệu y tế (PII Removal) tuân thủ luật bảo vệ dữ liệu cá nhân.

### 5.2 Các Hạng Mục Nhiệm Vụ Cụ Thể (Actionable Tasks)
1. **Nhiệm vụ 3.1 - Xác Thực Nâng Cao & Khóa An Toàn Brute-Force (`CareAI.API`)**:
   - Chuẩn hóa quy trình đăng ký/đăng nhập với BCrypt work factor 11.
   - Quản lý biến đếm `FailedLoginAttempts`: Nếu sai >= 5 lần, khóa tài khoản 15 phút (`LockoutEnd = DateTime.UtcNow.AddMinutes(15)`), trả về HTTP 423 Locked.
   - Cơ chế cấp lại mật khẩu qua mã OTP 6 số gửi qua Email.
2. **Nhiệm vụ 3.2 - Quản Lý Hồ Sơ Cụ & Sinh Mã PIN / QR Code Ghép Nối (`CareAI.API` & `companion_app`)**:
   - Màn hình Tạo/Sửa hồ sơ cụ: Họ tên, Năm sinh, Giới tính, Tiền sử bệnh lý nền, Số điện thoại khẩn cấp.
   - Endpoint `POST /api/v1/elders/{id}/pairing-code`: Sinh mã PIN 6 số (băm SHA-256 lưu CSDL, TTL 15 phút).
   - Sinh mã QR chứa chuỗi ghép nối chuẩn để điện thoại của cụ chỉ cần quét camera là tự động điền mã PIN và ghép nối.
3. **Nhiệm vụ 3.3 - Quản Trị Nhóm Gia Đình & Mã Mời 24 Giờ (`CareAI.API` & `companion_app`)**:
   - Endpoint `POST /api/v1/elders/{id}/invitations`: Sinh mã mời gia đình 6 ký tự viết hoa (ví dụ: `CARE88`, TTL 24 giờ).
   - Endpoint `POST /api/v1/invitations/accept`: Người thân phụ nhập mã mời để tham gia nhóm chăm sóc cụ.
   - Màn hình Quản lý thành viên gia đình trên app người thân: Hiển thị danh sách con cháu đang cùng chăm sóc, vai trò và nút thu hồi quyền theo dõi.
4. **Nhiệm vụ 3.4 - Thực Thi Ma Trận Phân Quyền RBAC Nghiêm Ngặt (`CareAI.Core`)**:
   - Xây dựng RBAC Policy Authorization:
     * **Primary Caregiver (Đại diện pháp lý)**: Toàn quyền cấu hình ngưỡng y tế, mời/xóa thành viên, hủy thiết bị, xóa hồ sơ và tiếp nhận/đóng sự cố.
     * **Secondary Caregiver (Thành viên theo dõi)**: Quyền xem Dashboard, nhận còi hú FCM, tiếp nhận ACK, gọi cứu hộ; TUYỆT ĐỐI KHÔNG có quyền thay đổi ngưỡng, không có quyền xóa thành viên khác hoặc hủy thiết bị.
   - Mọi vi phạm phân quyền đều bị chặn đứng với HTTP 403 Forbidden.
5. **Nhiệm vụ 3.5 - Vòng Đời Thiết Bị & Quyền Xóa Dữ Liệu An Toàn (`CareAI.API`)**:
   - Endpoint `POST /api/v1/devices/{id}/unpair`: Vô hiệu hóa thiết bị trong CSDL, đưa token vào danh sách đen (Blacklist) trong Cache, gửi bản tin FCM ngầm `WIPE_DEVICE_CREDENTIALS` yêu cầu điện thoại cụ xóa Keystore và quay về màn hình ghép nối.
   - Endpoint `DELETE /api/v1/elders/{id}`: Yêu cầu xác thực mật khẩu cấp 2 của Người thân chính. Xóa mềm hồ sơ cụ (`IsDeleted = true`), hủy liên kết toàn bộ thiết bị và ẩn danh hóa toàn bộ dữ liệu sinh hiệu (PII Removal).

### 5.3 Tiêu Chí Nghiệm Thu (Definition of Done - DoD)
- [ ] Nhập sai mật khẩu 5 lần: Tài khoản bị khóa 15 phút, trả về HTTP 423 Locked.
- [ ] Ghép nối thành công thiết bị qua mã PIN 6 số hoặc quét mã QR trong vòng 15 phút; mã hết hạn bị từ chối với HTTP 400.
- [ ] Mời thành viên mới qua mã 6 ký tự thành công; tài khoản người thân phụ không thể thực hiện các thao tác quản trị y tế (nhận HTTP 403 Forbidden).
- [ ] Hủy ghép nối thiết bị từ xa: Thiết bị của cụ nhận lệnh ngầm, xóa sạch bộ nhớ đệm và trở về trạng thái chờ ghép nối ban đầu.
- [ ] Bổ sung xUnit Fact Tests cho luồng RBAC Authorization, Brute-force Lockout và Data Anonymization.

---

## 6. CHI TIẾT TRIỂN KHAI PHẦN 4: TRỤC TRÍ TUỆ NHÂN TẠO (AI/ML) PHÂN TÍCH DỊ BIỆT SINH HOẠT & BÁO CÁO Y TẾ TUẦN

### 6.1 Mục Tiêu & Phạm Vi Nghiệp Vụ
- **Mã Use Case phụ trách**: UC-15, UC-16, và Module AI Health Insights trên ứng dụng di động.
- **Mục tiêu cốt lõi**:
  1. Ứng dụng mô hình học máy chuỗi thời gian (Time-Series Anomaly Detection) chạy trực tiếp trong tiến trình Monolith bằng thư viện **Microsoft.ML (.NET 9 LTS)**, không phụ thuộc vào dịch vụ đám mây bên ngoài.
  2. Tự động học đường cơ sở thói quen (Personalized Baseline) trong 14 ngày của cụ để phát hiện sớm các dị biệt sức khỏe âm thầm: Đột biến nhịp tim ban đêm khi ngủ và bất thường vận động buổi sáng.
  3. Xây dựng tiến trình ngầm `WeeklyReportWorker` tự động tổng hợp Báo cáo Sức khỏe Hàng tuần vào đúng 07:00 sáng Chủ Nhật.
  4. Ứng dụng mô hình ngôn ngữ lớn (Google Gemini 1.5 Flash / Groq) để chuyển đổi các chỉ số thống kê khô khan thành bản báo cáo văn phong ấm áp, ân cần bằng tiếng Việt.
  5. **Bảo mật dữ liệu tuyệt đối (Zero-PII Leakage)**: Ẩn danh hóa 100% thông tin định danh cá nhân trước khi gửi prompt lên API AI bên thứ ba.
  6. **Cơ chế Dự phòng Tất định Bắt buộc (Deterministic Fallback Engine)**: Nếu API AI gặp sự cố rớt mạng, timeout hoặc hết hạn mức (HTTP 429), hệ thống tự động kích hoạt bộ ghép chuỗi mẫu câu quy tắc nội bộ để đảm bảo gia đình luôn nhận được báo cáo đúng giờ 100%.

### 6.2 Các Hạng Mục Nhiệm Vụ Cụ Thể (Actionable Tasks)
1. **Nhiệm vụ 4.1 - Mô Hình Học Máy Chuỗi Thời Gian ML.NET (`CareAI.Infrastructure`)**:
   - Tích hợp package `Microsoft.ML` (phiên bản ổn định LTS) vào dự án Infrastructure.
   - Xây dựng `AnomalyDetectionWorker` kế thừa `BackgroundService` chạy ngầm định kỳ vào lúc 02:00 sáng hàng ngày.
   - Nạp chuỗi thời gian 14 ngày của cụ vào thuật toán `IidSpikeDetector` hoặc Spectral Residual SSA:
     * Phát hiện Đột biến Nhịp tim Ẩn: Nhịp tim khi ngủ cao bất thường so với thói quen của chính cụ (dù chưa vượt ngưỡng tĩnh 110 bpm của UC-06).
     * Phát hiện Bất thường Vận động: Số bước chân buổi sáng bằng 0 trái ngược thói quen đi bộ hàng ngày.
   - Tạo bản ghi `HealthInsight` (mức độ Info/Warning) lưu vào bảng `HealthInsights` trên Azure SQL.
2. **Nhiệm vụ 4.2 - Anonymizer & Khử Dữ Liệu Định Danh Cá Nhân (Zero-PII Engine)**:
   - Xây dựng dịch vụ `PiiAnonymizerService`: Chuyển đổi dữ liệu thống kê tuần thành đối tượng trừu tượng (nhịp tim trung bình, bước chân, số lần cảnh báo).
   - Loại bỏ 100% tên thật của cụ, số điện thoại, địa chỉ nhà, căn cước công dân.
3. **Nhiệm vụ 4.3 - WeeklyReportWorker & Tích Hợp GenAI Y Tế (`CareAI.Infrastructure`)**:
   - Triển khai tiến trình ngầm `WeeklyReportWorker` kích hoạt lúc 07:00 sáng Chủ Nhật hàng tuần.
   - Tạo cấu trúc Prompt Y tế chuẩn hóa hướng dẫn LLM phân tích theo 3 phần: (1) Tổng quan sức khỏe tuần; (2) Điểm tích cực & Cần lưu ý; (3) Lời khuyên sinh hoạt tuần tới cho gia đình.
   - Kết nối với Google Gemini 1.5 Flash API qua HttpClient với Timeout 5 giây.
4. **Nhiệm vụ 4.4 - Cơ Chế Dự Phòng Tất Định Bắt Buộc (Deterministic Fallback Engine)**:
   - Xây dựng `RuleBasedWeeklyReportFallbackEngine`:
     * Khi gọi API AI bên ngoài ném ngoại lệ (HttpRequestException, TaskCanceledException) hoặc trả về HTTP 429 Too Many Requests:
     * Tự động kích hoạt bộ sinh báo cáo quy tắc dựa trên số liệu thực tế: *"Báo cáo tuần [Ngày - Ngày]: Sức khỏe của Cụ tuần qua nhìn chung rất ổn định. Nhịp tim trung bình đạt [X] bpm. Cụ duy trì vận động trung bình [Y] bước/ngày. Trong tuần không phát sinh sự cố khẩn cấp nào..."*.
     * Đảm bảo báo cáo không bao giờ bị gián đoạn hoặc thất bại.
   - Lưu trữ văn bản vào bảng `WeeklyHealthReports` trên Azure SQL và gửi thông báo đẩy nhắc nhở người thân.
5. **Nhiệm vụ 4.5 - Giao Diện "Góc Sức Khỏe AI" & Lịch Sử Báo Cáo Tuần (`companion_app`)**:
   - Xây dựng tab "Góc Sức Khỏe AI" trên Chế độ Người thân: Hiển thị các thẻ nhận định thông minh (Health Insights) với lời khuyên thăm hỏi sức khỏe cho gia đình.
   - Màn hình xem Báo cáo Tuần chi tiết với giao diện thẻ thanh lịch, hỗ trợ tra cứu lịch sử báo cáo các tuần trước.

### 6.3 Tiêu Chí Nghiệm Thu (Definition of Done - DoD)
- [ ] Mô hình ML.NET chạy in-process trong RAM Kestrel, phát hiện chính xác điểm đột biến nhịp tim ẩn ban đêm và lưu bản ghi `HealthInsight` thành công.
- [ ] Toàn bộ chuỗi payload gửi tới API AI hoàn toàn sạch thông tin PII (chỉ chứa số liệu thống kê trừu tượng).
- [ ] Thử nghiệm ngắt mạng Internet của API AI: Hệ thống tự động chuyển sang Deterministic Fallback Engine trong 0ms, sinh ra bản báo cáo tuần chuẩn xác bằng tiếng Việt mà không ném ngoại lệ ra ngoài.
- [ ] Giao diện "Góc Sức Khỏe AI" và Báo cáo Tuần hiển thị trực quan, mượt mà trên ứng dụng di động.
- [ ] Bổ sung xUnit Fact Tests cho luồng ML.NET Spike Detection, PII Anonymizer và Deterministic Fallback.

---

## 7. BẢNG TIẾN ĐỘ THỜI GIAN & THỨ TỰ TRIỂN KHAI ĐỀ XUẤT

Do 4 phần được thiết kế hoàn toàn độc lập và có độ nặng đồng đều (mỗi phần 25%), User có thể linh hoạt chỉ thị triển khai theo thứ tự tự nhiên (từ Phần 1 đến Phần 4) hoặc triển khai bất kỳ phần nào trước mà không gặp rủi ro xung đột mã nguồn:

| Hạng Mục | Phạm Vi Chức Năng | Thời Gian Ước Tính | Trạng Thái |
| :--- | :--- | :---: | :---: |
| **Phần 1** | Trục Viễn Trắc, Đồng Bộ Smartwatch, GPS & Tự Điều Chỉnh Ngưỡng Thích Nghi | 2 - 3 phiên làm việc | **Sẵn sàng khởi động** |
| **Phần 2** | Trục Trung Tâm Cấp Cứu, Điều Phối Quorum SLA 60s & Dấu Vết Pháp Y | 2 - 3 phiên làm việc | Sẵn sàng khởi động |
| **Phần 3** | Trục Quản Trị Nhóm Gia Đình, Mã Mời 6 Số, RBAC & Vòng Đời Thiết Bị | 2 - 3 phiên làm việc | Sẵn sàng khởi động |
| **Phần 4** | Trục Trí Tuệ Nhân Tạo (ML.NET) Phân Tích Dị Biệt & Báo Cáo Y Tế Tuần | 2 - 3 phiên làm việc | Sẵn sàng khởi động |

---

## 8. CAM KẾT KỸ THUẬT VÀ BẢO TỒN CÁC BẤT BIẾN (INVARIANT CHECKLIST)

Trong suốt quá trình triển khai 4 phần trên, đội ngũ cam kết tuân thủ nghiêm ngặt 100% các nguyên tắc sau:
1. **Nguyên tắc Tối thượng 0**: Chỉ làm theo những gì User yêu cầu và chính xác 100%. Không tự ý làm lố, không suy diễn ngoài lề, báo cáo minh bạch sau mỗi bước và chờ chỉ thị tiếp theo.
2. **Anti-Scope Creep**: Giữ vững Sovereign Modular Monolith (.NET 9 LTS), tuyệt đối không cài đặt Kafka, Redis, RabbitMQ hay Kubernetes.
3. **Zero-Preview**: Sử dụng 100% thư viện ổn định LTS.
4. **Bảo tồn Invariants**:
   - `DeviceTokenHash.ToLowerInvariant()` trên toàn bộ hệ thống.
   - Header HTTP chuẩn hóa `X-DeviceId`.
   - Bộ lọc trùng lặp chỉ bắt trên `ProcessedTelemetryLedgers`.
   - Bất biến Fact 35: Gói tin Fast-Lane SOS lưu toàn bộ các mẫu sinh hiệu đi kèm.
   - Filtered Unique Index `UIX_Incidents_SingleActiveElder` trên `Incidents`.
   - Native Android Direct Boot và phân vùng Device Protected Storage giữ vững nguyên vẹn.
5. **Kỷ luật kiểm thử**: Mọi tính năng tạo ra phải build được thật (`dotnet build` 0 warning, 0 error), test pass thật (100% Facts Passed), và kiểm thử thực địa minh bạch trên thiết bị thật Samsung Galaxy A55 5G.
