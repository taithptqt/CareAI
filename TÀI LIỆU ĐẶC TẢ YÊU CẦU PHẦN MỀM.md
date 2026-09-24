# TÀI LIỆU ĐẶC TẢ YÊU CẦU PHẦN MỀM (SRS)
## HỆ THỐNG Y TẾ TỪ XA & CẢNH BÁO CẤP CỨU GIA ĐÌNH CAREAI

- **Phiên bản tài liệu:** v2.0 (Production-Grade Execution Baseline v96.0)
- **Dự án:** CareAI - Dự án Khởi nghiệp Y tế EXE101
- **Ngày ban hành:** 22/09/2026
- **Tác giả:** Đội ngũ Phát triển CareAI (Antigravity & Principal Engineering Team)
- **Kiến trúc mục tiêu:** .NET 10 LTS Web API Monolith (Azure Free-Tier B1s/F1 & Mini-PC Hub) + Flutter (Companion & Caregiver Apps) + Google Health Connect
- **Trạng thái:** Chính thức ban hành (Approved for Production & Defense)

---

## MỤC LỤC TỔNG QUAN
1. **TỔNG QUAN KIẾN TRÚC & MÔ HÌNH VẬN HÀNH DUAL-LANE**
2. **DANH SÁCH TÁC NHÂN HỆ THỐNG (ACTORS)**
3. **MA TRẬN TỔNG HỢP 16 USE CASE**
4. **ĐẶC TẢ CHI TIẾT 16 USE CASE (TỪNG PHÂN HỆ)**
   - Phân hệ 1: Tài khoản & Liên kết (UC-01 đến UC-03)
   - Phân hệ 2: Thu thập & Đệm Dữ liệu Viễn trắc (UC-04, UC-05)
   - Phân hệ 3: Engine Cảnh báo & Giám sát Hệ thống (UC-06, UC-07)
   - Phân hệ 4: Phản ứng Sự cố & Cấp cứu (UC-08 đến UC-10)
   - Phân hệ 5: Cấu hình Lâm sàng & Phân quyền Gia đình (UC-11, UC-12)
   - Phân hệ 6: Quản trị Vòng đời Dữ liệu & Kiểm toán (UC-13, UC-14)
   - Phân hệ 7: Trí tuệ Nhân tạo Phân tích Sức khỏe (UC-15, UC-16)
5. **PHỤ LỤC: MÃ LỖI HTTP, ENUMS & BẤT BIẾN VẬT LÝ HỆ THỐNG**

---

## 1. TỔNG QUAN KIẾN TRÚC & MÔ HÌNH VẬN HÀNH DUAL-LANE

Hệ thống **CareAI** được thiết kế để giải quyết bài toán giám sát sức khỏe từ xa và cảnh báo cấp cứu cho người cao tuổi trong gia đình. Nhằm bảo đảm tính sẵn sàng cao, tiết kiệm chi phí hạ tầng tối đa (chạy hoàn hảo trên gói Azure Free-Tier B1s 1GB RAM và CSDL Azure SQL 5 DTU), hệ thống áp dụng kiến trúc **Single-Process Modular Monolith (.NET 10 LTS)** kết hợp mô hình vận hành **Hai Luồng Tách Biệt (Dual-Lane Architecture)**:

1. **Luồng Cấp cứu Khẩn cấp (Fast-Lane)**:
   - Dành riêng cho các sự kiện khẩn cấp sinh tử: Bấm nút SOS, Thuật toán phát hiện ngã (Fall Detection), và Cơn rung thất/vô tâm thu kịch phát (`HR >= 180 bpm` hoặc `HR <= 35 bpm`).
   - Bỏ qua toàn bộ hàng đợi viễn trắc thông thường, ghi đồng bộ trực tiếp xuống CSDL trong vòng `< 50ms`.
   - Bắn thông báo đẩy Google FCM ưu tiên cao (`Priority = High`) kèm chuông còi hú cứu thương tới toàn bộ người thân trong gia đình trong vòng `< 3 giây`.
   - Tích hợp **Cửa sổ Hủy Cục bộ 30 giây** trên màn hình Companion App để triệt tiêu hoàn toàn báo động giả tại thiết bị mà không làm phiền gia đình.

2. **Luồng Viễn trắc Định kỳ (Batch-Lane)**:
   - Dành cho các chỉ số sinh hiệu định kỳ: Nhịp tim từng phút, số bước chân, SpO2, huyết áp thu thập thụ động qua Google Health Connect từ Samsung Watch.
   - Android WorkManager chạy ngầm mỗi 15 phút, đệm dữ liệu vào CSDL SQLite nội bộ (giữ lại 7 ngày chống mất mát khi mất mạng).
   - Truyền tải theo mẻ lên server, Kestrel nạp vào hàng đợi bộ nhớ `Channel<HealthMeasurementPacket>` và trả về ngay `202 Accepted` (< 15ms).
   - Background Worker `TelemetryBatchProcessor` thực thi Bulk Insert theo mẻ 100 gói kết hợp mạch Retry và mạch cầu dao bảo vệ RAM máy chủ không bị OOM.

---

## 2. DANH SÁCH TÁC NHÂN HỆ THỐNG (ACTORS)

| Tác nhân (Actor) | Phân loại | Vai trò & Trách nhiệm trong hệ thống |
|---|---|---|
| **Người cao tuổi (Elder)** | Con người (Chủ thể dữ liệu) | Đeo Samsung Galaxy Watch hoặc vòng đeo tay cảm biến; bấm nút khẩn cấp SOS khi gặp nạn; bấm nút 'Tôi ổn / Con không sao' trên màn hình Companion App để hủy báo động giả trong 30 giây đầu; theo dõi chỉ số sức khỏe trực tiếp trên màn hình đồng hồ/điện thoại. |
| **Người thân chính (Primary Caregiver - PC)** | Con người (Đại diện pháp lý) | Đại diện hợp pháp ký cấp phép đồng thuận dữ liệu y tế; tạo hồ sơ Cụ; sinh mã PIN 6 số để ghép nối thiết bị; cấu hình ngưỡng lâm sàng cá nhân hóa; mời người thân phụ; nhận cảnh báo ưu tiên cao (Còi hú/FCM); tiếp nhận (ACK) và hoàn tất xử lý sự cố; có toàn quyền hủy ghép nối thiết bị và xóa hồ sơ. |
| **Người thân phụ (Secondary Caregiver - SC)** | Con người (Thành viên theo dõi) | Được PC mời vào nhóm gia đình qua mã mời 6 ký tự; nhận thông báo đẩy FCM khi có sự cố; xem bảng điều khiển sức khỏe (Dashboard) và biểu đồ xu hướng; có quyền bấm 'Tiếp nhận' (ACK) và gọi điện cứu hộ. Tuyệt đối KHÔNG có quyền thay đổi ngưỡng y tế, không có quyền mời/xóa thành viên khác và không có quyền hủy thiết bị. |
| **Companion App (Ứng dụng Android/Watch)** | Hệ thống con (Thiết bị Cụ) | Ứng dụng Flutter/Kotlin chạy nền trên máy Cụ; kết nối Google Health Connect để đọc chỉ số nhịp tim, bước chân, huyết áp từ Samsung Watch; đệm dữ liệu vào SQLite WAL ngoại tuyến (lưu 7 ngày); tự động đồng bộ theo lô (Batch-Lane); kích hoạt màn hình đếm ngược 30 giây hủy báo động giả cục bộ; đẩy gói tin khẩn cấp Fast-Lane trực tiếp lên server khi phát hiện ngã hoặc bấm SOS. |
| **CareAI Monolith Engine (.NET 10 LTS)** | Hệ thống cốt lõi (Backend) | Đóng gói duy nhất dưới dạng Single-Process Modular Monolith; tiếp nhận gói tin Fast-Lane (< 50ms) và Batch-Lane (hàng đợi bộ nhớ Channel<T>); thẩm định luật lâm sàng tim mạch (rung thất >= 180 bpm, vô tâm thu <= 35 bpm, tăng vọt >= 15 bpm); quản lý máy trạng thái sự cố (Open, Acknowledged, Resolved); điều phối chu kỳ Watchdog 60s và tự động phục hồi kết nối; dọn dẹp dữ liệu SQL Server theo mẻ TOP 1000 chống quá tải 5 DTU. |
| **Dịch vụ Ngoại vi (External Cloud Services)** | Hạ tầng bên ngoài | Google Firebase Cloud Messaging (FCM) truyền thông báo đẩy ưu tiên cao (Priority High) kèm còi hú báo động; Google Health Connect quản lý quyền riêng tư và đồng bộ dữ liệu y tế trên thiết bị Android; LLM API (Google Gemini / Groq) hỗ trợ tổng hợp báo cáo sức khỏe tuần. |

---

## 3. MA TRẬN TỔNG HỢP 16 USE CASE

| Mã UC | Tên Use Case | Phân hệ chức năng | Đường truyền / Luồng xử lý | Mức ưu tiên |
|---|---|---|---|---|
| **UC-01** | Đăng ký, Đăng nhập & Khóa An toàn (Caregiver) | Phân hệ 1: Tài khoản & Liên kết | API Xác thực / RBAC | Cao |
| **UC-02** | Tạo Hồ sơ Người cao tuổi & Sinh mã PIN Ghép nối | Phân hệ 1: Tài khoản & Liên kết | Quản lý Hồ sơ | Cao |
| **UC-03** | Ghép nối Companion App & Cấp quyền Health Connect | Phân hệ 1: Tài khoản & Liên kết | Ghép nối Phần cứng | Cao |
| **UC-04** | Đồng bộ Viễn trắc Thụ động qua Health Connect | Phân hệ 2: Thu thập & Đệm Dữ liệu | Batch-Lane (Định kỳ 15m) | Cao |
| **UC-05** | Lưu trữ theo Lô & Mạch Cầu dao Bảo vệ RAM | Phân hệ 2: Thu thập & Đệm Dữ liệu | In-Memory Queue / Azure SQL | Cao |
| **UC-06** | Thẩm định Luật Lâm sàng & Leo thang Cấp cứu | Phân hệ 3: Engine Cảnh báo | Clinical Rule Engine | Khẩn cấp |
| **UC-07** | Giám sát Mất kết nối Đa thiết bị (Watchdog) | Phân hệ 3: Engine Cảnh báo | Background Worker (60s) | Cao |
| **UC-08** | Tiếp nhận Sự cố & Xử lý Khẩn cấp (Acknowledge) | Phân hệ 4: Phản ứng Sự cố | Fast Contact / Concurrency OCC | Khẩn cấp |
| **UC-09** | Phát Cấp cứu SOS & Cảnh báo Ngã kèm Hủy Cục bộ | Phân hệ 4: Phản ứng Sự cố | Fast-Lane (< 50ms sync) | Khẩn cấp |
| **UC-10** | Bảng điều khiển Sức khỏe Trực tiếp & Bản đồ Vị trí | Phân hệ 4: Phản ứng Sự cố | SignalR WebSocket / REST | Trung bình |
| **UC-11** | Tùy chỉnh Ngưỡng Lâm sàng Cá nhân hóa | Phân hệ 5: Cấu hình Lâm sàng | Medical Configuration | Trung bình |
| **UC-12** | Quản lý Thành viên Gia đình & Phân quyền RBAC | Phân hệ 5: Cấu hình Lâm sàng | Family RBAC Mapping | Trung bình |
| **UC-13** | Hủy Liên kết Thiết bị & Xóa Dữ liệu (Data Lifecycle) | Phân hệ 6: Vòng đời Dữ liệu | Device & Data Governance | Cao |
| **UC-14** | Tra cứu Lịch sử Sự cố & Dấu vết Kiểm toán Pháp y | Phân hệ 6: Vòng đời Dữ liệu | Forensic Audit Trail | Cao |
| **UC-15** | AI Phát hiện Bất thường Thói quen Sinh hoạt | Phân hệ 7: Trí tuệ Nhân tạo (Phase 2) | ML.NET Spike Detection | Phân tích / Giai đoạn 2 |
| **UC-16** | AI Tổng hợp Báo cáo Sức khỏe Hàng tuần | Phân hệ 7: Trí tuệ Nhân tạo (Phase 2) | LLM GenAI / Template Engine | Phân tích / Giai đoạn 2 |

---

## 4. ĐẶC TẢ CHI TIẾT 16 USE CASE

### 1. PHÂN HỆ 1: TÀI KHOẢN & LIÊN KẾT (ONBOARDING)

#### UC-01: Đăng ký, Đăng nhập & Khóa An toàn (Caregiver)
- **Phân hệ:** Phân hệ 1: Tài khoản & Liên kết
- **Tác nhân chính:** Caregiver (Người thân chính / Người thân phụ)
- **Tác nhân phụ:** CareAI Monolith Engine (.NET 10)
- **Mức độ ưu tiên:** Cao (P1 - Cốt lõi)
- **Luồng xử lý kiến trúc:** `REST API / Token JWT`
- **Mục tiêu:** Xác thực danh tính người chăm sóc, thiết lập phiên làm việc an toàn, cấp JWT Token và bảo vệ tài khoản chống lại các cuộc tấn công dò mật khẩu (Brute-force).
- **Tiền điều kiện:** Người dùng đã cài ứng dụng Flutter Caregiver trên điện thoại (Android/iOS) và có kết nối mạng Internet.
- **Hậu điều kiện:** Hệ thống cấp Access Token (JWT thời hạn 7 ngày) chứa thông tin định danh và vai trò; phiên làm việc được lưu an toàn trong Secure Storage của thiết bị.

**Luồng sự kiện chính (Main Flow):**
1. Người dùng mở Caregiver App, chọn 'Đăng ký' hoặc 'Đăng nhập'.
2. Người dùng nhập địa chỉ Email hợp lệ và Mật khẩu (yêu cầu tối thiểu 8 ký tự, bao gồm chữ hoa, chữ thường và chữ số).
3. Ứng dụng gửi yêu cầu HTTP POST /api/v1/auth/login (hoặc /api/v1/auth/register) kèm thông tin tài khoản.
4. Hệ thống Backend kiểm tra định dạng và truy vấn tài khoản trong CSDL:
5. Nếu là Đăng ký: Băm mật khẩu bằng thuật toán BCrypt (Work factor = 11), lưu bản ghi Caregiver mới vào bảng Caregivers, khởi tạo vai trò mặc định.
6. Nếu là Đăng nhập: Đối soát mật khẩu đã băm bằng BCrypt.Verify(). Nếu chính xác, hệ thống đặt lại bộ đếm FailedLoginAttempts = 0 và gán LockoutEnd = null.
7. Hệ thống sinh Access Token chuẩn JWT (ký bằng khóa bí mật HMAC-SHA256, thời hạn 7 ngày) chứa các Claims: UserId, Email, Role (PrimaryCaregiver hoặc SecondaryCaregiver).
8. Hệ thống trả về HTTP 200 OK kèm JWT Token và thông tin tóm tắt người dùng.
9. Ứng dụng lưu JWT Token vào bộ lưu trữ mã hóa phần cứng (Flutter Secure Storage / Keystore / Keychain) và điều hướng người dùng vào Màn hình Chính.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Khôi phục mật khẩu khi quên (Forgot Password):**
  + Tại màn hình Đăng nhập, người dùng bấm 'Quên mật khẩu' và nhập Email đã đăng ký.
  + Hệ thống sinh mã OTP ngẫu nhiên gồm 6 chữ số (thời hạn hiệu lực 5 phút), lưu mã hash vào bộ nhớ đệm và gửi email xác thực qua dịch vụ SMTP/SendGrid.
  + Người dùng nhập mã OTP nhận được và đặt Mật khẩu mới.
  + Hệ thống xác thực mã OTP, cập nhật PasswordHash mới vào CSDL, vô hiệu hóa các phiên đăng nhập cũ và cho phép người dùng đăng nhập ngay bằng mật khẩu mới.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Email đã được đăng ký (Duplicate Email):**
  + *Điều kiện phát sinh:* Người dùng thực hiện đăng ký với email đã tồn tại trong CSDL.
  + *Cơ chế xử lý hệ thống:* Hệ thống từ chối tạo mới và trả về mã lỗi HTTP 409 Conflict kèm payload: {"error": "EmailAlreadyExists", "message": "Email này đã được sử dụng. Vui lòng đăng nhập hoặc dùng tính năng quên mật khẩu."}. Giao diện thông báo rõ ràng cho người dùng.
