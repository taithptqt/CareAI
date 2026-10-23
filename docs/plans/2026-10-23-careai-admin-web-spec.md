# CareAI Admin Web — phạm vi và bản nháp spec MVP

Ngày: 23/10/2026.
Trạng thái: Đã xác nhận 8 phân hệ MVP, hình thức website và kiến trúc Razor Pages. Các đặc tả chi tiết bên dưới là đề xuất để review trước khi triển khai.

## 1. Yêu cầu đã xác nhận

- Xây dựng website quản trị CareAI, ưu tiên sử dụng trên máy tính và hỗ trợ màn hình nhỏ.
- MVP gồm: tổng quan; tài khoản; quản trị viên và phân quyền; hồ sơ người cao tuổi; liên kết chăm sóc; thiết bị; giám sát sự cố; nhật ký quản trị.
- Không đưa bốn phân hệ thông báo, báo cáo vận hành, ticket hỗ trợ và cấu hình hệ thống vào MVP.
- Giai đoạn hiện tại là lập spec và kế hoạch; chưa triển khai tính năng hoặc thay đổi database.

## 2. Hiện trạng được đối chiếu với code

- Backend hiện là modular monolith .NET 9, EF Core; API, Core và Infrastructure tách theo trách nhiệm.
- `Caregiver` có thông tin tài khoản, băm mật khẩu, số lần đăng nhập sai và thời hạn khóa tạm thời.
- `CaregiverRole.Primary/Secondary` là vai trò trên liên kết chăm sóc; không phải quyền quản trị hệ thống.
- JWT người thân đang mang role `Caregiver`. Cần bổ sung cơ chế admin riêng, không nâng quyền từ đăng ký thông thường.
- Người cao tuổi được biểu diễn bằng hồ sơ; không mặc định coi mỗi hồ sơ là một tài khoản đăng nhập.
- Có các mô hình liên kết chăm sóc, thiết bị, incident và timeline để làm nguồn dữ liệu cho trang quản trị.
- Chưa thấy dự án web admin riêng trong repo tại thời điểm khảo sát.
- Chưa xác minh schema hoặc cấu hình triển khai Azure đang chạy; không coi cấu hình cục bộ là bằng chứng trạng thái production.

## 3. Ba cách tích hợp để lựa chọn

### A. Web ASP.NET Core Razor Pages riêng — đề xuất

- Tạo dự án web quản trị riêng trong solution, tận dụng stack .NET hiện có.
- Trình duyệt dùng cookie HttpOnly; ứng dụng web gọi các nghiệp vụ quản trị với danh tính và quyền được xác thực phía server.
- Giữ nghiệp vụ trong backend dùng chung, không sao chép luật nghiệp vụ vào PageModel và không cho trình duyệt kết nối database trực tiếp.
- Phù hợp MVP thiên về bảng, bộ lọc, biểu mẫu và nhật ký; tránh thêm chuỗi công cụ JavaScript khi chưa cần.
- Đánh đổi: tương tác phức tạp cần JavaScript bổ sung; phải quyết định cách triển khai web và API.

### B. React/TypeScript riêng + API quản trị

- Thuận lợi cho giao diện nhiều tương tác và mở rộng frontend độc lập.
- Đánh đổi: thêm stack, dependency, pipeline và thiết kế phiên đăng nhập giữa web/API.

### C. Flutter Web quản trị riêng

- Tận dụng kiến thức Dart/Flutter hiện có.
- Đánh đổi: cần đầu tư thêm cho bảng dữ liệu, bàn phím, URL và trải nghiệm web quản trị.

Người dùng đã chọn phương án A. Không thêm dependency ngoài nhu cầu triển khai đã thống nhất.

## 4. Yêu cầu chức năng theo phân hệ

