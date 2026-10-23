# Cơ sở chuẩn bị video giới thiệu CareAI

Ngày đọc dự án: 16/10/2026.

Phạm vi: đọc tài liệu định hướng, tài liệu marketing hiện có và đối chiếu các luồng chính trong Flutter, Android native, Wear OS, watchOS, API và backend. Đây là ghi nhận từ mã nguồn, không phải biên bản nghiệm thu. Chưa chạy build, test, analyze hoặc ứng dụng trên thiết bị; chưa xác nhận cấu hình triển khai đang hoạt động. Không thay đổi mã nguồn sản phẩm.

## 1. Sản phẩm và người xem

CareAI hỗ trợ gia đình chăm sóc người cao tuổi từ xa: xem thông tin từ thiết bị, gửi tín hiệu cần giúp, nhận cảnh báo và phối hợp xử lý sự cố.

Người xem chính nên là người con hoặc người thân bận rộn, sống riêng hay ở xa cha mẹ. Người cao tuổi là người dùng trực tiếp của giao diện SOS; các thành viên khác cùng tham gia chăm sóc là nhóm người dùng phối hợp.

Thông điệp làm việc: **“Dù không ở cạnh, gia đình vẫn có thêm cách theo dõi, nhận tín hiệu cần giúp và cùng nhau phản hồi.”** Đây là định hướng sáng tạo cho video, chưa phải khẩu hiệu được nhóm phê duyệt.

Giọng kể nên gần gũi, tôn trọng sự chủ động của cha mẹ; giải thích tác dụng bằng tình huống gia đình. Các thuật ngữ backend như telemetry, quorum, ACK, outbox hoặc RowVersion không cần xuất hiện trong lời dẫn.

## 2. Hành trình sử dụng đã đối chiếu

| Chặng | Triển khai tìm thấy | Ý nghĩa với người dùng và cảnh có thể quay |
| --- | --- | --- |
| Chọn vai trò | `main.dart`, `role_selection_screen.dart` | Một ứng dụng có chế độ người cao tuổi và người thân. Quay màn chọn vai trò ngắn gọn. |
| Thiết lập gia đình | `home_screen.dart`, `family_management_screen.dart`, `CaregiversController.cs`, `FamilyController.cs` | Tạo hồ sơ, mời người thân cùng chăm sóc. Người bảo hộ chính có quyền tạo lời mời và thu hồi thành viên. |
| Ghép thiết bị | `device_pairing_screen.dart`, `DevicesController.cs`, thẻ PIN trong `elder_dashboard_screen.dart` | Người thân tạo PIN sáu số có thời hạn, nhập trên thiết bị cần ghép. Không đưa PIN/token thật vào video. |
| Theo dõi hằng ngày | `elder_dashboard_screen.dart`, `DashboardController.cs`, `health_connect_service.dart` | Có các thẻ và biểu đồ nhịp tim, SpO₂, huyết áp, vận động; dữ liệu hiển thị phụ thuộc nguồn đo. Có bản đồ và thời điểm dữ liệu. |
| Chủ động báo cần giúp | `sos_button_screen.dart` | Nút SOS lớn. Luồng bấm SOS có xác nhận đếm ngược năm giây, có thể hủy khi chạm nhầm hoặc chọn gửi ngay. |
| Tín hiệu ngã | `fall_countdown_dialog.dart`, `fall_service.dart`, Android native và module đồng hồ | Có đếm ngược, lựa chọn “TÔI ỔN - HỦY CẢNH BÁO” hoặc “CẦN TRỢ GIÚP - GỬI NGAY”. Thời gian thực tế nhận từ sự kiện; không cố định con số trong lời dẫn trước khi chọn thiết bị và luồng quay. |
| Gia đình phản hồi | `caregiver_push_service.dart`, `incident_detail_screen.dart`, `IncidentsController.cs` | Có cảnh báo, chi tiết sự cố, vị trí/chỉ đường khi có GPS, mở trình gọi điện và tiếp nhận sự cố. |
| Lưu diễn biến | `incident_history_screen.dart`, `IncidentsController.cs` | Sự cố đi từ đang mở sang đã tiếp nhận rồi đã giải quyết; đóng sự cố cần ghi chú. Có timeline và lịch sử để xem lại. |
| Quan tâm dài hạn | `health_corner_screen.dart`, `TimeSeriesAnomalyDetector.cs`, `WeeklyReportService.cs` | Có nhận định từ dữ liệu và báo cáo tuần. Dùng để kể về việc hỏi thăm và theo dõi diễn biến, tránh mô tả như kết luận bệnh. |

## 3. Trục kể chuyện ưu tiên

1. **Tình huống mở:** người con đang làm việc hoặc sống xa, muốn biết cha mẹ ở nhà thế nào.
2. **Giới thiệu ngắn:** CareAI kết nối hai phía trong cùng một hệ thống chăm sóc gia đình.
3. **Sinh hoạt bình thường:** người thân xem thông tin được thiết bị cung cấp, biểu đồ và thời điểm cập nhật.
4. **Một tình huống cần giúp:** cha/mẹ bấm SOS; hoặc dùng một cảnh mô phỏng ngã có ghi nhãn rõ. Không cần dồn nhiều tình huống khẩn vào cùng video.
5. **Điểm nhấn:** người thân mở sự cố, xem thông tin, gọi liên hệ và xác nhận tiếp nhận. Thể hiện việc gia đình biết sự cố đã được tiếp nhận.
6. **Kết:** xem lại lịch sử hoặc báo cáo tuần, trở về khoảnh khắc hỏi thăm trong gia đình.

