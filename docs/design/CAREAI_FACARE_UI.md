# Giao diện CareAI theo Facare Direction B

Nguồn tham khảo do người dùng chỉ định: https://facare-653376991564.asia-east1.run.app/

Ngày áp dụng: 21/10/2026. Các màu và quy cách dưới đây được đối chiếu từ CSS, design tokens và thành phần giao diện công khai của trang. Đã xem ảnh dựng widget Flutter và ảnh Chrome của màn chọn vai trò/đăng nhập; chưa kiểm tra toàn ứng dụng trên thiết bị thật.

## Màu và chữ

| Thành phần | Màu từ Facare |
| --- | --- |
| Nền màn hình | `#FAF7F2` |
| Nền kem phụ | `#F7F2EB` |
| Thẻ thông tin | `#FFFFFF` |
| Chữ chính | `#231811` |
| Nút chính, thương hiệu | `#4A3020` |
| Chữ phụ | `#7D7168` |
| Viền | `#E4DACD` |
| Xanh rêu | `#7A9850` |
| Nút thêm | `#9BB068` |
| Nền xanh nhạt | `#D5E2BE`, `#F0F4E4` |
| Nền đào | `#F8E5DC` |
| Nền lavender | `#F0EEFA` |
| Tín hiệu cần chú ý | `#C93B2B` |

Font Be Vietnam Pro được đóng gói tại máy, gồm các độ đậm 400–800, kèm giấy phép OFL trong `CareAI/companion_app/assets/fonts/be_vietnam_pro/`. Ứng dụng không cần tải font khi mở màn hình.

Thẻ bo góc 18–28, nút chính dạng viên thuốc, bóng nâu nhẹ, khoảng cách nhất quán. Thanh điều hướng cong và nút thêm xanh lấy hình thức từ Facare; các đích đến vẫn là Gia đình, Sự cố, Lịch sử và Tài khoản của CareAI.

## Áp dụng cho sản phẩm

- Màn đầu dùng bố cục chào mừng, minh họa gia đình và hai lựa chọn vai trò.
- Đăng nhập dùng mảng xanh nhạt phía trên, form nền kem và nút nâu; giữ các thao tác đăng nhập, đăng ký, quên mật khẩu và cấu hình máy chủ.
- Trang gia đình có lời chào, mảng thông tin xanh và thẻ hồ sơ trắng. Số hồ sơ, trạng thái thiết bị và sự cố lấy từ dữ liệu hiện có.
- Dashboard chuyển các bề mặt tối sang kem/trắng và chữ nâu; giữ chỉ số, biểu đồ, GPS, thời điểm đo, dữ liệu mô phỏng và cấu hình ngưỡng hiện có.
- Màn người cao tuổi ưu tiên nút SOS đỏ lớn trước thông tin đồng hồ; bố cục cuộn để chi tiết thiết bị không ép nhỏ nút SOS.
- Các màn sự cố, lịch sử, gia đình và báo cáo dùng cùng palette. Trạng thái khẩn vẫn dùng màu và nhãn riêng.

Hai ảnh minh họa `welcome-family-hero.png` và `girl-greeting-clean.png` được lấy từ đường dẫn công khai `/assets/facare/` của website mẫu theo yêu cầu tham khảo giao diện. Chúng là ảnh trang trí, không đại diện hồ sơ hoặc dữ liệu sức khỏe người dùng.

## Phạm vi và giới hạn

### Hoàn thiện theo ảnh mẫu người dùng