| Phân hệ | Dữ liệu và thao tác cần có | Điều kiện nghiệm thu chính |
| --- | --- | --- |
| Tổng quan | Tổng tài khoản/hồ sơ/thiết bị, sự cố đang mở, thiết bị mất kết nối; liên kết đến danh sách đã lọc | Số liệu lấy từ dữ liệu thật, có thời điểm cập nhật; lỗi tải không hiển thị thành 0 |
| Tài khoản | Tìm kiếm, lọc, phân trang, chi tiết, cập nhật trường cho phép, tạm ngưng/khôi phục, hỗ trợ reset mật khẩu và thu hồi phiên | Phân biệt khóa do đăng nhập sai với đình chỉ hành chính; xác thực quyền tại server; ghi lý do và audit |
| Quản trị viên và phân quyền | Quản lý nhân sự, vai trò và quyền nghiệp vụ | Tài khoản người thân không truy cập được; không tự cấp quyền; không vô hiệu hóa quản trị cấp cao cuối cùng |
| Hồ sơ người cao tuổi | Danh sách, người thân liên kết, thiết bị, độ mới dữ liệu | Quyền dữ liệu sức khỏe tách riêng; thiếu dữ liệu khác trạng thái bình thường |
| Liên kết chăm sóc | Người chăm sóc chính/phụ, lời mời, hỗ trợ sửa liên kết sai | Không tạo đường truy cập chéo hồ sơ; thay đổi người chăm sóc chính cần kiểm tra ảnh hưởng và lý do |
| Thiết bị | Loại/model, hồ sơ được gán, heartbeat, kết nối, pin khi có; thu hồi và ghép lại có xác minh | Không lộ token/hash; giữ xác thực thiết bị; không mặc định pin hoặc trạng thái đeo khi dữ liệu thiếu |
| Giám sát sự cố | Danh sách theo trạng thái/mức độ/thời gian, chi tiết và timeline | MVP mặc định chỉ đọc; giữ RowVersion, timeline, outbox và bất biến incident; không tự đóng sự cố |
| Nhật ký quản trị | Chủ thể, thao tác, đối tượng, thời gian, lý do, kết quả; lọc và xem chi tiết theo quyền | Không ghi mật khẩu/token hoặc toàn bộ dữ liệu sức khỏe; không có thao tác sửa/xóa qua giao diện admin |

## 5. Quyền dự kiến — cần chốt

- Chủ hệ thống: quản lý nhân sự và quyền; vẫn phải có quyền cụ thể khi truy cập dữ liệu nhạy cảm.
- Quản trị vận hành: quản lý tài khoản, hồ sơ, liên kết và thiết bị trong phạm vi được cấp.
- Hỗ trợ: xem thông tin tối thiểu phục vụ hỗ trợ; không mặc nhiên xem số đo sức khỏe.
- Người xem nhật ký: quyền đọc audit riêng; không được chỉnh sửa nghiệp vụ chỉ vì có quyền xem log.
- Các thay đổi nhạy cảm phải kiểm tra quyền phía server, có lý do, xử lý xung đột và lưu audit cùng giao dịch khi phù hợp.
- Tạm ngưng tài khoản không tự động xóa liên kết hoặc ngắt luồng cảnh báo; phải chốt phương án bảo đảm người chăm sóc thay thế.

## 6. Hướng giao diện dự kiến

- Nhận diện CareAI: Be Vietnam Pro đóng gói sẵn, nền kem nhạt, bề mặt trắng, chữ nâu; xanh rêu và đỏ dùng cho ý nghĩa trạng thái.
- Sidebar có tên tám phân hệ; header gồm tiêu đề trang, phạm vi môi trường và tài khoản nhân sự.
- Trang danh sách ưu tiên tìm kiếm, bộ lọc, bảng và thao tác theo hàng; không dùng hero trang trí chiếm diện tích làm việc.
- Màn hình tổng quan trả lời: “Có vấn đề vận hành nào cần chú ý ngay?”; số liệu dẫn tới đối tượng và bằng chứng tương ứng.
- Mọi màn hình có trạng thái tải, rỗng, lỗi, thiếu quyền và dữ liệu cũ. Dữ liệu mẫu chỉ có trong chế độ demo được ghi rõ.
- Hỗ trợ bàn phím, focus rõ, nhãn biểu mẫu, trạng thái không chỉ thể hiện bằng màu; màn hình nhỏ giữ được thao tác chính và đọc chi tiết.
- Đây là định hướng, chưa phải bố cục hoặc mockup được duyệt.

## 7. Yêu cầu phi chức năng dự kiến

