# CareAI và đánh giá từ phản hồi người dùng giả lập

Ngày lập: 15/10/2026. Đối tượng sử dụng tài liệu: nhóm sản phẩm, thiết kế, phát triển và marketing CareAI.

**Kết luận đánh giá:** CareAI đã có nền tảng nghiệp vụ đáng để tiếp tục hoàn thiện: người cao tuổi báo cần giúp, người thân xem tình huống, tiếp nhận và ghi lại cách xử lý. Ưu tiên cải tiến là giúp gia đình hiểu đúng trạng thái SOS, nhận ra dữ liệu thiếu hoặc đã cũ, hoàn thành cài đặt dễ hơn và thao tác rõ ràng lúc có việc khẩn. Chưa có cơ sở chấm điểm hài lòng hoặc khẳng định phần mềm dễ dùng trước khi quan sát người sử dụng thật.

**Toàn bộ nhân vật, lời nói và tình huống phản hồi trong phần 3 là giả lập phục vụ thiết kế.** Không có người tham gia khảo sát thật; không dùng các lời nói này làm testimonial, kết quả phỏng vấn, điểm sao hoặc bằng chứng nhu cầu thị trường.

## 1 Phương pháp và phạm vi đánh giá

Đánh giá dựa trên proposal `CareAI_Proposal_EXE101_Bug_Buck_V2.docx`, README GitHub, README trong dự án và đọc luồng mã nguồn Flutter, Android, Wear OS, watchOS và backend liên quan. Cơ sở nghiệp vụ là: người con thường cài đặt và chi trả; người cao tuổi cần thao tác ít, dễ đọc và có quyền quyết định về dữ liệu của mình.

Mã nguồn local được đọc tại `225bb60212e64f84bc39299b7a0e76c7897abe87`. Lần fetch nghiên cứu thấy GitHub `main` ở `4c85f0b4dfd43f7e19f23e6a8b51d6c50df4e4a7`; README giống local. Đã đọc diff mới về đồng hồ, chưa pull cập nhật mã nguồn. Các số dòng trong phụ lục tham chiếu bản local.

Tách ba mức nhận định:

- **Quan sát từ code:** có nhánh xử lý, nội dung chữ hoặc vị trí thành phần được đọc trực tiếp.
- **Giả thuyết trải nghiệm:** dự đoán người dùng có thể hiểu sai, khó tìm hoặc thao tác nhầm; cần kiểm chứng bằng sử dụng thực tế.
- **Đề xuất:** thay đổi muốn thực hiện và tiêu chí để đánh giá. Chưa có thay đổi chức năng nào được triển khai trong công việc này.

Không chạy build, test, analyze hoặc kiểm thử thiết bị. Vì vậy, đánh giá không xác nhận chất lượng âm thanh, độ trễ mạng, mức tiêu thụ pin, độ chính xác phát hiện ngã hoặc khả năng đọc giao diện trên màn hình thật.

## 2 Đánh giá phần mềm hiện tại

### 2.1 Những điểm nên giữ và phát triển

**Quy trình sự cố có ý nghĩa với gia đình.** Code có trạng thái mở, tiếp nhận, giải quyết, người tiếp nhận và timeline. Đây là nền tảng để người con biết việc đã có ai xử lý thay vì chỉ nhận một thông báo rồi tự phối hợp ngoài ứng dụng. Cần giữ lịch sử và cơ chế xử lý khi hai người thao tác đồng thời. [C4]

**Có sẵn nhiều thành phần phục vụ người cao tuổi.** Nút SOS, đếm ngược khi ngã, nút xác nhận mình ổn, âm báo và lời đọc khi phát hiện ngã đã có. Hướng cải tiến là làm rõ phản hồi và khả năng nhìn/nghe, không mô tả các chức năng này như chưa tồn tại. [C1], [C5], [C8]

**Có cơ chế hỗ trợ mạng chập chờn.** Luồng điện thoại có hàng đợi lưu gói gửi lại; native và đồng hồ cũng có các đường truyền/bộ đệm. Đây là nền tảng hữu ích, nhưng lưu tại máy chưa có nghĩa người thân đã nhận. Giao diện phải thể hiện chính xác bước đang đạt được. [C1], [C2]

**Có quản trị gia đình và báo cáo tổng hợp.** Mời thành viên, kiểm soát quyền, báo cáo tuần và nhận định dữ liệu đã có triển khai. Nên khai thác để làm thông tin đơn giản, có ngữ cảnh và gắn với việc hỏi thăm; chưa cần mở rộng thêm nhiều chỉ số trên màn đầu. [C9], [C10]

### 2.2 Những vấn đề có căn cứ và giả thuyết cần kiểm chứng

| Vấn đề | Điều quan sát được | Ảnh hưởng dự kiến |
| --- | --- | --- |
| SOS báo thành công quá mức | Sau nhánh bắt lỗi gửi HTTP, màn SOS vẫn hiện câu “gửi đến người thân” | Người già có thể chờ trợ giúp trong khi gói còn nằm ở máy; lỗi nội dung đã thấy trong code, hành vi hiểu sai chưa được quan sát thực tế |
| Thành công gửi bị đồng nhất với tiếp nhận | Backend `SENT` nghĩa là FCM chấp nhận; đồng hồ có nhãn đã gửi theo trạng thái cục bộ | Gia đình có thể hiểu nhầm người con đã biết hoặc đang đến |
| SOS tay còn chờ lấy vị trí | Sau xác nhận, code chờ `getCurrentLocation()` trước khi ghi hàng đợi và thử gửi SOS | Có thể làm chậm tín hiệu đầu khi định vị chưa sẵn sàng; chưa đo độ trễ thực tế |
| Tác vụ khẩn nằm sau nhiều thông tin | Màn chi tiết dùng danh sách cuộn, các nút gọi/tiếp nhận ở gần cuối | Có thể tăng thời gian tìm hành động lúc hoảng; cần thử trên màn hình thật |
| Một số từ dành cho chuyên môn | Có “Acknowledge”, “ghi chú lâm sàng” trong tác vụ gia đình | Người con có thể không hiểu cần viết gì để hoàn tất |
| Dữ liệu giấc ngủ tạo cảm giác chính xác quá mức | Ngủ sâu tính 28% tổng thời gian, số lần thức gán 1, có nhãn “Đạt chuẩn y tế” | Có thể khiến gia đình tin đây là đo lường giấc ngủ chuyên sâu đã được xác nhận |
| Cài đặt còn lộ khái niệm kỹ thuật | Có cấu hình server; ghép đôi qua PIN và quyền thiết bị | Người dùng phổ thông có thể cần nhóm hỗ trợ; chưa biết thời gian cài đặt thực tế |
| Chữ phụ và mật độ thông tin | Một số nhãn dùng cỡ 10–12 trong dashboard, đồng hồ có nhãn nhỏ | Nguy cơ khó đọc; không kết luận vi phạm tương phản hoặc tràn chữ khi chưa đo/render |
| Lời đọc chưa bao phủ toàn luồng | Có hàm đọc tiếp nhận nhưng chưa tìm thấy nơi gọi trong Dart; câu có sẵn nói “đang trên đường đến” | Cần nối luồng và sửa nội dung đúng trạng thái, tránh hứa hành động người thân chưa xác nhận |