- Navbar giữ tỷ lệ từ SVG Facare 375 × 128: bốn vị trí icon, nền trắng cong lõm, vòng tròn mục đang chọn, nút thêm 64 px ở giữa và dấu cộng trắng nét mảnh. Không hiển thị nhãn chữ dưới icon như bản trước; mỗi nút vẫn có tooltip và nhãn cho trình đọc màn hình. Icon và đích đến phục vụ các chức năng hiện có của CareAI.
- Phần tổng quan dùng chữ tên người thân 26/800, nhãn chào 13/700, tiêu đề thẻ 21/800, hai thẻ số liệu xanh nhạt/lavender. Giữ Be Vietnam Pro cho toàn bộ thành phần mới. Thêm ảnh `card1-green-b.png` từ cùng thư mục tài nguyên công khai của Facare để khớp phần minh họa trong ảnh mẫu.
- Con số trên tổng quan là số hồ sơ và số sự cố đang mở lấy từ state hiện có; khi còn tải dữ liệu sự cố thì hiển thị trạng thái tải. Không thêm chức năng nhắc thuốc hay chi phí bằng dữ liệu giả.
- Thẻ sinh hiệu chuyển thành một cột khi chữ lớn hoặc màn hình hẹp, hai cột trên điện thoại đủ rộng, bốn cột trên vùng nội dung từ 900 px. Các phép tính, ngưỡng và giá trị đo giữ nguyên.
- Nút gọi người cao tuổi được chuyển lên đầu chi tiết sự cố; các hành động tiếp nhận, giải quyết và gọi 115 giữ nguyên callback.
- Danh sách sự cố dùng thẻ trắng, tên người thân nổi bật và nhãn trạng thái có icon kèm chữ. Trạng thái rỗng chỉ thông báo chưa có sự cố đang mở, không khẳng định người dùng đang an toàn.
- Màn gia đình dùng thẻ thành viên và vai trò rõ ràng; nút mời giữ điều kiện quyền hiện có. Mã mời có thể chọn để sao chép; dòng hết hạn xuống dòng khi thiếu chỗ.
- Lịch sử có bộ lọc cuộn khi chữ lớn, thẻ sự cố thống nhất và số liệu lấy từ kết quả hiện có. Tài khoản gom các thao tác hiện có thành nhóm dễ đọc.
- Hộp thoại phát hiện ngã dùng nền kem, nút hủy xanh và nút gửi SOS có nhãn rõ, cuộn được khi chữ lớn. Câu đếm ngược mô tả đúng việc gửi SOS; thời gian và callback giữ nguyên. Giảm hiệu ứng nhấp nháy khi hệ thống yêu cầu giảm chuyển động.
- Hộp thoại sửa hồ sơ có tiêu đề linh hoạt, nút lưu dạng viên thuốc và phần xóa hồ sơ giải thích bằng tiếng Việt; giữ xác nhận mật khẩu và callback hiện có. Hộp thoại kết nối máy chủ dùng thẻ lựa chọn có dấu chọn, trạng thái chữ/icon và địa chỉ xuống dòng.
- Trường địa chỉ dùng theme chung, gợi ý địa điểm không rút gọn tên. Màn chọn bản đồ có thanh xác nhận riêng trong vùng an toàn, nội dung địa chỉ cuộn khi chữ lớn; giữ nguyên tìm kiếm, đặt ghim, lớp bản đồ, ghi nguồn và dữ liệu trả về.

Chỉ thay đổi lớp trình bày Flutter, theme và tài nguyên hình/font. Không sửa backend, controller, middleware, model, service API, cơ chế gửi SOS, phân quyền, notification outbox hoặc mã native đồng hồ/điện thoại.

UI UX Pro Max được dùng để tra accessibility và Flutter; Taste Skill cung cấp nguyên tắc phân cấp thông tin cho màn hình ứng dụng. Palette, font và bố cục Facare được người dùng chỉ định nên ưu tiên hơn đề xuất ngẫu nhiên của skill. Các repo và công cụ skill vẫn nằm ngoài CareAI.

## Kết quả kiểm tra sau khi người dùng yêu cầu chạy UI

- `flutter devices` chỉ phát hiện Chrome và Edge, không có điện thoại/emulator kết nối.
- `flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5173 --no-pub` biên dịch bản web thành công. Công cụ browser không có surface khả dụng và Computer Use báo lỗi native pipe, nên chưa chụp/điều khiển được cửa sổ web. Chưa nghiệm thu tương tác end-to-end hoặc pixel-perfect trên trình duyệt.
- `flutter test test/widget_test.dart test/facare_ui_test.dart --no-pub --reporter expanded`: 28 bài qua. Kiểm tra bốn màn/component (vai trò, đăng nhập, ghép thiết bị, tổng quan) ở chiều rộng 320/390/600 px, chữ 100%/200%, cùng vùng chạm tối thiểu 48 px và callback của năm nút navbar. Bài ghép thiết bị giữ xác nhận mã PIN trống không hợp lệ.
- Đã dựng và xem ảnh Flutter với Be Vietnam Pro và Material Icons thật tại `CareAI/artifacts/facare-ui-review/`. Dữ liệu Minh Anh/3 hồ sơ/2 sự cố là fixture của kiểm tra component, không đưa vào dữ liệu chạy thật. Ảnh không thể hiện cả màn Home đã đăng nhập hay xác nhận trạng thái mạng/thiết bị.
- Từ ảnh chữ 200%, đã sửa tổng quan: bỏ ảnh trang trí để chữ dùng toàn chiều ngang, thẻ số liệu chuyển một cột. Tách component trình bày `CareAiFamilyOverview`; Home vẫn cung cấp các count/callback cũ.
- `flutter test test/health_corner_test.dart test/incident_history_and_chart_test.dart test/caregiver_emergency_test.dart test/permission_checklist_dialog_test.dart --no-pub --reporter expanded`: 15 bài qua. Cập nhật nhãn mới và thao tác cuộn trong các bài UI; giữ kiểm tra sinh hiệu, địa chỉ, nút gọi bị vô hiệu hóa khi thiếu số, chu kỳ cảnh báo và timeline.
- Analyze lần đầu trên nhóm màn/widget có 41 thông báo mức info, không có error/warning. Analyze sau cùng trên theme, widget chung, tổng quan và hai tệp kiểm tra UI mới/cập nhật không còn issue. Chưa coi phạm vi hẹp này là kết quả analyze sạch toàn ứng dụng.
- `git diff --check` qua; backend, service/model API và mã native không thay đổi.

