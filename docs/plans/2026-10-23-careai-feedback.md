# Feedback khách hàng — bổ sung theo yêu cầu 23/10/2026

Mở rộng phạm vi admin ban đầu bằng mục **Phản hồi khách hàng**, đồng thời thêm
**Tài khoản → Kết nối & hỗ trợ → Góp ý & phản hồi** trong app người thân.

## Phạm vi đã viết

- App gửi loại `Bug` / `Suggestion` / `Other`, tiêu đề 3–120 ký tự và nội dung
  10–3000 ký tự. Tiêu đề/nội dung được trim, có kiểm tra phía server.
- Chỉ báo nhận thành công khi API trả receipt; lỗi gửi giữ nội dung. Thử lại cùng
  payload trong màn hình hiện tại dùng cùng request ID 32 ký tự hex.
- Backend unique `(CaregiverId, RequestId)`, so sánh payload khi retry: cùng nội dung
  trả receipt cũ, khác nội dung trả 409. Giao dịch Serializable và execution strategy
  bảo vệ gửi đồng thời. Không tự failover nội dung sang database khác.
- Giới hạn 10 phản hồi mới/giờ/tài khoản tại database, không tính retry hợp lệ.
- Người thân chỉ xem được lịch sử của chính mình, phân trang 25. Không nhận
  CaregiverId từ body/query; lấy từ danh tính JWT caregiver đã xác thực.
- Admin dùng policy `admin.feedback.read`, cấp cho Owner/Operations/Support;
  Auditor và JWT caregiver không được cấp quyền. Không thay đổi quyền theo elder.
- Admin tìm tiêu đề/nội dung, lọc loại, phân trang, mở chi tiết bằng details;
  văn bản do khách hàng nhập được Razor encode, không dùng Html.Raw.
- Bản Preview admin có nhãn mô phỏng, inbox rỗng; không giả lập phản hồi thật.
- Không gửi email/push, không thêm file đính kèm, không có chức năng trả lời,
  sửa/xóa hoặc đánh dấu xử lý trong đợt này. Đây không phải kênh SOS.
- Không tự thu thập elder ID, vị trí, số đo, token hay log thiết bị. UI nhắc người
  gửi tránh thông tin nhạy cảm; nội dung tự nhập vẫn cần quyền staff phù hợp.

## API

| Endpoint | Xác thực | Kết quả |
| --- | --- | --- |
| `POST /api/v1/caregivers/feedback` | JWT scheme caregiver, role Caregiver | Receipt chứa ID, nội dung và thời điểm UTC |
| `GET /api/v1/caregivers/feedback?page=1` | Như trên | Chỉ feedback của người đang đăng nhập |
| `GET /api/v1/admin/feedback?search=&category=&page=1` | Scheme admin, server-to-server key, policy feedback | Inbox, tên/ID người gửi, không trả email/SĐT |

Không có API anonymous hoặc ID người gửi có thể ghi đè từ client.

## Cài đặt dữ liệu và trạng thái kiểm tra

Review rồi áp dụng thủ công script
`CareAI/src/CareAI.Infrastructure/Data/Scripts/20261023_customer_feedback.sql`
vào đúng database môi trường đã chọn. Script chỉ thêm bảng/index/FK; không thay
đổi caregiver, incident, telemetry hoặc cấu hình database. Không được gọi bởi
startup migration helper. Trước khi áp dụng, kiểm tra quyền/schema và kế hoạch
backup của môi trường đó. Chưa có retention tự động cho nội dung feedback.

Admin thật vẫn tuân theo giới hạn Development/MFA của AdminWeb hiện hữu.
Đã thêm FeedbackTests cho cách ly lịch sử, validation và tách quyền. Chưa chạy
build, test, analyze, ứng dụng hoặc emulator theo AGENTS.md.
Concurrency/idempotency thực tế cần kiểm thử bằng SQL Server khi được yêu cầu;
EF InMemory không xác minh được unique index hay transaction SQL Server.

### Áp dụng Azure SQL ngày 23/10/2026

Theo yêu cầu trực tiếp của người dùng, đã áp dụng script feedback vào database
`CareAI` trên server Azure SQL và xác minh metadata:
7 cột, primary key, 3 index, foreign key và check constraint đều được tạo, bật và
trusted. Không thêm dữ liệu feedback thử nghiệm hoặc chạy script nền tảng admin.

Lần đầu thất bại với SQL 1753 do độ dài khóa ngoại không khớp. Đã xác minh bảng
không tồn tại sau lỗi, sửa `CaregiverId` trong script và mapping EF về 50 ký tự
theo `Caregivers.Id` thực tế rồi chạy lại thành công, transaction đã commit.
Kết quả này chỉ xác nhận schema Azure; chưa xác nhận API/app đã deploy hoặc luồng
feedback hoạt động đầu cuối.