Đây là khung nội dung chuẩn bị, chưa phải kịch bản lời thoại và phân cảnh theo giây. Có thể phát triển thành bản khoảng 90–120 giây nếu chưa có yêu cầu thời lượng khác. Lời kêu gọi cuối cần theo tình trạng phát hành thực tế: không tự thêm “tải ngay”, giá bán, mã QR hoặc liên kết cửa hàng khi chưa có thông tin.

## 4. Các giới hạn phải phản ánh đúng khi viết lời dẫn

- **Gửi cảnh báo và gọi cấp cứu:** có UI dùng câu “tự động gọi cấp cứu”, nhưng đường xử lý đếm ngược ngã gửi gói SOS tới backend. Nút gọi trong màn người thân mở trình gọi điện. Không mô tả CareAI tự gọi 115, tự điều xe hoặc có đội cứu hộ riêng.
- **Thông báo:** code hiện tại đăng ký `FirebasePushSender` và gọi Firebase SDK thật; mô tả FCM mô phỏng trong hướng dẫn cũ không còn khớp triển khai này. Tuy nhiên, chưa kiểm chứng cấu hình và việc nhận thông báo đầu cuối trong lần đọc này. Server ghi gửi thành công không chứng minh người thân đã đọc.
- **Ngoại tuyến:** có lưu hàng đợi và gửi lại. Không nói người thân vẫn nhận cảnh báo ngay khi thiết bị không có đường truyền. Snackbar SOS có câu thành công ngay cả sau nhánh lỗi mạng, nên không lấy riêng câu này làm bằng chứng nhận cảnh báo khi quay.
- **Dữ liệu sức khỏe:** có các đường nhập dữ liệu thực và công cụ mô phỏng. Mọi chỉ số bơm để quay phải ghi rõ “Dữ liệu minh họa” hoặc “Tình huống mô phỏng”. Có thẻ huyết áp không đồng nghĩa mọi đồng hồ tự đo được huyết áp.
- **Giấc ngủ:** API hiện suy ra ngủ sâu bằng 28% tổng thời gian ngủ và gán một số thông tin thức giấc. Không lấy thẻ này làm bằng chứng đo chuyên sâu hoặc lặp lại nhãn “đạt chuẩn y tế” trong lời quảng cáo.
- **AI:** có ML.NET tìm một số bất thường theo lịch sử cá nhân; có tổng kết tuần qua Gemini và phương án tổng kết bằng quy tắc. Có phân tích đề xuất ngưỡng nhịp tim để người thân xác nhận. Chưa có căn cứ từ lần đọc này cho tuyên bố dự báo đột quỵ, chẩn đoán bệnh hoặc độ chính xác lâm sàng.
- **Đồng hồ:** có module Wear OS và watchOS, nhưng đường cảm biến và phát hiện ngã khác nhau, phụ thuộc phần cứng, quyền và điều kiện chạy nền. Không lấy README về tương đương tính năng làm bằng chứng mọi thiết bị hoạt động giống nhau.
- **GPS và ảnh:** có cập nhật vị trí, đính kèm ảnh sự cố. Ảnh Flutter phụ thuộc quyền camera và app đang hiển thị; GPS có thể thiếu hoặc đến trễ. Không dựng thành lời hứa luôn có ảnh/vị trí tức thì.
- **Tính năng tương lai:** không đưa nhắc thuốc, nhắc uống nước, chatbot, thuê bao hoặc thanh toán vào danh sách hiện có chỉ vì chúng xuất hiện trong định hướng kinh doanh.

## 5. Chuẩn bị khi bước sang quay và viết bản cuối

- Chọn một gia đình giả định xuyên suốt, dùng tên, ảnh, địa chỉ và dữ liệu minh họa.
- Ưu tiên màn hình: chọn vai trò → danh sách người thân → dashboard → SOS → chi tiết/tiếp nhận → lịch sử → góc sức khỏe.
- Chọn đúng điện thoại/đồng hồ sẽ xuất hiện; xác nhận riêng luồng đếm ngược, quyền, thông báo và dữ liệu trên các thiết bị đó khi được yêu cầu kiểm tra.
- Không dùng phản hồi giả lập trong tài liệu marketing như lời chứng thực của khách hàng thật.
- Giữ lời dẫn ở mức “hỗ trợ theo dõi và cảnh báo”; tránh hứa hẹn an toàn tuyệt đối, phát hiện mọi cú ngã, độ trễ cố định hoặc cứu sống đã được chứng minh.

## 6. Tài liệu nền và vị trí tra cứu

Tài liệu đã tham khảo: `AGENTS.md`, `README.md`, `HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md`, README Wear OS/watchOS và các tài liệu marketing hiện có. Một số mô tả trong tài liệu cũ khác mã nguồn hiện tại; các nhận định chức năng ở trên lấy code làm căn cứ.

Các thư mục tra cứu chính:

- `CareAI/companion_app/lib/screens/`: trải nghiệm người cao tuổi.
- `CareAI/companion_app/lib/caregiver/screens/`: trải nghiệm người thân.
- `CareAI/companion_app/lib/services/` và `lib/caregiver/services/`: dữ liệu, SOS, đồng bộ và push.
- `CareAI/src/CareAI.API/Controllers/`: hồ sơ, gia đình, thiết bị, dashboard, sự cố, ảnh/vị trí và báo cáo.
- `CareAI/src/CareAI.Infrastructure/`: quy tắc cảnh báo, ngưỡng thích nghi, phân tích bất thường, báo cáo và thông báo.
- `CareAI/companion_app/android/app/src/main/kotlin/`, `CareAI/wearos/`, `CareAI/watchos/`: xử lý native và đồng hồ.
