# CareAI — Các nhiệm vụ 4.1–4.5

Gói `CareAI-part4-changes.zip` là **bản tích hợp tích lũy**, bao gồm cả nhiệm vụ 4.1 đã làm trước đó và các nhiệm vụ 4.2–4.5. Gói chỉ chứa file mới/thay đổi so với ZIP CareAI-main.zip gốc, không chứa file cấu hình database, Gemini key hay Firebase service account. Sao chép nội dung thư mục `CareAI` trong gói vào thư mục CareAI có `CareAI.slnx`; nếu đã sửa source riêng, đối chiếu trước khi ghép. Không cần áp dụng lại gói cũ.

## Phần đã triển khai

| Nhiệm vụ | Triển khai |
|---|---|
| 4.1 | Worker ML.NET in-process, phân tích 14 khung ngày, HealthInsights, DI, 9 test. Chi tiết/giới hạn trong README-anomaly-detection.md. |
| 4.2 | PiiAnonymizerService chỉ tạo DTO 5 trường số: nhịp tim trung bình, bước/ngày có dữ liệu, số ngày đo nhịp tim, số ngày đo bước chân và số cảnh báo. Không gửi tên, điện thoại, địa chỉ, ID người dùng/thiết bị, ghi chú, timestamp hoặc bản ghi gốc sang Gemini. |
| 4.3 | WeeklyReportWorker: Chủ Nhật 07:00, múi giờ Asia/Ho_Chi_Minh mặc định. Gemini qua HttpClient với timeout 5 giây, prompt tiếng Việt, ba phần báo cáo. |
| 4.4 | RuleBasedWeeklyReportFallbackEngine ghép câu tiếng Việt cục bộ. Fallback đã tính sẵn trước request; không gọi mạng hoặc chờ thêm khi AI lỗi. Lưu WeeklyHealthReports và hàng đợi WeeklyReportNotifications trong cùng SaveChanges. |
| 4.5 | Góc Sức Khỏe AI trong hồ sơ người cao tuổi; hai tab Nhận định/Báo cáo tuần, thẻ nhận định và lời hỏi thăm, phân trang lịch sử, xem chi tiết có cuộn, trạng thái tải/trống/lỗi và thử lại. |

API mới kiểm tra JWT và liên kết chăm sóc đang hoạt động cho từng hồ sơ. Luồng thông báo báo cáo sử dụng Firebase Admin SDK thật, tách khỏi NotificationDispatcherWorker cũ vốn chỉ mô phỏng thông báo sự cố. Khi chưa bật Firebase, báo cáo vẫn lưu được và thông báo được giữ ở trạng thái PENDING; không báo SENT giả.

## Build và chạy backend

Tại thư mục CareAI:

```powershell
dotnet restore CareAI.slnx
dotnet test tests/CareAI.UnitTests/CareAI.UnitTests.csproj --collect:"XPlat Code Coverage"
dotnet run --project src/CareAI.API/CareAI.API.csproj
```

DatabaseMigrationHelper tạo thêm bảng/index nếu chưa tồn tại, theo convention SQL idempotent hiện có. Cần quyền DDL trên database đích. Script không tự sửa schema của bảng cùng tên đã tồn tại với cấu trúc khác. Luồng startup gốc tiếp tục chạy khi DDL lỗi; kiểm tra log DB-INIT để chắc chắn schema đã tạo thành công.

## Cấu hình Gemini

Không cần key để tạo báo cáo: mặc định dùng tổng kết quy tắc nội bộ. Muốn bật Gemini, đặt biến môi trường trên máy chủ trước khi khởi chạy:

```powershell
$env:WeeklyReports__GeminiApiKey="<GEMINI_API_KEY>"
$env:WeeklyReports__GeminiModel="<MODEL_GENERATE_CONTENT_DUOC_TAI_KHOAN_HO_TRO>"
$env:WeeklyReports__TimeZoneId="Asia/Ho_Chi_Minh"
```

