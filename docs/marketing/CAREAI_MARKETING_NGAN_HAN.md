# CareAI và kế hoạch marketing trong 90 ngày

Ngày lập: 15/10/2026. Đối tượng sử dụng tài liệu: nhóm Bug & Buck, phụ trách sản phẩm và marketing.

**Đề xuất trọng tâm:** tiếp cận gia đình có con cái bận rộn hoặc sống xa cha mẹ, trong một địa bàn mà nhóm có thể hỗ trợ cài đặt trực tiếp. Giá trị cần chứng minh là gia đình hiểu được thông tin theo dõi, biết khi nào cần liên hệ và biết ai đã tiếp nhận sự cố. Trong 90 ngày đầu, mục tiêu là kiểm chứng khả năng sử dụng và nhu cầu trả phí bằng một pilot có hỗ trợ.

## 1 Căn cứ và cách hiểu trạng thái sản phẩm

Tài liệu kết hợp ba loại căn cứ:

- **Định hướng kinh doanh:** đọc toàn bộ `CareAI_Proposal_EXE101_Bug_Buck_V2.docx`, đặc biệt các mục Customer Segments, Value Proposition, Key Features, Business Model, Marketing Strategy và Go To Market.
- **Tài liệu và mã nguồn:** README gốc, README ứng dụng Flutter, Wear OS, watchOS, tài liệu cấu trúc và các README phân hệ AI; đối chiếu với code tại commit local `225bb60212e64f84bc39299b7a0e76c7897abe87`.
- **Bối cảnh thị trường:** nguồn thống kê và UNFPA đã kiểm tra ngày 15/10/2026. Số liệu có năm tham chiếu riêng, không được coi là số người dùng CareAI.

README trên GitHub được đọc từ nhánh `main` qua Git remote. Lần fetch phục vụ nghiên cứu thấy remote ở `4c85f0b4dfd43f7e19f23e6a8b51d6c50df4e4a7`; nội dung README không khác bản local. Đã đọc thêm diff của commit mới về giao diện đồng hồ và thẻ huyết áp; không cập nhật mã nguồn local trong công việc này.

**Quy ước:** “có trong mã nguồn” nghĩa là tìm thấy triển khai liên quan; chưa có nghĩa đã kiểm chứng chạy trên máy chủ, điện thoại hoặc đồng hồ thật. Các giá bán, ngân sách, quy mô pilot và tỷ lệ chuyển đổi dưới đây là giả định lập kế hoạch. Chưa có khảo sát, doanh thu hoặc kết quả pilot mới được thu thập trong lần làm việc này.

## 2 Hiểu nghiệp vụ CareAI

### 2.1 Vấn đề gia đình cần giải quyết

Người con muốn quan tâm cha mẹ nhưng thường vắng nhà hoặc không thể gọi điện liên tục. Người cao tuổi có thể khó đọc chỉ số, ngại làm phiền con cháu hoặc không thao tác được khi cần hỗ trợ. Một ứng dụng hữu ích phải giúp cả hai phía phối hợp: người cao tuổi báo cần giúp dễ dàng, còn người thân hiểu tình huống và thực hiện bước tiếp theo.

Nhu cầu trung tâm có thể diễn đạt thành hai câu:

> Người cao tuổi: Khi cần giúp, tôi muốn báo cho người nhà bằng thao tác dễ nhớ và biết tín hiệu đang ở trạng thái nào.
>
> Người con: Khi không ở cạnh cha mẹ, tôi muốn biết có thông tin gì cần chú ý, dữ liệu còn mới không và trong gia đình ai đã nhận xử lý.

Đây là giả thuyết nhu cầu được rút từ proposal và luồng sản phẩm; cần phỏng vấn để xác nhận mức độ phổ biến.

### 2.2 Luồng tạo giá trị

1. Người thân tạo tài khoản và hồ sơ cha/mẹ, ghép điện thoại hoặc thiết bị phù hợp, mời thành viên gia đình.
2. Thiết bị gửi dữ liệu hoặc tín hiệu SOS/ngã; hệ thống ghi nhận theo người cao tuổi đã liên kết.
3. Khi đủ điều kiện, backend tạo hoặc cập nhật sự cố và thông báo cho người thân có quyền.
4. Người thân xem tình huống, gọi điện, xác nhận tiếp nhận và ghi lại kết quả xử lý.
5. Dashboard, lịch sử và báo cáo giúp gia đình xem lại thông tin để tiếp tục quan tâm.

Giá trị của chuỗi này phụ thuộc vào cấu hình thiết bị, quyền truy cập, mạng, dữ liệu và khả năng người thân phản hồi. Cần kiểm chứng toàn bộ chuỗi trước khi đưa một tính năng vào lời hứa thương mại.