- Giả định quy mô ban đầu: 10.000 tài khoản, 20 quản trị viên đồng thời; cần xác nhận trước khi dùng làm tiêu chí tải.
- Mục tiêu đề xuất: P95 API danh sách dưới 2 giây với dữ liệu và tải đã thống nhất; phân trang phía server, không tải toàn bộ hồ sơ về trình duyệt.
- Admin ngừng hoạt động không được làm gián đoạn telemetry, SOS, tiếp nhận hoặc ứng dụng người thân.
- Phiên quản trị có thời hạn, thu hồi được và chống CSRF cho thao tác dùng cookie; xác thực mạnh cho tài khoản quản trị cần chốt trong thiết kế bảo mật.
- Giữ database theo cấu hình môi trường hiện hữu; không tự chuyển sang database local hoặc chạy migration production.
- Nhóm phát triển CareAI bảo trì backend và web; đầu mối vận hành và yêu cầu thời gian khôi phục chưa được xác nhận.
- Chỉ chạy build/test/analyze/kiểm thử thiết bị khi người dùng yêu cầu theo AGENTS.md.

## 8. Các bước tiếp theo sau khi chốt kiến trúc

1. Chốt ma trận quyền, vòng đời tài khoản, danh tính admin và chính sách phiên.
2. Đặc tả tám màn hình: trường dữ liệu, bộ lọc, thao tác, lỗi và tiêu chí nghiệm thu.
3. Chốt API contract, schema bổ sung, audit, concurrency và khả năng thu hồi phiên.
4. Thiết kế giao diện tổng quan và tài khoản trước; duyệt hướng rồi áp dụng cho sáu phân hệ còn lại.
5. Lập implementation plan theo file/module, migration, kiểm thử và thứ tự bàn giao.
6. Triển khai lần lượt, không đưa thao tác quản trị chưa được backend bảo vệ lên giao diện production.

## 9. Decision log

| Quyết định | Trạng thái | Lý do |
| --- | --- | --- |
| Tám phân hệ MVP | Người dùng đã chốt | Tập trung tài khoản và vận hành cốt lõi |
| Website quản trị | Người dùng đã chốt | Quản trị qua trình duyệt |
| Giữ kiến trúc backend hiện hữu | Ràng buộc AGENTS.md | Bảo toàn nghiệp vụ và phân lớp |
| Web ASP.NET Core Razor Pages riêng | Người dùng đã chốt | Cùng stack .NET, phù hợp bảng và biểu mẫu; đã cân nhắc React và Flutter Web |
| Giám sát incident mặc định chỉ đọc | Đề xuất | Chưa có yêu cầu thay đội chăm sóc tiếp nhận sự cố |

## 10. Kiến trúc kỹ thuật đề xuất

```text
Trình duyệt
  -> CareAI.AdminWeb (Razor Pages, cookie quản trị, antiforgery)
  -> CareAI.API (/api/v1/admin/*, policy admin)
  -> Core (DTO, entity, contract) + Infrastructure (nghiệp vụ, EF Core)
  -> Database theo cấu hình môi trường hiện hữu
```

- `CareAI/src/CareAI.AdminWeb/`: dự án `net9.0`, Razor Pages và static assets. Chỉ tham chiếu Core; không truy cập EF/database nghiệp vụ trực tiếp.
- `Pages/`: Login, Overview, Accounts, Staff, Elders, CareLinks, Devices, Incidents, Audit; trang chi tiết dùng ID trong URL.
- `Services/AdminApiClient.cs`: gọi HTTP phía server, chuyển lỗi thành thông báo UI có correlation ID; không chuyển nguyên lỗi nội bộ cho trình duyệt.
- `CareAI/src/CareAI.API/Controllers/Admin/`: controller mỏng, policy theo quyền và scheme admin riêng.
- `CareAI/src/CareAI.Core/DTOs/Admin/`, `Entities/Admin/`, `Interfaces/Admin/`: contract và kiểu dữ liệu quản trị.
- `CareAI/src/CareAI.Infrastructure/Admin/`: truy vấn, command và audit; bổ sung mapping/migration trong Infrastructure theo quy ước hiện hữu.
- Frontend dùng HTML/CSS, JavaScript tối thiểu cho bộ lọc, dialog và cập nhật trạng thái; không thêm React hoặc thư viện biểu đồ mặc định.
- Cấu hình API qua môi trường; không gán cứng Azure/local. Chưa tạo tài nguyên, domain hoặc deployment Azure mới.
- Website được triển khai độc lập, không khởi chạy worker telemetry/cảnh báo. Không thêm dịch vụ quản trị thành dependency bắt buộc của luồng SOS.