Nguồn cho các quan sát: [C1]–[C8], [C11]. Các điểm về vị trí thao tác, chữ nhỏ và độ khó cài đặt là giả thuyết UX, chưa phải kết quả kiểm thử khả dụng.

### 2.3 Đánh giá theo tiêu chí sản phẩm

| Tiêu chí | Nhận định từ tài liệu và code | Điều cần chứng minh tiếp |
| --- | --- | --- |
| Phù hợp bài toán gia đình | Có liên kết người cao tuổi và nhiều người thân, có luồng phối hợp sự cố | Gia đình có dùng luồng này thay cho hoặc cùng nhóm chat không |
| Dễ dùng với người cao tuổi | Có SOS và xác nhận ổn; cần xem lại chữ, phản hồi và thao tác phụ | Người ít quen công nghệ có tự làm được tác vụ chính không |
| Dễ dùng với con cái | Có dashboard, lịch sử và tiếp nhận; hành động khẩn và từ ngữ còn có thể đơn giản hóa | Mở cảnh báo có biết ngay cha/mẹ nào, chuyện gì và làm gì tiếp không |
| Trung thực về dữ liệu và trạng thái | Có phân biệt dữ liệu demo và kiểm soát server, nhưng còn câu thành công và nội dung ngủ cần sửa | Không ai hiểu dữ liệu thiếu là sức khỏe ổn hoặc hiểu chờ mạng là đã nhận |
| Thông báo và khả năng vận hành | Có tích hợp FCM, hàng đợi và nhắc lại | Kết quả đầu cuối theo từng điện thoại, trạng thái nền, mạng và quyền |
| Quyền chủ động của người cao tuổi | Có kiểm soát người thân ở backend; trải nghiệm giải thích GPS/camera cần được xem riêng | Cha/mẹ hiểu dữ liệu chia sẻ và có lựa chọn phù hợp |
| Sẵn sàng thương mại | Chưa đủ bằng chứng để kết luận từ đọc source | Pilot thật, khả năng hỗ trợ và hành vi tiếp tục/trả phí |

Không gán điểm tổng hoặc tỷ lệ hài lòng cho bảng này vì chưa có mẫu người dùng, quan sát và thang đo thực tế.

## 3 Bộ phản hồi người dùng giả lập

Chín nhân vật dưới đây đại diện cho các nhu cầu khác nhau, không đại diện thống kê cho toàn bộ người cao tuổi hoặc con cái. Tuổi, hoàn cảnh và câu nói đều được tạo để kiểm tra giả thuyết.

### F01 Bà Lan 68 tuổi và trạng thái SOS khi mất mạng

**Tình huống giả lập:** bà dùng điện thoại để báo cần giúp trong lúc Wi-Fi mất kết nối. Bà chỉ đọc dòng thông báo sau khi bấm nút.

> “Máy nói đã gửi cho con thì tôi tưởng con đã biết. Nếu chưa gửi được, nói rõ để tôi tìm cách gọi người nhà.”

**Giá trị bà có thể thấy:** một nút báo cần giúp dễ nhớ. **Điểm có thể làm bà mất niềm tin:** thông báo thành công khi chưa có bằng chứng truyền tới người thân.

**Hàm ý:** cần trạng thái bền trên màn hình: đang gửi, đã lưu chờ mạng, máy chủ đã nhận, người thân đã xác nhận. Chỉ hiện trạng thái mà hệ thống có bằng chứng. Kiểm chứng xem bà có phân biệt được ba tình huống đầu mà không cần giải thích lần hai. Liên kết B01, B03.

### F02 Ông Hùng 72 tuổi và thao tác xác nhận mình ổn

**Tình huống giả lập:** một sự kiện chuyển động tạo màn đếm ngược ngã trong buổi diễn tập. Ông muốn hủy vì mình vẫn ổn, tay thao tác chậm.

> “Tôi muốn nhìn thấy rõ nút tôi vẫn ổn, máy đọc chậm một lần. Bấm rồi phải biết máy đã nhận lời tôi.”

**Giá trị ông có thể thấy:** được hỏi lại trước khi báo ngã. **Điểm gây khó:** phải đọc nhiều chữ hoặc không chắc thao tác đã được ghi nhận.

**Hàm ý:** cải thiện nút “Tôi vẫn ổn”, rung/âm đọc và phản hồi sau chạm. Chức năng hủy đếm ngược đã có; cần đo khả năng sử dụng của nó. Phân biệt hủy trước lúc gửi với cập nhật “tôi ổn” sau khi sự cố đã gửi, để giữ lịch sử và tránh đóng sự cố âm thầm. Liên kết B04, B06.

### F03 Cô Mai 64 tuổi và việc chia sẻ vị trí cùng ảnh