### Mở rộng kiểm tra chi tiết sự cố và biểu đồ

- Bổ sung 18 trường hợp chi tiết sự cố (Open/Acknowledged/Resolved × 320/390/600 px × chữ 100%/200%) và 6 trường hợp biểu đồ có mẫu đo. Đã phát hiện và sửa tràn ngang ở tiêu đề timeline, thống kê biểu đồ và chú giải khi chữ lớn.
- Hai nút Gọi 115 và tiếp nhận/giải quyết xếp thành một cột khi chữ lớn, giữ nguyên callback. Các dòng sinh hiệu/địa chỉ chuyển nhãn và giá trị thành hai hàng khi cần. Tiêu đề tiếp nhận/giải quyết có thể xuống dòng.
- Thống kê biểu đồ và chú giải tự xuống hàng; badge số mẫu không ép hẹp tiêu đề ở chữ lớn. Font trong CustomPainter dùng Be Vietnam Pro. Không đổi công thức thống kê, mẫu đo, cửa sổ thời gian hoặc ngưỡng vẽ.
- Lần kiểm tra mới nhất: `flutter test test/facare_ui_test.dart test/caregiver_emergency_test.dart test/incident_history_and_chart_test.dart --no-pub --reporter expanded`: 59 bài qua. Log tại `CareAI/artifacts/facare-ui-review/verification.log`; ảnh `incident-*.png` và `heart-rate-*.png` được dựng từ fixture trong bài kiểm tra.
- Các request HTTP trong widget test bị Flutter chặn và trả 400; fixture đầu vào được dùng để kiểm tra hiển thị. Kết quả này không chứng minh backend, tự làm mới dữ liệu, gọi điện hay cảnh báo native hoạt động trên thiết bị.
- Analyze cho chi tiết sự cố, biểu đồ và bộ kiểm tra mới: không có error/warning; còn 6 thông báo info về dấu ngoặc của các nhánh if hiện có.

### Kiểm tra gia đình, mã mời và lịch sử với dữ liệu mẫu

- Bổ sung 12 trường hợp màn gia đình (vai trò chính/phụ × 320/390/600 px × chữ 100%/200%) và 6 trường hợp lịch sử có sự cố. HTTP của các trường hợp này dùng MockClient từ dependency `http` hiện có; không gọi backend hoặc thay service ứng dụng.
- Ảnh cho thấy nhãn bộ lọc chiếm hết chiều ngang ở chữ 200%; đã chuyển nhãn và ô chọn người cao tuổi thành hai hàng. Kiểm tra xác nhận ô chọn vẫn đủ rộng và tên đầy đủ còn xuất hiện ở phần tóm tắt.
- Mã mời 6 ký tự giảm giãn chữ ở cỡ chữ lớn để giữ một dòng; đã kiểm tra cả bố cục dòng và nội dung `Clipboard.setData`. Hai nút sao chép/xong xếp dọc khi chữ lớn, không thay mã hoặc thời hạn mời.
- Kiểm tra hiển thị nút mời/thu hồi theo vai trò trong fixture, cuộn xem thành viên và mở/đóng hộp mời. Đây là kiểm tra giao diện theo dữ liệu đầu vào, không thay thế kiểm thử phân quyền của backend.
- Lần chạy tổng hợp mới nhất: `flutter test test/facare_ui_test.dart test/widget_test.dart test/caregiver_emergency_test.dart test/incident_history_and_chart_test.dart test/health_corner_test.dart test/permission_checklist_dialog_test.dart --no-pub --reporter expanded`: **85 bài qua**. Log tổng hợp tại `CareAI/artifacts/facare-ui-review/verification.log`.
- Ảnh bổ sung: `family-primary-*.png`, `family-secondary-*.png`, `family-invite-*.png`, `history-*.png` trong cùng thư mục artifacts. Tên và thông tin liên hệ là fixture kiểm tra, không phải dữ liệu người dùng.