Model mặc định trong code là gemini-2.5-flash; có thể thay bằng model đang được tài khoản hỗ trợ. Khi model không khả dụng, HTTP 429/401/5xx, mất mạng, timeout, nội dung bị chặn, JSON sai hoặc thiếu các phần báo cáo, hệ thống dùng fallback. Hủy từ host được truyền ra, không bị coi là lỗi AI.

Payload sức khỏe vẫn là dữ liệu nhạy cảm dù đã bỏ định danh trực tiếp. Cơ chế allowlist bảo đảm không truyền các trường PII gốc qua đường gọi Gemini; không phải bảo đảm toán học rằng số liệu tổng hợp không thể bị tái nhận diện trong mọi bối cảnh.

## Cấu hình thông báo Firebase

Backend:

```powershell
$env:ReportPush__Enabled="true"
$env:ReportPush__ProjectId="<FIREBASE_PROJECT_ID>"
$env:GOOGLE_APPLICATION_CREDENTIALS="<DUONG_DAN_JSON_SERVICE_ACCOUNT>"
```

Có thể dùng Application Default Credentials của môi trường triển khai thay cho file. Bật Cloud Messaging API và cấp quyền gửi FCM phù hợp cho service account. Không đưa service account hoặc Gemini API key vào app di động.

Flutter đã có mã xin quyền thông báo, đăng ký/cập nhật token, thu hồi khi đăng xuất, nhận thông báo trong app và mở báo cáo khi chạm thông báo. Cần hoàn thiện cấu hình Firebase cho ứng dụng Android/iOS của chính dự án bằng FlutterFire theo tài liệu bên dưới. Android có applicationId `vn.careai.companion`; cấu hình google-services tương ứng, iOS cần cấu hình APNs/capabilities và bundle ID đúng. Các file Firebase riêng của tài khoản không được tạo giả trong gói.

Mã dùng FirebaseOptions từ dart-define. Tạo một file JSON cấu hình ứng dụng riêng, ví dụ:

```json
{
  "CAREAI_FIREBASE_ENABLED": "true",
  "FIREBASE_API_KEY": "<FIREBASE_CLIENT_API_KEY>",
  "FIREBASE_APP_ID": "<FIREBASE_APP_ID_THEO_PLATFORM>",
  "FIREBASE_SENDER_ID": "<SENDER_ID>",
  "FIREBASE_PROJECT_ID": "<PROJECT_ID>",
  "FIREBASE_IOS_BUNDLE_ID": "<IOS_BUNDLE_ID_NEU_CO>"
}
```

Tại companion_app:

```powershell
flutter pub get
flutter analyze
flutter test test/health_corner_test.dart
flutter run --dart-define-from-file=<FILE_CAU_HINH_FIREBASE_JSON>
```

Nếu không bật CAREAI_FIREBASE_ENABLED, giao diện/báo cáo vẫn hoạt động qua API nhưng app không đăng ký nhận push. Sau khi cập nhật dependencies, `flutter pub get` sẽ cập nhật pubspec.lock tại máy có Flutter; gói không ghi đè lockfile bằng dữ liệu chưa xác minh.

## Lịch và dữ liệu