### 2.3 Những gì có thể đưa vào mô tả sản phẩm

| Nhóm chức năng | Bằng chứng trong dự án | Cách diễn đạt phù hợp |
| --- | --- | --- |
| Hồ sơ và gia đình | Tạo hồ sơ, liên kết caregiver, lời mời và thu hồi thành viên | Quản lý thông tin người cao tuổi và những người thân cùng chăm sóc |
| SOS và ngã | Luồng SOS, đếm ngược ngã, hàng đợi gửi lại, incident và timeline | Hỗ trợ báo cần giúp và ghi nhận sự cố; khả năng phát hiện ngã phụ thuộc thiết bị và điều kiện sử dụng |
| Theo dõi và lịch sử | Dashboard, mẫu đo, biểu đồ, lịch sử sự cố | Xem thông tin được thiết bị cung cấp và lịch sử đã ghi nhận |
| Phối hợp xử lý | Tiếp nhận, người tiếp nhận, đóng sự cố và ghi chú | Gia đình biết ai đã nhận xử lý và xem lại diễn biến |
| Cảnh báo sinh hiệu | Quy tắc nhịp tim, SpO₂ và quản lý ngưỡng có trong code | Đánh dấu một số dữ liệu cần chú ý để người thân kiểm tra thêm |
| Báo cáo và nhận định | ML.NET cho một số dạng bất thường; báo cáo tuần, Gemini và tổng kết bằng quy tắc dự phòng | Tổng hợp thông tin để gia đình đọc dễ hơn; nội dung phụ thuộc độ đầy đủ của dữ liệu |
| Đồng hồ | Có module Wear OS và watchOS, cảm biến và đường truyền khác nhau | Thử nghiệm trên danh sách thiết bị đã xác minh; công bố rõ khả năng từng mẫu máy |

FCM đã có triển khai gọi Firebase SDK thật trong code. Trạng thái server `SENT` chỉ thể hiện FCM chấp nhận thông báo, chưa chứng minh điện thoại đã hiển thị hoặc người thân đã đọc. Tài liệu cũ có chỗ mô tả FCM mô phỏng, nên lấy triển khai hiện tại làm căn cứ kỹ thuật. [N3], [N4]

### 2.4 Những nội dung còn cần phân biệt

- **Nhắc thuốc, uống nước và trợ lý trò chuyện:** là hướng phát triển trong proposal; chưa tìm thấy luồng nhắc thuốc hoàn chỉnh trong phạm vi code đã rà soát. Không đưa vào danh sách tính năng hiện có.
- **Freemium, Premium, Family Plan:** là mô hình kinh doanh dự kiến. Quản trị thành viên gia đình đã có code không đồng nghĩa đã có gói thuê bao, thanh toán hay hạn mức thương mại.
- **Giấc ngủ:** có đường xử lý dữ liệu ngủ, nhưng API tổng kết đang suy ra thời gian ngủ sâu bằng tỷ lệ cố định và gán số lần thức. Không dùng các con số này để quảng cáo đo giấc ngủ chuyên sâu hoặc “đạt chuẩn y tế”. [N6]
- **Huyết áp:** commit mới trên remote thêm thẻ dữ liệu. watchOS đọc bản ghi HealthKit khi có; Wear OS có nhánh nhận dữ liệu bơm vào. Có thẻ hiển thị chưa chứng minh đồng hồ tự đo được huyết áp hoặc dữ liệu đã đi đầy đủ tới caregiver.
- **AI:** đã có code phân tích thống kê và tổng kết, nhưng chưa có bằng chứng đánh giá độ chính xác lâm sàng. Không dùng tên CareAI để suy ra khả năng dự báo bệnh.

## 3 Đối tượng người dùng mục tiêu

### 3.1 Phân biệt người mua và người sử dụng

| Nhóm | Chân dung định hướng | Điều họ cần | Vai trò trong quyết định |
| --- | --- | --- | --- |
| Người con hoặc người thân | Khoảng 25–45 tuổi theo proposal; dùng smartphone, đi làm, thường vắng nhà hoặc ở xa | Thông tin dễ hiểu, cảnh báo có ý nghĩa, biết ai xử lý, chi phí rõ | Người tìm hiểu, cài đặt, quyết định mua và thường trả phí |
| Cha mẹ hoặc ông bà | Proposal đề cập từ khoảng 55 tuổi; pilot ưu tiên người từ 60 tuổi, còn tự sinh hoạt và đồng ý tham gia | Ít thao tác, chữ dễ đọc, báo cần giúp đơn giản, biết dữ liệu chia sẻ cho ai | Người sử dụng trực tiếp và quyết định chấp nhận việc theo dõi |
| Anh chị em cùng chăm sóc | Có thể ở khác nơi hoặc luân phiên hỗ trợ | Nhìn thấy người đã tiếp nhận, tránh bỏ sót hoặc cùng tưởng người khác xử lý | Người dùng phối hợp, ảnh hưởng quyết định tiếp tục dùng |
| Người hỗ trợ gần nhà | Thành viên gia đình hoặc người được gia đình chỉ định | Nhận thông tin cần thiết, hiểu cách liên hệ | Hỗ trợ thực tế khi gia đình thống nhất; không mặc định có dịch vụ cứu hộ |