## 11. Danh tính, phiên và ma trận quyền đề xuất

### Danh tính và phiên

- `AdminUser` là tài khoản nhân sự riêng; không sử dụng role chăm sóc làm quyền quản trị.
- API đăng nhập admin cấp token chỉ cho AdminWeb qua HTTPS. Token chỉ lưu phía server; không đặt trong URL, HTML, localStorage hoặc log.
- Cookie web `Secure`, `HttpOnly`, `SameSite=Lax`; cookie chỉ chứa mã tham chiếu phiên, không chứa bearer token hoặc dữ liệu sức khỏe.
- Session store phía server phải hỗ trợ chia sẻ giữa instance và thu hồi; không dùng bộ nhớ tiến trình làm store production. Chọn store triển khai cụ thể trước khi viết cấu hình hosting.
- JWT admin có issuer/audience và authentication scheme riêng. API kiểm tra admin còn hoạt động, phiên chưa thu hồi/hết hạn và phiên bản quyền hiện hành ở mỗi request quản trị.
- Đề xuất hết phiên sau 30 phút không hoạt động, tối đa 8 giờ; thao tác cấp quyền hoặc thu hồi thiết bị yêu cầu xác thực lại gần đây.
- Tài khoản chủ hệ thống đầu tiên được bootstrap một lần ngoài public registration; không seed mật khẩu mặc định. Khôi phục tài khoản và MFA phải có luồng vận hành được review trước khi mở public.
- Đề xuất yêu cầu MFA cho admin production; lựa chọn TOTP hoặc nhà cung cấp danh tính là quyết định triển khai còn mở, không giả định hệ thống đã có email/SMS.
- POST web kiểm tra antiforgery; GET không thay đổi dữ liệu; đăng nhập giới hạn tốc độ và dùng lỗi không tiết lộ tài khoản tồn tại.

### Ma trận quyền mặc định

| Nhóm quyền | Chủ hệ thống | Vận hành | Hỗ trợ | Kiểm tra nhật ký |
| --- | --- | --- | --- | --- |
| Tổng quan tổng hợp | Có | Có | Có, giới hạn | Không mặc định |
| Tài khoản: đọc thông tin tối thiểu | Có | Có | Có | Không |
| Tài khoản: sửa, đình chỉ, thu hồi phiên | Có | Có | Không | Không |
| Nhân sự và cấp quyền | Có | Không | Không | Không |
| Hồ sơ, liên kết, thiết bị: đọc metadata | Có | Có | Có, giới hạn | Không |
| Sửa liên kết / thu hồi thiết bị | Có | Có, xác thực lại | Không | Không |
| Incident: đọc metadata | Có | Có | Không mặc định | Không |
| Số đo, vị trí, ảnh incident | Cần cấp quyền riêng | Cần cấp quyền riêng | Không | Không |
| Audit đã lọc dữ liệu nhạy cảm | Có | Theo quyền riêng | Không | Có |

Mỗi quyền là policy độc lập. Ẩn nút trên UI không thay thế kiểm tra tại API. Không cho cấp quyền vượt quyền được phép ủy quyền; thay đổi quyền làm mất hiệu lực quyền cũ ngay lần gọi tiếp theo.

## 12. Đặc tả tám phân hệ

### 12.1 Tổng quan — `/Overview`

- Câu hỏi chính: vấn đề vận hành nào cần xem trước?
- Dải số liệu gọn: tài khoản, hồ sơ đang hoạt động, thiết bị hoạt động, incident Open/Acknowledged; mỗi số dẫn tới bộ lọc tương ứng.
- Danh sách ưu tiên: sự cố đang mở và thời gian đã trôi qua; thiết bị mất heartbeat kèm hồ sơ liên kết; hoạt động quản trị gần nhất nếu có quyền.
- Hiển thị `asOfUtc` và phạm vi thời gian; không dùng số mẫu, phần trăm tăng trưởng hoặc đồ thị khi không có dữ liệu nguồn.
- Chỉ refresh phần đọc khi tab hiện hữu, chu kỳ đề xuất 30 giây; không ghi đè bộ lọc hoặc focus của người dùng. Đây không phải màn hình trực cấp cứu được cam kết realtime.