- Tuần gồm bảy ngày trọn vẹn từ Chủ Nhật 00:00 đến trước Chủ Nhật kế tiếp 00:00 theo múi giờ cấu hình, tạo báo cáo lúc 07:00. Khởi động muộn sẽ tạo kỳ gần nhất đã đến hạn. Không tự lấp toàn bộ lịch sử các tuần đã bỏ lỡ.
- Worker kiểm tra lại mỗi 15 phút để thử lại lỗi database; khóa duy nhất người dùng/kỳ ngăn báo cáo trùng. Nhiều instance có thể gọi Gemini trùng trước khi khóa database loại bản ghi trùng.
- Bước chân giữ semantics tăng thêm của DashboardController gốc. Chọn một thiết bị có nhiều ngày dữ liệu nhất trong tuần; không cộng nhiều thiết bị. Trung bình chỉ tính ngày có dữ liệu, không điền 0 cho ngày thiếu. Nếu thiết bị gửi bộ đếm tích lũy, cần đổi cách chuẩn hóa tại đầu vào.
- Fallback không có I/O hoặc delay; **không cam kết CPU xử lý chính xác 0ms**. Với timeout AI, vẫn có thể chờ tối đa 5 giây trước khi dùng kết quả cục bộ đã tính sẵn.
- Lỗi AI không ngăn sinh báo cáo. Database/máy chủ mất kết nối vẫn có thể làm chậm việc lưu; không thể bảo đảm dịch vụ không bao giờ thất bại trước mọi loại sự cố.
- Outbox có lease và rowversion chống cùng lúc gửi từ nhiều instance, retry với backoff tối đa 6 giờ. Giao hàng at-least-once: có thể trùng push nếu FCM nhận tin nhưng server chết trước khi ghi SENT. Chỉ thông báo chung xuất hiện trên màn hình khóa, không đưa chỉ số sức khỏe vào nội dung push.
- Chỉ token đang hoạt động lúc tạo báo cáo được đưa vào hàng đợi; đăng ký token sau đó không gửi bù push báo cáo cũ. Quyền chăm sóc và trạng thái token được kiểm tra lại trước khi gửi.
- Nhịp tim nhiệm vụ 4.1 vẫn phát hiện tăng **trung bình đêm**, không bảo đảm bắt mọi spike ngắn từng mẫu; khung giờ là đại diện cho ngủ vì source chưa có nhãn ngủ.

## Endpoint mới

```text
GET    /api/v1/elders/{elderId}/health/insights?beforeId=...
GET    /api/v1/elders/{elderId}/health/weekly-reports?beforeId=...
GET    /api/v1/elders/{elderId}/health/weekly-reports/{reportId}
PUT    /api/v1/caregivers/push-token       body: { "token": "..." }
DELETE /api/v1/caregivers/push-token       body: { "token": "..." }
```

Danh sách trả `{ items, nextBeforeId }`, tối đa 20 mục mỗi trang. 401: chưa đăng nhập; 403: không có quyền chăm sóc; 404: báo cáo không thuộc hồ sơ được yêu cầu hoặc không tồn tại. Ứng dụng lấy báo cáo từ server đang cấu hình, không tự gửi JWT/dữ liệu sang host dự phòng.

## Kiểm thử và nghiệm thu

- Backend build thành công trên .NET SDK 9.0.318, net9.0.
- **73/73 test đạt**, gồm test có sẵn và test mới cho ML, payload PII, fallback, HTTP 429/500/401, timeout thực 5 giây qua handler giả, mất mạng, phản hồi lỗi, lịch Chủ Nhật, persistence, chống trùng, quyền xem và outbox gửi/thử lại/hủy.
- Coverlet ghi nhận **100% line coverage và branch coverage** cho ba class: TimeSeriesAnomalyDetector, PiiAnonymizerService, RuleBasedWeeklyReportFallbackEngine. Đây không phải 100% toàn dự án và không chứng minh độ chính xác lâm sàng. Báo cáo XML kèm trong gói.
- Đã thêm **3 Flutter widget test** cho giao diện nhận định/lịch sử/chi tiết, trạng thái trống và lỗi có retry. **Chưa chạy Flutter analyze, widget test hoặc build APK** vì chưa tìm thấy Flutter SDK trong môi trường này.
- Chưa gọi Gemini hoặc Firebase thật, chưa gửi thông báo tới người dùng, chưa chạy DDL trên Azure SQL và chưa kiểm thử lease cạnh tranh trên SQL Server. Persistence tests dùng EF Core InMemory. Cần cấu hình tài khoản và nghiệm thu các phần này trên môi trường dự án.
- Có warning CS1998 cũ trong CareAiMasterFactsTests và warning SDK FirebaseAdmin 3.6.0 đánh dấu Message.Token obsolete; mã vẫn build và hiện sử dụng FCM registration token của client.

## Nguồn API chính thức

- Gemini generateContent: https://ai.google.dev/api/generate-content
- Firebase Admin gửi thông báo: https://firebase.google.com/docs/cloud-messaging/send/admin-sdk
- Cấu hình FlutterFire: https://firebase.google.com/docs/flutter/setup
- Flutter FCM client: https://firebase.google.com/docs/cloud-messaging/flutter/client