### Kiểm tra Home hoàn chỉnh và biểu mẫu khi mở bàn phím

- Thêm 6 trường hợp Home thật với MockClient trả danh sách người thân và sự cố, ở 320/390/600 px và chữ 100%/200%. Đã kiểm tra cuộn thẻ người thân, chuyển tab Sự cố/Tài khoản bằng navbar và mở/đóng hộp thêm hồ sơ.
- Từ ảnh chữ lớn, rút gọn tiêu đề thêm hồ sơ thành “Thêm người thân”, tăng chiều rộng hộp trên điện thoại nhỏ, bỏ viền vuông ghi đè theme, làm rõ các ô không bắt buộc và đồng bộ tiêu đề dialog 20/800 Be Vietnam Pro.
- Kiểm tra với inset bàn phím 300 px: cuộn được tới ô địa chỉ, nút Hủy và Tạo hồ sơ vẫn nhận thao tác; không gửi yêu cầu tạo hồ sơ. Đây là mô phỏng bố cục bàn phím trong widget test, chưa phải bàn phím hệ điều hành thật.
- Lần chạy tổng hợp sau cùng của sáu tệp kiểm tra UI nêu trên: **91 bài qua**. Log tổng hợp vẫn ở `CareAI/artifacts/facare-ui-review/verification.log`. Analyze theme và bộ kiểm tra UI không có issue.
- Ảnh Home hoàn chỉnh và tài khoản ở `home-*.png`, `home-account-*.png`; biểu mẫu ở `home-add-profile-*.png`, `home-add-profile-keyboard-*.png`. Đây là widget ứng dụng với dữ liệu mock, không phải phiên đăng nhập backend thật.

### Màn sinh hiệu: tiêu đề, biểu đồ và trạng thái thiếu dữ liệu

- Thêm 12 trường hợp dashboard (có/thiếu số đo × 320/390/600 px × chữ 100%/200%). Fixture có dữ liệu gồm sinh hiệu, trạng thái đồng hồ, bốn chuỗi biểu đồ và phiên ngủ; không dùng vị trí GPS hay dữ liệu người dùng thật.
- Sửa các hàng tràn ở tiêu đề sức khỏe, vị trí, nhận định, ngưỡng ngày/đêm và PIN. Nhóm tiêu đề chuyển thành hai hàng khi chữ lớn; ngưỡng tự xuống hàng. Các giá trị ngưỡng, điều kiện và callback không đổi.
- Tab biểu đồ chuyển thành nút có semantics và vùng chạm tối thiểu 48 px, xếp hai cột trên điện thoại, hiển thị đủ tên. Thống kê biểu đồ xếp một cột khi chữ lớn hoặc vùng nội dung hẹp; chú giải xuống hàng và giữ nguyên ý nghĩa màu/giá trị.
- Tăng vùng dành cho nhãn trục theo text scaler. Khi chữ lớn, phần đồ thị có chiều rộng tối thiểu 520 px và cuộn ngang; đã kiểm tra kéo cuộn khi nội dung rộng hơn viewport. Các điểm đo, phép tính thống kê, cửa sổ thời gian và ngưỡng vẽ giữ nguyên.
- Đồng bộ màu huyết áp/giấc ngủ sang lavender và sage của Facare; tên người cao tuổi trên thẻ hồ sơ không bị rút gọn. Khi chưa có phiên ngủ, badge hiển thị “Chưa có dữ liệu”, tránh nhãn “Bình thường” từ mặc định của model.
- Đã xem ảnh dashboard, từng tab và phần đồ thị, gồm `dashboard-true-*.png`, `dashboard-false-*.png`, `dashboard-chart-*.png`, `dashboard-plot-*.png` trong thư mục artifacts.
- Lần chạy tổng hợp sáu tệp kiểm tra UI sau cùng: **103 bài qua**; log tại `CareAI/artifacts/facare-ui-review/verification.log`. Analyze dashboard và bộ kiểm tra UI không có issue. Chưa thay thế kiểm tra thiết bị hoặc kiểm chứng dữ liệu backend thật.