### 12.2 Tài khoản — `/Accounts`, `/Accounts/{id}`

- Cột: họ tên, email/SĐT theo quyền, ngày tạo, trạng thái hành chính, trạng thái khóa đăng nhập, số liên kết đang hoạt động.
- Lọc theo từ khóa, ngày tạo, trạng thái hành chính, đang khóa đăng nhập; phân trang mặc định 25, tối đa 100.
- Chi tiết: thông tin chung, liên kết chăm sóc, phiên đang hoạt động nếu hệ thống bắt đầu ghi nhận, audit theo quyền. Không suy đoán “đăng nhập gần nhất” từ CreatedAt.
- Sửa tên và SĐT có kiểm tra định dạng; thay email cần xác minh, chưa mở sửa trực tiếp trong MVP.
- Tạm ngưng/khôi phục: lý do bắt buộc, preview hồ sơ bị ảnh hưởng, concurrency token và audit; đình chỉ thu hồi quyền đăng nhập/API nhưng không tự xóa push token hay liên kết.
- Chặn đình chỉ nếu sẽ để hồ sơ không còn người chăm sóc hoạt động phù hợp; UI dẫn sang xử lý thay thế. Phải xác minh luồng cảnh báo vẫn có người nhận trước khi hoàn tất.
- Đặt lại mật khẩu bằng token một lần theo cơ chế được rà soát; không trả token cho admin hoặc tự nhận là đã gửi email khi chưa có dịch vụ gửi thật.
- Thu hồi phiên caregiver cần mở rộng kiểm tra JWT hiện hữu; token cũ không có phiên bản mới được xử lý bằng kế hoạch cutover rõ ràng, không tuyên bố đã thu hồi nếu API vẫn nhận token cũ.

### 12.3 Nhân sự và quyền — `/Staff`, `/Staff/{id}`

- Danh sách tên, email, vai trò, trạng thái, trạng thái MFA và lần đăng nhập gần nhất khi có dữ liệu.
- Tạo lời mời có hạn sử dụng; nếu chưa có kênh gửi thật thì hiển thị trạng thái chưa gửi, không dùng mật khẩu dùng chung.
- Chỉnh vai trò, đình chỉ, thu hồi phiên có xác thực lại và audit.
- Không cho xóa/đình chỉ/hạ quyền chủ hệ thống hoạt động cuối cùng, kể cả hai request chạy đồng thời; kiểm tra trong giao dịch có bảo vệ concurrency.
- Không hỗ trợ impersonation người dùng trong MVP.

### 12.4 Hồ sơ người cao tuổi — `/Elders`, `/Elders/{id}`

- Danh sách: tên, thông tin nhận diện tối thiểu, người chăm sóc chính, số người thân, thiết bị và độ mới heartbeat.
- Chi tiết: thông tin hồ sơ, liên kết, thiết bị, danh sách incident theo quyền; dữ liệu sức khỏe/vị trí là khu vực kiểm soát riêng và ghi nhận truy cập.
- MVP không sửa ngưỡng lâm sàng, số đo, timeline, ảnh hay báo cáo lịch sử.
- Hồ sơ đã soft-delete không tự hiện lại qua query bỏ filter; việc phục hồi nằm ngoài MVP.

### 12.5 Liên kết chăm sóc — `/CareLinks`, `/CareLinks/{elderId}`

- “Gia đình” trong MVP là nhóm liên kết quanh một ElderProfile; chưa thêm entity Family khi mô hình hiện tại chưa cần.
- Hiển thị người thân, Primary/Secondary, hiệu lực liên kết; lời mời hiện có chỉ hiển thị metadata và hạn sử dụng, không lộ mã/hash.
- Chuyển người chăm sóc chính hoặc vô hiệu liên kết sai cần lý do hỗ trợ/xác minh và preview ảnh hưởng.
- Không tạo liên kết đến tài khoản đình chỉ; không gỡ người chăm sóc chính đang là người tiếp nhận incident Open/Acknowledged trong MVP.
- Thao tác chuyển chính phải nguyên tử và giữ các luật liên kết đã có; không suy diễn rằng mọi hồ sơ cũ đều có một Primary hợp lệ.