**Tình huống giả lập:** con cài ứng dụng giúp, cô thấy điện thoại xin quyền vị trí và camera nhưng chưa hiểu khi nào ứng dụng dùng.

> “Tôi đồng ý báo vị trí khi cần giúp. Tôi muốn biết lúc nào máy chụp ảnh và những ai xem được.”

**Giá trị cô có thể thấy:** con biết thêm thông tin khi cần liên hệ. **Điểm khiến cô do dự:** cảm giác bị theo dõi hoặc camera hoạt động ngoài điều đã hiểu.

**Hàm ý:** giải thích từng mục bằng câu ngắn; tách dữ liệu cần cho SOS khỏi quyền bổ sung ảnh/vị trí. Cho xem danh sách người đang được quyền truy cập và cách yêu cầu thay đổi chia sẻ. Khi từ chối camera, vẫn cần giải thích phần SOS còn hoạt động được. Liên kết B08.

### F04 Ông Bình 76 tuổi và chữ cùng âm thanh

**Tình huống giả lập:** ông khó đọc chữ nhỏ, nghe còi không rõ khi ở phòng khác; sau khi quay lại điện thoại muốn biết đang xảy ra việc gì.

> “Chữ lớn và có câu nói thì tôi hiểu hơn. Chỉ đổi màu hoặc kêu một tiếng tôi không biết phải làm gì.”

**Hàm ý:** kết hợp chữ, biểu tượng, rung và giọng nói; không dựa vào màu hoặc âm thanh duy nhất. Có cách tăng cỡ chữ, nghe thử tiếng Việt và chỉnh âm lượng nhắc nhẹ. Cần kiểm tra câu đọc vẫn đúng khi tắt mạng và khi thiết bị chưa có giọng tiếng Việt. Liên kết B04, B06.

### F05 Chị Linh 32 tuổi và cảnh báo khi đang làm việc

**Tình huống giả lập:** chị mở cảnh báo lúc đang họp. Chị cần biết mẹ có chuyện gì, cần tắt âm và có thể gọi ngay.

> “Tôi cần thấy tên mẹ, chuyện gì vừa xảy ra và nút gọi. Tắt còi để nghe điện thoại không có nghĩa tôi đã xử lý xong.”

**Giá trị chị có thể thấy:** thông tin giúp hành động nhanh. **Điểm gây khó:** phải cuộn qua biểu đồ hoặc không phân biệt tắt âm với nhận trách nhiệm.

**Hàm ý:** đưa hành động chính lên đầu hoặc thanh cố định; “Tắt âm trên máy này”, “Tôi nhận hỗ trợ” và “Đã hỗ trợ xong” phải có ý nghĩa khác nhau. App đã có các hành động tương ứng; đề xuất là thay cách trình bày và kiểm chứng sự hiểu. Liên kết B05.

### F06 Anh Nam 40 tuổi và hai người con cùng chăm sóc

**Tình huống giả lập:** anh sống xa, em gái ở gần bố. Hai người cùng nhận một cảnh báo và mở sự cố gần như đồng thời.

> “Tôi muốn biết em đã nhận chưa và đang gọi hay sẽ đến kiểm tra. Nếu tôi chỉ xác nhận đã thấy thì đừng nói với bố là tôi đang đến.”

**Hàm ý:** giữ thông tin/thời gian người tiếp nhận đã có; hiển thị tên dễ hiểu thay mã định danh. Làm rõ “đã tiếp nhận” khác “đang gọi” hoặc “đang đến”. Nếu thêm các cập nhật hành động thì người thân phải chủ động chọn. Khi hai người nhận cùng lúc, màn hình tải lại trạng thái hiện tại và nói ai đã nhận, thay vì chỉ hiện mã lỗi tranh chấp. Liên kết B01, B05, B06.

### F07 Chị Thảo 37 tuổi và thông tin cũ trên dashboard

**Tình huống giả lập:** chị xem được một chỉ số gần nhất nhưng đồng hồ đã hết pin. Chị không để ý thời gian nhỏ bên dưới; hôm khác báo cáo có quá ít ngày dữ liệu.

> “Số nhìn bình thường nhưng có phải số của hôm nay không? Nếu máy chưa đo thì cứ ghi chưa đủ dữ liệu.”

**Hàm ý:** đặt thời gian đo và chất lượng dữ liệu cạnh trạng thái chính. Tách “không ghi nhận cảnh báo trong dữ liệu hiện có” khỏi kết luận sức khỏe ổn. Báo cáo cần nêu khoảng thời gian và số ngày có dữ liệu, thay vì khiến khoảng trống trông như không có vấn đề. Liên kết B02, B07, B09.

### F08 Chị Hạnh 45 tuổi và cài đặt cho bố

**Tình huống giả lập:** chị muốn thử CareAI nhưng chỉ có điện thoại cũ và một vòng đeo phổ thông. Chị không biết cấu hình máy chủ là gì.

> “Cho tôi biết máy nào dùng được, cần mua gì thêm và hướng dẫn từng bước. Tôi không muốn mua đồng hồ rồi mới biết thiếu tính năng.”

**Hàm ý:** có danh sách cấu hình được xác minh, phân biệt dùng điện thoại với cảm biến đồng hồ. Đưa cấu hình kỹ thuật vào chế độ hỗ trợ; người thân đi theo luồng tạo hồ sơ, ghép đúng người, xin quyền và diễn tập. Tổng giá gồm phần mềm và phần cứng phải rõ. Liên kết B03 và tài liệu marketing.

### F09 Ông Sơn 70 tuổi và lời nhắc sinh hoạt

**Tình huống giả lập:** sau khi hiểu SOS, ông hỏi liệu có thể nhận lời nhắc theo lịch thuốc gia đình đã thống nhất hay không.

> “Tôi muốn máy nhắc đúng giờ đã ghi. Nếu chưa nhớ mình uống hay chưa thì cần xem lại, chứ đừng nhắc là uống thêm.”