Tuổi chỉ là tiêu chí tuyển mẫu ban đầu. Cần ưu tiên mức quen công nghệ, khả năng nhìn/nghe, thói quen đeo thiết bị và mạng lưới hỗ trợ thực tế. Người con đồng ý trả phí không thay thế sự đồng ý chia sẻ dữ liệu của cha mẹ.

### 3.2 Phân khúc nên tiếp cận trước

**Ưu tiên một:** gia đình có cha/mẹ ở địa bàn nhóm hỗ trợ được, con cái đi làm hoặc sống riêng; có người thân sẵn sàng cài đặt và nhận thông báo. Cha/mẹ muốn chủ động báo cần giúp và chấp nhận dùng điện thoại hoặc một thiết bị trong danh sách thử nghiệm.

**Ưu tiên hai:** gia đình có hai hoặc nhiều người con cùng quan tâm nhưng thiếu cách phối hợp khi có việc. Giá trị cần kiểm chứng là biết ai đã nhận xử lý và giảm việc gọi hỏi chồng chéo.

**Tiếp cận sau:** gia đình ở ngoài vùng hỗ trợ, người cần chăm sóc chuyên sâu, cơ sở chăm sóc nhiều người, phòng khám hoặc bảo hiểm. Những nhóm này có thể có nhu cầu nhưng đòi hỏi vận hành và điều kiện sản phẩm khác. Chưa chọn B2B làm thị trường chính trong 90 ngày.

### 3.3 Động lực và rào cản cần kiểm chứng

| Câu hỏi của gia đình | Điều marketing cần làm rõ | Bằng chứng cần có |
| --- | --- | --- |
| Bố mẹ có dùng nổi không | Cho xem tác vụ thực tế, để cha mẹ tự thao tác | Quan sát sử dụng với người cao tuổi thật |
| Bấm SOS thì con có biết không | Giải thích trạng thái gửi và cách tiếp nhận | Ghi nhận thử nghiệm từ thiết bị tới điện thoại người thân |
| Có phải mua thêm đồng hồ không | Công khai lựa chọn dùng điện thoại và phần cần thiết bị đeo | Danh sách thiết bị và tính năng đã xác minh |
| Có theo dõi riêng tư quá không | Nói rõ dữ liệu, người được xem, quyền GPS/camera | Luồng giải thích và lựa chọn chia sẻ dễ hiểu |
| Mỗi tháng trả phí để được gì | Chứng minh giá trị theo dõi và phối hợp, công khai tổng chi phí | Phỏng vấn giá và hành vi tiếp tục sử dụng |
| Có cảnh báo sai, làm hoảng sợ không | Giải thích khả năng thiếu dữ liệu và cách kiểm tra | Nhật ký cảnh báo, phản hồi và lý do tắt thông báo |

## 4 Mô tả và định vị sản phẩm

### 4.1 Mô tả dùng cho hồ sơ dự án

CareAI là ứng dụng hỗ trợ gia đình chăm sóc người cao tuổi từ xa. Sản phẩm kết nối người cao tuổi với con cái hoặc người thân thông qua hồ sơ chăm sóc, dữ liệu từ thiết bị tương thích, tín hiệu SOS, cảnh báo và lịch sử sự cố. Gia đình có thể xem thông tin theo dõi, liên hệ người thân, xác nhận ai tiếp nhận và xem báo cáo tổng hợp. CareAI hướng tới thao tác đơn giản cho cha mẹ và thông tin dễ hiểu cho con cái. Các tính năng đang được hoàn thiện và cần kiểm chứng trên thiết bị thực tế trước khi mở rộng.

### 4.2 Mô tả ngắn cho lời mời dùng thử

CareAI giúp gia đình theo dõi thông tin của cha mẹ và phối hợp khi có tín hiệu cần giúp. Nhóm đang tuyển gia đình dùng thử tại khu vực có thể hỗ trợ cài đặt trực tiếp, để hoàn thiện thao tác cho người cao tuổi và cách nhận cảnh báo cho người thân.

