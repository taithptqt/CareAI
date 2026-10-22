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

## Skill UI/UX cho CareAI
- Khi thiết kế, sửa hoặc review UI/UX, dùng `ui-ux-pro-max` để tra design system, typography, màu sắc, accessibility và hướng dẫn Flutter; dùng `design-taste-frontend` (Taste Skill) để định hướng thẩm mỹ và tránh giao diện rập khuôn.
- Hai skill được cài ngoài repository tại thư mục người dùng `~/.agents/skills/ui-ux-pro-max/` và `~/.agents/skills/design-taste-frontend/`. Đọc `SKILL.md` tương ứng trước khi dùng; với màn hình ứng dụng, đọc thêm `references/app-screens.md` của Taste Skill.
- Repo nguồn được tải ngoài project tại `~/.codex/skill-sources/ui-ux-pro-max-skill/` và `~/.codex/skill-sources/taste-skill/`. Không sao chép repo nguồn, dữ liệu hay bộ công cụ skill vào CareAI hoặc thêm chúng vào dependency ứng dụng.
- Áp dụng gợi ý theo stack hiện có: Flutter/Dart, Kotlin Android/Wear OS, SwiftUI watchOS. Giữ nhận diện CareAI và ưu tiên chữ dễ đọc, vùng chạm lớn, thao tác SOS/tiếp nhận rõ, trạng thái dữ liệu thật/cũ/thiếu/mô phỏng; không áp dụng bố cục landing page vào màn hình cấp cứu.
- Skill là hướng dẫn hỗ trợ; yêu cầu người dùng và các bất biến trong tài liệu này được ưu tiên. Không tự thay giao diện ngoài phạm vi yêu cầu, đổi framework, thêm dependency hoặc chạy build/test/analyze/kiểm thử thiết bị chỉ vì skill đề xuất.