**Hàm ý:** nhắc thuốc có thể có giá trị nhưng là chức năng mới cần khảo sát. Bắt đầu từ lịch do người dùng nhập theo hướng dẫn đã có của người chăm sóc/chuyên môn, trạng thái đã dùng/chưa xác nhận và lịch sử thao tác. Không tự gợi ý liều hoặc coi việc chưa bấm xác nhận là chắc chắn chưa uống. Liên kết B10; chưa đưa vào quảng cáo tính năng hiện có.

## 4 Nhu cầu rút ra từ các tình huống giả lập

| Nhóm nhu cầu | Điều người dùng cần hiểu hoặc làm | Ưu tiên sản phẩm |
| --- | --- | --- |
| Tin được phản hồi của hệ thống | Tín hiệu đã đi tới đâu, ai đã xác nhận | Sửa trạng thái SOS và nội dung lời đọc |
| Dùng được khi thao tác chậm | Tìm đúng nút, đọc được, biết chạm có hiệu lực | Chữ lớn, nút lớn, xác nhận rõ, ít lớp điều hướng |
| Hành động nhanh với thông tin vừa đủ | Biết ai, chuyện gì, lúc nào và làm gì tiếp | Đưa gọi/tiếp nhận lên đầu, giữ chi tiết ở phía sau |
| Nhận biết giới hạn dữ liệu | Chưa đo, số cũ, demo, thiếu mẫu khác bình thường | Nhãn nguồn, thời gian đo và độ đầy đủ |
| Quyết định chia sẻ | Biết ai xem ảnh, vị trí và thông tin theo dõi | Giải thích quyền và lựa chọn chia sẻ |
| Duy trì sử dụng hằng ngày | Ít công sức cài đặt, sạc, hiểu báo cáo | Onboarding, hỗ trợ thiết bị, báo cáo ngắn |

Đây là tổng hợp giả thuyết thiết kế, không phải kết luận “đa số người dùng mong muốn” hoặc “người dùng đã yêu cầu”.

## 5 Backlog cải tiến có thứ tự

P0 là việc cần xử lý trước khi mở rộng pilot cảnh báo. P1 ưu tiên trong pilot để giảm khó dùng. P2 chỉ triển khai sau khi xác nhận nhu cầu. S/M/L là ước lượng tương đối về phạm vi, chưa phải cam kết thời gian.

| Mã | Ưu tiên | Cải tiến | Bản chất thay đổi | Phạm vi |
| --- | --- | --- | --- | --- |
| B01 | P0 | Thể hiện đúng quá trình gửi và tiếp nhận SOS trên điện thoại và đồng hồ | Sửa phản hồi hiện có; có thể bổ sung theo dõi trạng thái | L |
| B02 | P0 | Xử lý minh bạch dữ liệu thiếu, demo và giấc ngủ suy ra | Sửa nội dung và điều kiện tổng kết | M |
| B03 | P0 | Cài đặt theo gia đình và kiểm tra sẵn sàng nhận cảnh báo | Hoàn thiện luồng đang có, thêm diễn tập và chẩn đoán dễ hiểu | L |
| B04 | P1 | Chữ, vùng chạm và tác vụ SOS phù hợp khả năng nhìn và vận động | Hoàn thiện giao diện hiện có | M |
| B05 | P1 | Hành động khẩn dễ tìm và ngôn ngữ gia đình | Sắp xếp và sửa nhãn tác vụ hiện có | M |
| B06 | P1 | Lời đọc tiếng Việt đúng trạng thái, có kiểm tra giọng và lựa chọn | Tích hợp và hoàn thiện TTS có sẵn | M |
| B07 | P1 | Dashboard một thông điệp chính, kèm nguồn và thời gian | Đơn giản hóa phần trình bày đang có | M |
| B08 | P1 | Giải thích và quản lý chia sẻ ảnh, GPS, thành viên gia đình | Hoàn thiện trải nghiệm quyền; bổ sung lựa chọn nếu còn thiếu | L |
| B09 | P1 | Báo cáo tuần ngắn, có độ đầy đủ và hành động hỏi thăm | Hoàn thiện báo cáo hiện có | M |
| B10 | P2 | Nhắc thuốc hoặc sinh hoạt theo lịch gia đình | Chức năng mới cần xác nhận nhu cầu | L |
| B11 | P2 | Xác nhận ổn hằng ngày theo lựa chọn | Chức năng mới, khác nút hủy đếm ngược ngã đã có | M |
| B12 | P2 | Nhắc sạc và hướng dẫn khôi phục kết nối dễ hiểu | Hoàn thiện trạng thái thiết bị hiện có | M |

### B01 Trạng thái SOS trung thực

Hiển thị tiến trình dựa trên bằng chứng: đang gửi → đã lưu tại máy chờ mạng hoặc máy chủ đã nhận → người thân đã tiếp nhận. Có thể bổ sung “điện thoại người thân đã nhận” sau khi xây cơ chế xác nhận phù hợp; chưa có xác nhận thì không hiển thị bước đó. Không suy từ HTTP thành công hoặc FCM `SENT` ra người thân đã đọc.

**Tiêu chí chấp nhận:** mất mạng không xuất hiện câu đã gửi tới người thân; retry vẫn giữ cùng mã gói, tránh sự cố trùng; trạng thái được khôi phục khi mở lại app; lời đọc và đồng hồ theo cùng nghĩa. Sau khi có xác nhận, chỉ nói tên người đã tiếp nhận; không nói họ đang đến nếu chưa có cập nhật hành động đó. Cần giữ RowVersion, timeline và outbox.

Ưu tiên ghi nhận và gửi tín hiệu đầu sau khi người dùng xác nhận, không chờ ảnh hoặc lượt lấy GPS bổ sung. Gắn vị trí mới khi đã có kết quả, giữ rõ thời điểm và nguồn. Kiểm tra trường hợp định vị chậm/từ chối quyền để bảo đảm SOS vẫn được lưu và thử gửi; chưa đặt một cam kết độ trễ trước khi đo thực tế.

### B02 Dữ liệu và kết luận có căn cứ

