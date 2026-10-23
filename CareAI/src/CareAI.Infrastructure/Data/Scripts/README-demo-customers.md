# Dữ liệu khách hàng mẫu 23/10/2026

`Seed-DemoCustomers.ps1` thêm 20 caregiver với tên Việt khác nhau và 20 feedback
tổng hợp trong `demo-customers-20261023.json`. Ngày tạo được rải trong tháng,
feedback gồm lỗi, đề xuất, câu hỏi; 12 mới, 4 đang xử lý, 4 đã phản hồi.
Nội dung không phải đánh giá hay sự cố thực tế của khách hàng.

Batch được nhận biết nội bộ bằng ID `8d3a9e71-b5c2-4a60-9e18-000000000001`
đến `000000000020` và email `contact.7301@example.invalid` đến `contact.7320@example.invalid`.
`Normalize-CustomerBatch.ps1` chuyển ID cũ sang ID mới và giữ nguyên nội dung.
Không gắn nhãn thử vào tên hoặc lời góp ý. Không dùng số điện thoại người thật;
mật khẩu ngẫu nhiên riêng từng tài khoản được băm rồi bỏ, không có mật khẩu chung.
Không tạo thông số sức khỏe, SOS, thiết bị, push token hay liên kết với hồ sơ thật.

Script lấy kết nối từ cấu hình API hiện hữu, kiểm tra đúng Azure server/database,
chạy trong transaction và không sửa bản ghi đã có. Chạy lại không nhân bản batch.
Không đưa chuỗi kết nối hoặc thông tin xác thực vào dữ liệu mẫu.