### 4.3 Giá trị cần truyền đạt cho từng phía

- **Với cha mẹ:** có cách báo cần giúp dễ nhớ; giảm việc tự đọc nhiều thông số; hiểu ai đang được xem thông tin của mình.
- **Với người con:** có thêm thông tin để hỏi thăm và kiểm tra; biết dữ liệu có còn mới; cùng anh chị em tiếp nhận sự cố rõ ràng hơn.
- **Với gia đình:** nối thông tin theo dõi với hành động cụ thể như gọi điện, kiểm tra hoặc ghi nhận đã hỗ trợ.

Thông điệp cảm xúc kế thừa proposal là **“Chăm sóc từ xa, yêu thương gần hơn.”** Khi giới thiệu tính năng, đi kèm nội dung cụ thể: **“Xem thông tin cha mẹ, nhận tín hiệu cần giúp và biết ai đã tiếp nhận.”**

### 4.4 Điểm khác biệt nên kiểm chứng

Định hướng khác biệt của CareAI là quy trình chăm sóc trong gia đình Việt Nam: giao diện tiếng Việt, người thân hỗ trợ thiết lập, nhiều thành viên cùng theo dõi và thông tin gắn với bước hành động. Đây là giả thuyết định vị cần được người dùng xác nhận; chưa phải lợi thế độc quyền hoặc kết quả so sánh với toàn bộ thị trường.

Thay vì xếp hạng hãng đồng hồ hay tuyên bố đối thủ không có chức năng tương tự, hãy hỏi gia đình họ đang dùng gì: gọi điện, nhóm chat, tính năng có sẵn trên đồng hồ, ứng dụng sức khỏe hoặc người chăm sóc. Sau đó chứng minh CareAI giúp ích thêm ở bước nào và có đáng với công sức cài đặt hay không.

### 4.5 Giới hạn lời hứa truyền thông

| Nội dung dự định sử dụng | Cách diễn đạt có căn cứ |
| --- | --- |
| Cảnh báo SOS | Hỗ trợ gửi và theo dõi tín hiệu SOS; việc nhận thông báo phụ thuộc cấu hình, mạng và thiết bị |
| Cảm biến | Dữ liệu khả dụng theo thiết bị và quyền đã cấp; hiển thị thời điểm đo |
| AI | Hỗ trợ nhận định một số thay đổi dữ liệu và tổng kết bằng tiếng Việt |
| Tình trạng sức khỏe | Hiển thị thông tin đã ghi nhận và điều cần kiểm tra thêm |
| Phản ứng khẩn cấp | Người thân chủ động tiếp nhận và liên hệ; ứng dụng không tự tổ chức cứu hộ hoặc tự gọi cấp cứu |
| Dễ sử dụng | Thiết kế hướng tới người cao tuổi; chỉ công bố mức độ dễ dùng sau khi quan sát người dùng thật |

Không dùng các lời hứa như phát hiện mọi cú ngã, luôn theo dõi liên tục, thông báo chắc chắn tới máy ngay lập tức, chẩn đoán bệnh hoặc giảm tử vong khi chưa có bằng chứng tương ứng. Không lấy ảnh dữ liệu demo làm chứng cứ đo thật.

## 5 Phạm vi thị trường trong 90 ngày

### 5.1 Bối cảnh thị trường Việt Nam