Không hiện ngủ sâu/số lần thức như số đo thật khi đang suy ra bằng hằng số. Bỏ hoặc đổi nhãn “Đạt chuẩn y tế”; dữ liệu thiếu thì nói thiếu. Mỗi chỉ số cần biết nguồn và thời điểm; dữ liệu demo gắn nhãn riêng và không tham gia kết luận thật.

**Tiêu chí chấp nhận:** không có giá trị minh họa hoặc suy ra không được giải thích trên màn người dùng; thiếu dữ liệu không tạo trạng thái sức khỏe ổn; không còn tổng kết mang nghĩa chứng nhận y tế từ phép tính kỹ thuật. Rà cả dashboard, báo cáo và ảnh demo marketing.

### B03 Cài đặt và kiểm tra sẵn sàng

Đề xuất luồng: người thân tạo hồ sơ → chọn thiết bị/khả năng → ghép đúng cha/mẹ → giải thích và cấp quyền → mời người thân → diễn tập gửi, nhận, tiếp nhận. Có chỉ dẫn cụ thể khi chưa đủ quyền thông báo, nền hoặc kết nối. Người cao tuổi chỉ cần nhận diện hồ sơ và thực hiện tác vụ đơn giản; người thân xử lý phần cấu hình.

**Tiêu chí chấp nhận:** 8/10 gia đình mục tiêu hoàn tất luồng với tối đa một lần nhắc; hiển thị đúng hồ sơ trước khi ghép; PIN có thời hạn rõ lấy từ server; lỗi nêu cách khắc phục. Nhãn “sẵn sàng” phải nói sẵn sàng ở phần nào, không suy từ server online thành cảnh báo tới máy người thân đã hoạt động. Cấu hình server nằm trong chế độ hỗ trợ, tránh người dùng vô tình đổi.

### B04 Khả năng đọc và chạm

Ưu tiên một hành động chính trên màn người cao tuổi, nhãn chữ kèm biểu tượng, phân tách nút SOS và nút xác nhận ổn. Không thu nhỏ chữ để nhét nhiều thông tin vào màn đồng hồ. Kiểm tra TalkBack/VoiceOver, thứ tự đọc, cỡ chữ hệ thống và thao tác một tay.