### 12.6 Thiết bị — `/Devices`, `/Devices/{id}`

- Cột: model/loại, ID rút gọn có nút sao chép, hồ sơ, IsActive, heartbeat, trạng thái kết nối và pin có đơn vị.
- Phân biệt online/offline theo cùng logic staleness backend; `unknown` khác offline, pin null khác 0%.
- Thu hồi thiết bị yêu cầu xác thực lại, lý do, cảnh báo ảnh hưởng; chặn khi liên quan incident chưa giải quyết, không tạo tự động thiết bị thay thế.
- Ghép lại là quy trình pairing được xác minh, không sửa ElderProfileId trực tiếp hoặc tái sử dụng token cũ.
- Không đưa DeviceTokenHash, token thô, pairing PIN/hash hoặc khóa cấu hình vào response admin.

### 12.7 Sự cố — `/Incidents`, `/Incidents/{id}`

- Lọc theo Open/Acknowledged/Resolved, mức độ, loại, hồ sơ, thiết bị và khoảng thời gian.
- Chi tiết có thời điểm phát sinh/tiếp nhận/giải quyết và timeline; snapshot tại lúc phát sinh phân biệt với dữ liệu cập nhật về sau.
- Chỉ xem; không có nút tiếp nhận, giải quyết, sửa nội dung hoặc xóa incident trên admin MVP.
- Vị trí, ảnh và số đo chỉ trả về sau kiểm tra quyền riêng. Ảnh yêu cầu endpoint được xác thực; không phát URL công khai dài hạn.
- Hiển thị trạng thái thông báo đúng nghĩa nguồn dữ liệu; SENT không được ghi thành “đã đến điện thoại”.

### 12.8 Nhật ký — `/Audit`, `/Audit/{id}`

- Cột: thời gian, nhân sự, action, loại/ID đối tượng, kết quả và correlation ID.
- Lọc actor, action, đối tượng, thời gian và kết quả; mặc định 7 ngày gần nhất, server giới hạn khoảng truy vấn.
- Chi tiết gồm lý do và thay đổi các trường được cho phép; che email/SĐT theo quyền, không lưu nguyên request/response.
- Ghi cả thay đổi thành công, thất bại nghiệp vụ và truy cập dữ liệu nhạy cảm. Denied auth đi qua security logging riêng nếu không đủ ngữ cảnh ghi audit.
- Audit nghiệp vụ được ghi cùng transaction thay đổi. Nếu không ghi được audit thì không xác nhận mutation đã thành công.
- Không có export hàng loạt hoặc sửa/xóa audit trong MVP. Chính sách lưu trữ, quyền DBA và bảo vệ log ở tầng hạ tầng cần được chốt trước production.

## 13. API contract dự kiến

Prefix `/api/v1/admin`; tất cả endpoint nghiệp vụ cần scheme admin và policy tương ứng. Các route auth anonymous được giới hạn rõ ràng, không vô tình mở toàn controller.

| Nhóm | Endpoint chính |
| --- | --- |
| Auth | `POST /auth/login`, `/auth/mfa/verify`, `/auth/logout`; `GET /auth/me` |
| Overview | `GET /overview` |
| Accounts | `GET /accounts`, `/accounts/{id}`; `PATCH /accounts/{id}/profile`; `POST /accounts/{id}/suspend`, `/restore`, `/unlock`, `/revoke-sessions`, `/password-reset` |
| Staff | `GET /staff`, `/staff/{id}`; `POST /staff/invitations`; `PATCH /staff/{id}/role`; `POST /staff/{id}/suspend`, `/restore`, `/revoke-sessions` |
| Elders | `GET /elders`, `/elders/{id}`; endpoint đọc dữ liệu nhạy cảm tách riêng và audit truy cập |
| Care links | `GET /care-links`, `/care-links/{elderId}`; `POST /care-links/{elderId}/transfer-primary`, `/deactivate` |
| Devices | `GET /devices`, `/devices/{id}`; `POST /devices/{id}/revoke`, `/pairing-request` |
| Incidents | `GET /incidents`, `/incidents/{id}`, `/incidents/{id}/timeline`; dữ liệu nhạy cảm tách policy |
| Audit | `GET /audit`, `/audit/{id}` |

