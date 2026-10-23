# Đề xuất bổ sung chức năng vào video CareAI

Ngày rà soát: 16/10/2026. Đã đối chiếu mã Flutter, API/backend, Wear OS và watchOS với kịch bản Remotion hiện tại. Đây là đánh giá từ mã nguồn; chưa chạy build, test hoặc kiểm chứng trên thiết bị trong lần rà soát này. Chưa thay đổi video.

## Nhận xét về bản hiện tại

Bản xem trước dài khoảng 40,6 giây, tập trung vào kết nối đồng hồ với điện thoại, SOS, cảnh báo ngã, vị trí/liên hệ và tiếp nhận sự cố. Đồng hồ mới xuất hiện dưới dạng sơ đồ. Các màn chăm sóc hằng ngày, gia đình, nhận định/báo cáo và hoàn tất xử lý chưa được giới thiệu rõ.

## Các nội dung đề xuất

| Ưu tiên | Chức năng | Giá trị nên kể cho người xem | Cách thể hiện |
|---|---|---|---|
| 1 — Rất nên | Giao diện đồng hồ và SOS trên cổ tay | Người cao tuổi có thể chủ động báo cần giúp ngay trên đồng hồ. | Mặt CareAI Watch → chạm SOS → điện thoại người thân nhận cảnh báo. Dùng giao diện đúng nền tảng. |
| 2 — Rất nên | Biểu đồ sức khỏe theo thời gian | Gia đình nhìn được diễn biến, thay vì chỉ một con số tại thời điểm chụp. | Thẻ nhịp tim → biểu đồ 24 giờ → SpO₂/vận động khi có dữ liệu phù hợp. |
| 3 — Rất nên | Góc Sức Khỏe: nhận định và báo cáo tuần | Có thêm thông tin để hỏi thăm và theo dõi người thân mỗi ngày. | Một nhận định có dữ liệu → mở bản tổng kết tuần. Không trình bày như chẩn đoán. |
| 4 — Rất nên | Nhóm gia đình và mời thêm thành viên | Nhiều người thân có thể cùng theo dõi và phối hợp hỗ trợ. | Một người cao tuổi kết nối với nhiều thành viên → màn gia đình → trạng thái tiếp nhận. |
| 5 — Nên | Pin, sạc và kết nối đồng hồ | Biết thiết bị có cần sạc hoặc kiểm tra kết nối hay không. | Phóng to trạng thái thiết bị trên điện thoại; chuyển giữa pin/sạc/mất tín hiệu bằng minh họa có nhãn. |
| 6 — Nên | Cảnh báo chỉ số bất thường ngoài té ngã | CareAI có luồng xử lý cảnh báo nhịp tim và SpO₂ dựa trên dữ liệu nhận được. | Một thẻ cảnh báo nhịp tim hoặc SpO₂ → người thân mở xem. Không dùng Test Lab làm bằng chứng cảm biến thật. |
| 7 — Nên | Hoàn tất xử lý, ghi chú và lịch sử sự cố | Gia đình xem lại quá trình hỗ trợ, không chỉ biết sự cố đã được tiếp nhận. | Tiếp nhận → ghi chú/đánh dấu đã giải quyết → dòng thời gian/lịch sử. |
| 8 — Có thể thêm | Ngưỡng nhịp tim ngày và đêm, đề xuất ngưỡng mới | Ngưỡng cảnh báo có thể được cá nhân hóa dựa trên lịch sử. | Màn ngưỡng ngày/đêm → đề xuất → người thân xác nhận áp dụng. Có thể tận dụng ảnh số 04 đã gửi. |
| 9 — Có thể thêm | Trang sức khỏe trên đồng hồ | Thể hiện đồng hồ còn phục vụ theo dõi hằng ngày. | Vuốt từ màn chính sang nhịp tim/bước chân. Chọn chỉ số đúng module; không hứa tất cả đều đồng bộ về người thân. |
| 10 — Dành cho bản hướng dẫn | Ghép nối bằng mã PIN | Giúp người dùng hình dung cách bắt đầu. | Tạo PIN trên điện thoại → nhập trên màn thiết bị có hỗ trợ. Apple Watch có màn nhập PIN; không gán giao diện này cho Wear OS hiện tại. |
| 11 — Dành cho bản hướng dẫn | Hàng đợi dữ liệu và gửi lại sau khi có kết nối | Giải thích việc lưu chờ, đồng bộ lại ở các luồng có hỗ trợ. | Biểu tượng dữ liệu chờ → gửi lại. Không diễn đạt thành vẫn luôn gửi được cảnh báo khi mất mạng. |

## Những khác biệt cần giữ đúng trong kịch bản

