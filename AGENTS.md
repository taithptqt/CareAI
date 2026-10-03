# Hướng dẫn cho agent

## Phạm vi và tài liệu
- Áp dụng cho toàn bộ repository. Mã nguồn chính nằm trong `CareAI/`; tài liệu định hướng ở `README.md` và `HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md`.
- Đối chiếu mô tả trong tài liệu với mã nguồn trước khi khẳng định tính năng đã hoạt động; không coi số liệu kiểm thử ghi trong README là kết quả của lần chạy hiện tại.
- Giữ nguyên các thay đổi có sẵn của người dùng; chỉ sửa tệp liên quan đến yêu cầu.

## Cấu trúc và công cụ
- `CareAI/src/CareAI.Core`: entity, enum, DTO; `CareAI.Infrastructure`: EF Core, engine, background worker; `CareAI.API`: controller, middleware, cấu hình HTTP; `CareAI/tests/CareAI.UnitTests`: xUnit.
- `CareAI/companion_app`: ứng dụng Flutter hợp nhất cho người cao tuổi và người thân (`lib/caregiver/`), kèm Kotlin Android; `CareAI/wearos`: module đồng hồ Wear OS độc lập; `CareAI/watchos`: module đồng hồ Apple Watch độc lập.
- Backend dùng .NET 9, NuGet qua các `.csproj`; ứng dụng Flutter dùng `flutter pub get` với `pubspec.lock`; Wear OS dùng Gradle wrapper độc lập trong `CareAI/wearos`.

## Lệnh kiểm tra tham khảo

- Không tự chạy build, test, analyze hoặc kiểm thử trên thiết bị khi người dùng không yêu cầu. Các lệnh dưới đây chỉ dùng khi người dùng yêu cầu kiểm tra.

| Phạm vi | Lệnh chạy từ thư mục gốc |
| --- | --- |
| Build backend | `dotnet build CareAI/CareAI.slnx --nologo` |
| Một bài kiểm thử | `dotnet test CareAI/tests/CareAI.UnitTests/CareAI.UnitTests.csproj --filter "FullyQualifiedName~TenTest" --nologo` |
| Toàn bộ kiểm thử backend | `dotnet test CareAI/CareAI.slnx --nologo` |
| Phân tích một tệp Dart | `cd CareAI/companion_app; flutter analyze lib/duong_dan.dart` |
| Build Wear OS trên Windows | `cd CareAI/wearos; .\gradlew.bat assembleDebug` |
- Khi được yêu cầu kiểm tra, chọn lệnh sát phạm vi thay đổi; chỉ báo kết quả đã thực sự chạy và nêu rõ khi thiếu SDK, thiết bị hoặc SQL Server.

## Bất biến cần giữ
- Giữ kiến trúc backend modular monolith và các phiên bản .NET/EF Core ổn định đang khai báo trong `.csproj`.
- Xác thực thiết bị dùng `X-DeviceId` và `X-Device-Token`; băm SHA-256 của token phải là chữ thường bằng `.ToLowerInvariant()`.
- Giữ kiểm soát quyền caregiver với từng elder; không bỏ qua xác thực JWT hoặc middleware thiết bị.
- Giữ tính idempotent của gói telemetry theo `(DeviceId, PacketId)`, lưu mẫu đo kèm gói SOS và ràng buộc một incident `Open`/`Acknowledged` cho mỗi elder; xem `TelemetryEngine` và `CareAiDbContext`.
- Khi sửa luồng incident, giữ `RowVersion`, timeline và notification outbox. `NotificationDispatcherWorker` hiện mô phỏng gửi FCM; không coi trạng thái `SENT` là bằng chứng đã gửi đến thiết bị.
- Khi sửa cảnh báo Android, giữ luồng Direct Boot, Device Protected Storage và `RTC_WAKEUP`; nếu người dùng yêu cầu kiểm thử, kiểm tra hành vi trên thiết bị hoặc emulator khi có sẵn.

## Quy ước thay đổi
- Đặt entity và DTO ở Core, ánh xạ/lưu trữ ở Infrastructure, HTTP ở API; theo mẫu code cùng phân hệ.
- Flutter: dùng quy tắc trong `CareAI/companion_app/analysis_options.yaml`; tránh sửa tệp Flutter/Gradle sinh tự động trừ khi thay đổi phụ thuộc yêu cầu.
- Không đưa secret, token thô, chuỗi kết nối thật hoặc dữ liệu sức khỏe thật vào code, log, test hay commit.
- Nếu agent tạo commit, thêm trailer `Co-Authored-By: Codex <codex@openai.com>`; dùng đúng tên agent thực hiện nếu khác Codex.