### SOS và xác nhận phát hiện ngã ở cỡ chữ lớn

- Thêm 6 trường hợp màn SOS và 6 trường hợp hộp xác nhận ngã, ở 320/390/600 px và chữ 100%/200%. Kênh native, quyền, cảm biến và SQLite được mock trong bài UI; HTTP dùng phản hồi offline giả lập. Không gửi SOS, không thu GPS/camera hay mở cơ sở dữ liệu thật.
- Ảnh đã xác nhận lỗi nút hành động nằm ngoài màn hình khi chữ lớn. Màn SOS đưa hành động chính lên trước hồ sơ/GPS/đồng hồ; nút SOS nằm trọn vùng nội dung khi mở màn hình. Bỏ chữ phụ bên trong vòng tròn để không bị mép tròn cắt ở cỡ chữ 200%; hướng dẫn vẫn nằm ngay dưới nút.
- Icon đồng bộ đổi sang nâu trên appbar trắng. Thẻ hồ sơ/GPS dùng toàn chiều rộng, tên không rút gọn và nhãn thiếu vị trí rõ hơn; giữ callback lấy vị trí và xin quyền hiện có. Thanh đồng bộ dưới cùng cho chữ xuống dòng.
- Hộp ngã giữ hai nút “Tôi vẫn ổn” và “Gửi SOS ngay” ở phần cố định; số đếm được đưa lên trước giải thích. Giảm phần trang trí khi chữ lớn. Thời gian đếm, các handler, đóng gói SOS và kênh native giữ nguyên.
- Bài kiểm tra xác nhận số đếm và hai nút xuất hiện ngay, nút “Tôi vẫn ổn” gọi `cancelFallAlarm` với đúng mã sự kiện fixture rồi đóng hộp. Không kích hoạt handler gửi SOS để kiểm tra bố cục.
- Lần chạy tổng hợp sáu tệp UI: **115 bài qua**; sau tinh chỉnh chữ trong nút tròn, chạy lại riêng 12 trường hợp SOS/ngã đều qua. Log ở `verification.log` và `sos-fall-verification.log` trong thư mục artifacts. Ảnh ở `sos-screen-*.png`, `fall-dialog-*.png`.
- Những kết quả này chỉ xác minh lớp hiển thị và callback hủy qua mock; không chứng minh còi, TTS, cảm biến, SOS, quyền hay đồng bộ native hoạt động trên thiết bị thật.

### Cài đặt và đổi tên đồng hồ

- Sửa chữ trắng trên nút đóng nền kem và chữ nâu trên các nút lưu/chuyển vai trò nền nâu. Nút đóng cài đặt có tooltip và vùng bấm tối thiểu 48 px.
- Hộp cài đặt giới hạn chiều rộng 480 px, nội dung cuộn; thông tin đồng hồ và các nút đổi tên/ngắt kết nối xuống dòng, tránh cắt tên hoặc ép chữ. Giữ điều kiện hiển thị và callback cũ.
- Biểu mẫu đổi tên có tiêu đề co giãn, phần nhập liệu cuộn khi bàn phím mở, nhãn rõ và nút lưu dạng viên thuốc. Giữ validation và luồng lưu tên; kiểm tra chỉ mở rồi hủy, không ghi thay đổi.
- Mở rộng sáu trường hợp SOS hiện có để xem/đóng cài đặt, mở biểu mẫu đổi tên và giả lập inset bàn phím 300 px ở chữ 100%/200%. Ảnh bổ sung `sos-settings-*.png`, `sos-rename-keyboard-*.png`; các kênh GPS/native tiếp tục được mock.
- Công cụ browser kiểm tra lại vẫn trả danh sách app/browser rỗng. Các ảnh và kết quả widget không được coi là đối chiếu toàn ứng dụng trên trình duyệt hoặc thiết bị thật.
### Nhận định và báo cáo tuần: kiểm tra bổ sung

