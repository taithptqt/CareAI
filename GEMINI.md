# CAREAI CORE INSTRUCTION & MANDATORY COMMITMENT CONTRACT

> **QUY TẮC TỐI THƯỢNG CỦA DỰ ÁN**:
> Trước khi thực hiện BẤT KỲ yêu cầu nào trong dự án CareAI, Agent BẮT BUỘC phải đọc và đối chiếu với file cam kết:
> `d:\IT\PRACTICE\CAM_KET_NGUYEN_TAC_TRIEN_KHAI_CAREAI.md`

## ĐIỀU KHOẢN TỐI CAO:
0. **CHỈ LÀM THEO NHỮNG GÌ USER YÊU CẦU & CHÍNH XÁC 100%**:
   - AI tuyệt đối KHÔNG được tự ý "cầm đèn chạy trước ô tô", không tự ý tải, cài đặt, viết code hay chỉnh sửa khi chưa được User chỉ thị rõ ràng.
   - User yêu cầu đến đâu thì tập trung làm chuẩn chỉ, triệt để đến đó. Không tự ý suy diễn hoặc làm lố.
   - Mọi câu trả lời, giải thích và dòng mã phải chính xác 100%. Nếu có điểm nào chưa rõ, BẮT BUỘC phải hỏi lại User, không được tự ý phán đoán liều lĩnh.
   - Khi hoàn thành xong yêu cầu của User trong lượt chat, DỪNG LẠI báo cáo và chờ chỉ thị tiếp theo.
   - BẮT BUỘC ĐỌC VÀ TỰ ĐỘNG CẬP NHẬT TIẾN TRÌNH: Đọc file `d:\IT\PRACTICE\TIEN_TRINH_DU_AN_CAREAI.md` trước khi làm việc và tự động cập nhật tiến độ, nhật ký sau mỗi lượt làm việc.
   - BẮT BUỘC ĐỌC VÀ TỰ ĐỘNG CẬP NHẬT SỔ TAY KINH NGHIỆM: Đọc file `d:\IT\PRACTICE\SO_TAY_KINH_NGHIEM_DEV_VA_FIX_LOI_CAREAI.md` trước khi xử lý kỹ thuật hoặc khi gặp lỗi; sau mỗi phiên làm việc nếu có bài học mới phải cập nhật ngay vào sổ tay.

## 5 ĐIỀU CẤM & BẤT BIẾN BẮT BUỘC:
1. **CẤM TỰ Ý MỞ RỘNG PHẠM VI (ANTI-SCOPE CREEP)**: Chỉ tập trung 100% vào 16 Use Case đã chốt. Tuyệt đối không vẽ thêm Microservices, Kafka, RabbitMQ, Redis, Kubernetes hay ví điện tử ngoài lề. Giữ vững Sovereign Modular Monolith (.NET 9 LTS).
2. **CẤM DÙNG PACKAGE PREVIEW (ZERO-PREVIEW)**: Bắt buộc dùng phiên bản ổn định LTS (.NET 9.0 LTS, EF Core 9.0.2). Không kéo bất kỳ package rc/preview/beta nào.
3. **CẤM VIẾT CODE GIẢ HOẶC CODE CỤT**: Mọi code viết ra phải build được thật (`dotnet build` 0 warning, 0 error), test pass thật (36/36 Facts Passed), không để `// TODO: implement later` ở các luồng cấp cứu sống còn.
4. **TUÂN THỦ 100% CÁC BẤT BIẾN KỸ THUẬT**:
   - `DeviceTokenHash` trong CSDL và Middleware phải dùng `.ToLowerInvariant()`.
   - Header HTTP xác thực thiết bị phải là `X-DeviceId` (không có gạch nối).
   - Bộ lọc trùng lặp chỉ bắt trên `ProcessedTelemetryLedgers`.
   - Giữ nguyên Filtered Unique Index `UIX_Incidents_SingleActiveElder` trên `Incidents`.
   - Gói Fast-Lane SOS bắt buộc lưu toàn bộ mẫu đo sinh hiệu đi kèm vào CSDL (Bất biến Fact 35).
   - Native Android dùng `Device Protected Storage` (Direct Boot) và `AlarmManager.RTC_WAKEUP`.
5. **KỶ LUẬT LÀM VIỆC TỪNG BƯỚC**:
   - Làm xong bước nào nghiệm thu chắc chắn bước đó, không làm ào ào một lúc gây lỗi.
   - Luôn phân định minh bạch giữa kiểm thử giả lập và thiết bị thật ngoài đời.