- **SOS đồng hồ và điện thoại khác nhau:** hai module đồng hồ đang gửi SOS ngay khi bấm. Bước xác nhận/đếm ngược và hủy chạm nhầm đang thấy ở điện thoại; không dựng bước đó thành giao diện đồng hồ.
- **Dữ liệu đồng hồ chưa giống nhau:** Apple Watch có luồng đồng bộ HealthKit cho nhịp tim và SpO₂; bước chân/giấc ngủ có hiển thị cục bộ nhưng chưa nằm trong danh sách metric của luồng đồng bộ này. Wear OS có cảm biến nhịp tim/bước chân cập nhật UI; hàm telemetry định kỳ trong màn chính gửi pin/đeo/sạc, còn HR/SpO₂ được kèm gói SOS khi có. Chưa nên nói cả hai đều gửi mọi chỉ số liên tục về điện thoại.
- **SpO₂ phụ thuộc thiết bị và nguồn dữ liệu:** Wear OS chưa thấy listener thu SpO₂ thật trong `onSensorChanged`; không lấy số liệu inject thử nghiệm để quảng bá khả năng đo thật.
- **Trạng thái đeo chưa phải phép đo chính xác trên mọi máy:** một số luồng đang suy ra từ việc không sạc. Ưu tiên quảng bá pin/sạc/kết nối, không khẳng định phát hiện tháo cổ tay tuyệt đối.
- **Báo cáo tuần có nguồn AI hoặc tổng kết theo số liệu:** có cơ chế dự phòng theo quy tắc. Nhận định xu hướng cần đủ dữ liệu lịch sử; không hứa xuất hiện ngay sau ghép nối.
- **Ngưỡng nhịp tim là đề xuất có xác nhận:** thuật toán dùng lịch sử, không phải tự chẩn đoán hoặc tự thay đổi mọi lúc.
- **Giấc ngủ chưa nên làm điểm quảng bá chính:** Wear OS hiện hiển thị “Chưa ghi nhận”; phần tổng hợp backend đang ước tính ngủ sâu bằng 28% tổng thời gian và đặt số lần thức là 1 khi có mẫu ngủ. Không giới thiệu đây là phân tích giai đoạn ngủ chính xác.
- **Huyết áp:** có thẻ hiển thị/API không đồng nghĩa mọi đồng hồ tự đo được huyết áp.
- **Ảnh hiện trường:** phụ thuộc quyền camera và trạng thái app trên điện thoại người cao tuổi. Nút gọi liên hệ/115 là thao tác người dùng, không mô tả thành hệ thống tự gọi cấp cứu.

## Phương án biên tập đề xuất

Chọn **1–7** làm phần bổ sung chính, khoảng **65–75 giây**. Mạch kể: kết nối → giao diện đồng hồ → theo dõi hằng ngày/biểu đồ/trạng thái pin → nhận định và báo cáo tuần → gia đình cùng chăm sóc → SOS hoặc cảnh báo → xem thông tin/tiếp nhận → ghi nhận xử lý và lịch sử → kết.

Giữ giọng nam tiếng Việt, tốc độ vừa như bản đang xem và lời dẫn liền mạch. Tăng thời lượng bằng nội dung mới, không kéo dài khoảng nghỉ. Các mục 8–11 phù hợp bản giới thiệu dài hơn hoặc video hướng dẫn riêng.

Ảnh đã gửi đủ cho phần SOS/cảnh báo/tiếp nhận và có thể tái sử dụng màn ngưỡng ngày/đêm. Chưa có ảnh giao diện đồng hồ, báo cáo tuần, nhóm gia đình và lịch sử xử lý trong bộ ảnh hiện tại. Khi dựng các phần này, ưu tiên màn thật; nếu dùng sơ đồ thì ghi rõ là minh họa.

## Đối chiếu mã nguồn

| Nội dung | Tệp và vị trí đã đọc |
|---|---|
| Kịch bản đang dùng | `remotion/public/timeline-continuous.json` |
| Wear OS SOS, cảm biến, telemetry | `CareAI/wearos/src/main/kotlin/vn/careai/companion/WearOsMainActivity.kt:246`, `:372`, `:452`, `:469`, `:544`, `:569` |
| Wear OS cảnh báo ngã | `CareAI/wearos/src/main/kotlin/vn/careai/companion/WearOsFallListenerService.kt:14`; `WearOsFallRegistrationHelper.kt:16` cùng thư mục |
| Apple Watch màn chính/SOS/sức khỏe/PIN | `CareAI/watchos/Sources/CareAIWatchApp.swift:76`, `:395`, `:478`, `:548`, `:596` |
| Apple Watch HealthKit, trạng thái, hàng đợi | `CareAI/watchos/Sources/HealthSync.swift:139`, `:330`, `:440`, `:486`, `:610`, `:1048`, `:1084` |
| Biểu đồ, thiết bị, ngưỡng, PIN trên điện thoại | `CareAI/companion_app/lib/caregiver/screens/elder_dashboard_screen.dart:148`, `:475`, `:1025`, `:1508`, `:1760`, `:2592` |
| Góc sức khỏe | `CareAI/companion_app/lib/caregiver/screens/health_corner_screen.dart:21`, `:94`, `:105`, `:128`; `CareAI/src/CareAI.API/Controllers/HealthReportsController.cs:18` |
| Nhận định chuỗi thời gian | `CareAI/src/CareAI.Infrastructure/AnomalyDetection/TimeSeriesAnomalyDetector.cs:33`, `:57` |
| Báo cáo tuần và dự phòng | `CareAI/src/CareAI.Infrastructure/WeeklyReports/WeeklyReportService.cs`; `GeminiWeeklyReportClient.cs` cùng thư mục |
| Mời gia đình/phân quyền | `CareAI/companion_app/lib/caregiver/screens/family_management_screen.dart:73`, `:269`, `:340`; `CareAI/src/CareAI.API/Controllers/FamilyController.cs:56`, `:76`, `:102` |
| Lịch sử, dòng thời gian, giải quyết | `CareAI/companion_app/lib/caregiver/screens/incident_detail_screen.dart:193`, `:521`, `:739`, `:757`; `incident_history_screen.dart:26` cùng thư mục |
| Đếm ngược ngã trên điện thoại | `CareAI/companion_app/lib/screens/fall_countdown_dialog.dart:43`, `:54`, `:106`, `:127` |
| Cảnh báo chỉ số | `CareAI/src/CareAI.Infrastructure/Engines/ClinicalDiagnosticEngine.cs` |
| Đề xuất ngưỡng | `CareAI/src/CareAI.Infrastructure/Services/AdaptiveThresholdService.cs:20`, `:74` |
| Giới hạn dữ liệu giấc ngủ | `CareAI/src/CareAI.API/Controllers/DashboardController.cs:482` |

