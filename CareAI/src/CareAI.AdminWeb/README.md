# CareAI AdminWeb

## Sử dụng trên máy hiện tại

Website admin chạy tại https://localhost:7241/Accounts, API riêng tại
https://localhost:7156, kết nối dữ liệu thật trong Azure SQL database CareAI.
Không cần hosting website để quản lý tài khoản trên máy này. Tài khoản đăng nhập
ban đầu là `admin`; mật khẩu đã được thiết lập theo yêu cầu, chỉ lưu hash trong DB.

Mở hai terminal PowerShell, chạy lần lượt (giữ cả hai tiến trình):

```powershell
& "$env:LOCALAPPDATA\CareAI\AdminLocal\Start-Admin.ps1" -Mode Api
```

```powershell
& "$env:LOCALAPPDATA\CareAI\AdminLocal\Start-Admin.ps1" -Mode Web
```

Launcher và khóa mã hóa bằng Windows DPAPI nằm ngoài repository. Cần .NET 9 và
HTTPS development certificate được tin cậy. API cục bộ dùng AdminOnlyHost:
không chạy worker telemetry/SOS hoặc startup migration, chỉ nghe HTTPS localhost.

## Chức năng hiện có

- Tài khoản người thân: tìm kiếm, lọc, phân trang, xem chi tiết, sửa họ tên/SĐT,
  mở khóa đăng nhập. Danh sách che thông tin liên hệ.
- Nhân sự admin: tạo tài khoản nội bộ, quản lý vai trò/trạng thái, thu hồi phiên.
  Không cho tự hạ quyền hoặc vô hiệu hóa Owner cuối cùng.
- Người cao tuổi và liên kết chăm sóc: tra cứu, chuyển người chăm sóc chính hoặc
  ngừng liên kết phụ với kiểm tra sự cố đang mở.
- Thiết bị: tra cứu, thu hồi với kiểm tra thiết bị thay thế/sự cố.
- Sự cố: đọc metadata và timeline; không thao tác xử lý y tế từ admin.
- Feedback: đọc, trả lời và cập nhật trạng thái. App có màn hình gửi/lịch sử phản hồi.
- Nhật ký: xem thay đổi thành công và yêu cầu bị từ chối.

Mỗi thay đổi yêu cầu lý do, mật khẩu xác thực lại, kiểm tra quyền phía API,
phiên bản dữ liệu và request ID chống lặp. Audit được giữ cùng giao dịch.

**Giới hạn hiện tại:** đình chỉ/thu hồi JWT người thân chưa bật vì API ứng dụng
trên Azure chưa thực thi cơ chế phiên mới. Nút tương ứng được ẩn, API cũng từ chối
thao tác. Không cần cập nhật API Azure để dùng tra cứu/sửa hồ sơ/mở khóa đăng nhập.
API Azure public cũng chưa có luồng feedback mới; đã kiểm tra luồng này qua API
cục bộ + Azure SQL và widget Flutter, chưa kiểm thử trên điện thoại thật.

## Bảo vệ truy cập

Admin có bảng tài khoản, vai trò và JWT scheme riêng với caregiver. Cookie web
Secure/HttpOnly chỉ giữ tham chiếu; ticket mã hóa lưu phía server trong SQL cache.
Mỗi request kiểm tra phiên, trạng thái và quyền hiện tại. Có giới hạn đăng nhập,
khóa tạm thời, CSRF và PBKDF2-SHA256. Có trang thiết lập TOTP; môi trường local
hiện không bắt buộc MFA. Không tự kích hoạt MFA cho admin hiện tại.

Chế độ Preview chỉ dành cho Development và dùng dữ liệu mẫu; launcher ở trên
bật Live và không fallback sang mẫu. Các script admin/feedback đã áp dụng vào
Azure SQL ngày 23/10/2026. Không tự chạy script bằng startup migration.

Nếu sau này cần website truy cập qua Internet, phải cấu hình riêng hosting,
HTTPS, persistent keys có certificate bảo vệ và MFA bắt buộc. Chưa có hosting
production được triển khai trong lần làm này. Phục hồi MFA/backup keys cần quy
trình vận hành riêng; không có public reset MFA.

## Kiểm tra đã chạy ngày 23/10/2026

- Build solution .NET: thành công, 0 warning/error.
- Backend: 222 test đạt.
- HTTP + Azure SQL: đăng nhập/cookie/CSRF, trang dữ liệu thật; phân quyền admin,
  thu hồi phiên nhân sự, chống lặp/xung đột, audit; gửi feedback và trả lời bằng
  tài khoản tổng hợp, xóa dữ liệu caregiver/feedback tổng hợp sau kiểm tra.
- Analyze bốn tệp Dart liên quan feedback: không có issue; hai widget test đạt.
- Build APK debug thành công; chưa cài/kiểm thử thiết bị.

Các gói trong `CareAI/artifacts` là bản thử từ quá trình phát triển, không dùng
làm bằng chứng đã triển khai hosting. Dùng mã nguồn và launcher hiện tại.