- **E2 - Khóa tài khoản chống dò mật khẩu (Brute-force Lockout):**
  + *Điều kiện phát sinh:* Người dùng nhập sai mật khẩu liên tiếp từ 5 lần trở lên.
  + *Cơ chế xử lý hệ thống:* Hệ thống kích hoạt cơ chế phòng thủ vật lý: Tăng FailedLoginAttempts >= 5 và đặt LockoutEnd = DateTime.UtcNow.AddMinutes(15). Mọi yêu cầu đăng nhập tiếp theo bị từ chối ngay lập tức với mã lỗi HTTP 423 Locked kèm thông báo: {"error": "AccountLocked", "message": "Tài khoản đã bị tạm khóa 15 phút do nhập sai mật khẩu quá 5 lần để bảo vệ an toàn."}. Hệ thống không kiểm tra mật khẩu trong thời gian này để chống cạn kiệt tài nguyên CPU do băm BCrypt.
- **E3 - Sai thông tin đăng nhập:**
  + *Điều kiện phát sinh:* Email không tồn tại hoặc mật khẩu không khớp.
  + *Cơ chế xử lý hệ thống:* Hệ thống tăng biến đếm FailedLoginAttempts lên 1 và trả về HTTP 401 Unauthorized kèm thông báo chung: 'Email hoặc mật khẩu không chính xác' (không chỉ rõ sai email hay sai mật khẩu để tránh tấn công User Enumeration).

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Tuyệt đối không lưu trữ mật khẩu dạng văn bản thô (Clear-text); bắt buộc dùng BCrypt với work factor tối thiểu 11.
- Áp dụng Rate Limiting tối đa 10 requests/phút trên toàn bộ các Endpoint xác thực /api/v1/auth/* từ cùng một địa chỉ IP.
- Token JWT chứa đủ các Claims ngữ cảnh để các API sau thực thi kiểm tra phân quyền (RBAC) trực tiếp mà không cần truy vấn CSDL nhiều lần.

---

#### UC-02: Tạo Hồ sơ Người cao tuổi & Sinh mã PIN Ghép nối
- **Phân hệ:** Phân hệ 1: Tài khoản & Liên kết
- **Tác nhân chính:** Người thân chính (Primary Caregiver - PC)
- **Tác nhân phụ:** CareAI Monolith Engine (.NET 10)
- **Mức độ ưu tiên:** Cao (P1 - Cốt lõi)
- **Luồng xử lý kiến trúc:** `Quản lý Hồ sơ & Token ghép nối`
- **Mục tiêu:** Khởi tạo hồ sơ quản lý sức khỏe cho người già và sinh mã PIN 6 chữ số dùng 1 lần (Single-Use Pairing Code) để ghép nối thiết bị đo Companion App.
- **Tiền điều kiện:** PC đã đăng nhập vào hệ thống với vai trò Primary Caregiver.
- **Hậu điều kiện:** Bản ghi ElderProfile được tạo trong CSDL, mối quan hệ đại diện pháp lý được xác lập trong ElderCaregiverMappings, mã PIN 6 số hiệu lực 15 phút sẵn sàng để nhập trên thiết bị của cụ.

**Luồng sự kiện chính (Main Flow):**
1. PC chọn mục 'Thêm hồ sơ người thân' trên Caregiver App.
2. PC nhập đầy đủ thông tin: Họ và tên cụ, Năm sinh, Giới tính, Địa chỉ cư trú, Số điện thoại khẩn cấp, Tiền sử bệnh lý (tim mạch, huyết áp, tiểu đường).
3. PC bấm nút 'Tạo hồ sơ và lấy mã ghép nối'.
4. Caregiver App gửi HTTP POST /api/v1/elders kèm Bearer JWT của PC và thông tin hồ sơ.
5. Backend kiểm tra tính hợp lệ của dữ liệu, mở giao dịch CSDL:
6. - Tạo bản ghi mới trong bảng ElderProfiles với trạng thái IsActive = true.
7. - Tạo bản ghi liên kết trong bảng ElderCaregiverMappings gán PC với vai trò PrimaryCaregiver (IsLegalRepresentative = true).
8. - Khởi tạo cấu hình ngưỡng lâm sàng mặc định trong DeviceClinicalStates (MinHeartRate = 50, MaxHeartRate = 110, CriticalSurgeBpm = 15).
9. - Sinh ngẫu nhiên mã PIN gồm 6 chữ số (PairingCode, ví dụ: 839201), băm SHA-256 và lưu vào bảng DevicePairingTokens với hạn sử dụng ExpiresAt = DateTime.UtcNow.AddMinutes(15) và cờ IsUsed = false.
10. Backend commit giao dịch và trả về HTTP 201 Created kèm ElderProfileId và mã PIN 6 chữ số dạng rõ (Plaintext PIN) cho PC.
11. Caregiver App hiển thị màn hình hướng dẫn kèm mã PIN nổi bật và đồng hồ đếm ngược 15 phút để PC nhập vào Companion App của cụ.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Cấp lại mã PIN ghép nối mới khi mã cũ hết hạn:**
  + Tại trang quản lý hồ sơ của cụ, PC bấm 'Tạo mã ghép nối mới'.
  + App gửi HTTP POST /api/v1/elders/{id}/pairing-code.
  + Hệ thống vô hiệu hóa các mã PIN chưa sử dụng trước đó của cụ, sinh mã PIN mới 6 số với thời hạn 15 phút và trả về cho PC.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Thiếu thông tin bắt buộc hoặc năm sinh phi logic:**
  + *Điều kiện phát sinh:* PC bỏ trống Họ tên, SĐT khẩn cấp hoặc nhập năm sinh tương lai / tuổi cụ < 40 hoặc > 130 tuổi.
  + *Cơ chế xử lý hệ thống:* Client kiểm tra và chặn thao tác; nếu yêu cầu gửi lên server, Backend từ chối với HTTP 400 Bad Request kèm chi tiết: {"error": "ValidationError", "message": "Năm sinh không hợp lệ hoặc thiếu số điện thoại khẩn cấp."}
- **E2 - Người dùng không có quyền tạo hồ sơ đại diện:**
  + *Điều kiện phát sinh:* Tài khoản có vai trò Secondary Caregiver cố gọi API tạo hồ sơ mới gắn quyền đại diện pháp lý.
  + *Cơ chế xử lý hệ thống:* Hệ thống kiểm tra Claim trong JWT và trả về HTTP 403 Forbidden với thông báo: 'Chỉ tài khoản Người thân chính mới có quyền khởi tạo hồ sơ người già'.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Mỗi hồ sơ người già chỉ có DUY NHẤT một Người thân chính (Primary Caregiver) đóng vai trò đại diện pháp lý theo quy định bảo vệ dữ liệu y tế.
- Mã PIN ghép nối là mã dùng 1 lần (Single-Use Token), có hiệu lực chính xác 15 phút (900 giây) kể từ thời điểm sinh; sau khi được sử dụng hoặc hết hạn sẽ bị hủy hiệu lực vĩnh viễn.

---

#### UC-03: Ghép nối Companion App & Cấp quyền Health Connect
- **Phân hệ:** Phân hệ 1: Tài khoản & Liên kết
- **Tác nhân chính:** Companion App (Máy của Cụ già / Đồng hồ Samsung Watch)
- **Tác nhân phụ:** Cụ già / Người thân hỗ trợ, Google Health Connect API, CareAI Monolith Engine (.NET 10)
- **Mức độ ưu tiên:** Cao (P1 - Cốt lõi)
- **Luồng xử lý kiến trúc:** `Xác thực Thiết bị & Khởi tạo Nền tảng Viễn trắc`
- **Mục tiêu:** Định danh phần cứng thiết bị, cấp khóa bảo mật dài hạn (DeviceToken JWT) gắn chặt với hồ sơ Cụ, và cấp quyền truy cập Google Health Connect để thu thập chỉ số sinh tồn từ Samsung Watch.
- **Tiền điều kiện:** Companion App đã được cài đặt trên điện thoại/đồng hồ của cụ; PC đã tạo hồ sơ và cung cấp mã PIN 6 số còn hạn (UC-02).
- **Hậu điều kiện:** Thiết bị được lưu vào DeviceRegistrations, nhận DeviceToken dài hạn, quyền Google Health Connect được cấp, Background WorkManager sẵn sàng đồng bộ dữ liệu.

**Luồng sự kiện chính (Main Flow):**
1. Người thân mở Companion App trên điện thoại của cụ già, màn hình hiển thị ô nhập mã ghép nối.
2. Người dùng nhập mã PIN 6 số (do PC cung cấp từ UC-02).
3. Companion App tự động lấy Hardware Device UUID (định danh phần cứng duy nhất) và Tên dòng máy (Model, ví dụ: 'Samsung Galaxy Watch6').
4. Companion App gửi HTTP POST /api/v1/devices/pair với body: {"pairingCode": "839201", "deviceUuid": "...", "deviceName": "Samsung Galaxy Watch6"}.
5. Backend tiếp nhận, băm SHA-256 mã PIN và tìm kiếm trong bảng DevicePairingTokens:
6. - Kiểm tra: Mã PIN tồn tại, IsUsed == false, và ExpiresAt > DateTime.UtcNow.
7. - Lấy ElderProfileId liên kết từ bản ghi mã PIN.
8. - Đánh dấu mã PIN IsUsed = true và UsedAt = DateTime.UtcNow.
9. - Tạo bản ghi mới trong bảng DeviceRegistrations: Id = Guid mới, ElderProfileId, DeviceHardwareUuid, DeviceName, IsActive = true, LastHeartbeat = DateTime.UtcNow.
10. - Sinh Access Token chuyên dụng cho thiết bị (DeviceToken JWT) có thời hạn dài hạn (1 năm), chứa các Claims: DeviceId, ElderProfileId, Role: 'Device'.
11. Backend trả về HTTP 200 OK kèm DeviceToken và thông tin hồ sơ của Cụ.
12. Companion App lưu trữ DeviceToken an toàn vào Android EncryptedSharedPreferences (Hardware Keystore).
13. Companion App kích hoạt Intent yêu cầu cấp quyền Google Health Connect: Đọc Nhịp tim (Heart Rate), Đọc Bước chân (Steps), Đọc Nồng độ Oxy trong máu (Oxygen Saturation), Đọc Huyết áp (Blood Pressure).
14. Người dùng chọn 'Cho phép tất cả' trên hộp thoại phân quyền hệ thống của Android Health Connect.
15. Companion App kiểm tra quyền đã được cấp thành công, khởi động Foreground Service giám sát và kích hoạt trình chạy ngầm Android WorkManager (TelemetrySyncWorker).

**Các luồng thay thế (Alternative Flows):**
- **A1 - Ghép nối lại thiết bị đã từng hoạt động (Re-pairing):**
  + Thiết bị đã từng được ghép nối nhưng bị xóa app hoặc cài lại, người dùng nhập mã PIN mới sinh từ PC.
  + Hệ thống phát hiện DeviceHardwareUuid đã tồn tại trong DeviceRegistrations cho cụ này.
  + Hệ thống kích hoạt lại bản ghi (IsActive = true), làm mới DeviceToken và cập nhật LastHeartbeat mà không sinh bản ghi trùng lặp.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Mã PIN không chính xác hoặc đã hết hạn:**
  + *Điều kiện phát sinh:* Mã PIN nhập sai hoặc thời gian từ lúc sinh mã đã vượt quá 15 phút.
  + *Cơ chế xử lý hệ thống:* Backend từ chối ghép nối và trả về HTTP 400 Bad Request kèm payload: {"error": "InvalidOrExpiredPairingToken", "message": "Mã PIN không chính xác hoặc đã hết hiệu lực (15 phút). Vui lòng yêu cầu người thân tạo lại mã mới."} Companion App hiển thị thông báo lỗi và cho phép nhập lại.
- **E2 - Người dùng từ chối cấp quyền Google Health Connect:**
  + *Điều kiện phát sinh:* Người dùng bấm 'Từ chối' hoặc hủy hộp thoại cấp quyền của Google Health Connect.
  + *Cơ chế xử lý hệ thống:* Companion App phát hiện thiếu quyền đọc dữ liệu (HealthConnectClient.permissionController), lập tức chuyển sang trạng thái cảnh báo: Hiển thị banner màu đỏ 'Thiếu quyền truy cập dữ liệu sức khỏe. Hệ thống không thể đọc nhịp tim từ đồng hồ'. Nút 'Mở Cài đặt để Cấp quyền' xuất hiện; chức năng đồng bộ bị tạm khóa cho đến khi đủ quyền.
- **E3 - Thiết bị không tương thích Google Health Connect:**
  + *Điều kiện phát sinh:* Điện thoại chạy phiên bản Android quá cũ (< Android 9) hoặc không có dịch vụ Google Play.
  + *Cơ chế xử lý hệ thống:* App phát hiện lỗi không tìm thấy Health Connect SDK, hiển thị thông báo: 'Thiết bị không hỗ trợ Google Health Connect. Vui lòng cài đặt ứng dụng Health Connect từ Google Play Store hoặc nâng cấp hệ điều hành Android'.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Bảo vệ Chống Mạo Danh Thiết Bị (Anti-Device-Impersonation Invariant): DeviceToken sinh ra bị khóa cứng (hard-bound) với DeviceId và ElderProfileId. Mọi gói tin gửi lên sau đó đều được kiểm tra đối chiếu; thiết bị tuyệt đối không thể gửi dữ liệu thay thế cho hồ sơ cụ khác.
- Một cụ già có thể liên kết nhiều thiết bị (ví dụ: 1 Smartwatch Samsung và 1 Điện thoại Android Companion), hệ thống quản lý danh sách thiết bị theo từng bản ghi độc lập.

---

### 2. PHÂN HỆ 2: THU THẬP & ĐỆM DỮ LIỆU VIỄN TRẮC

#### UC-04: Đồng bộ Viễn trắc Thụ động qua Health Connect (Batch-Lane)
- **Phân hệ:** Phân hệ 2: Thu thập & Đệm Dữ liệu
- **Tác nhân chính:** Companion App (Android WorkManager - Chạy ngầm định kỳ)
- **Tác nhân phụ:** Google Health Connect Client, Samsung Galaxy Watch, CareAI Monolith Engine (.NET 10)
- **Mức độ ưu tiên:** Cao (P1 - Cốt lõi)
- **Luồng xử lý kiến trúc:** `Batch-Lane (Đồng bộ định kỳ 15 phút)`
- **Mục tiêu:** Tự động trích xuất các chỉ số sinh hiệu (nhịp tim, số bước chân, SpO2, huyết áp) từ Samsung Watch thông qua Google Health Connect, đệm an toàn vào SQLite cục bộ và truyền theo lô lên máy chủ mà không làm hao pin người dùng.
- **Tiền điều kiện:** Companion App đã được ghép nối thành công (UC-03); quyền đọc dữ liệu Health Connect đã được cấp; thiết bị có pin và dịch vụ nền Android WorkManager đang hoạt động.
- **Hậu điều kiện:** Dữ liệu sinh hiệu được lưu trữ an toàn trong SQLite cục bộ (lưu 7 ngày) và được nạp thành công vào hàng đợi bộ nhớ Channel<HealthMeasurementPacket> trên máy chủ Backend.

**Luồng sự kiện chính (Main Flow):**
1. Android WorkManager định kỳ 15 phút (hoặc khi thiết bị cắm sạc/có kết nối WiFi) đánh thức tiến trình chạy ngầm TelemetrySyncWorker.
2. Worker truy vấn Google Health Connect Client để lấy toàn bộ các bản ghi đo mới phát sinh từ mốc thời gian LastSyncTimestamp đến hiện tại:
3. - Nhịp tim (HeartRateRecord): mẫu nhịp tim chi tiết (bpm) kèm dấu thời gian đo (Timestamp).
4. - Bước chân (StepsRecord): số bước chân tích lũy trong khoảng thời gian tương ứng.
5. - Nồng độ oxy trong máu (OxygenSaturationRecord) và Huyết áp (BloodPressureRecord) nếu thiết bị có hỗ trợ.
6. Worker mở CSDL SQLite cục bộ trên điện thoại (chế độ ghi nhật ký Write-Ahead Logging WAL), lưu trữ toàn bộ các mẫu đo mới vào bảng health_packets với trạng thái Synced = 0.
7. Worker đọc tối đa 500 bản ghi chưa đồng bộ (Synced = 0) từ SQLite, sắp xếp theo thứ tự thời gian tăng dần (Timestamp ASC), đóng gói thành cấu trúc JSON Batch chuẩn (TelemetryBatchRequest).
8. Companion App gửi HTTP POST /api/v1/telemetry/batch kèm Header 'Authorization: Bearer <DeviceToken>' (đường truyền Batch-Lane).
9. Máy chủ Kestrel của CareAI tiếp nhận gói tin:
10. - Kiểm tra tính hợp lệ của chữ ký DeviceToken và xác nhận vai trò Role: 'Device'.
11. - Trích xuất định danh DeviceId và ElderProfileId từ Claims.
12. - Đẩy toàn bộ danh sách mẫu đo vào hàng đợi bộ nhớ trong bị chặn kích thước Channel<HealthMeasurementPacket> (In-Memory Bounded Queue) thông qua ITelemetryChannelQueue.WriteAsync().
13. - Cập nhật mốc thời gian nhận tín hiệu LastHeartbeatAt của thiết bị trong bộ nhớ đệm (MemoryCache).
14. - Máy chủ lập tức trả về HTTP 202 Accepted trong vòng dưới 15 mili-giây mà KHÔNG chờ thao tác ghi đĩa CSDL, giải phóng ngay luồng mạng Kestrel.
15. Companion App nhận được mã phản hồi HTTP 202 Accepted:
16. - Cập nhật trạng thái Synced = 1 cho các bản ghi vừa gửi thành công trong SQLite cục bộ.
17. - Cập nhật mốc LastSyncTimestamp bằng thời gian của bản ghi mới nhất.
18. - Kích hoạt hàm dọn dẹp định kỳ purgeOldSyncedPackets(): Chỉ xóa các bản ghi đã đồng bộ (Synced = 1) có tuổi thọ LỚN HƠN 7 NGÀY, TUYỆT ĐỐI KHÔNG xóa ngay lập tức để duy trì kho lưu trữ đệm phục vụ đối soát kiểm toán và bảo vệ chống thất thoát dữ liệu.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Đồng hồ tháo khỏi tay hoặc chưa phát sinh dữ liệu mới:**
  + WorkManager thức dậy nhưng Google Health Connect trả về danh sách rỗng (do cụ tháo đồng hồ ra sạc pin hoặc không đeo).
  + Companion App không gửi gói đo rác, nhưng gửi một gói tin Heartbeat tối giản HTTP POST /api/v1/telemetry/heartbeat.
  + Server nhận Heartbeat, cập nhật LastHeartbeatAt để hệ thống giám sát kết nối (Watchdog) biết thiết bị vẫn đang sống, không tạo cảnh báo mất mạng sai.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Mất kết nối Internet (Điện thoại mất sóng 4G/WiFi):**
  + *Điều kiện phát sinh:* Thao tác gửi HTTP POST /telemetry/batch phát sinh lỗi mạng (SocketException, ConnectException, TimeoutException).
  + *Cơ chế xử lý hệ thống:* Companion App bắt ngoại lệ an toàn: Giữ nguyên toàn bộ các bản ghi trong SQLite cục bộ với cờ Synced = 0. Toàn bộ dữ liệu sinh hiệu được bảo toàn nguyên vẹn 100% trên bộ nhớ flash của điện thoại. Khi có kết nối mạng trở lại, chu kỳ WorkManager tiếp theo sẽ tự động đọc lại và xả toàn bộ dữ liệu dồn ứ lên server mà không bị mất một mẫu đo nào.
- **E2 - Token thiết bị bị thu hồi hoặc hết hạn (401 / 403):**
  + *Điều kiện phát sinh:* Người thân đã hủy ghép nối thiết bị từ xa (UC-13) hoặc token bị vô hiệu hóa.
  + *Cơ chế xử lý hệ thống:* Server trả về HTTP 401 Unauthorized hoặc 403 Forbidden. Companion App hủy đăng ký các tác vụ WorkManager định kỳ, dừng Foreground Service, chuyển sang trạng thái chờ và hiển thị thông báo: 'Thiết bị đã bị hủy liên kết khỏi hệ thống. Vui lòng liên hệ người thân để ghép nối lại'.
- **E3 - Gói tin viễn trắc sai cấu trúc (Validation Error):**
  + *Điều kiện phát sinh:* Gói tin thiếu trường bắt buộc hoặc chỉ số nhịp tim âm / phi lý (> 300 bpm).
  + *Cơ chế xử lý hệ thống:* Server trả về HTTP 400 Bad Request. Companion App chuyển các bản ghi lỗi vào bảng dead_letter_packets cục bộ để không lặp lại việc gửi gói tin độc này, tiếp tục xử lý các mẻ dữ liệu mới bình thường.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Kiến trúc Hai Luồng Tách Biệt (Dual-Lane Architecture): Dữ liệu viễn trắc định kỳ BẮT BUỘC đi qua luồng Batch-Lane (hàng đợi Channel và xử lý bất đồng bộ), TUYỆT ĐỐI KHÔNG đi qua luồng khẩn cấp Fast-Lane để giữ băng thông và CPU trống cho việc cứu nạn.
- Quy tắc lưu đệm 7 ngày: Bản ghi đã đồng bộ chỉ được xóa sau 7 ngày trong SQLite cục bộ, bảo đảm tính sẵn sàng ngoại tuyến cao.

---

#### UC-05: Lưu trữ theo Lô & Mạch Cầu dao Bảo vệ RAM (Batch Ingestion & RAM Shield)
- **Phân hệ:** Phân hệ 2: Thu thập & Đệm Dữ liệu
- **Tác nhân chính:** CareAI Monolith Engine (TelemetryBatchProcessor Worker)
- **Tác nhân phụ:** ITelemetryChannelQueue (In-Memory Queue), Azure SQL Database (Gói 5 DTU Free-Tier)
- **Mức độ ưu tiên:** Cao (P1 - Cốt lõi)
- **Luồng xử lý kiến trúc:** `In-Process Background Worker / Bulk Database Storage`
- **Mục tiêu:** Tiêu thụ các gói tin viễn trắc từ hàng đợi bộ nhớ, chèn hàng loạt (Bulk Insert) vào CSDL Azure SQL một cách bền vững, có cơ chế thử lại thông minh chống mất dữ liệu khi DB quá tải và kích hoạt mạch cầu dao bảo vệ RAM máy chủ không bị OOM (Out-of-Memory).
- **Tiền điều kiện:** Backend Monolith .NET 10 đang chạy; hàng đợi Channel<HealthMeasurementPacket> có dữ liệu viễn trắc do UC-04 gửi lên.
- **Hậu điều kiện:** Các mẫu đo sinh hiệu được ghi bền vững vào bảng HealthMeasurements; bảng nhật ký ProcessedTelemetryLedgers được cập nhật để chống trùng lặp; chỉ số nhịp tim được gửi tới Engine thẩm định lâm sàng.

**Luồng sự kiện chính (Main Flow):**
1. Tiến trình nền TelemetryBatchProcessor (kế thừa BackgroundService) chạy ngầm liên tục, lắng nghe kênh dữ liệu Channel.Reader.ReadAllAsync().
2. Worker thu thập các gói tin viễn trắc vào bộ đệm RAM cục bộ (List<HealthMeasurementPacket> buffer):
3. - Kích thước mẻ tối đa (Batch Size): 100 gói tin.
4. - Thời gian chờ tối đa (Flush Timeout): 1.000 mili-giây (1 giây). Khi đủ 100 gói hoặc hết 1 giây (tùy điều kiện nào đến trước), mẻ dữ liệu được kích hoạt xử lý.
5. Worker khởi tạo một IServiceScope mới, lấy đối tượng CareAiDbContext và HardenedTelemetryEngine.
6. Worker tiến hành tiền lọc chống trùng lặp (Idempotency Pre-filter): Đối chiếu mã định danh mẫu đo (SampleId / PacketId) với bảng ProcessedTelemetryLedgers, loại bỏ các mẫu đo đã từng được ghi trước đó.
7. Worker chuyển từng mẫu đo nhịp tim hợp lệ qua HardenedTelemetryEngine để thẩm định luật lâm sàng tức thời (chuyển sang UC-06).
8. Worker mở giao dịch CSDL, thực thi Bulk Insert danh sách thực thể HealthMeasurement vào bảng HealthMeasurements trên Azure SQL.
9. Đồng thời chèn các bản ghi nhật ký vào bảng ProcessedTelemetryLedgers.
10. Thực thi await db.SaveChangesAsync(). Giao dịch hoàn tất thành công (Commit):
11. - Đặt lại biến đếm lỗi thử lại _batchRetryCount = 0.
12. - Xóa sạch bộ đệm buffer.Clear().
13. - Tiếp tục vòng lặp tiêu thụ mẻ tiếp theo từ Channel.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Lưu lượng thấp trong đêm (Tự động xả mẻ nhỏ):**
  + Trong khung giờ ban đêm, số lượng người dùng gửi dữ liệu ít, hàng đợi chỉ có từ 1 đến 5 gói tin.
  + Hết thời gian chờ 1.000ms, Worker tự động xả ngay các gói tin hiện có vào CSDL mà không đợi đủ 100 gói, đảm bảo dữ liệu hiển thị trên Dashboard của gia đình luôn tươi mới với độ trễ tối đa không quá 1 giây.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Azure SQL quá tải hoặc lỗi mạng chớp nhoáng (5 DTU Throttling / Transient Fault):**
  + *Điều kiện phát sinh:* Thao tác SaveChangesAsync() ném ngoại lệ SqlException (các mã lỗi mạng tạm thời 40613, 40197, 10928 do chạm trần tài nguyên Azure SQL 5 DTU).
  + *Cơ chế xử lý hệ thống:* Hệ thống kích hoạt Mạch Thử Lại Lỗi Tạm Thời (Transient Retry Circuit): Worker TUYỆT ĐỐI KHÔNG xóa buffer trong khối finally mù quáng. Tăng biến đếm _batchRetryCount += 1. Nếu _batchRetryCount < 5: Giữ nguyên 100% dữ liệu mẻ đo trong RAM, hoãn tiến trình trong 5 giây (Task.Delay(5000)) để Azure SQL hạ nhiệt tài nguyên, sau đó thử ghi lại chính xác mẻ này ở chu kỳ kế tiếp. Nhờ có bộ lọc ProcessedTelemetryLedgers, việc ghi lại bảo đảm không bao giờ gây trùng lặp dữ liệu.
- **E2 - Mẻ dữ liệu lỗi nghiêm trọng lặp lại liên tiếp (Poison Pill Batch):**
  + *Điều kiện phát sinh:* Một mẻ dữ liệu thử lại thất bại liên tiếp 5 lần (_batchRetryCount >= 5).
  + *Cơ chế xử lý hệ thống:* Để giải phóng Worker không bị kẹt vô tận và giải phóng bộ nhớ RAM: Worker trích xuất toàn bộ mẻ dữ liệu lỗi, chuyển đổi thành chuỗi JSON và ghi vào bảng DeadLetterBatches trên CSDL cùng nguyên nhân lỗi. Sau khi đã lưu dự phòng vào Dead Letter, Worker mới thực hiện buffer.Clear(), đặt lại _batchRetryCount = 0 và ghi log cảnh báo mức Critical để kỹ thuật viên kiểm tra.
- **E3 - Mạch cầu dao bảo vệ RAM máy chủ (RAM OOM Circuit Breaker):**
  + *Điều kiện phát sinh:* Hạ tầng máy chủ gói tiết kiệm (Azure B1s/F1 với 1GB RAM) gặp tình huống số lượng gói tin trong hàng đợi Channel vượt quá 10.000 phần tử (do DB bảo trì kéo dài).
  + *Cơ chế xử lý hệ thống:* Cầu dao kích hoạt cơ chế tự bảo vệ: Áp dụng Backpressure tại tầng Kestrel (trả về HTTP 429 Too Many Requests đối với các gói tin viễn trắc bước chân thứ cấp), ưu tiên tuyệt đối giữ lại các gói tin nhịp tim và cờ SOS. Cấu hình MemoryCache nghiêm ngặt SizeLimit = 50,000 và thời gian sống TTL = 2 phút, đảm bảo tiến trình Monolith không bao giờ tiêu thụ quá 700MB RAM, triệt tiêu 100% nguy cơ sập ứng dụng do Out-Of-Memory.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Bảo Toàn Dữ Liệu Sinh Hiệu (Data Integrity Invariant): Mọi lỗi tạm thời của CSDL đều không được phép làm mất mẫu đo của bệnh nhân; hệ thống phải giữ trong bộ nhớ đệm và thử lại tối thiểu 5 lần trước khi chuyển sang Dead Letter.
- Xử lý đơn luồng tiêu thụ (Single Consumer): Tiến trình Worker xử lý tuần tự trên từng phân vùng thiết bị để bảo đảm tuyệt đối tính thứ tự thời gian của các mẫu đo y tế.

---

### 3. PHÂN HỆ 3: ENGINE CẢNH BÁO & GIÁM SÁT HỆ THỐNG

#### UC-06: Thẩm định Luật Lâm sàng & Leo thang Cấp cứu (Clinical Engine)
- **Phân hệ:** Phân hệ 3: Engine Cảnh báo
- **Tác nhân chính:** CareAI Monolith Engine (HardenedTelemetryEngine & ClinicalWatchdogWorker)
- **Tác nhân phụ:** NotificationOutbox, Google FCM Service, Người thân trong gia đình
- **Mức độ ưu tiên:** Khẩn cấp (P0 - Sinh tử)
- **Luồng xử lý kiến trúc:** `In-Memory Clinical Evaluation / Real-time Alerting`
- **Mục tiêu:** Phân tích tức thời từng chỉ số nhịp tim của người già theo các ngưỡng y tế cá nhân hóa, phát hiện các cơn nguy kịch tim mạch đe dọa tính mạng và tự động leo thang báo động tới người thân.
- **Tiền điều kiện:** Gói tin viễn trắc nhịp tim vừa được giải mã; hồ sơ cụ già đã được liên kết với cấu hình ngưỡng trong DeviceClinicalStates.
- **Hậu điều kiện:** Tạo bản ghi Incident nếu có vi phạm; đưa lệnh thông báo ưu tiên cao vào bảng NotificationOutbox; tự động tái kích hoạt báo động nếu tình trạng tái phát nặng hơn.

**Luồng sự kiện chính (Main Flow):**
1. HardenedTelemetryEngine nhận mẫu đo nhịp tim (HR) kèm định danh ElderProfileId và thời điểm đo.
2. Engine truy xuất cấu hình ngưỡng lâm sàng của cụ già từ bộ nhớ đệm (MemoryCache) hoặc bảng DeviceClinicalStates (ngưỡng mặc định: Min = 50 bpm, Max = 110 bpm, Surge = 15 bpm, Debounce = 10 phút).
3. Engine thực thi kiểm tra theo ma trận quy tắc y tế:
4. - Tình trạng Bình thường: 50 <= HR <= 110 bpm -> Không phát sinh cảnh báo, ghi nhận trạng thái bình thường.
5. - Tình trạng Nhịp nhanh / Nhịp chậm thông thường: HR > 110 bpm hoặc HR < 50 bpm -> Đánh dấu vi phạm mức Cảnh báo (IncidentSeverity.Warning).
6. - TÌNH TRẠNG NGUY KỊCH LÂM SÀNG (CLINICAL ESCALATION):
7.   + HR >= 180 bpm (Nghi ngờ Cơn Rung thất / Tim nhanh thất kịch phát) HOẶC HR <= 35 bpm (Nhịp tim chậm nguy kịch / Nguy cơ vô tâm thu ngừng tuần hoàn): Engine lập tức nâng mức nghiêm trọng lên Khẩn cấp (IncidentSeverity.Critical)!
8.   + Tăng nhịp tim đột ngột (Sudden Surge): Nhịp tim tăng vọt >= 15 bpm trong vòng 1 phút mà dữ liệu bước chân bằng 0 (người già đang ngồi nghỉ hoặc nằm ngủ): Kích hoạt cảnh báo tăng nhịp tim bất thường mức Warning.
9. Engine áp dụng Cửa Sổ Khử Trùng Lặp & Chống Báo Động Rác (Debounce Cooldown Window - 10 phút):
10. - Kiểm tra CSDL xem cụ già có sự cố cùng loại đang ở trạng thái Open hoặc Acknowledged trong vòng 10 phút qua hay không.
11. - Nếu có sự cố đang mở và mức độ nghiêm trọng không tăng: Bỏ qua tạo bản ghi mới, ghi log kiểm toán nội bộ để không spam hàng loạt thông báo làm hoảng loạn gia đình.
12. Nếu thỏa mãn điều kiện tạo mới:
13. - Khởi tạo thực thể Incident: Id = Guid mới, ElderProfileId, EmergencyType = 'ABNORMAL_HEART_RATE', Severity = Warning hoặc Critical, Status = IncidentStatus.Open, TriggeredAt = DateTime.UtcNow, MetricValue = HR.
14. - Lưu bản ghi Incident vào CSDL Azure SQL.
15. - Thêm bản ghi thông báo vào bảng NotificationOutbox: RecipientType = 'CAREGIVER_ALL', Priority = 'HIGH', PayloadJson chứa chi tiết sự cố và chỉ số vi phạm.
16. - Đánh thức tiến trình NotificationDispatcherWorker tức thời qua kênh in-memory để bắn thông báo đẩy Google FCM (High Priority) kích hoạt chuông còi hú trên điện thoại của người thân.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Tái kích hoạt báo động khi tái phát nguy kịch (Re-escalation Invariant):**
  + Người thân đã bấm 'Tiếp nhận' (Sự cố đang ở trạng thái Acknowledged).
  + Khoảng 3 phút sau, mẫu đo mới gửi về ghi nhận nhịp tim của cụ đột ngột tăng vọt lên mức tử thần HR >= 180 bpm.
  + Engine phát hiện tình trạng chuyển biến xấu nghiêm trọng:
  + - Tự động chuyển trạng thái của Incident từ Acknowledged trở lại Open (Re-open).
  + - Nâng mức nghiêm trọng lên IncidentSeverity.Critical.
  + - Cập nhật ghi chú: 'CẢNH BÁO TÁI PHÁT: Nhịp tim chuyển biến nguy kịch lên 185 bpm sau khi đã tiếp nhận!'.
  + - Đẩy ngay đợt thông báo Outbox khẩn cấp lần 2 tới toàn bộ người thân chính và phụ để yêu cầu can thiệp y tế tức thời.
- **A2 - Tự động hồi phục khi nhịp tim ổn định (Auto-Recovery):**
  + Sự cố cảnh báo nhịp tim đang ở trạng thái Open (chưa có người thân nào kịp mở máy tiếp nhận).
  + Các gói viễn trắc đo đạc liên tiếp trong 5 phút tiếp theo đều trả về chỉ số nhịp tim ổn định nằm gọn trong dải an toàn (ví dụ: 72 bpm).
  + Engine tự động cập nhật trạng thái Incident sang IncidentStatus.Resolved kèm ghi chú: 'Hệ thống tự động đóng: Chỉ số sinh tồn của Cụ đã trở lại dải an toàn (72 bpm) trong 5 phút liên tục'.
  + Gửi thông báo nhẹ nhàng cho người thân: 'Chỉ số nhịp tim của Cụ đã ổn định trở lại mức an toàn'.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Xung đột tương tranh dữ liệu (OCC Concurrency Collision):**
  + *Điều kiện phát sinh:* Nhiều luồng xử lý viễn trắc đồng thời cùng cập nhật bản ghi Incident của một cụ già.
  + *Cơ chế xử lý hệ thống:* Hệ thống bắt ngoại lệ DbUpdateConcurrencyException: Tải lại bản ghi mới nhất từ CSDL qua GetDatabaseValuesAsync(), áp dụng nguyên tắc bảo tồn Dấu Vết Kiểm Toán Pháp Y (Medical Forensic Audit Trail) - không ghi đè mất thông tin đo ban đầu, thử lại tối đa 3 lần với thuật toán Jitter ngẫu nhiên (5-15ms) trước khi hoàn tất lưu CSDL.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Bất biến về Tái mở Sự cố (Re-escalation Invariant): Sự cố đang Acknowledged BẮT BUỘC phải tự động mở lại Open nếu xuất hiện mẫu đo nguy kịch mới (HR >= 180 bpm hoặc <= 35 bpm) để bảo vệ mạng sống của người già.
- Quy tắc chống trùng lặp 10 phút: Ngăn chặn gửi hàng trăm thông báo rác khi người già bị nhịp nhanh kéo dài nhưng không tăng mức độ nguy hiểm.

---

#### UC-07: Giám sát Mất kết nối Đa thiết bị (Multi-Device Watchdog)
- **Phân hệ:** Phân hệ 3: Engine Cảnh báo
- **Tác nhân chính:** CareAI Monolith Engine (DeviceStaleWorker)
- **Tác nhân phụ:** DeviceRegistrations, Incidents, NotificationOutbox, Người thân chính
- **Mức độ ưu tiên:** Cao (P1 - Cốt lõi)
- **Luồng xử lý kiến trúc:** `In-Process Background Worker (Quét chu kỳ 60 giây)`
- **Mục tiêu:** Phát hiện kịp thời trường hợp đồng hồ hoặc điện thoại của người già bị hết pin, tắt nguồn, rớt mạng hoặc mất sóng để thông báo cho gia đình, với cơ chế tập hợp đa thiết bị chống báo động giả và cơ chế tự động phục hồi độc lập.
- **Tiền điều kiện:** Hệ thống CareAI Monolith đang hoạt động; cụ già có ít nhất một thiết bị đã đăng ký; DeviceStaleWorker đang chạy theo lịch trình.
- **Hậu điều kiện:** Tạo sự cố DeviceDisconnected nếu toàn bộ thiết bị mất tín hiệu quá 5 phút; tự động đóng sự cố sang Resolved khi thiết bị có tín hiệu trở lại.

**Luồng sự kiện chính (Main Flow):**
1. Tiến trình DeviceStaleWorker được kích hoạt tự động theo chu kỳ định kỳ đúng 60 giây / lần (TimeSpan.FromSeconds(60)).
2. Worker tính toán mốc thời gian mất kết nối vật lý: StaleThreshold = DateTime.UtcNow.AddMinutes(-5) (ngưỡng 5 phút không có tín hiệu).
3. Worker truy vấn bảng DeviceRegistrations lấy danh sách các thiết bị đang kích hoạt (IsActive == true) có mốc LastHeartbeat < StaleThreshold.
4. KIỂM TRA TẬP HỢP ĐA THIẾT BỊ (MULTI-DEVICE AGGREGATION):
5. - Worker gom nhóm danh sách thiết bị theo từng cụ già (GroupBy(d => d.ElderProfileId)).
6. - Với mỗi cụ, Worker tính toán thời điểm nhận tín hiệu mới nhất trong TẤT CẢ các thiết bị của cụ: maxHeartbeat = Group.Max(d => d.LastHeartbeat).
7. - QUY TẮC CỐT LÕI: Chỉ khi TẤT CẢ các thiết bị của cụ già đều có maxHeartbeat < StaleThreshold (mất liên lạc hoàn toàn trên mọi phương tiện), hệ thống mới kết luận cụ bị mất kết nối!
8. - Nếu cụ đeo đồng hồ bị hết pin nhưng điện thoại Companion vẫn đang gửi tín hiệu Heartbeat bình thường, hệ thống KHÔNG kích hoạt sự cố mất tín hiệu toàn phần.
9. QUY TẮC ỨC CHẾ CẢNH BÁO KHI CÓ CẤP CỨU (EMERGENCY SUPPRESSION RULE):
10. - Worker truy vấn xem cụ già có đang có sự cố Cấp cứu khẩn cấp (EmergencyType là 'SOS' hoặc 'FALL') ở trạng thái Open hoặc Acknowledged hay không.
11. - NẾU ĐANG CÓ CẤP CỨU: Worker TỰ ĐỘNG BỎ QUA (SUPPRESS) việc tạo sự cố mất kết nối mới nhằm tuân thủ ràng buộc Unique Index (UIX_Incidents_SingleActiveElder) và tránh làm phân tâm người nhà bằng tin nhắn rác về đường truyền khi tính mạng cụ đang ngàn cân treo sợi tóc!
12. - Worker chỉ ghi chú thêm vào sự cố cấp cứu hiện tại: 'CẢNH BÁO NGUY HIỂM: Toàn bộ thiết bị đã mất tín hiệu ngầm trong quá trình cấp cứu!'.
13. Nếu cụ già đang bình thường và chưa có sự cố mất kết nối nào đang mở:
14. - Worker tạo bản ghi Incident mới: EmergencyType = 'DEVICE_STALE_DISCONNECTED', Severity = IncidentSeverity.Warning (hoặc High), Status = IncidentStatus.Open, Notes = 'Toàn bộ thiết bị theo dõi của người cao tuổi không gửi dữ liệu quá 5 phút.'.
15. - Đẩy lệnh thông báo vào bảng NotificationOutbox gửi tới Người thân chính (Primary Caregiver).
16. - Lưu vào CSDL Azure SQL.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Tự động phục hồi độc lập khi thiết bị kết nối lại (Decoupled Auto-Resolution):**
  + Worker kích hoạt Pha 2 độc lập hoàn toàn: Truy vấn danh sách các sự cố có EmergencyType == 'DEVICE_STALE_DISCONNECTED' đang ở trạng thái Open hoặc Acknowledged.
  + Với mỗi sự cố mất kết nối, Worker kiểm tra lại mốc LastHeartbeat mới nhất của cụ già.
  + Nếu phát hiện thiết bị đã kết nối lại và có tín hiệu mới (maxHeartbeat >= StaleThreshold):
  + - Worker tự động cập nhật trạng thái sự cố sang IncidentStatus.Resolved.
  + - Cập nhật ResolvedAt = DateTime.UtcNow.
  + - Bổ sung ghi chú: 'Hệ thống tự động đóng: Thiết bị đã kết nối và truyền dữ liệu trở lại bình thường'.
  + - Lưu CSDL và gửi thông báo nhẹ cho người thân: 'Thiết bị của Cụ đã kết nối lại bình thường'.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Sự cố mất kết nối cũ vẫn đang mở (Spam Prevention):**
  + *Điều kiện phát sinh:* Cụ già đã bị mất kết nối từ trước và sự cố DeviceDisconnected vẫn đang ở trạng thái Open hoặc Acknowledged.
  + *Cơ chế xử lý hệ thống:* Worker kiểm tra thấy đã tồn tại sự cố mất kết nối đang Active, lập tức bỏ qua không tạo thêm bản ghi mới, bảo vệ tuyệt đối ràng buộc CSDL và ngăn ngừa gửi thông báo rác lặp lại mỗi 60 giây.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Chu kỳ quét vật lý: Chính xác 60 giây / lần; Ngưỡng xác định mất kết nối vật lý: Chính xác 5 phút (300 giây) không nhận được bất kỳ gói tin nào từ mọi thiết bị của cụ.
- Quy tắc Ức chế Cấp cứu (Suppression Invariant): Tuyệt đối không tạo sự cố mất kết nối mới đè lên sự cố SOS hoặc Té ngã đang diễn ra.
- Tự động phục hồi tách lập (Decoupled Resolution): Tiến trình phục hồi quét độc lập trên CSDL, không phụ thuộc vào danh sách thiết bị lỗi của Pha 1.

---

### 4. PHÂN HỆ 4: PHẢN ỨNG SỰ CỐ & CẤP CỨU

#### UC-08: Tiếp nhận Sự cố & Xử lý Khẩn cấp (Acknowledge & Resolution)
- **Phân hệ:** Phân hệ 4: Phản ứng Sự cố
- **Tác nhân chính:** Caregiver (Người thân chính hoặc Người thân phụ)
- **Tác nhân phụ:** CareAI Monolith Engine (.NET 10), Caregiver App (Flutter), Đầu số Cấp cứu 115
- **Mức độ ưu tiên:** Khẩn cấp (P0 - Sinh tử)
- **Luồng xử lý kiến trúc:** `Fast-Action API / Concurrency OCC / Human-in-the-Loop`
- **Mục tiêu:** Xác nhận tiếp nhận xử lý sự cố khẩn cấp, giải tỏa còi hú báo động, kích hoạt các kênh liên lạc cứu nạn nhanh (Gọi điện cho cụ / Gọi 115), và kết thúc đóng sự cố sau khi người già đã an toàn.
- **Tiền điều kiện:** Người thân nhận được thông báo đẩy FCM khẩn cấp hoặc mở ứng dụng khi đang có sự cố ở trạng thái Open.
- **Hậu điều kiện:** Trạng thái sự cố chuyển sang Acknowledged (ghi nhận danh tính người tiếp nhận và thời điểm); khi hoàn tất cứu nạn chuyển sang Resolved kèm ghi chú y tế.

**Luồng sự kiện chính (Main Flow):**
1. Người thân nhấn vào thông báo đẩy FCM khẩn cấp trên điện thoại -> Ứng dụng Caregiver App mở trực tiếp Màn hình Chi tiết Sự cố.
2. Màn hình hiển thị toàn bộ bối cảnh cấp cứu: Loại sự cố (Té ngã / SOS / Nhịp tim bất thường), Thời điểm kích hoạt, Chỉ số đo lúc xảy ra, và Vị trí GPS của cụ già trên bản đồ.
3. Người thân bấm nút nổi bật 'TÔI TIẾP NHẬN' (Acknowledge).
4. Ứng dụng gửi yêu cầu HTTP POST /api/v1/incidents/{id}/acknowledge kèm Bearer JWT của người thân.
5. Backend Kestrel tiếp nhận và thực thi chuỗi kiểm soát chặt chẽ:
6. - KIỂM TRA PHÂN QUYỀN CHỐNG BOLA (Broken Object Level Authorization): Kiểm tra người dùng hiện tại có nằm trong danh sách ElderCaregiverMappings được phân công chăm sóc cụ già này hay không. Nếu không -> Từ chối ngay với HTTP 403 Forbidden.
7. - KIỂM SOÁT TƯƠNG TRANH LẠC QUAN (Optimistic Concurrency Control - OCC):
8.   + Kiểm tra trạng thái hiện tại: Incident.Status == IncidentStatus.Open.
9.   + Gán Status = IncidentStatus.Acknowledged, AcknowledgedByCaregiverId = currentUserId, AcknowledgedAt = DateTime.UtcNow.
10.   + Thực thi await db.SaveChangesAsync() với trường kiểm tra phiên bản RowVersion (kiểu byte[] trong SQL Server).
11. Backend trả về HTTP 200 OK kèm thông tin cập nhật của sự cố.
12. Giao diện Caregiver App chuyển sang chế độ Ứng Phó Cứu Hộ (Rescue Mode):
13. - Còi hú trên điện thoại tắt.
14. - Xuất hiện banner thông báo: 'Đã tiếp nhận bởi [Tên người thân] lúc [HH:mm]'.
15. - Hiển thị 2 nút hành động nhanh:
16.   + Nút 'Gọi điện cho Cụ': Bấm vào sẽ mở ngay trình gọi điện thoại của máy với số của cụ già.
17.   + Nút 'Gọi Cấp cứu 115': Bấm vào sẽ quay số khẩn cấp 115 kèm hướng dẫn đọc nhanh địa chỉ nhà của cụ.
18. Sau khi người thân đã liên hệ kiểm tra hoặc trực tiếp đến hỗ trợ cụ già an toàn:
19. - Người thân bấm nút 'HOÀN TẤT XỬ LÝ' (Resolve).
20. - Nhập ghi chú y tế (Resolution Notes, ví dụ: 'Cụ bị vấp thảm ngã nhẹ, không trầy xước, nhịp tim đã ổn định trở lại').
21. - App gửi HTTP POST /api/v1/incidents/{id}/resolve kèm ghi chú.
22. - Backend chuyển trạng thái sang IncidentStatus.Resolved, gán ResolvedAt = DateTime.UtcNow và ResolvedByCaregiverId = currentUserId.
23. - Sự cố được đóng vĩnh viễn và lưu vào Dấu vết Kiểm toán Pháp y.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Xung đột tiếp nhận đồng thời (Hai người thân cùng bấm tiếp nhận):**
  + Người thân A và Người thân B cùng nhận được báo động. Người thân A bấm tiếp nhận trước Người thân B 2 giây.
  + Yêu cầu của Người thân B gửi lên khi bản ghi đã được cập nhật RowVersion mới.
  + Hệ thống phát hiện xung đột tương tranh hoặc trạng thái đã là Acknowledged, trả về HTTP 409 Conflict kèm thông tin: {"message": "Sự cố đã được [Tên Người Thân A] tiếp nhận lúc 14:32:15."}.
  + Caregiver App của Người thân B tự động cập nhật giao diện, làm mờ nút Tiếp nhận và hiển thị thông báo Người thân A đang xử lý, tránh việc gọi điện trùng lặp gây rối loạn.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Người dùng không được phân quyền theo dõi cụ (BOLA Attack):**
  + *Điều kiện phát sinh:* Caregiver của một gia đình khác cố tình gọi API tiếp nhận sự cố của cụ già này.
  + *Cơ chế xử lý hệ thống:* Backend phát hiện UserId không có bản ghi liên kết trong ElderCaregiverMappings, lập tức từ chối và trả về HTTP 403 Forbidden kèm mã lỗi: {"error": "ForbiddenAccess", "message": "Bạn không có quyền tiếp nhận sự cố của người cao tuổi này."}
- **E2 - Tiếp nhận sự cố đã đóng (Already Resolved):**
  + *Điều kiện phát sinh:* Người dùng mở app chậm và bấm tiếp nhận khi sự cố đã được đóng từ trước.
  + *Cơ chế xử lý hệ thống:* Backend kiểm tra trạng thái Incident.Status == IncidentStatus.Resolved, trả về HTTP 400 Bad Request kèm thông báo: 'Sự cố này đã được hoàn tất xử lý trước đó'.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Kiểm soát Tương tranh Lạc quan (OCC Invariant): Sử dụng token RowVersion để triệt tiêu 100% lỗi Lost Update khi nhiều người thân cùng thao tác trong tích tắc.
- Quy trình Đóng Sự Cố Bắt Buộc Có Con Người Can Thiệp (Human-in-the-Loop): Một sự cố nguy kịch (SOS/Ngã) một khi đã ghi nhận thì chỉ có Người thân hoặc Bác sĩ mới có quyền bấm Hoàn tất xử lý (Resolve) sau khi đã xác minh thể trạng thực tế của cụ.

---

#### UC-09: Phát Cấp cứu SOS & Cảnh báo Ngã kèm Hủy Cục bộ (Fast-Lane Emergency)
- **Phân hệ:** Phân hệ 4: Phản ứng Sự cố
- **Tác nhân chính:** Người cao tuổi (Elder) & Companion App
- **Tác nhân phụ:** CareAI Monolith Engine (.NET 10), Google FCM Push Service, Người thân trong gia đình
- **Mức độ ưu tiên:** Khẩn cấp (P0 - Sinh tử)
- **Luồng xử lý kiến trúc:** `Fast-Lane (< 50ms Ghi CSDL / < 3s Bắn Còi Hú)`
- **Mục tiêu:** Kích hoạt báo động cứu sinh tức thời khi cụ già bấm nút SOS hoặc bị té ngã, bảo đảm truyền tín hiệu tới điện thoại gia đình dưới 3 giây, đồng thời loại trừ triệt để báo động giả thông qua Cửa sổ Hủy Cục bộ 30 giây.
- **Tiền điều kiện:** Companion App đang hoạt động trên điện thoại hoặc đồng hồ của cụ già; cụ gặp tai nạn té ngã hoặc bấm nút khẩn cấp.
- **Hậu điều kiện:** Nếu hủy kịp trong 30 giây: Hủy cục bộ tại máy, không gửi dữ liệu lên server; Nếu quá 30 giây hoặc bấm SOS: Tạo sự cố Critical trên máy chủ, kích hoạt còi hú FCM khẩn cấp tới toàn bộ gia đình.

**Luồng sự kiện chính (Main Flow):**
1. TÌNH HUỐNG 1: THUẬT TOÁN PHÁT HIỆN TÉ NGÃ (FALL DETECTION):
2. - Cảm biến gia tốc trên Samsung Watch / Điện thoại ghi nhận cú va chạm chấn động đột ngột kèm trạng thái bất động sau ngã.
3. - Companion App lập tức kích hoạt CỬA SỔ HỦY CỤC BỘ 30 GIÂY (30-Second Local Abort Window):
4.   + Màn hình thiết bị phát sáng tối đa, phát chuông bíp cảnh báo to dần và rung liên tục.
5.   + Hiển thị đồng hồ đếm ngược từ 30 giây kèm nút bấm to màu xanh: 'TÔI ỔN / CON KHÔNG SAO'.
6. - KỊCH BẢN HỦY BÁO ĐỘNG GIẢ TẠI THIẾT BỊ (LOCAL FALSE ALARM ABORT):
7.   + Nếu cụ chỉ vô tình đánh rơi máy hoặc trượt nhẹ tự đứng dậy được, cụ bấm nút 'TÔI ỔN' trong vòng 30 giây đếm ngược.
8.   + Companion App HỦY TIẾN TRÌNH BÁO ĐỘNG NGAY TRÊN THIẾT BỊ.
9.   + BẤT BIẾN QUAN TRỌNG: Thiết bị TUYỆT ĐỐI KHÔNG GỬI BẤT KỲ GÓI TIN BÁO ĐỘNG NÀO LÊN SERVER. Người thân hoàn toàn không bị làm phiền, tiết kiệm 100% tài nguyên mạng và hạn mức FCM.
10. - KỊCH BẢN KHẲNG ĐỊNH CẤP CỨU (EMERGENCY DISPATCH):
11.   + Nếu hết 30 giây đếm ngược mà cụ không bấm nút, hoặc cụ bấm ngay nút 'CẤP CỨU NGAY':
12.   + Companion App kích hoạt luồng khẩn cấp FAST-LANE: Bỏ qua toàn bộ hàng đợi viễn trắc thông thường, lấy ngay tọa độ GPS hiện tại.
13.   + Gửi yêu cầu HTTP POST /api/v1/incidents/sos kèm Bearer DeviceToken và body chứa tọa độ GPS.
14. TÌNH HUỐNG 2: CỤ GIÀ BẤM NÚT SOS THỦ CÔNG:
15. - Cụ già cảm thấy mệt mỏi, khó thở hoặc đau ngực, cụ bấm giữ nút SOS màu đỏ to trên màn hình Companion App trong 2 giây.
16. - Thiết bị rung xác nhận và gửi thẳng yêu cầu Fast-Lane lên server mà không cần đếm ngược.
17. XỬ LÝ FAST-LANE TRÊN CAREAI MONOLITH ENGINE:
18. - BẢO VỆ CHỐNG MẠO DANH THIẾT BỊ (ANTI-DEVICE-IMPERSONATION BOLA): Server xác thực DeviceToken, lấy ValidatedDeviceId từ Claims, đối chiếu với CSDL để bảo đảm thiết bị này thuộc quyền sở hữu của cụ già.
19. - Khởi tạo thực thể Incident: EmergencyType = 'FALL' hoặc 'SOS', Severity = IncidentSeverity.Critical, Status = IncidentStatus.Open, TriggeredAt = DateTime.UtcNow, GPSLocation.
20. - Ghi đồng bộ trực tiếp xuống Azure SQL trong vòng dưới 50 mili-giây.
21. - Ghi lệnh thông báo vào NotificationOutbox với Priority = 'CRITICAL'.
22. - Worker đánh thức tức thời gửi thông báo Google FCM (High Priority Data Message) tới toàn bộ người thân.
23. Chuông còi hú cứu thương kích hoạt trên máy của toàn bộ người thân trong gia đình trong vòng dưới 3 giây kể từ khi gói tin rời khỏi máy cụ.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Dự phòng khi mất kết nối mạng (Offline Telephony Fallback):**
  + Khi cụ già bấm SOS hoặc hết thời gian đếm ngược ngã nhưng điện thoại hoàn toàn mất kết nối 4G/WiFi.
  + Companion App phát hiện lỗi mạng không thể gửi HTTP POST lên máy chủ.
  + Ứng dụng tự động kích hoạt Cơ chế Dự phòng Viễn thông (Telephony Fallback): Tự động mở trình quay số và gọi thẳng vào Số điện thoại khẩn cấp của Người thân chính (hoặc đầu số 115) thông qua sóng di động thoại GSM truyền thống.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Mạo danh thiết bị gửi tín hiệu SOS giả (Device Impersonation Attack):**
  + *Điều kiện phát sinh:* Kẻ tấn công đánh cắp token của thiết bị A nhưng gửi SOS cho cụ B.
  + *Cơ chế xử lý hệ thống:* Backend phát hiện sự sai lệch giữa ValidatedDeviceId trong Token và ElderProfileId chỉ định trong URL/body, từ chối xử lý và trả về HTTP 403 Forbidden kèm ghi log cảnh báo an ninh.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- BẤT BIẾN MÁY TRẠNG THÁI SERVER: TUYỆT ĐỐI KHÔNG TỒN TẠI TRẠNG THÁI 'Cancelled' TRÊN SERVER!
- Enum IncidentStatus trên Backend chỉ có đúng 3 giá trị: Open, Acknowledged, Resolved. Một khi tín hiệu SOS đã truyền thành công lên máy chủ, đây là một sự kiện cấp cứu chính thức có giá trị pháp lý, TUYỆT ĐỐI KHÔNG cho phép cụ già (vốn có thể bị mê sảng hoặc kẻ xấu ép buộc) tự bấm hủy trên server. Chỉ có người thân hoặc bác sĩ mới có quyền đóng sự cố qua API /resolve.
- Ưu tiên tối thượng của luồng Fast-Lane: Bỏ qua mọi hàng đợi đệm, ghi trực tiếp CSDL và phát thông báo còi hú trong thời gian < 3 giây.

---

#### UC-10: Bảng điều khiển Sức khỏe Trực tiếp & Bản đồ Vị trí (Live Dashboard)
- **Phân hệ:** Phân hệ 4: Phản ứng Sự cố
- **Tác nhân chính:** Caregiver (Người thân chính hoặc Người thân phụ)
- **Tác nhân phụ:** CareAI Monolith Engine (.NET 10), SignalR Real-Time WebSocket, OpenStreetMap API
- **Mức độ ưu tiên:** Trung bình (P2 - Trực quan hóa)
- **Luồng xử lý kiến trúc:** `SignalR WebSocket / REST Read-Optimized API`
- **Mục tiêu:** Cung cấp cho gia đình cái nhìn trực quan, thời gian thực về tình trạng thể trạng tổng quan, vị trí địa lý trên bản đồ và các chỉ số sinh tồn mới nhất của người già.
- **Tiền điều kiện:** Người thân đã đăng nhập và được cấp quyền theo dõi hồ sơ cụ già.
- **Hậu điều kiện:** Dữ liệu sinh hiệu mới nhất, thẻ màu sức khỏe và tọa độ vị trí được hiển thị cập nhật trực tiếp trên Caregiver App.

**Luồng sự kiện chính (Main Flow):**
1. Người thân mở Caregiver App, chọn hồ sơ cụ già cần theo dõi.
2. App gửi yêu cầu HTTP GET /api/v1/elders/{id}/dashboard kèm Bearer JWT.
3. Backend xác thực quyền truy cập (BOLA Check) và truy vấn dữ liệu từ bộ nhớ đệm (MemoryCache) kết hợp CSDL:
4. - TÍNH TOÁN THẺ MÀU SỨC KHỎE TỔNG THỂ (HEALTH BADGE COLOR):
5.   + XANH LÁ (NORMAL): Nhịp tim nằm trong ngưỡng an toàn, không có sự cố nào đang mở.
6.   + VÀNG (WARNING): Nhịp tim có dấu hiệu tăng/giảm nhẹ hoặc đang có sự cố mức độ Warning.
7.   + ĐỎ (CRITICAL): Đang có sự cố nguy kịch mức Critical ở trạng thái Open (Ngã, SOS, Rung thất).
8.   + XÁM (OFFLINE): Thiết bị đã mất kết nối quá 5 phút hoặc chưa phát sinh dữ liệu trong ngày.
9. - Lấy chỉ số nhịp tim gần nhất (bpm) kèm biểu đồ biến thiên 24 giờ qua.
10. - Lấy số bước chân tích lũy trong ngày so với mục tiêu vận động (ví dụ: 3.200 / 5.000 bước).
11. - Lấy tọa độ GPS gần nhất và mốc thời gian nhận dữ liệu cuối cùng (LastSyncAt).
12. Backend trả về HTTP 200 OK kèm DashboardResponse DTO.
13. Caregiver App hiển thị giao diện trực quan:
14. - Thẻ trạng thái màu sắc nổi bật.
15. - Bản đồ vị trí tương tác (OpenStreetMap) định vị vị trí hiện tại của cụ.
16. - Biểu đồ sinh hiệu cập nhật mượt mà.
17. Caregiver App tự động mở kết nối WebSocket SignalR tới endpoint /hubs/caregiver, lắng nghe sự kiện 'HealthMetricsUpdated' để cập nhật dữ liệu đẩy trực tiếp từ server mà không cần người dùng vuốt làm mới.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Tự động chuyển sang chế độ Polling khi mất kết nối WebSocket:**
  + Do mạng di động 4G chập chờn hoặc hệ điều hành hạn chế tiến trình ngầm, kết nối SignalR WebSocket bị gián đoạn.
  + Caregiver App phát hiện sự kiện 'Closed', tự động kích hoạt chế độ Polling dự phòng: Định kỳ mỗi 30 giây gửi một yêu cầu HTTP GET /dashboard để làm mới màn hình cho đến khi kết nối WebSocket được thiết lập lại thành công.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Chưa có dữ liệu đo đạc nào trong ngày:**
  + *Điều kiện phát sinh:* Cụ già tháo đồng hồ từ đêm qua hoặc thiết bị mới ghép nối chưa truyền gói tin nào.
  + *Cơ chế xử lý hệ thống:* Dashboard hiển thị Thẻ trạng thái màu Xám kèm thông điệp: 'Chưa có dữ liệu đồng bộ trong hôm nay. Vui lòng kiểm tra việc đeo đồng hồ và pin thiết bị của Cụ'.
- **E2 - Không có quyền truy cập hồ sơ cụ (BOLA):**
  + *Điều kiện phát sinh:* Người dùng cố tình nhập ID của một cụ già không thuộc gia đình mình.
  + *Cơ chế xử lý hệ thống:* Backend kiểm tra ElderCaregiverMappings và trả về HTTP 403 Forbidden. App thông báo lỗi và quay trở lại danh sách người thân được phép xem.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Tối ưu hóa Truy vấn Đọc: Dữ liệu Dashboard được đọc từ bộ nhớ đệm MemoryCache để phản hồi nhanh (< 100ms) và tiết kiệm tài nguyên đọc của Azure SQL 5 DTU.
- Màu sắc trạng thái tuân thủ nghiêm ngặt chuẩn y tế: Đỏ (Cấp cứu khẩn cấp), Vàng (Cần lưu ý), Xanh (An toàn), Xám (Mất tín hiệu).

---

### 5. PHÂN HỆ 5: CẤU HÌNH LÂM SÀNG & PHÂN QUYỀN GIA ĐÌNH

#### UC-11: Tùy chỉnh Ngưỡng Lâm sàng Cá nhân hóa (Medical Configuration)
- **Phân hệ:** Phân hệ 5: Cấu hình Lâm sàng
- **Tác nhân chính:** Người thân chính (Primary Caregiver - PC)
- **Tác nhân phụ:** CareAI Monolith Engine (.NET 10), Bác sĩ điều trị
- **Mức độ ưu tiên:** Trung bình (P2 - Nghiệp vụ y tế)
- **Luồng xử lý kiến trúc:** `Configuration API / Cache Invalidation`
- **Mục tiêu:** Cho phép người thân chính (đại diện pháp lý) điều chỉnh các ngưỡng sinh tồn cảnh báo nhịp tim phù hợp với bệnh lý nền và chỉ định riêng của bác sĩ cho từng cụ già.
- **Tiền điều kiện:** PC đã đăng nhập, sở hữu quyền đại diện pháp lý trên hồ sơ cụ (IsLegalRepresentative = true).
- **Hậu điều kiện:** Bản ghi DeviceClinicalStates được cập nhật trong CSDL và bộ nhớ đệm MemoryCache được làm mới ngay tức khắc cho các lần thẩm định viễn trắc tiếp theo.

**Luồng sự kiện chính (Main Flow):**
1. PC mở mục 'Cài đặt Ngưỡng Sức khỏe' trên Caregiver App.
2. Giao diện hiển thị các thanh trượt và ô nhập liệu với các giá trị hiện hành:
3. - Ngưỡng nhịp tim tối thiểu an toàn (MinHeartRate, mặc định: 50 bpm).
4. - Ngưỡng nhịp tim tối đa an toàn (MaxHeartRate, mặc định: 110 bpm).
5. - Ngưỡng tăng vọt đột ngột (CriticalSurgeBpm, mặc định: 15 bpm).
6. - Khoảng thời gian chống báo động lặp (DebounceMinutes, mặc định: 10 phút).
7. PC điều chỉnh các giá trị (ví dụ: Bác sĩ yêu cầu hạ Max xuống 100 bpm do cụ có tiền sử thiếu máu cơ tim), sau đó bấm nút 'Lưu Cấu Hình'.
8. App kiểm tra tính hợp lệ ở Client và gửi HTTP PUT /api/v1/elders/{id}/thresholds kèm Bearer JWT của PC.
9. Backend Kestrel thực thi thẩm định nghiệp vụ y tế:
10. - Kiểm tra quyền đại diện pháp lý của PC: Bắt buộc tài khoản phải có vai trò PrimaryCaregiver liên kết với cụ già này.
11. - THẨM ĐỊNH TÍNH LOGIC Y TẾ (CLINICAL LOGIC VALIDATION):
12.   + 40 bpm <= MinHeartRate <= 80 bpm.
13.   + 90 bpm <= MaxHeartRate <= 160 bpm.
14.   + BẮT BUỘC: MinHeartRate < MaxHeartRate (khoảng cách tối thiểu giữa 2 ngưỡng là 20 bpm).
15.   + 5 phút <= DebounceMinutes <= 30 phút.
16. Backend cập nhật dữ liệu vào bảng DeviceClinicalStates trong CSDL Azure SQL.
17. Backend lập tức xóa và nạp lại Cache trạng thái lâm sàng của cụ trong IMemoryCache (Cache Eviction & Refresh).
18. Backend trả về HTTP 200 OK kèm bộ ngưỡng mới cập nhật.
19. App hiển thị thông báo thành công: 'Đã cập nhật ngưỡng cảnh báo lâm sàng. Cấu hình mới có hiệu lực ngay lập tức'.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Khôi phục về ngưỡng chuẩn khuyến nghị:**
  + PC bấm nút 'Đặt lại mặc định chuẩn y tế'.
  + Giao diện tự động điền lại các giá trị tiêu chuẩn: Min 50 bpm, Max 110 bpm, Surge 15 bpm, Debounce 10 phút.
  + PC bấm Lưu và hệ thống áp dụng lại bộ tham số tiêu chuẩn của Bộ Y tế.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Nhập số liệu phi logic y tế:**
  + *Điều kiện phát sinh:* PC vô tình kéo MinHeartRate >= MaxHeartRate (ví dụ: Min 115, Max 90).
  + *Cơ chế xử lý hệ thống:* Client bôi đỏ cảnh báo và chặn nút Lưu; nếu gửi trực tiếp API, Backend trả về HTTP 400 Bad Request kèm payload: {"error": "InvalidThresholdRange", "message": "Ngưỡng nhịp tim tối thiểu phải nhỏ hơn ngưỡng nhịp tim tối đa ít nhất 20 bpm."}
- **E2 - Người thân phụ cố tình thay đổi cấu hình:**
  + *Điều kiện phát sinh:* Tài khoản có vai trò Secondary Caregiver gửi request thay đổi ngưỡng.
  + *Cơ chế xử lý hệ thống:* Backend kiểm tra vai trò trong ElderCaregiverMappings, từ chối và trả về HTTP 403 Forbidden kèm thông điệp: 'Chỉ Người thân chính (Đại diện pháp lý) mới có quyền thay đổi cấu hình y tế'.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Hiệu lực tức thì (Zero-Downtime Cache Invalidation): Việc cập nhật ngưỡng y tế phải làm mới MemoryCache ngay lập tức để gói tin viễn trắc kế tiếp (đến sau 1 mili-giây) được so sánh với ngưỡng mới mà không cần khởi động lại dịch vụ.
- Bảo vệ giới hạn an toàn y tế: Không cho phép thiết lập ngưỡng tối đa vượt quá 160 bpm hoặc ngưỡng tối thiểu dưới 40 bpm để bảo đảm hệ thống luôn bắt được các cơn nguy kịch tim mạch.

---

#### UC-12: Quản lý Thành viên Gia đình & Phân quyền RBAC (Family Management)
- **Phân hệ:** Phân hệ 5: Cấu hình Lâm sàng
- **Tác nhân chính:** Người thân chính (Primary Caregiver - PC)
- **Tác nhân phụ:** Người thân phụ (Secondary Caregiver - SC), CareAI Monolith Engine (.NET 10)
- **Mức độ ưu tiên:** Trung bình (P2 - Nghiệp vụ gia đình)
- **Luồng xử lý kiến trúc:** `Family RBAC Mapping / Invitation Code`
- **Mục tiêu:** Cho phép người thân chính mời thêm các thành viên trong gia đình (con cái, bác sĩ gia đình) cùng giám sát và tiếp nhận cảnh báo cho cụ, đồng thời thực thi nghiêm ngặt ma trận phân quyền dựa trên vai trò (RBAC).
- **Tiền điều kiện:** PC đã đăng nhập và sở hữu quyền quản trị trên hồ sơ cụ.
- **Hậu điều kiện:** Thành viên mới được bổ sung vào bảng ElderCaregiverMappings với vai trò SecondaryCaregiver, nhận được quyền xem Dashboard và quyền tiếp nhận báo động khẩn cấp.

**Luồng sự kiện chính (Main Flow):**
1. PC mở mục 'Thành viên Gia đình' trên Caregiver App, chọn 'Mời thành viên mới'.
2. PC chọn mối quan hệ của thành viên mới (Con trai, Con gái, Cháu, Bác sĩ riêng).
3. App gửi yêu cầu HTTP POST /api/v1/elders/{id}/invitations.
4. Backend xác thực quyền PC, sinh ngẫu nhiên Mã mời gia đình gồm 6 ký tự chữ và số viết hoa (ví dụ: 'CARE88'), lưu vào bảng FamilyInvitations với thời hạn hiệu lực chính xác 24 giờ (ExpiresAt = DateTime.UtcNow.AddHours(24)) và cờ IsUsed = false.
5. Backend trả về HTTP 201 Created kèm mã mời.
6. PC sao chép mã mời và gửi cho người thân phụ (SC) qua tin nhắn Zalo/SMS.
7. SC tải ứng dụng Caregiver App, đăng ký tài khoản (UC-01), tại màn hình tham gia chọn 'Nhập mã mời gia đình' và điền mã 'CARE88'.
8. SC App gửi HTTP POST /api/v1/invitations/accept kèm mã mời và Bearer JWT của SC.
9. Backend kiểm tra mã mời: tồn tại, chưa sử dụng và chưa hết hạn 24 giờ.
10. Backend tạo bản ghi mới trong bảng ElderCaregiverMappings:
11. - ElderProfileId = ID cụ già liên kết với mã mời.
12. - CaregiverId = UserId của SC.
13. - Role = CaregiverRole.SecondaryCaregiver.
14. - IsLegalRepresentative = false.
15. Backend đánh dấu mã mời IsUsed = true và trả về HTTP 200 OK.
16. Giao diện của SC tự động mở Dashboard của cụ già; SC được bổ sung vào danh sách nhận thông báo đẩy FCM khi có sự cố.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Thu hồi quyền theo dõi của người thân phụ (Revoke Access):**
  + PC vào danh sách thành viên, chọn một người thân phụ và bấm nút 'Xóa quyền theo dõi'.
  + App gửi HTTP DELETE /api/v1/elders/{id}/caregivers/{caregiverId}.
  + Backend kiểm tra quyền PC, xóa bản ghi liên kết tương ứng trong ElderCaregiverMappings.
  + Hệ thống thu hồi tức thì quyền xem Dashboard và hủy đăng ký nhận thông báo FCM của người đó đối với hồ sơ cụ già này.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Mã mời hết hạn hoặc không tồn tại:**
  + *Điều kiện phát sinh:* SC nhập mã mời đã tạo cách đây hơn 24 giờ hoặc gõ sai ký tự.
  + *Cơ chế xử lý hệ thống:* Backend từ chối và trả về HTTP 400 Bad Request kèm thông báo: {"error": "InvalidOrExpiredInvitationCode", "message": "Mã mời không tồn tại hoặc đã hết hạn (24 giờ). Vui lòng yêu cầu Người thân chính cấp lại mã mới."}
- **E2 - Tài khoản đã nằm trong danh sách theo dõi (Duplicate Member):**
  + *Điều kiện phát sinh:* SC đã là thành viên trong nhóm nhưng lại nhập lại mã mời.
  + *Cơ chế xử lý hệ thống:* Backend phát hiện trùng lặp trong ElderCaregiverMappings, trả về HTTP 409 Conflict với thông báo: 'Bạn đã nằm trong danh sách theo dõi của người cao tuổi này'.
- **E3 - Người thân phụ cố tình xóa quyền của thành viên khác:**
  + *Điều kiện phát sinh:* SC cố tình gọi API xóa thành viên trong gia đình.
  + *Cơ chế xử lý hệ thống:* Backend kiểm tra vai trò, phát hiện IsLegalRepresentative == false, lập tức trả về HTTP 403 Forbidden.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- MA TRẬN PHÂN QUYỀN GIA ĐÌNH (RBAC MATRIX):
- - Primary Caregiver (Người thân chính): Toàn quyền (Quản lý hồ sơ, cấu hình ngưỡng y tế, mời/xóa thành viên, hủy thiết bị, xóa dữ liệu, tiếp nhận và giải quyết sự cố).
- - Secondary Caregiver (Người thân phụ): Quyền hạn chế (Xem Dashboard, xem lịch sử, nhận còi hú FCM, bấm 'Tiếp nhận' ACK, gọi điện cứu hộ; KHÔNG có quyền thay đổi ngưỡng, không có quyền xóa hồ sơ hoặc xóa thành viên khác).
- Mã mời gia đình có hiệu lực chính xác 24 giờ và là mã dùng một lần (Single-Use).

---

### 6. PHÂN HỆ 6: QUẢN TRỊ VÒNG ĐỜI DỮ LIỆU & KIỂM TOÁN

#### UC-13: Hủy Liên kết Thiết bị & Xóa Dữ liệu (Device Unpair & Data Lifecycle)
- **Phân hệ:** Phân hệ 6: Quản trị Vòng đời Dữ liệu
- **Tác nhân chính:** Người thân chính (Primary Caregiver - PC)
- **Tác nhân phụ:** Companion App, CareAI Monolith Engine (.NET 10)
- **Mức độ ưu tiên:** Cao (P1 - Bảo mật & Pháp lý)
- **Luồng xử lý kiến trúc:** `Device & Data Governance / Revocation`
- **Mục tiêu:** Quản trị vòng đời thiết bị phần cứng và dữ liệu cá nhân của người già; cho phép ngắt kết nối đồng hồ cũ để thay thế thiết bị mới hoặc thực thi quyền xóa dữ liệu theo quy định pháp luật.
- **Tiền điều kiện:** PC đã đăng nhập và được xác thực danh tính đại diện pháp lý (IsLegalRepresentative = true).
- **Hậu điều kiện:** Token của thiết bị bị thu hồi vĩnh viễn; hoặc toàn bộ hồ sơ dữ liệu cá nhân của cụ được xóa an toàn / ẩn danh hóa trong CSDL.

**Luồng sự kiện chính (Main Flow):**
1. KỊCH BẢN 1: HỦY LIÊN KẾT THIẾT BỊ (UNPAIR DEVICE):
2. - PC mở mục 'Quản lý Thiết bị' trong hồ sơ cụ, chọn thiết bị cần thay thế (ví dụ: 'Samsung Galaxy Watch6').
3. - PC bấm nút 'Hủy ghép nối thiết bị'.
4. - App gửi yêu cầu HTTP POST /api/v1/devices/{id}/unpair kèm Bearer JWT của PC.
5. - Backend xác thực quyền sở hữu của PC (BOLA Check), mở giao dịch CSDL:
6.   + Cập nhật bản ghi DeviceRegistrations: IsActive = false, DeactivatedAt = DateTime.UtcNow.
7.   + Đưa DeviceToken của thiết bị vào Danh sách Đen Thu Hồi (Token Revocation Blacklist) trong Redis/MemoryCache để từ chối ngay lập tức mọi gói tin gửi lên sau đó.
8. - Backend gửi một bản tin ngầm Google FCM (Data-Only Message) tới Companion App mang lệnh: {"action": "WIPE_DEVICE_CREDENTIALS"}.
9. - Companion App nhận lệnh ngầm: Xóa sạch DeviceToken lưu trong Android Keystore, hủy bỏ các tác vụ WorkManager định kỳ và tự động điều hướng giao diện về màn hình Chờ nhập mã ghép nối ban đầu.
10. - Backend trả về HTTP 200 OK cho PC.
11. KỊCH BẢN 2: XÓA TOÀN BỘ HỒ SƠ & DỮ LIỆU CỦA CỤ (RIGHT TO ERASURE):
12. - PC chọn mục 'Xóa hồ sơ người thân', hệ thống yêu cầu nhập lại Mật khẩu tài khoản PC để xác thực bảo mật cấp 2.
13. - App gửi HTTP DELETE /api/v1/elders/{id} kèm mật khẩu xác nhận trong body.
14. - Backend xác thực mật khẩu qua BCrypt, kiểm tra vai trò đại diện pháp lý duy nhất của PC.
15. - Backend thực thi quy trình xóa an toàn (Safe Erasure):
16.   + Đánh dấu xóa mềm: ElderProfiles.IsDeleted = true, DeletedAt = DateTime.UtcNow.
17.   + Vô hiệu hóa toàn bộ DeviceRegistrations liên quan và hủy bỏ các bản ghi trong ElderCaregiverMappings.
18.   + ẨN DANH HÓA DỮ LIỆU Y TẾ: Các bản ghi đo đạc sinh hiệu cũ trong HealthMeasurements được xóa bỏ các thông tin định danh cá nhân (PII Removal) để bảo vệ quyền riêng tư tuyệt đối cho gia đình.
19. - Backend trả về HTTP 200 OK, hoàn tất vòng đời quản trị dữ liệu.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Hủy liên kết khi thiết bị đã bị hỏng hoặc mất cắp (Offline Device Unpair):**
  + Thiết bị của cụ bị rơi mất hoặc hỏng hoàn toàn không thể nhận lệnh FCM ngầm.
  + PC thực hiện thao tác Hủy ghép nối trên máy mình.
  + Server vẫn cập nhật vô hiệu hóa Token và đánh dấu IsActive = false.
  + Nếu kẻ gian nhặt được thiết bị và cố gắng truyền dữ liệu, Server sẽ từ chối với HTTP 401 Unauthorized.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Người thân phụ cố gắng hủy thiết bị hoặc xóa hồ sơ:**
  + *Điều kiện phát sinh:* Tài khoản có vai trò Secondary Caregiver gọi API unpair hoặc delete.
  + *Cơ chế xử lý hệ thống:* Backend kiểm tra vai trò IsLegalRepresentative == false, lập tức từ chối và trả về HTTP 403 Forbidden kèm thông điệp: 'Chỉ Người thân chính (Đại diện pháp lý) mới có quyền hủy thiết bị hoặc xóa hồ sơ người già'.
- **E2 - Nhập sai mật khẩu xác nhận xóa hồ sơ:**
  + *Điều kiện phát sinh:* PC nhập sai mật khẩu đăng nhập khi xác nhận thao tác xóa dữ liệu.
  + *Cơ chế xử lý hệ thống:* Backend từ chối thực thi và trả về HTTP 401 Unauthorized với thông báo: 'Mật khẩu xác nhận không chính xác. Thao tác xóa hồ sơ bị hủy bỏ'.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Thu hồi Token Tức thì: Ngay khi PC bấm Hủy ghép nối, DeviceToken của thiết bị bị vô hiệu hóa ngay trên bộ nhớ Cache máy chủ; mọi gói tin gửi lên sau đó đều bị chặn với HTTP 401.
- Quyền Xóa Dữ liệu (Right to Erasure): Việc xóa hồ sơ phải tuân thủ quy định bảo vệ dữ liệu cá nhân, xóa bỏ định danh PII nhưng bảo toàn cấu trúc dữ liệu tổng quan cho mục đích kiểm toán y tế.

---

#### UC-14: Tra cứu Lịch sử Sự cố & Dấu vết Kiểm toán Pháp y (Forensic Audit Trail)
- **Phân hệ:** Phân hệ 6: Quản trị Vòng đời Dữ liệu
- **Tác nhân chính:** Caregiver (Người thân chính hoặc phụ), Bác sĩ điều trị
- **Tác nhân phụ:** CareAI Monolith Engine (.NET 10), CareAiDbContext (SQL Server)
- **Mức độ ưu tiên:** Cao (P1 - Giám sát & Bằng chứng)
- **Luồng xử lý kiến trúc:** `Read-Only Audit Query / Medical Forensics`
- **Mục tiêu:** Cung cấp bức tranh toàn cảnh, minh bạch về lịch sử các cảnh báo sức khỏe và cấp cứu đã xảy ra với người già, phục vụ công tác chẩn đoán bệnh lý của bác sĩ và đóng vai trò chứng thực y tế độc lập.
- **Tiền điều kiện:** Người dùng đã đăng nhập và có quyền truy cập hồ sơ cụ già.
- **Hậu điều kiện:** Danh sách các sự cố được trả về với đầy đủ dấu vết kiểm toán (Thời gian phát hiện, Chỉ số đo, Ai tiếp nhận, Ai giải quyết, Ghi chú y tế).

**Luồng sự kiện chính (Main Flow):**
1. Người dùng mở tab 'Lịch sử Cảnh báo & Sự cố' trên Caregiver App.
2. Người dùng chọn bộ lọc tra cứu: Khoảng thời gian (Hôm nay, 7 ngày qua, Tháng này, Tùy chỉnh), Mức độ nghiêm trọng (Tất cả, Cảnh báo, Nguy kịch), Loại sự cố (Tất cả, Té ngã, SOS, Nhịp tim bất thường, Mất kết nối).
3. App gửi yêu cầu HTTP GET /api/v1/elders/{id}/incidents?page=1&pageSize=20&severity=... kèm Bearer JWT.
4. Backend xác thực quyền truy cập của người dùng đối với hồ sơ cụ già (BOLA Check).
5. Backend thực thi truy vấn phân trang trên bảng Incidents, sắp xếp theo thứ tự thời gian giảm dần (TriggeredAt DESC):
6. - Mã định danh sự cố duy nhất (IncidentId kiểu Guid).
7. - Loại sự cố (EmergencyType: FALL, SOS, ABNORMAL_HEART_RATE, DEVICE_STALE_DISCONNECTED).
8. - Mức độ nghiêm trọng (Severity: Warning, Critical, High).
9. - Thời điểm phát sinh sự cố chính xác (TriggeredAt UTC).
10. - Giá trị chỉ số đo lúc xảy ra (MetricValue: ví dụ '185 bpm' hoặc 'Té ngã tại phòng khách').
11. - Trạng thái xử lý (Status: Resolved, Acknowledged, Open).
12. - DẤU VẾT TIẾP NHẬN (ACKNOWLEDGEMENT AUDIT TRAIL):
13.   + Họ tên người tiếp nhận (AcknowledgedByName).
14.   + Thời điểm tiếp nhận chính xác (AcknowledgedAt UTC).
15. - DẤU VẾT HOÀN TẤT XỬ LÝ (RESOLUTION AUDIT TRAIL):
16.   + Họ tên người giải quyết (ResolvedByName).
17.   + Thời điểm giải quyết (ResolvedAt UTC).
18.   + Ghi chú xử lý y tế lâm sàng (ResolutionNotes: ví dụ 'Đã cho uống thuốc hạ áp theo chỉ định bác sĩ').
19. Backend trả về HTTP 200 OK kèm danh sách và siêu dữ liệu phân trang (TotalCount, TotalPages, CurrentPage).
20. Caregiver App hiển thị danh sách dạng Timeline thẻ trực quan.
21. Người dùng bấm vào một sự cố cụ thể để xem biểu đồ nhịp tim chi tiết trong khoảng 15 phút trước và 15 phút sau khi sự cố xảy ra nhằm hỗ trợ bác sĩ đánh giá nhịp tim phục hồi.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Không có sự cố nào trong khoảng thời gian đã chọn:**
  + Trong khoảng thời gian đã lọc, cụ già hoàn toàn khỏe mạnh và không có sự cố nào phát sinh.
  + Hệ thống trả về danh sách rỗng (Count = 0).
  + App hiển thị thông điệp tích cực: 'Sức khỏe của Cụ trong thời gian qua rất ổn định, không có sự cố nào được ghi nhận'.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Người dùng không được phân quyền xem hồ sơ cụ (BOLA):**
  + *Điều kiện phát sinh:* Người dùng cố tình đổi ID trên URL để xem lịch sử sự cố của một cụ già khác.
  + *Cơ chế xử lý hệ thống:* Backend kiểm tra ElderCaregiverMappings, phát hiện không có quyền và trả về HTTP 403 Forbidden.
- **E2 - Tham số phân trang không hợp lệ:**
  + *Điều kiện phát sinh:* Client gửi page < 1 hoặc pageSize > 100.
  + *Cơ chế xử lý hệ thống:* Backend tự động chuẩn hóa về giá trị an toàn mặc định (page = 1, pageSize = 20) và trả về kết quả bình thường mà không gây crash hệ thống.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- BẤT BIẾN DẤU VẾT PHÁP Y Y TẾ (MEDICAL FORENSIC AUDIT TRAIL): Mọi bản ghi Incident một khi đã được tạo ra trong CSDL là BẤT BIẾN (Append-Only / Immutable). Tuyệt đối không có bất kỳ API hay người dùng nào có quyền XÓA hoặc CHỈNH SỬA các trường lịch sử (TriggeredAt, MetricValue, AcknowledgedAt, AcknowledgedByCaregiverId). Dữ liệu này đóng vai trò bằng chứng kiểm toán độc lập khi có yêu cầu điều tra y tế.
- Bảo toàn dữ liệu khi xung đột tương tranh: Ngay cả khi xảy ra va chạm ghi đồng thời (OCC Collision), hệ thống nạp lại giá trị gốc từ CSDL và bảo tồn nguyên vẹn các trường kiểm toán pháp y ban đầu.

---

### 7. PHÂN HỆ 7: TRÍ TUỆ NHÂN TẠO PHÂN TÍCH SỨC KHỎE (AI ANALYTICAL ENGINE - PHASE 2)

#### UC-15: AI Phát hiện Bất thường Thói quen Sinh hoạt (ML.NET Anomaly Detection)
- **Phân hệ:** Phân hệ 7: Trí tuệ Nhân tạo (Giai đoạn 2)
- **Tác nhân chính:** CareAI Monolith Engine (AnomalyDetectionWorker - Tiến trình Chạy ngầm Ban đêm)
- **Tác nhân phụ:** Thư viện Microsoft.ML (.NET 10), Caregiver App (Flutter)
- **Mức độ ưu tiên:** Phân tích / Giai đoạn 2 (P2 - Hỗ trợ Quyết định)
- **Luồng xử lý kiến trúc:** `In-Process Machine Learning / Nightly Batch Job`
- **Mục tiêu:** Ứng dụng mô hình học máy chuỗi thời gian (Time-Series) chạy trực tiếp trong tiến trình Monolith để tự động học đường cơ sở thói quen sinh hoạt (Baseline) trong 14 ngày của cụ già, từ đó phát hiện sớm các dấu hiệu suy giảm sức khỏe âm thầm mà các ngưỡng tĩnh thông thường không phát hiện được.
- **Tiền điều kiện:** Hồ sơ cụ già đã tích lũy tối thiểu từ 7 đến 14 ngày dữ liệu viễn trắc đo đạc liên tục; tiến trình nền AnomalyDetectionWorker được kích hoạt.
- **Hậu điều kiện:** Tạo bản ghi nhận định phân tích sức khỏe HealthInsight hiển thị trên tab 'Nhận định AI' của Caregiver App; không phát sinh bất kỳ nguy cơ nghẽn mạng hay chi phí API bên ngoài.

**Luồng sự kiện chính (Main Flow):**
1. Tiến trình AnomalyDetectionWorker thức dậy tự động định kỳ vào lúc 02:00 sáng hàng ngày (khung giờ tải hệ thống thấp nhất).
2. Worker truy vấn CSDL trích xuất chuỗi thời gian (Time-series) của cụ già trong 14 ngày gần nhất: Nhịp tim trung bình theo từng khung giờ và số bước chân vận động theo từng buổi.
3. Worker nạp chuỗi số liệu vào thuật toán phát hiện đột biến chuỗi thời gian của thư viện Microsoft.ML (thuật toán IidSpikeDetector hoặc Spectral Residual SSA):
4. - Thuật toán tự động học đường cơ sở thói quen (Personalized Habit Baseline) của riêng cụ già:
5.   + Ví dụ: Cụ thường thức dậy và đi lại nhẹ nhàng vào lúc 06:00 - 07:00 sáng (trung bình 1.200 bước).
6.   + Nhịp tim lúc nghỉ ngơi khi ngủ ban đêm của cụ thường dao động ổn định trong khoảng 60 - 65 bpm.
7. - Thuật toán tính toán chỉ số tin cậy (Confidence Level) và điểm dị biệt P-Value kết hợp Martingale Score:
8.   + Phát hiện Đột biến Nhịp tim Ẩn: Ví dụ từ 01:00 đến 03:00 sáng, nhịp tim của cụ duy trì ở mức 92 bpm liên tục (dù con số 92 bpm này vẫn nằm trong ngưỡng an toàn tĩnh 50 - 110 bpm của UC-06 nên không kích hoạt còi hú, nhưng thuật toán AI phát hiện nó cao hơn 45% so với thói quen ngủ 62 bpm của chính cụ).
9.   + Phát hiện Bất thường Vận động: Ví dụ trong khung giờ 06:00 - 09:00 sáng cụ hoàn toàn không có bước chân nào (0 bước), trái ngược với thói quen đi bộ đều đặn 14 ngày qua.
10. Nếu phát hiện điểm đột biến có ý nghĩa thống kê y tế (P-Value < 0.05):
11. - Worker khởi tạo bản ghi HealthInsight mới:
12.   + Category = 'HabitAnomaly'.
13.   + Title = 'Phát hiện thay đổi thói quen nhịp tim ban đêm'.
14.   + Summary = 'Nhịp tim khi ngủ của Cụ lúc 02:00 sáng cao hơn 45% so với mức trung bình 14 ngày qua (92 bpm so với 62 bpm). Khuyến nghị gia đình thăm hỏi chất lượng giấc ngủ hoặc tình trạng sốt nhẹ của Cụ.'.
15.   + Severity = 'Info' hoặc 'Warning'.
16. - Lưu bản ghi vào bảng HealthInsights trên Azure SQL.
17. Caregiver App hiển thị thẻ nhận định này trong mục 'Góc Sức Khỏe AI' để người thân tham khảo và chủ động theo dõi.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Thói quen sinh hoạt hoàn toàn ổn định:**
  + Mô hình chuỗi thời gian phân tích và không phát hiện bất kỳ điểm đột biến nào vượt ngưỡng ý nghĩa thống kê.
  + Hệ thống ghi nhận trạng thái: 'Các chỉ số thói quen của Cụ trong 14 ngày qua duy trì tính ổn định rất cao'.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Chưa đủ dữ liệu tối thiểu để huấn luyện mô hình (< 7 ngày):**
  + *Điều kiện phát sinh:* Cụ già mới sử dụng thiết bị được 2-3 ngày, số lượng mẫu đo không đủ để tạo baseline đáng tin cậy.
  + *Cơ chế xử lý hệ thống:* Worker kiểm tra tổng số ngày có dữ liệu: Nếu Count < 7 ngày, Worker tự động bỏ qua phân tích AI cho hồ sơ này, ghi log: 'Skipping ML.NET analysis: Insufficient samples (3/7 days required)'. Hệ thống vận hành hoàn toàn dựa trên Engine Luật Lâm sàng Tĩnh (UC-06), bảo đảm người dùng luôn an toàn tuyệt đối mà không bị các nhận định sai lệch.
- **E2 - Dữ liệu bị đứt gãy nhiều ngày do không đeo thiết bị:**
  + *Điều kiện phát sinh:* Cụ già tháo đồng hồ liên tục 3-4 ngày khiến chuỗi thời gian bị khuyết nhiều điểm.
  + *Cơ chế xử lý hệ thống:* Mô hình phát hiện tỷ lệ dữ liệu rỗng (Missing Data Ratio) vượt quá 30%, tự động hạ điểm tin cậy và hiển thị khuyến nghị: 'Dữ liệu đo bị ngắt quãng nhiều ngày. Gia đình vui lòng nhắc Cụ đeo thiết bị thường xuyên hơn để tối ưu độ chính xác của AI'.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Thực thi Cục bộ 100% (In-Process Execution): Toàn bộ thuật toán ML.NET chạy trực tiếp trong RAM của tiến trình Monolith, TUYỆT ĐỐI KHÔNG gửi dữ liệu sinh hiệu nhạy cảm của người già ra các dịch vụ AI đám mây công cộng bên thứ ba, tuân thủ nghiêm ngặt Luật Bảo vệ dữ liệu cá nhân.
- Vai trò Hỗ trợ Quyết định (Non-Diagnostic Advisory): Các nhận định AI chỉ đóng vai trò khuyến nghị gợi ý cho gia đình chăm sóc, không thay thế cho các chẩn đoán y khoa chính thức của bác sĩ.

---

#### UC-16: AI Tổng hợp Báo cáo Sức khỏe Hàng tuần (LLM GenAI Weekly Summary)
- **Phân hệ:** Phân hệ 7: Trí tuệ Nhân tạo (Giai đoạn 2)
- **Tác nhân chính:** CareAI Monolith Engine (WeeklyReportWorker - Định kỳ Chủ Nhật)
- **Tác nhân phụ:** LLM API (Google Gemini 1.5 Flash / Groq), Caregiver App (Flutter)
- **Mức độ ưu tiên:** Phân tích / Giai đoạn 2 (P2 - Trải nghiệm Gia đình)
- **Luồng xử lý kiến trúc:** `Scheduled Background Job / GenAI Prompt Engineering`
- **Mục tiêu:** Tự động tổng hợp toàn bộ dữ liệu đo đạc, sự cố và thói quen trong 7 ngày thành một bản báo cáo tự nhiên bằng tiếng Việt mạch lạc, ấm áp, dễ hiểu, giúp gia đình nắm bắt toàn diện tình hình thể trạng của người già mà không phải đọc các bảng biểu kỹ thuật phức tạp.
- **Tiền điều kiện:** Đến lịch tổng hợp định kỳ (07:00 sáng Chủ Nhật hàng tuần); hồ sơ cụ già có phát sinh dữ liệu đo đạc trong tuần.
- **Hậu điều kiện:** Báo cáo tổng kết tuần dạng văn bản được tạo, lưu vào bảng WeeklyHealthReports và gửi thông báo đẩy nhắc nhở người thân mở xem.

**Luồng sự kiện chính (Main Flow):**
1. Đúng 07:00 sáng Chủ Nhật hàng tuần, tiến trình ngầm WeeklyReportWorker được kích hoạt.
2. Worker tổng hợp toàn bộ dữ liệu thống kê trong 7 ngày vừa qua của từng cụ già:
3. - Chỉ số Nhịp tim: Nhịp tim trung bình trong tuần, nhịp tim cao nhất, nhịp tim thấp nhất.
4. - Mức độ Vận động: Tổng số bước chân cả tuần, số bước chân trung bình/ngày, ngày vận động tích cực nhất.
5. - Sự cố & Khẩn cấp: Tổng số lần phát sinh cảnh báo (nếu có), thời gian phản ứng trung bình của gia đình.
6. - Dị biệt thói quen: Các nhận định từ mô hình ML.NET của UC-15.
7. Worker đóng gói các thông số trên thành cấu trúc dữ liệu JSON trừu tượng, BẢO ĐẢM LOẠI BỎ 100% THÔNG TIN ĐỊNH DANH CÁ NHÂN (PII Anonymization: Không gửi Họ tên thật, Không gửi Địa chỉ nhà, Không gửi Số điện thoại).
8. Worker ghép JSON vào Mẫu Prompt Y Tế Chuẩn Hóa (Medical Prompt Template):
9.   Prompt: 'Bạn là trợ lý sức khỏe gia đình tận tâm CareAI. Dựa trên dữ liệu thống kê tuần sau đây của một người cao tuổi: {metrics_json}. Hãy viết một bản báo cáo tổng kết tuần bằng tiếng Việt ngắn gọn, ấm áp, gồm 3 phần: 1. Tổng quan sức khỏe; 2. Điểm tích cực & Cần lưu ý; 3. Lời khuyên sinh hoạt tuần tới cho gia đình. Giọng văn ân cần, dễ hiểu, không dùng thuật ngữ kỹ thuật khó hiểu.'
10. Worker gọi API của dịch vụ LLM (Google Gemini 1.5 Flash hoặc Groq Llama 3) qua kết nối HTTPS an toàn (thời gian phản hồi trung bình 2 - 3 giây).
11. LLM trả về đoạn văn bản báo cáo hoàn chỉnh mạch lạc bằng tiếng Việt.
12. Worker lưu trữ văn bản vào bảng WeeklyHealthReports trong CSDL Azure SQL, liên kết với ElderProfileId và mốc tuần tương ứng.
13. Worker thêm lệnh thông báo vào NotificationOutbox, gửi thông báo đẩy nhẹ nhàng tới toàn bộ người thân trong gia đình: 'Báo cáo sức khỏe tuần này của Cụ đã có sẵn. Mời bạn mở xem!'.

**Các luồng thay thế (Alternative Flows):**
- **A1 - Người thân xem lại lịch sử báo cáo các tuần cũ:**
  + Trên Caregiver App, người thân vào mục 'Báo cáo Tuần' và chọn xem tuần trước hoặc tháng trước.
  + Ứng dụng gọi HTTP GET /api/v1/elders/{id}/weekly-reports.
  + Hệ thống truy vấn trực tiếp bản báo cáo đã lưu sẵn trong CSDL và hiển thị ngay tức thì mà không cần gọi lại API LLM, tiết kiệm chi phí vận hành.

**Các luồng ngoại lệ & Xử lý lỗi (Exception Flows):**
- **E1 - Dịch vụ LLM gặp sự cố, Timeout hoặc Hết hạn mức Free-Tier (Rate Limit 429):**
  + *Điều kiện phát sinh:* Khi gọi API Google Gemini / Groq phát sinh lỗi HttpRequestException, Timeout hoặc HTTP 429 Too Many Requests.
  + *Cơ chế xử lý hệ thống:* Hệ thống lập tức kích hoạt CƠ CHẾ DỰ PHÒNG TỰ ĐỘNG BẢO TOÀN (Deterministic Fallback Engine): Worker KHÔNG làm sập tiến trình và KHÔNG bỏ dở báo cáo tuần. Hệ thống tự động chuyển sang công cụ ghép chuỗi quy tắc nội bộ (Rule-based String Template) dựa trên các số liệu thống kê thực tế: 'Báo cáo tuần [Ngày - Ngày]: Sức khỏe của Cụ nhìn chung rất ổn định. Nhịp tim trung bình tuần qua đạt [X] bpm. Cụ duy trì vận động trung bình [Y] bước/ngày. Trong tuần không phát sinh sự cố khẩn cấp nào. Chúc Cụ và gia đình một tuần mới an vui!'. Người dùng luôn nhận được báo cáo tuần đúng 07:00 sáng Chủ Nhật 100%, bảo đảm độ tin cậy tuyệt đối của hệ thống.
- **E2 - Cụ già không đeo thiết bị trong suốt cả tuần:**
  + *Điều kiện phát sinh:* Tổng số mẫu đo trong 7 ngày bằng 0 hoặc quá ít (< 10 mẫu đo).
  + *Cơ chế xử lý hệ thống:* Worker ghi nhận báo cáo đặc biệt: 'Trong tuần qua hệ thống không nhận được đủ dữ liệu đo đạc từ thiết bị của Cụ do đồng hồ bị tắt nguồn hoặc Cụ không đeo. Gia đình vui lòng kiểm tra việc sạc pin và hỗ trợ Cụ duy trì đeo đồng hồ để hệ thống bảo vệ sức khỏe tốt nhất'.

**Quy tắc nghiệp vụ & Bất biến hệ thống (Business Rules & Invariants):**
- Bảo vệ Dữ liệu Riêng tư Tuyệt đối (Zero-PII Leakage): Tuyệt đối không gửi bất kỳ thông tin nhận dạng cá nhân nào (Họ tên, SĐT, Địa chỉ, CMND/CCCD) lên API AI bên thứ ba. Chỉ gửi các số liệu thống kê trừu tượng (nhịp tim, bước chân).
- Cơ chế Dự phòng Bắt buộc (Deterministic Fallback): Báo cáo tuần là cam kết dịch vụ với gia đình, bắt buộc phải có công cụ ghép chuỗi mẫu câu nội bộ để thay thế tức thời khi API bên ngoài bị lỗi hoặc hết tiền.

---

## 5. PHỤ LỤC: MÃ LỖI HTTP, ENUMS & BẤT BIẾN VẬT LÝ HỆ THỐNG

### 5.1 Danh mục Mã lỗi HTTP & Quy chuẩn Phản hồi API

| Mã HTTP | Ngữ cảnh sử dụng trong CareAI | Ý nghĩa & Cơ chế xử lý |
|---|---|---|
| **200 OK** | Yêu cầu xử lý thành công (Đăng nhập, Tiếp nhận ACK sự cố, Đọc Dashboard, Cập nhật ngưỡng y tế). | Trả về dữ liệu JSON của thực thể tương ứng. |
| **201 Created** | Khởi tạo thành công tài nguyên mới (Tạo hồ sơ cụ, Sinh mã PIN ghép nối, Mời thành viên gia đình). | Trả về ID tài nguyên mới tạo và header Location nếu có. |
| **202 Accepted** | Tiếp nhận thành công gói tin viễn trắc định kỳ (Batch-Lane POST /telemetry/batch). | Gói tin đã được nạp an toàn vào hàng đợi bộ nhớ Channel<T> trong vòng < 15ms mà không cần chờ ghi đĩa CSDL. |
| **400 Bad Request** | Dữ liệu yêu cầu sai cú pháp, thiếu trường bắt buộc, hoặc vi phạm tính logic y tế (MinHeartRate >= MaxHeartRate, Mã PIN hết hạn). | Trả về mã lỗi chi tiết và thông điệp hướng dẫn khắc phục. |
| **401 Unauthorized** | Yêu cầu thiếu Token, Token hết hạn, chữ ký JWT không hợp lệ, hoặc sai mật khẩu xác thực. | Từ chối thực thi và yêu cầu người dùng/thiết bị đăng nhập lại. |
| **403 Forbidden** | Vi phạm phân quyền BOLA (Broken Object Level Authorization) hoặc RBAC (Secondary Caregiver cố tình xóa hồ sơ, hoặc thiết bị A cố gửi SOS cho cụ B). | Chặn đứng hành vi xâm phạm dữ liệu trái phép. |
| **409 Conflict** | Xung đột tương tranh dữ liệu (OCC RowVersion collision khi 2 người cùng bấm tiếp nhận), hoặc Email/Thành viên đã tồn tại. | Bảo vệ CSDL không bị ghi đè mất mát dữ liệu. |
| **423 Locked** | Tài khoản bị tạm khóa 15 phút do nhập sai mật khẩu quá 5 lần liên tiếp. | Cơ chế phòng thủ vật lý chống dò quét mật khẩu Brute-force. |
| **429 Too Many Requests** | Mạch bảo vệ máy chủ kích hoạt khi hàng đợi Channel vượt ngưỡng 10.000 phần tử hoặc vượt tần suất Rate Limit. | Tạm dừng nhận các gói tin phụ để ưu tiên tuyệt đối cho dữ liệu cấp cứu nhịp tim và SOS. |
| **500 Internal Server Error** | Lỗi nội bộ máy chủ không mong muốn. | Hệ thống ghi log cảnh báo kèm TraceId để đội ngũ kỹ thuật tra soát. |
| **503 Service Unavailable** | CSDL Azure SQL gặp sự cố mạng chớp nhoáng hoặc bảo trì. | Worker tự động kích hoạt mạch Retry với Exponential Backoff để chờ dịch vụ hồi phục. |

### 5.2 Danh mục Máy trạng thái & Enums Cốt lõi

#### Enum: `IncidentStatus`
*Máy trạng thái vòng đời sự cố trên máy chủ Backend. TUYỆT ĐỐI KHÔNG CÓ TRẠNG THÁI 'Cancelled' TRÊN SERVER!*

| Tên giá trị (Value) | Ý nghĩa nghiệp vụ |
|---|---|
| **Open (0)** | Sự cố vừa phát sinh từ viễn trắc/SOS/ngã, chưa có người thân nào tiếp nhận. |
| **Acknowledged (1)** | Đã được một người thân bấm 'Tiếp nhận' (ACK), còi hú đã tắt, đang trong quá trình ứng phó cứu nạn. |
| **Resolved (2)** | Đã hoàn tất xử lý (do người thân xác nhận cụ an toàn hoặc do hệ thống tự động đóng khi nhịp tim ổn định 5 phút liên tục). Không thể mở lại thủ công. |

#### Enum: `IncidentSeverity`
*Mức độ nghiêm trọng của sự cố sức khỏe để quyết định kênh phân phối thông báo và chuông báo động.*

| Tên giá trị (Value) | Ý nghĩa nghiệp vụ |
|---|---|
| **Info (0)** | Thông tin thường (Nhận định thói quen AI, thông báo báo cáo tuần). Không phát chuông còi. |
| **Warning (1)** | Cảnh báo mức độ nhẹ (Nhịp tim hơi cao/thấp, tăng đột ngột 15 bpm, thiết bị mất kết nối quá 5 phút). Phát thông báo tiêu chuẩn. |
| **High (2)** | Mức độ cao (Mất kết nối kéo dài toàn bộ thiết bị, nhịp tim lệch chuẩn mạnh). Gửi thông báo ưu tiên cao. |
| **Critical (3)** | Nguy kịch đe dọa tính mạng (Cụ bấm nút SOS, Thuật toán phát hiện té ngã, Rung thất >= 180 bpm, Vô tâm thu <= 35 bpm). KÍCH HOẠT CÒI HÚ CỨU THƯƠNG TRÊN TOÀN BỘ ĐIỆN THOẠI GIA ĐÌNH. |

#### Enum: `CaregiverRole`
*Phân quyền vai trò người chăm sóc trong nhóm gia đình theo tiêu chuẩn RBAC.*

| Tên giá trị (Value) | Ý nghĩa nghiệp vụ |
|---|---|
| **PrimaryCaregiver** | Người thân chính / Đại diện pháp lý (IsLegalRepresentative = true). Toàn quyền cấu hình y tế, ghép nối thiết bị, mời/xóa thành viên và xóa hồ sơ. |
| **SecondaryCaregiver** | Người thân phụ / Bác sĩ gia đình (IsLegalRepresentative = false). Quyền xem Dashboard, nhận còi hú FCM, tiếp nhận ACK và gọi điện cứu nạn; không thể phá hủy dữ liệu. |

### 5.3 Bảng Tham số Cấu hình & Bất biến Vật lý Toàn hệ thống

| Tham số cấu hình vật lý | Giá trị chuẩn hóa v96.0 | Mục đích kỹ thuật & Ý nghĩa vận hành |
|---|---|---|
| **Chu kỳ quét Watchdog (Scan Interval)** | `60 giây (1 phút / lần)` | Đảm bảo phát hiện sự cố mất tín hiệu kịp thời trong vòng 60 giây, không để người già bị mất kết nối quá lâu. |
| **Ngưỡng mất tín hiệu (Stale Disconnect Threshold)** | `5 phút (300 giây)` | Khoảng thời gian vật lý tối đa cho phép mất tín hiệu trước khi kết luận toàn bộ thiết bị đã tắt nguồn/rớt mạng. |
| **Cửa sổ Hủy Báo động Giả Cục bộ (Local Abort Window)** | `30 giây đếm ngược tại máy` | Loại trừ 100% báo động giả khi cụ ngã nhẹ hoặc bấm nhầm; KHÔNG gửi gói tin lên server nếu cụ bấm 'Tôi ổn' trong 30s. |
| **Cửa sổ Khử Trùng Lặp Cảnh báo (Debounce Window)** | `10 phút` | Ngăn chặn việc tạo hàng loạt sự cố trùng lặp và spam thông báo khi nhịp tim cụ duy trì ở mức cao kéo dài. |
| **Ngưỡng Leo thang Rung thất (Ventricular Fibrillation)** | `>= 180 bpm hoặc <= 35 bpm` | Lập tức nâng cấp độ lên Critical và kích hoạt còi hú Fast-Lane vì đây là dấu hiệu ngừng tuần hoàn đe dọa tính mạng. |
| **Ngưỡng Tăng vọt Nhịp tim (Sudden Surge)** | `>= 15 bpm / 1 phút (0 bước chân)` | Bắt kịp thời các cơn đau thắt ngực hoặc nhồi máu cơ tim tiềm ẩn khi người già đang ngồi nghỉ/ngủ. |
| **Thời hạn Mã PIN Ghép nối (Pairing PIN TTL)** | `15 phút (Mã dùng 1 lần)` | Chống tấn công dò quét mã ghép nối thiết bị trái phép. |
| **Thời hạn Mã mời Gia đình (Family Invitation TTL)** | `24 giờ (Mã dùng 1 lần)` | Bảo đảm an toàn khi chia sẻ mã tham gia nhóm qua mạng xã hội. |
| **Thời gian lưu đệm SQLite Cục bộ (SQLite Local Buffer)** | `7 ngày (Bảo toàn dữ liệu)` | Bảo đảm dữ liệu đo đạc không bị mất khi điện thoại cụ bị mất mạng Internet dài ngày. |
| **Thời hạn Lưu trữ CSDL Đám mây (Azure SQL Retention)** | `30 ngày (Data Retention Worker)` | Dọn dẹp tự động để bảo vệ CSDL không vượt quá hạn mức 2GB trên gói Azure SQL Free-Tier. |
| **Kích thước Mẻ Xóa CSDL (Database Deletion Chunk)** | `TOP (1000) + Nghỉ 50ms` | Triệt tiêu hiện tượng Lock Escalation từ Row-Lock lên Table-Lock, không làm nghẽn luồng Kestrel khi có cấp cứu SOS. |
| **Hạn mức Bộ nhớ Đệm RAM (MemoryCache SizeLimit)** | `50.000 phần tử (TTL = 2 phút)` | Bảo vệ máy chủ 1GB RAM trên Azure B1s/F1 không bao giờ bị sập do Out-Of-Memory (OOM). |