**Tiêu chí thiết kế tham khảo:** vùng chạm Android tối thiểu 48×48 dp, nút khẩn có thể lớn hơn; tương phản chữ thường 4,5:1, chữ lớn 3:1; tăng chữ tới 200% không mất tác vụ chính; trạng thái có chữ/biểu tượng bên cạnh màu. Đây là mục tiêu áp dụng cho app, không phải kết luận app đã đạt chuẩn. [Nguồn Android](https://developer.android.com/guide/topics/ui/accessibility/views/apps-views), [hướng dẫn W3C cho người cao tuổi](https://www.w3.org/WAI/older-users/developing/).

**Tiêu chí sử dụng:** ít nhất 8/10 người cao tuổi trong mẫu thử tự tìm SOS và xác nhận ổn trong tình huống giả lập sau hướng dẫn. Ghi thời gian và lỗi thực tế; không yêu cầu họ diễn lại một cú ngã.

### B05 Tác vụ người thân khi có cảnh báo

Đầu màn hiển thị tên cha/mẹ, loại tín hiệu, thời điểm, nguồn dữ liệu và người đã tiếp nhận. Đưa “Gọi cho bố/mẹ” và “Tôi nhận hỗ trợ” vào vị trí luôn dễ thấy. Giữ “Tắt âm trên máy này” riêng. Đổi “ghi chú lâm sàng” thành “Ghi lại cách gia đình đã hỗ trợ”; gợi ý ngắn, vẫn giữ yêu cầu ghi nhận trước khi đóng.

**Tiêu chí chấp nhận:** không phải cuộn để tìm hành động khẩn trên cấu hình mục tiêu; 8/10 người thân nói đúng khác biệt tắt âm, tiếp nhận và hoàn tất; khi hai người nhận cùng lúc, tải trạng thái mới và chỉ rõ ai đã nhận. Nút gọi hiện có phải giữ việc người dùng chủ động xác nhận cuộc gọi.

### B06 Giọng nói đúng ngữ cảnh

Giữ lời đọc ngã đã có; bổ sung phản hồi khi cần nhưng tránh đọc lặp liên tục. Có nút nghe thử tiếng Việt và tùy chọn âm nhắc. Nếu thiếu giọng phù hợp, hướng dẫn hoặc dùng chữ/rung rõ ràng, không âm thầm coi ngôn ngữ mặc định là tiếng Việt.

**Tiêu chí chấp nhận:** lời đọc khớp trạng thái thực B01; không nói “đang trên đường đến” từ thao tác tiếp nhận đơn thuần; không đọc thông tin riêng tư dài khi chưa được lựa chọn; kiểm tra trường hợp offline và thiếu gói giọng. Chưa quảng cáo hoạt động ngoại tuyến hoàn toàn trước khi xác minh.

### B07 Thông tin đầu màn dễ hiểu

Dashboard trả lời trước: có tín hiệu nào cần xem, dữ liệu cập nhật lúc nào và gia đình có thể làm gì. Biểu đồ và lịch sử vẫn truy cập được ở phía sau. Có trạng thái riêng cho chưa đủ dữ liệu, thiết bị chưa gửi dữ liệu và sự cố đang được tiếp nhận.

**Tiêu chí chấp nhận:** sau khi xem nhanh, 8/10 người thân xác định đúng người, độ mới dữ liệu và việc cần làm; không hiểu nhãn không có cảnh báo là xác nhận người cao tuổi an toàn. Ngưỡng “cũ” phải được xác định theo loại dữ liệu và nhịp gửi thực tế của thiết bị, không dùng một thời hạn tùy ý cho tất cả.

### B08 Chia sẻ minh bạch

Giải thích ảnh, GPS và cảm biến ở thời điểm cần dùng, bằng ví dụ dễ hiểu. Cho người cao tuổi và người thân xem ai có quyền, vai trò của người quản lý chính và cách đề nghị thay đổi. Rà luồng đồng ý, thay đổi quyền và thu hồi thiết bị; không công bố đã có đầy đủ khi mới thấy kiểm soát ở backend.

**Tiêu chí chấp nhận:** người thử nói được khi nào ảnh/vị trí được dùng và ai xem; từ chối camera không chặn SOS cơ bản; thay đổi người thân vẫn giữ phân quyền theo từng hồ sơ và lịch sử sự cố. Thông báo màn hình khóa chỉ chứa thông tin phù hợp với lựa chọn chia sẻ.

### B09 Báo cáo tuần giúp gia đình hành động

Tận dụng báo cáo đã có để thể hiện: khoảng thời gian, số ngày có dữ liệu, một vài điểm cần xem và một lời hỏi thăm phù hợp. Hiển thị trung thực khi chưa đủ lịch sử hoặc khi dùng tổng kết bằng quy tắc. Không suy từ điểm thống kê ra xác suất mắc bệnh hoặc tạo lời khuyên đổi thuốc.

**Tiêu chí chấp nhận:** người thân hiểu một điểm chính và điều còn chưa biết; báo cáo thiếu ngày đo không bị diễn giải như đủ cả tuần; Gemini không khả dụng vẫn dùng phương án dự phòng hiện có. Dữ liệu gửi ra dịch vụ AI phải giữ giới hạn trường cần thiết; giải thích rõ việc dùng dịch vụ bên ngoài cho người dùng theo luồng sản phẩm.

### B10 đến B12 Chức năng bổ sung sau khi xác nhận nhu cầu

**Nhắc thuốc/sinh hoạt:** chỉ thử sau khi người dùng thật ưu tiên. Cần lịch do gia đình cấu hình, xác nhận rõ ai đã thao tác, tránh nhắc trùng và phân biệt chưa xác nhận với chưa dùng. Không tự sinh liều. Chỉ báo marketing có chức năng khi đã triển khai và kiểm tra luồng.

**Xác nhận ổn hằng ngày:** cho chọn giờ và tắt nhắc; “chưa phản hồi” trước hết là thông tin để hỏi thăm, không tự kết luận nguy kịch. Không dùng tính năng này thay cho nút xác nhận ổn khi đếm ngược ngã.

**Sạc và kết nối:** mô tả cụ thể như “chưa nhận dữ liệu từ đồng hồ”, “kiểm tra Bluetooth”, kèm thời gian gần nhất. Chỉ nhắc pin khi giá trị pin thực sự có nguồn; tránh dùng giá trị mặc định như pin đo thật. Đo số thông báo gây phiền trước khi tăng tần suất nhắc.

## 6 Luồng giao diện đề xuất

### 6.1 Màn hình người cao tuổi

Nội dung cốt lõi: tên người đang dùng, trạng thái kết nối ngắn, nút lớn “Báo con cần giúp” có nhãn SOS, trạng thái gửi hiện tại và liên hệ gia đình phù hợp. Các thông tin cảm biến chi tiết đặt ở màn tiếp theo. Trên đồng hồ, giữ trang khẩn dễ truy cập; cơ chế tự quay về trang khẩn đã có ở local và được bổ sung trong commit remote, cần hoàn thiện điều kiện và kiểm chứng thay vì tạo lại.

Ví dụ nội dung đề xuất, không phải dữ liệu thật:

> Đã lưu tín hiệu trên điện thoại, đang chờ mạng.
>
> Khi có kết nối, ứng dụng sẽ thử gửi lại. Bác có thể dùng nút gọi người nhà nếu cần liên hệ ngay.

Khi server chấp nhận thì nói “Máy chủ đã nhận tín hiệu”. Khi có ACK hợp lệ thì nói “Người thân đã xác nhận tiếp nhận”. Có thể hiển thị tên theo lựa chọn chia sẻ; không suy ra họ đã gọi hoặc đang đến.

### 6.2 Màn hình người thân

Theo thứ tự: người đang cần xem → chuyện gì vừa ghi nhận → thời điểm và độ mới → ai đã tiếp nhận → gọi/nhận hỗ trợ → vị trí và bằng chứng nếu có → biểu đồ/timeline. Nếu không có tọa độ mới, hiển thị điều đó cùng địa chỉ nhà được lưu trong hồ sơ, phân biệt hai nguồn.

Sau hỗ trợ, gợi ý ghi chú bằng ngôn ngữ gia đình như đã gọi, đã nhờ người kiểm tra, hoặc cần theo dõi tiếp. Đây là ghi nhận hành động của gia đình, không phải chẩn đoán lâm sàng.

## 7 Kế hoạch thay phản hồi giả lập bằng bằng chứng thật

Đây là kế hoạch nghiên cứu đề xuất, chưa được thực hiện. Phạm vi địa bàn và quy mô theo [kế hoạch marketing 90 ngày](./CAREAI_MARKETING_NGAN_HAN.md).

### 7.1 Người tham gia

Tuyển khoảng 10–12 gia đình để phỏng vấn ban đầu, có cả người cao tuổi lẫn người con. Trong đó, mời ít nhất 5 cặp vào vòng quan sát đầu tiên; sửa lỗi rồi thử tiếp với 5 cặp khác hoặc nhóm bổ sung phù hợp. Cần có người ít quen smartphone, người cần chữ lớn, gia đình có nhiều người con và cấu hình thiết bị khác nhau trong danh sách hỗ trợ.

Không chỉ hỏi người con muốn theo dõi gì. Phỏng vấn riêng điều cha/mẹ thấy hữu ích, khó chịu hoặc không muốn chia sẻ. Mẫu thuận tiện nhỏ chỉ giúp tìm vấn đề thiết kế và kiểm chứng giả thuyết ban đầu, không đại diện cho thị trường Việt Nam.

### 7.2 Tác vụ quan sát

| Tác vụ | Điều quan sát | Dấu hiệu cần sửa |
| --- | --- | --- |
| Cài đặt và ghép thiết bị | Các bước tự làm, cần nhắc, ghép đúng hồ sơ | Nhầm cha/mẹ, mắc ở cấu hình, không hiểu quyền |
| Bấm SOS khi có mạng | Tìm nút, hiểu trạng thái sau thao tác | Tưởng đã có người đọc chỉ vì server nhận |
| SOS khi không có mạng | Hiểu lưu tại máy và cách liên hệ khác | Tiếp tục chờ vì tưởng người thân đã được báo |
| Hủy đếm ngược ngã giả lập | Tìm nút xác nhận ổn và hiểu phản hồi | Bấm nhầm SOS, không biết đã hủy chưa |
| Người thân mở cảnh báo | Biết ai, chuyện gì, thời điểm, nút gọi/tiếp nhận | Cuộn tìm lâu, tắt âm rồi tưởng đã hoàn tất |
| Hai người nhận cùng lúc | Hiểu người đã nhận và cách phối hợp | Cả hai cùng tưởng người kia xử lý hoặc không thấy cập nhật |
| Xem dữ liệu cũ/thiếu/demo | Nói đúng điều biết và chưa biết | Đọc chỉ số cũ như hiện tại, hiểu demo là đo thật |
| Đọc báo cáo tuần | Tóm tắt nội dung và độ đầy đủ | Xem tổng kết thành chẩn đoán hoặc bỏ qua ngày thiếu dữ liệu |
| Từ chối camera hoặc vị trí | Hiểu phần còn hoạt động và cách đổi quyền | Tưởng phải cho mọi quyền mới dùng được SOS |

Thực hiện bằng dữ liệu, tài khoản và cảnh báo thử nghiệm có nhãn rõ. Không yêu cầu người cao tuổi tự ngã, tạo bất thường sức khỏe hoặc gọi số cấp cứu để thử sản phẩm.

### 7.3 Câu hỏi tránh dẫn dắt

1. Khi vắng nhà, gia đình hiện liên hệ hoặc kiểm tra cha/mẹ bằng cách nào? Lần gần nhất gặp khó là khi nào?
2. Bác nghĩ màn hình này đang nói điều gì? Sau khi bấm nút này, bác mong chuyện gì xảy ra?
3. Anh/chị nghĩ ai đã biết về tín hiệu này? Điều gì trên màn hình khiến anh/chị nghĩ vậy?
4. Nếu chưa có dữ liệu hôm nay, gia đình muốn ứng dụng thể hiện ra sao?
5. Dữ liệu nào bác muốn chia sẻ, dữ liệu nào bác thấy không cần? Bác muốn ai được xem?
6. Trong trải nghiệm vừa rồi, phần nào giúp ích và phần nào gây thêm việc cho gia đình?
7. Nếu ngừng dùng, lý do có thể là gì? Sau khi biết đầy đủ chi phí, gia đình cân nhắc mức nào và vì sao?

Hỏi nhu cầu và hành vi trước khi đưa danh sách tính năng để tránh người tham gia chỉ đồng ý với gợi ý của nhóm.

### 7.4 Phiếu ghi kết quả

Mỗi buổi ghi: mã người tham gia, nhóm vai trò, cấu hình thiết bị, mức quen công nghệ tự mô tả, tác vụ, kết quả hoàn thành, thời gian, số lần trợ giúp, lỗi nghiêm trọng, câu nói được đồng ý ghi và đề xuất của người quan sát. Dùng mã thay tên thật trong tài liệu phát triển; không đưa dữ liệu sức khỏe thật vào repository.

Ghi phản hồi theo ba cột: **quan sát thực tế**, **lời người tham gia**, **diễn giải của nhóm**. Không điền lời giả lập F01–F09 vào phiếu kết quả thật. Nếu dùng thang điểm dễ dùng 1–5 sau tác vụ thì ghi rõ câu hỏi, số người trả lời và phân bố; chưa có trả lời thì để trống.

### 7.5 Chỉ số và điều kiện kết thúc một vòng

- Tỷ lệ hoàn thành tác vụ = số người hoàn thành / số người đã thử; tách tự hoàn thành và có trợ giúp.
- Hiểu đúng trạng thái = số người giải thích đúng / số người được hỏi, riêng cho chờ mạng, server nhận và người thân tiếp nhận.
- Thời gian tác vụ = thời gian từ yêu cầu tới hành động; báo trung vị kèm phạm vi khi đủ mẫu, không chỉ chọn trường hợp nhanh nhất.
- Đường cảnh báo = sự kiện tạo → server nhận → điện thoại nhận → người thân tiếp nhận; ghi mốc và lỗi cho từng bước, không suy từ FCM `SENT`.
- Thông báo gây phiền = số thông báo người dùng đánh dấu không hữu ích / số thông báo đã xem; kèm lý do, không dùng đánh giá này như độ chính xác lâm sàng.
- Duy trì = gia đình chủ động muốn dùng tiếp sau ít nhất hai tuần / gia đình hoàn tất pilot; ghi cả người rút lui và lý do.

Mục tiêu ban đầu là ít nhất 8/10 người trong mẫu thử hiểu và làm được tác vụ chính, không còn lỗi nghiêm trọng về trạng thái SOS. Đây là ngưỡng quyết định nội bộ, không phải chứng nhận an toàn hoặc suy rộng mức hài lòng toàn thị trường. Nếu chưa đạt, sửa và kiểm tra lại trước khi tuyển thêm nhiều gia đình.

## 8 Trình tự triển khai được đề xuất

**Trước pilot mở rộng:** B01–B03; rà lại ảnh demo và nội dung marketing. Xác minh dữ liệu và đường cảnh báo trên cấu hình mục tiêu. Lần làm tài liệu này chưa thực hiện các bước kiểm thử đó.

**Trong các vòng quan sát đầu:** B04–B09, ưu tiên lỗi gây nhầm trước, rồi giảm số bước và cải thiện khả năng đọc. Giữ tính nhất quán giữa Flutter, Android, Wear OS và watchOS; không giả định chúng có đầy đủ tính năng giống nhau chỉ từ README.

**Sau bằng chứng dùng tiếp:** cân nhắc B10–B12 theo nhu cầu thật và công sức duy trì. Hoàn thiện chức năng chăm sóc hằng ngày sau khi gia đình đã tin và hiểu các chức năng cốt lõi.

## 9 Phụ lục bằng chứng từ mã nguồn

Các đường dẫn sau phục vụ truy lại quan sát, không phải kết quả chạy kiểm thử.

| Mã | Tệp và mốc dòng local | Nội dung đối chiếu |
| --- | --- | --- |
| C1 | [sos_button_screen.dart](../../CareAI/companion_app/lib/screens/sos_button_screen.dart), dòng 483, 502–534; [location_service.dart](../../CareAI/companion_app/lib/services/location_service.dart), dòng 62–116 | Chờ lượt lấy GPS trước khi lưu/gửi SOS tay; sau đó lưu SQLite, thử gửi, bắt lỗi và vẫn hiện câu đã gửi tới người thân |
| C2 | [WearOsMainActivity.kt](../../CareAI/wearos/src/main/kotlin/vn/careai/companion/WearOsMainActivity.kt), dòng 546–560; [CareAIWatchApp.swift](../../CareAI/watchos/Sources/CareAIWatchApp.swift) | Nhãn trạng thái SOS trên đồng hồ cần gắn với bằng chứng gửi thay vì trạng thái cục bộ |
| C3 | [FirebasePushSender.cs](../../CareAI/src/CareAI.Infrastructure/Notifications/FirebasePushSender.cs), dòng 63; [NotificationDispatchEngine.cs](../../CareAI/src/CareAI.Infrastructure/Notifications/NotificationDispatchEngine.cs), dòng 162 | Tích hợp FCM thật; `SENT` là FCM chấp nhận |
| C4 | [IncidentsController.cs](../../CareAI/src/CareAI.API/Controllers/IncidentsController.cs), dòng 296–413 | Tiếp nhận, RowVersion, giải quyết sau tiếp nhận; giữ quy tắc khi cải tiến UX |
| C5 | [fall_countdown_dialog.dart](../../CareAI/companion_app/lib/screens/fall_countdown_dialog.dart), dòng 43, 54, 317 | Đếm ngược, gọi lời đọc ngã và nút xác nhận ổn đã có |
| C6 | [incident_detail_screen.dart](../../CareAI/companion_app/lib/caregiver/screens/incident_detail_screen.dart), dòng 203, 390, 698–739 | Từ “ghi chú lâm sàng”, danh sách cuộn và vị trí các nút gọi/tiếp nhận |
| C7 | [device_pairing_screen.dart](../../CareAI/companion_app/lib/screens/device_pairing_screen.dart), dòng 133–182; [home_screen.dart](../../CareAI/companion_app/lib/caregiver/screens/home_screen.dart), dòng 397–416, 561; [DevicesController.cs](../../CareAI/src/CareAI.API/Controllers/DevicesController.cs), dòng 62–66 | PIN, giải thích ghép đôi, đường vào cấu hình; code server hiện đặt PIN 15 phút, khác README cũ ghi 10 phút |
| C8 | [voice_guidance_service.dart](../../CareAI/companion_app/lib/services/voice_guidance_service.dart), dòng 55, 68, 75–93; [MainActivity.kt](../../CareAI/companion_app/android/app/src/main/kotlin/vn/careai/companion/MainActivity.kt), dòng 748–750 | Kiểm tra giọng, các hàm lời đọc, nội dung tiếp nhận và fallback ngôn ngữ; có hàm chưa chứng minh đã nối toàn luồng |
| C9 | [FamilyController.cs](../../CareAI/src/CareAI.API/Controllers/FamilyController.cs), dòng 31, 102, 186, 232 | Mời, tham gia, liệt kê và thu hồi thành viên đã có backend |
| C10 | [TimeSeriesAnomalyDetector.cs](../../CareAI/src/CareAI.Infrastructure/AnomalyDetection/TimeSeriesAnomalyDetector.cs), dòng 28–57; [WeeklyReportService.cs](../../CareAI/src/CareAI.Infrastructure/WeeklyReports/WeeklyReportService.cs), dòng 36; [GeminiWeeklyReportClient.cs](../../CareAI/src/CareAI.Infrastructure/WeeklyReports/GeminiWeeklyReportClient.cs), dòng 37–43 | Nhận định có phạm vi hẹp, có yêu cầu dữ liệu và phương án báo cáo dự phòng |
| C11 | [DashboardController.cs](../../CareAI/src/CareAI.API/Controllers/DashboardController.cs), dòng 128, 482–503; [elder_dashboard_screen.dart](../../CareAI/companion_app/lib/caregiver/screens/elder_dashboard_screen.dart), ví dụ dòng 562, 602 | Demo tách riêng; ngủ sâu/số lần thức suy ra; một số nhãn nhỏ cần đánh giá hiển thị |
| C12 | [README.md](../../README.md), dòng 210–214; [emergency_evidence_service.dart](../../CareAI/companion_app/lib/services/emergency_evidence_service.dart) | Luồng vị trí/ảnh, quyền thiết bị và giới hạn khi chạy nền; cần kiểm chứng thêm bằng sử dụng thực tế |

Tài liệu nền: [Proposal](../../CareAI_Proposal_EXE101_Bug_Buck_V2.docx), [README local](../../README.md), [README GitHub tại lần đọc](https://github.com/taithptqt/CareAI/blob/4c85f0b4dfd43f7e19f23e6a8b51d6c50df4e4a7/README.md), [README AI](../README-part4.md), [README anomaly](../README-anomaly-detection.md).

Nguồn thiết kế tham khảo: [W3C về người cao tuổi](https://www.w3.org/WAI/older-users/developing/), [WCAG 2.2](https://www.w3.org/TR/WCAG22/), [Android về khả năng tiếp cận](https://developer.android.com/guide/topics/ui/accessibility/views/apps-views), [khác biệt khả năng thiết bị Wear OS](https://developer.android.com/health-and-fitness/health-services/compatibility). Các nguồn này định hướng tiêu chí; chưa thay thế việc đo và kiểm thử CareAI.