Điều tra dân số giữa kỳ ghi nhận Việt Nam có **14,2 triệu người từ 60 tuổi trở lên tại thời điểm 01/04/2024**. Đây là số liệu dân số, cho thấy quy mô nhu cầu xã hội cần quan tâm; chưa phản ánh số gia đình có thiết bị phù hợp, muốn dùng CareAI hoặc sẵn sàng trả tiền. [Thông cáo thống kê chính thức](https://www.nso.gov.vn/du-lieu-va-so-lieu-thong-ke/2025/01/thong-cao-bao-chi-ket-qua-dieu-tra-dan-so-va-nha-o-giua-ky-nam-2024/)

UNFPA trong bài ngày 10/02/2026 tiếp tục nhấn mạnh già hóa dân số và nhu cầu phát triển dịch vụ tôn trọng lựa chọn, phẩm giá người cao tuổi. Bối cảnh này ủng hộ việc nghiên cứu sản phẩm; nhu cầu mua CareAI vẫn phải được kiểm chứng riêng. [UNFPA Việt Nam](https://vietnam.unfpa.org/en/news/population-ageing-viet-nam-demographic-transition-development-opportunity)

### 5.2 Địa bàn triển khai

Theo lựa chọn của nhóm, phạm vi ban đầu là **nơi nhóm có thể hỗ trợ trực tiếp**. Chọn một cụm địa bàn quanh nơi nhóm học tập hoặc sinh sống, đủ thuận tiện để hẹn cài đặt và quay lại khi gia đình gặp lỗi. Chưa ấn định thành phố khi nhóm chưa chọn địa điểm cụ thể.

Điều kiện địa bàn: có đầu mối tuyển gia đình, có lịch hỗ trợ được công bố và có khả năng theo dõi yêu cầu hỗ trợ. Người con có thể sống ở nơi khác; ưu tiên cha/mẹ ở trong vùng hỗ trợ. Không quảng bá hỗ trợ kỹ thuật 24/7 nếu nhóm chưa tổ chức được.

### 5.3 Phạm vi sản phẩm và thiết bị

Pilot tập trung vào tạo hồ sơ, ghép thiết bị, SOS, nhận và tiếp nhận sự cố, xem dữ liệu còn mới và đọc báo cáo khi đủ dữ liệu. Mỗi cấu hình điện thoại/đồng hồ phải được kiểm tra trước khi tuyển thêm gia đình dùng cấu hình đó.

Không buộc mọi gia đình mua đồng hồ chỉ để đánh giá luồng báo cần giúp. Có thể chia hai nhóm: điện thoại cho giá trị SOS/phối hợp và một nhóm nhỏ có đồng hồ phù hợp để đánh giá thêm cảm biến. Tính năng cảm biến không có trên điện thoại phải được giải thích riêng.

Google nêu rõ dữ liệu và khả năng Health Services khác nhau theo đồng hồ, dữ liệu thụ động có thể được gom lô. Vì vậy chưa có cơ sở hứa mọi thiết bị đều cung cấp dữ liệu liên tục như nhau. [Tương thích Wear OS](https://developer.android.com/health-and-fitness/health-services/compatibility)

### 5.4 Quy mô thử nghiệm theo khả năng hỗ trợ

Đề xuất tuyển **10–12 gia đình để phỏng vấn**, triển khai đợt đầu **5 gia đình**, sau đó tăng lên **10–15 gia đình hoạt động** nếu vận hành ổn. Mỗi gia đình nên có người cao tuổi và ít nhất một người thân tham gia; tuyển một số gia đình có hai người thân để đánh giá phối hợp.

Đây là quy mô nhỏ hơn khoảng 20–50 gia đình trong proposal, nhằm phù hợp với lựa chọn hỗ trợ trực tiếp và hạn chế mở rộng khi chưa kiểm chứng luồng cảnh báo. Nếu nhóm có thêm nhân lực và thiết bị, có thể nâng mục tiêu sau đợt đầu.

Quy mô phục vụ tối đa phải lấy giá trị nhỏ nhất của: số gia đình đạt điều kiện, số bộ thiết bị đã xác minh và số gia đình nhóm có thể cài đặt/hỗ trợ. Không lấy tổng dân số người cao tuổi nhân giá thuê bao để dự báo doanh thu 90 ngày.

| Lớp thị trường | Cách sử dụng trong giai đoạn này |
| --- | --- |
| Bối cảnh toàn quốc | Dùng số dân số để giải thích vấn đề xã hội, chưa tính thành thị trường doanh thu |
| Nhóm có thể phục vụ | Các gia đình tại địa bàn được chọn, đồng ý tham gia, có cấu hình phù hợp và mạng lưới người thân |
| Mục tiêu 90 ngày | 10–15 gia đình hoạt động theo năng lực hỗ trợ; đây là mục tiêu tuyển, chưa phải thị phần đã đạt |

## 6 Kế hoạch tiếp cận khách hàng

### 6.1 Kênh và vai trò

| Kênh dự kiến | Việc thực hiện | Mục tiêu cần đo |
| --- | --- | --- |
| Người quen, phụ huynh, gia đình trong mạng lưới nhóm | Mời phỏng vấn cả người con và cha/mẹ, hẹn demo trực tiếp | Số gia đình đúng tiêu chí, lý do nhận hoặc từ chối |
| Cộng đồng địa phương, câu lạc bộ người cao tuổi | Xin phép giới thiệu và tổ chức buổi hướng dẫn nhỏ | Số cuộc hẹn phù hợp và công sức hỗ trợ |
| Facebook, Zalo | Đăng nội dung ngắn trong cộng đồng phù hợp khi được cho phép | Cuộc trao đổi đủ điều kiện và lịch cài đặt |
| Video ngắn và trang giới thiệu | Minh họa một tình huống giả lập, trạng thái gửi và cách người thân tiếp nhận | Người xem hiểu đúng sản phẩm và đăng ký trao đổi |
| Giới thiệu từ gia đình đã dùng thử | Chỉ mời sau khi họ tự nguyện thấy hữu ích | Gia đình được giới thiệu có tiếp tục sử dụng không |

Chưa có đối tác hoặc chiến dịch nào được xác nhận trong tài liệu này. Nhóm chat Zalo có thể là kênh hỗ trợ thủ công của nhóm; không mô tả thành tính năng gửi cảnh báo Zalo tích hợp sẵn trong CareAI.

### 6.2 Nội dung marketing đề xuất

**Nội dung giải thích nhu cầu:** kể tình huống người con đi làm, cha/mẹ muốn báo cần giúp và gia đình cần biết ai đã nhận. Tránh tạo cảm giác cha mẹ có lỗi nếu không muốn bị theo dõi hoặc người con thiếu hiếu thảo nếu chưa mua sản phẩm.

**Nội dung hướng dẫn:** video khoảng một phút cho thấy bấm SOS, phân biệt chờ mạng với máy chủ đã nhận và cách người thân tiếp nhận. Video dùng tình huống giả lập phải gắn nhãn rõ; chỉ dùng giao diện đã sửa đúng trạng thái cho bản giới thiệu.

**Nội dung xây niềm tin:** giải thích dữ liệu nào được chia sẻ, thiết bị hỗ trợ, khi thiếu dữ liệu màn hình thể hiện ra sao và cách liên hệ nhóm hỗ trợ. Không đưa dữ liệu sức khỏe thật hoặc ảnh riêng tư vào nội dung marketing nếu chưa có sự đồng ý phù hợp.

**Lời mời mẫu:**

> Nhóm CareAI đang tìm gia đình tại khu vực có thể hỗ trợ cài đặt trực tiếp để cùng hoàn thiện ứng dụng chăm sóc cha mẹ từ xa. Gia đình sẽ dùng thử cách báo cần giúp, nhận thông tin và phối hợp giữa người thân. Nhóm mong được nghe ý kiến của cả cha mẹ và con cái về điều dễ dùng, điều gây khó hiểu và điều cần thay đổi. Đăng ký một buổi trao đổi để kiểm tra thiết bị và xem demo.

Lời mời này dùng để tuyển pilot; không trình bày dưới dạng lời chứng thực của khách hàng.

### 6.3 Hành trình tiếp cận

1. Gia đình biết đến CareAI và đăng ký trao đổi với thông tin liên hệ tối thiểu.
2. Nhóm kiểm tra nhu cầu, địa bàn hỗ trợ, thiết bị và sự đồng ý của cả hai phía.
3. Phỏng vấn ngắn, cho gia đình xem demo và tự quyết định tham gia.
4. Hỗ trợ ghép thiết bị, giải thích quyền, diễn tập nhận cảnh báo trên tài khoản thử nghiệm.
5. Hỏi lại sau vài ngày, ghi lỗi và công sức hỗ trợ; duy trì dùng thử trong 2–4 tuần.
6. Hỏi lý do tiếp tục/ngừng dùng và mức phí có thể cân nhắc; mời giới thiệu nếu gia đình tự nguyện.

Đơn vị theo dõi là **gia đình**, tránh đếm một cha/mẹ và hai người con thành ba khách hàng mua độc lập.

## 7 Mô hình giá và ngân sách thử nghiệm

### 7.1 Giá là giả thuyết cần kiểm chứng

Proposal đưa giá Premium tham khảo 99.000 đồng/tháng, khoảng thử 79.000–149.000 đồng; Family Plan 199.000–299.000 đồng/tháng. Đây chưa phải giá được khách hàng chấp nhận hoặc bảng giá đã triển khai.

Trong pilot đầu, nên cho gia đình trải nghiệm bộ chức năng cốt lõi thống nhất. Sau khi họ hiểu giá trị, có thể lần lượt hỏi về 79.000, 99.000 và 149.000 đồng/tháng cho cùng một cấu hình dịch vụ đã mô tả rõ. Không thay đổi cả tính năng lẫn mức giá trong cùng câu hỏi rồi kết luận chênh lệch do giá.

Ghi riêng bốn loại bằng chứng: người nói có hứng thú, người đồng ý tiếp tục, người chấp nhận một mức giá và người thực sự thanh toán. Không chuyển câu trả lời “có thể trả” thành doanh thu dự kiến chắc chắn. Nếu chưa triển khai thanh toán thì chỉ báo cáo ý định và hành vi dùng tiếp.

Tổng chi phí cho gia đình cần nêu riêng: thuê bao phần mềm, điện thoại/đồng hồ nếu phải mua, kết nối dữ liệu và công sức cài đặt. Chỉ thử bán sau khi xác định rõ sản phẩm cung cấp, cách hỗ trợ và điều kiện áp dụng.

### 7.2 Ngân sách marketing 90 ngày đề xuất

| Hạng mục | Khoản dự trù |
| --- | ---: |
| Đi lại và hỗ trợ buổi phỏng vấn/cài đặt | 1.200.000 đồng |
| Hướng dẫn in và vật liệu demo | 300.000 đồng |
| Nội dung ngắn và trang đăng ký | 500.000 đồng |
| Quảng cáo quy mô nhỏ sau khi nội dung đã được kiểm chứng | 1.000.000 đồng |
| Dự phòng | 500.000 đồng |
| **Tổng giả định** | **3.500.000 đồng** |

Khoản này nằm trong khoảng marketing tham khảo của proposal, chưa được chi. Không bao gồm lương, máy chủ, mua đồng hồ hoặc phí dịch vụ bên thứ ba. Nếu kênh người quen đủ tuyển pilot thì giữ lại ngân sách quảng cáo. Chi phí trên mỗi gia đình trả phí chỉ tính được khi có thanh toán thật; trước đó theo dõi chi phí tuyển và kích hoạt gia đình.

## 8 Lộ trình 90 ngày và tiêu chí quyết định

Mốc ngày tính từ khi nhóm bắt đầu triển khai kế hoạch, chưa phải lịch đã cam kết.

| Giai đoạn | Công việc | Đầu ra cần có |
| --- | --- | --- |
| Ngày 1–14 | Chọn địa bàn, phỏng vấn 10–12 gia đình, ghi cách họ đang chăm sóc và điều cha/mẹ chấp nhận chia sẻ | Danh sách nhu cầu, rào cản, cấu hình thiết bị và gia đình muốn tiếp tục |
| Ngày 15–30 | Sửa vấn đề P0 trong tài liệu đánh giá; xác minh cảnh báo; triển khai 5 gia đình đầu | Hướng dẫn cài đặt, danh sách thiết bị đã kiểm tra, lỗi và thời gian hỗ trợ |
| Ngày 31–60 | Cho dùng 2–4 tuần, mở từng đợt lên 10–15 gia đình khi hỗ trợ được | Dữ liệu hoàn thành tác vụ, hiểu trạng thái, phản hồi cảnh báo và lý do ngừng dùng |
| Ngày 61–90 | Cải tiến từ phản hồi, hỏi giá, mời tiếp tục dùng; tổng kết kinh tế hỗ trợ | Quyết định tiếp tục cùng phân khúc, thu hẹp phạm vi hoặc mở rộng một đợt nhỏ |

### 8.1 Mục tiêu kiểm chứng

Các ngưỡng sau là đề xuất nội bộ ban đầu, chưa phải kết quả hay chuẩn chứng nhận:

| Chỉ số | Cách đo | Mục tiêu để cân nhắc mở rộng |
| --- | --- | --- |
| Thiết lập thành công | Gia đình ghép đúng hồ sơ và hoàn thành diễn tập / gia đình bắt đầu cài | Ít nhất 8/10 gia đình; ghi riêng cần hỗ trợ ở bước nào |
| Tác vụ chính của người cao tuổi | Tự tìm SOS và xử lý màn đếm ngược giả lập sau hướng dẫn / số người thử | Ít nhất 8/10; không còn lỗi nhầm trạng thái gửi nghiêm trọng |
| Hiểu cảnh báo | Người thân nói đúng trạng thái dữ liệu, người tiếp nhận và hành động kế tiếp / số người thử | Ít nhất 8/10 |
| Dùng tiếp | Gia đình chủ động muốn dùng tiếp sau tối thiểu 2 tuần / gia đình hoàn tất pilot | Ít nhất 6/10; ghi đủ lý do của người dừng |
| Nhu cầu chi trả | Số gia đình chấp nhận từng mức giá, và số thanh toán thật nếu có | Báo bằng số đếm và bằng chứng; chưa áp tỷ lệ thị trường từ mẫu nhỏ |
| Công sức hỗ trợ | Phút cài đặt và số lượt hỗ trợ mỗi gia đình mỗi tuần | Có xu hướng giảm sau khi sửa hướng dẫn và lỗi lặp |
| Khả năng truyền cảnh báo | Đối chiếu sự kiện tạo, máy chủ nhận, điện thoại nhận và người thân tiếp nhận trong diễn tập | Báo số lần thành công/tổng lần, độ trễ và lỗi theo từng cấu hình |

Không dùng số lần SOS tăng lên làm chỉ số thành công marketing. Mục đích là phối hợp tốt hơn và hiểu đúng cảnh báo, không khuyến khích tạo thêm tình huống khẩn.

### 8.2 Điều kiện ra quyết định

**Tiếp tục pilot nhỏ** nếu gia đình thấy hữu ích nhưng còn vướng cài đặt, hiểu dữ liệu hoặc công sức hỗ trợ. **Thu hẹp phạm vi** nếu một loại thiết bị hoặc tính năng chưa ổn. **Mở rộng một đợt** khi đã xác minh luồng cảnh báo, người dùng hiểu đúng trạng thái và nhóm đủ khả năng hỗ trợ.

Chưa chạy quảng cáo rộng khi còn thông báo thành công sai, dữ liệu minh họa dễ bị hiểu là thật hoặc chưa kiểm tra được đường cảnh báo tới máy người thân. Những điểm này ảnh hưởng trực tiếp đến điều CareAI đang hứa với gia đình.

## 9 Nguồn và tài liệu đối chiếu

### Tài liệu nội bộ

- [N1 Proposal CareAI EXE101 Bug Buck V2](../../CareAI_Proposal_EXE101_Bug_Buck_V2.docx): định hướng khách hàng, mô hình giá, phạm vi MVP và marketing.
- [N2 README repository](../../README.md), [README Flutter](../../CareAI/companion_app/README.md), [README Wear OS](../../CareAI/wearos/README.md), [README watchOS](../../CareAI/watchos/README.md): tài liệu mô tả; README Flutter hiện là mẫu giới thiệu Flutter. [README trên GitHub](https://github.com/taithptqt/CareAI/blob/4c85f0b4dfd43f7e19f23e6a8b51d6c50df4e4a7/README.md).
- [N3 Program.cs](../../CareAI/src/CareAI.API/Program.cs): đăng ký FCM dòng 57, anomaly dòng 75–76 và báo cáo tuần dòng 78–96.
- [N4 FirebasePushSender.cs](../../CareAI/src/CareAI.Infrastructure/Notifications/FirebasePushSender.cs): gửi SDK dòng 63; [NotificationDispatchEngine.cs](../../CareAI/src/CareAI.Infrastructure/Notifications/NotificationDispatchEngine.cs): ý nghĩa `SENT` dòng 162.
- [N5 FamilyController.cs](../../CareAI/src/CareAI.API/Controllers/FamilyController.cs), [IncidentsController.cs](../../CareAI/src/CareAI.API/Controllers/IncidentsController.cs): quyền thành viên và vòng đời tiếp nhận/đóng sự cố.
- [N6 DashboardController.cs](../../CareAI/src/CareAI.API/Controllers/DashboardController.cs): dữ liệu demo dòng 128; suy ra giấc ngủ sâu dòng 482, số lần thức dòng 484 và nhãn chất lượng dòng 503.
- [N7 TimeSeriesAnomalyDetector.cs](../../CareAI/src/CareAI.Infrastructure/AnomalyDetection/TimeSeriesAnomalyDetector.cs), [GeminiWeeklyReportClient.cs](../../CareAI/src/CareAI.Infrastructure/WeeklyReports/GeminiWeeklyReportClient.cs), [WeeklyReportService.cs](../../CareAI/src/CareAI.Infrastructure/WeeklyReports/WeeklyReportService.cs): phạm vi nhận định và báo cáo.
- [N8 Hướng dẫn cấu trúc](../../HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md), [README phần AI](../README-part4.md), [README anomaly](../README-anomaly-detection.md): dùng làm bối cảnh; số kiểm thử lịch sử không phải kết quả hiện tại.
- [Đánh giá phản hồi giả lập và cải tiến](./CAREAI_FEEDBACK_GIA_LAP_VA_CAI_TIEN.md): các vấn đề cần giải quyết trước và trong pilot.

### Nguồn bên ngoài

- [Cơ quan thống kê quốc gia về Điều tra dân số giữa kỳ 2024](https://www.nso.gov.vn/du-lieu-va-so-lieu-thong-ke/2025/01/thong-cao-bao-chi-ket-qua-dieu-tra-dan-so-va-nha-o-giua-ky-nam-2024/): thời điểm dữ liệu 01/04/2024.
- [UNFPA Việt Nam về già hóa dân số](https://vietnam.unfpa.org/en/news/population-ageing-viet-nam-demographic-transition-development-opportunity): bài ngày 10/02/2026.
- [Android Developers về khả năng tương thích Health Services](https://developer.android.com/health-and-fitness/health-services/compatibility): căn cứ để giới hạn lời hứa về dữ liệu đồng hồ.

Chưa chạy build, test, analyze hoặc thử thiết bị trong công việc lập tài liệu này. Chưa liên hệ, gửi nội dung marketing hoặc tuyển người tham gia thực tế.