- List response: `{ items, totalCount, page, pageSize, asOfUtc }`; bộ lọc và sort dùng allowlist, không nhận tên thuộc tính SQL tùy ý.
- Tìm kiếm có giới hạn độ dài; ngày dùng ISO 8601 UTC; UI hiển thị Asia/Saigon và ghi rõ timezone. Khoảng ngày dùng đầu bao gồm/cuối không bao gồm.
- Mutation gồm `reason`, `expectedVersion` và request ID chống lặp; unique command record theo actor/action/request ID trả lại kết quả cũ khi retry cùng payload. Payload khác cùng ID trả 409.
- Response chỉ chứa DTO allowlist, không serialize entity EF trực tiếp.
- Lỗi chuẩn ProblemDetails: validation 400, chưa xác thực 401, không có quyền 403, không tìm thấy 404, xung đột phiên bản/luật nghiệp vụ 409, rate limit 429, lỗi phụ thuộc 503. Có `code`, `traceId`, không có stack trace hay secret.
- Trang thay đổi không tự retry mutation thất bại mà không có request ID; trả 409 yêu cầu tải lại và review thay đổi.

## 14. Thay đổi dữ liệu dự kiến

| Thành phần | Trách nhiệm / trường bổ sung |
| --- | --- |
| AdminUser | Tên, normalized email unique, trạng thái, password hash nếu dùng local identity, security version, lockout, MFA metadata được bảo vệ, RowVersion |
| AdminRole / AdminUserRole | Vai trò allowlist; policy mapping tại server. MVP không mở trình tạo permission tùy ý |
| AdminSession | AdminId, hạn tuyệt đối/idle, revokedAt, security version; không lưu token thô trong cột plaintext |
| AdminWebSessionStore | Lưu ticket/token phía server có bảo vệ và TTL, hỗ trợ nhiều instance; tách trách nhiệm khỏi session revocation nghiệp vụ |
| AdminAuditEvent | Actor, action, target, thời điểm UTC, reason, result, traceId, thay đổi allowlist, không chứa secret |
| AdminCommandRecord | Idempotency key, actor/action, payload fingerprint, kết quả tối thiểu và TTL; không lưu payload nhạy cảm thô |
| Caregiver | Trạng thái đình chỉ và lý do, thời điểm/người thực hiện; security version để vô hiệu JWT; RowVersion cho thao tác quản trị |
| ElderCaregiver / DeviceRegistration | Concurrency token cho command quản trị nếu chưa có; trường xác minh/thu hồi chỉ thêm khi luồng cụ thể cần |

- Không tạo entity Family trùng mô hình liên kết hiện hữu. Không biến ElderProfile thành user đăng nhập.
- Migration bổ sung theo hướng tương thích; caregiver hiện hữu mặc định Active. Không reset mật khẩu, xóa token hoặc sửa số đo khi migrate.
- Thêm index cho tìm kiếm/lọc thực tế sau khi kiểm tra execution plan; không đặt mục tiêu hiệu năng chỉ dựa trên tên index.
- Audit không cascade-delete theo tài khoản/đối tượng. Mọi request và log phải tránh dữ liệu sức khỏe thật không cần thiết.
- Rà soát JWT caregiver, device middleware và đường refresh/auth hiện có trước khi chốt migration thu hồi phiên. Không áp dụng thay đổi auth production cùng migration mà không có kế hoạch cutover.

## 15. Giao diện và tiêu chí nghiệm thu chung