- Đồng bộ đầu báo cáo sang nền xanh nhạt, chữ nâu và font Be Vietnam Pro; nhãn nguồn tự xuống dòng. Các ô số liệu xếp một cột khi màn hình hẹp hoặc chữ lớn. Số cảnh báo bằng không hiển thị “0 lần”, không suy diễn thành trạng thái sức khỏe “Ổn định”.
- Thanh tab cho phép cuộn ngang ở cỡ chữ lớn; trạng thái lỗi báo cáo dùng thẻ thông báo và nút thử lại hiện có. Không đổi API, cách phân tích báo cáo hoặc callback tải dữ liệu.
- Thêm sáu trường hợp nhận định/báo cáo ở 320/390/600 px, chữ 100%/200%, với dữ liệu giả lập. Tổng lần chạy sáu tệp UI gần nhất: **121 bài qua**; log tại `CareAI/artifacts/facare-ui-review/verification.log`. Ảnh bổ sung: `health-insights-*.png`, `health-reports-*.png`, `health-report-detail-*.png`.
- Analyze hai tệp liên quan không có lỗi hoặc cảnh báo, còn một thông tin quy ước ngoặc tại `health_corner_screen.dart:111`. Kiểm tra diff xác nhận backend, services, models và native không thay đổi.

### Đối chiếu Chrome và tinh chỉnh cuối

- Chạy trình kiểm tra của Taste Skill bằng Chrome headless tại `http://127.0.0.1:5173`. Đã xem ảnh màn chọn vai trò và đăng nhập ở 320/390/600 px. Chuyển vai trò bằng thao tác chuột thật, không gửi biểu mẫu đăng nhập hoặc gọi API bằng tài khoản thật. Không ghi nhận JavaScript exception trong lượt kiểm tra này (`browser/runtime-errors.json`).
- Báo cáo HTML của skill có lỗi `no-title` vì giao diện Flutter vẽ lên canvas, không xuất `h1` như trang HTML. Không coi phép đo DOM này là kết quả đánh giá typography hoặc bố cục Flutter; đối chiếu bằng ảnh thực tế và widget tests.
- Ở 320 px, hình trang trí làm tiêu đề đăng nhập bị chia bốn dòng. Ẩn hình khi chiều rộng dưới 360 px hoặc chữ lớn để tiêu đề dùng đủ bề ngang. Tăng tương phản icon navbar chưa chọn bằng màu chữ phụ `#7D7168`.
- Sau hai tinh chỉnh này, sáu trường hợp đăng nhập và ba trường hợp navbar đều qua; analyze hai tệp thay đổi không có issue. Các màn cần đăng nhập vẫn được kiểm tra bằng widget với dữ liệu mock, không coi là phiên backend thật. Backend, services, models và mã native không thay đổi.

### Home trong Chrome và rà soát bàn giao

- Đã chạy chính `HomeScreen` bằng entry point chỉ dành cho review tại `CareAI/artifacts/facare-ui-review/browser/home_preview.dart`. Entry point dùng `MockClient` chặn toàn bộ HTTP; không được import bởi `lib/main.dart`, không thêm dependency và không đưa fixture vào ứng dụng thật.
- Đã xem `browser/home-chrome-320.png`, `home-chrome-390.png`, `home-chrome-600.png`. Chỉnh hai thẻ số liệu cùng chiều cao khi nhãn xuống dòng; chữ lớn vẫn chuyển thành một cột. Sáu bài overview và sáu bài Home chạy lại đều qua; analyze `family_overview.dart` không có issue.
- Đã thao tác chuột trên Chrome: nút cộng mở biểu mẫu, Escape đóng biểu mẫu, hai nút navbar chuyển sang Tài khoản và Sự cố. Ảnh `home-add-chrome-390.png`, `home-account-chrome-390.png`, `home-incidents-chrome-390.png`; `home-runtime-errors.json` không ghi nhận JavaScript exception. Không nhấn tạo hồ sơ, gọi điện, gửi SOS hoặc đổi cấu hình thật.
- Font được đăng ký đủ năm trọng lượng 400–800 trong pubspec và theme thật dùng `BeVietnamPro`. Navbar giữ hình học SVG tham chiếu, nút cộng và bốn vị trí icon; nội dung và icon gắn với chức năng CareAI hiện có. Các màu, hình minh họa và bố cục đã đối chiếu bằng ảnh dựng Flutter và Chrome.
- Kiểm tra diff cuối xác nhận backend, services, models và mã native không thay đổi. Hai skill và repo nguồn vẫn ở thư mục người dùng ngoài project. Giữ nguyên các thay đổi và tệp xóa có sẵn của người dùng.
- Giới hạn bàn giao: chưa kiểm tra trên điện thoại/emulator, chưa đăng nhập hoặc xác minh API/backend thật; kết quả UI với dữ liệu giả lập không chứng minh luồng cảm biến, cảnh báo hoặc đồng bộ native.