- Khung sidebar desktop khoảng 240px; nội dung theo viewport, không kéo bảng toàn trang ra khỏi màn hình. Mobile chuyển sidebar thành drawer, bảng có vùng cuộn riêng hoặc chế độ danh sách giữ được trường và thao tác chính.
- Mỗi trang có tiêu đề, mô tả công việc ngắn, bộ lọc, tổng số kết quả; trạng thái bộ lọc giữ trong URL để reload/back không mất ngữ cảnh.
- Màu nền `#FAF7F2`, chữ `#231811`, hành động chính `#4A3020`, viền `#E4DACD`; font Be Vietnam Pro theo asset và license hiện hữu. Mọi cặp màu thực tế phải được đo tương phản khi dựng UI.
- Không dùng minh họa gia đình cỡ lớn, animation trang trí, số giả hay nhiều biểu đồ trên màn hình vận hành.
- Dialog nhạy cảm ghi đối tượng, thay đổi, lý do và ảnh hưởng; focus trap, Escape hủy và trả focus về nút mở. Không đóng dialog khi lỗi validation.
- Preview và API đều kiểm tra lại quyền/ảnh hưởng lúc commit; disable nút không được xem là chống request trùng.
- Dữ liệu tải lỗi giữ thông báo rõ; giá trị 0 chỉ xuất hiện khi API trả 0. Không suy luận thiết bị online đồng nghĩa người cao tuổi an toàn.
- Dự kiến review ở 1440, 768, 390px và zoom 200%; đó là tiêu chí cho lần kiểm tra được người dùng yêu cầu, chưa phải kết quả đã chạy.

## 16. Thứ tự bàn giao và kiểm tra dự kiến

1. Nền tảng danh tính admin, policy, session, audit và cơ chế bootstrap; kiểm tra chặn caregiver truy cập admin và chặn JWT admin truy cập nhầm tài nguyên caregiver.
2. Web shell, login và danh sách tài khoản chỉ đọc; kiểm tra URL, pagination, masking và lỗi API.
3. Nhân sự/quyền và thao tác tài khoản; kiểm tra quản trị cuối cùng, đình chỉ, thu hồi JWT cũ, CSRF và concurrency.
4. Hồ sơ/liên kết/thiết bị; kiểm tra chuyển chăm sóc nguyên tử, giới hạn thu hồi, không lộ token và không phá quyền caregiver theo elder.
5. Sự cố chỉ đọc, overview và audit hoàn chỉnh; kiểm tra snapshot/timeline không đổi và số tổng quan khớp nguồn dữ liệu.
6. Review tám màn hình cùng luồng bàn phím/mobile; chỉ triển khai Azure sau khi cấu hình danh tính, MFA, session store, rollback và môi trường đã review.

Không chạy build/test/analyze trong bước viết spec này. Chưa tạo tài khoản quản trị thật, chạy migration, gửi email hoặc thay cấu hình Azure.

## 17. Các điểm cần chốt trước production

- MFA/identity provider và quy trình khôi phục nhân sự; dịch vụ gửi lời mời/reset mật khẩu thật.
- Store phiên phía server và quản lý Data Protection keys trên nhiều instance.
- Domain/hosting AdminWeb và cách xác thực đường server-to-server; không mặc định repo đã có Azure credentials.
- Người chịu trách nhiệm vận hành, retention audit, yêu cầu khôi phục và tải thực tế.
- Chính sách chuyển tiếp cảnh báo khi đình chỉ người chăm sóc chính; không triển khai command đình chỉ nếu chưa bảo đảm đường nhận cảnh báo.

## 18. Bổ sung đã được yêu cầu: feedback khách hàng

Theo yêu cầu bổ sung ngày 23/10/2026, admin có thêm mục **Phản hồi khách hàng**,
đồng thời app người thân có mục **Góp ý & phản hồi** trong tab Tài khoản.
Như vậy điều hướng admin mở rộng từ tám lên chín phân hệ. Đây là hộp thư góp ý,
chưa mở quy trình ticket hỗ trợ hoặc phản hồi hai chiều.

- Người thân gửi loại góp ý, tiêu đề, nội dung và chỉ xem lịch sử của chính mình.
- Admin có quyền feedback riêng để đọc, tìm kiếm, lọc loại và phân trang.
- Không nhận thông tin định danh người gửi từ body; lấy từ JWT caregiver.
- Có validation, chống trùng khi retry và giới hạn gửi; không dùng feedback thay SOS.
- Chi tiết contract, script schema và trạng thái triển khai nằm tại
  [2026-10-23-careai-feedback.md](2026-10-23-careai-feedback.md).
- Đã viết mã; chưa chạy build/test/analyze, kiểm thử thiết bị hoặc áp dụng schema.

