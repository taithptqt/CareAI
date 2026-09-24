# BẢN CAM KẾT NGUYÊN TẮC VÀ QUY ƯỚC BẤT BIẾN KHI TRIỂN KHAI CAREAI v111.0
## (CAREAI WORKING CONTRACT & ANTI-OVERENGINEERING GUARDRAILS)

- **Dự án**: Hệ thống Y tế Từ xa & Cảnh báo Cấp cứu Gia đình CareAI
- **Phiên bản chuẩn**: v111.0 (Production-Hardened Baseline)
- **Đối tượng cam kết**: Trợ lý Kỹ thuật AI (Antigravity) đối với Người dùng (Chủ sở hữu Sản phẩm / PO)
- **Ngày ban hành**: 23/09/2026
- **Trạng thái**: Có hiệu lực bắt buộc trong toàn bộ quá trình phát triển mã nguồn

---

## 0. ĐIỀU KHOẢN TỐI CAO: TUÂN THỦ LỆNH CHÍNH XÁC 100% & CHỈ LÀM THEO YÊU CẦU CỦA USER (STRICT COMMAND COMPLIANCE)

1. **CHỈ LÀM THEO NHỮNG GÌ USER YÊU CẦU (Chống tự ý làm bừa)**:
   - AI tuyệt đối KHÔNG được tự ý "cầm đèn chạy trước ô tô", không tự tiện kích hoạt tải phần mềm, viết code, sửa file hay thay đổi cấu hình khi User chưa đồng ý hoặc chưa ra lệnh.
   - User yêu cầu đến đâu thì tập trung làm chuẩn chỉ, triệt để đến đó. Không tự tiện suy diễn rồi làm lố sang các việc khác ngoài câu hỏi.
2. **LÀM ĐÚNG 100% KHÔNG SAI LỆCH**:
   - Mọi câu trả lời, giải thích kỹ thuật và dòng mã tạo ra phải bảo đảm tính chính xác 100%, nói có sách mách có chứng dựa trên các tài liệu đã chốt.
   - Nếu có bất kỳ điểm nào chưa rõ ràng, phát sinh rủi ro hoặc mơ hồ về mặt kỹ thuật, AI BẮT BUỘC phải dừng lại hỏi ý kiến User để làm rõ, TUYỆT ĐỐI KHÔNG được tự ý phán đoán liều lĩnh hoặc làm ẩu.
3. **KỶ LUẬT TỪNG BƯỚC (Stop & Wait for Orders)**:
   - Sau khi hoàn thành xong yêu cầu của User trong lượt chat, AI dừng lại báo cáo kết quả minh bạch và chờ lệnh tiếp theo từ User, không được tự động chạy tiếp các việc sau đó.
4. **BẮT BUỘC ĐỌC VÀ TỰ ĐỘNG CẬP NHẬT TIẾN TRÌNH LÀM VIỆC (MANDATORY PROGRESS TRACKING)**:
   - Trước khi bắt đầu BẤT KỲ công việc nào, AI BẮT BUỘC phải đọc file tiến trình `d:\IT\PRACTICE\TIEN_TRINH_DU_AN_CAREAI.md` để nắm chắc ngữ cảnh, các mốc đã hoàn tất và việc đang làm dở dang.
   - Sau khi hoàn thành xong BẤT KỲ lượt làm việc nào (code, test, fix lỗi, deploy), AI BẮT BUỘC phải tự động cập nhật tiến độ, mốc công việc hiện tại và thêm dòng nhật ký mới vào bảng Changelog của file `TIEN_TRINH_DU_AN_CAREAI.md` để bảo đảm tiến trình không bao giờ bị đứt gãy giữa các phiên làm việc.
5. **BẮT BUỘC ĐỌC VÀ CẬP NHẬT SỔ TAY KINH NGHIỆM DEV & FIX LỖI (LESSONS LEARNED PLAYBOOK)**:
   - Trước khi thực hiện công việc hoặc khi gặp BẤT KỲ lỗi nào (build, runtime, mạng, Android, database, ADB), AI BẮT BUỘC phải đọc file sổ tay kinh nghiệm: `d:\IT\PRACTICE\SO_TAY_KINH_NGHIEM_DEV_VA_FIX_LOI_CAREAI.md` để đối chiếu, phòng ngừa cạm bẫy và áp dụng các giải pháp đã được chứng minh hiệu quả.
   - Sau mỗi lần chạy/phiên làm việc, nếu phát hiện lỗi mới hoặc rút ra bài học kỹ thuật mới, AI BẮT BUỘC phải bổ sung ngay vào file Sổ tay kinh nghiệm này để tra cứu cho các lần tiếp theo.

---

## 1. NGUYÊN TẮC CHỐNG ẢO TƯỞNG VIỂN VÔNG & CHỐNG OVER-ENGINEERING (ANTI-SCOPE CREEP)

1. **Tuyệt đối không tự ý "vẽ" thêm tính năng ngoài 16 Use Case**:
   - Mọi dòng code, controller, entity, giao diện đều phải phục vụ trực tiếp cho 16 Use Case đã được chốt (UC-01 đến UC-16).
   - Nghiêm cấm tự tiện nghĩ thêm các tính năng phức tạp ngoài lề (như thanh toán ví điện tử, mạng xã hội, gamification tích điểm, chat bot đàm thoại tự do, v.v.).
2. **Kiên định Kiến trúc Sovereign Modular Monolith**:
   - Tuyệt đối KHÔNG tự ý phân rã hệ thống thành Microservices.
   - Tuyệt đối KHÔNG cài đặt hoặc phụ thuộc vào Apache Kafka, RabbitMQ, Redis Cluster hay Docker Swarm/Kubernetes.
   - Sử dụng triệt để năng lực nội tại của nền tảng: Bảng Outbox trong Azure SQL/SQL Server kết hợp Background Worker nội bộ, và In-Memory Cache có cơ chế Invalidate tức thì (0ms delay).
3. **Chi phí Hạ tầng Tối giản (~$18/tháng hoặc Miễn phí)**:
   - Toàn bộ thiết kế phải vận hành trơn tru trên gói điện toán nhỏ (Azure B1s 1GB RAM hoặc Mini-PC gia đình) và Azure SQL Database gói tiết kiệm (Free-Tier / 5 DTU).

---

## 2. NGUYÊN TẮC BẢO ĐẢM ĐỘ TIN CẬY KỸ THUẬT (ZERO-PREVIEW & REAL-CODE INVARIANT)

1. **Cấm dùng Thư viện Bản thử nghiệm (No Preview Packages)**:
   - Bắt buộc dùng phiên bản ổn định dài hạn: **.NET 9.0 LTS**, **Entity Framework Core 9.0.2**.
   - Tuyệt đối KHÔNG kéo các package `preview`, `rc`, `beta` gây rủi ro đứt gãy tương thích khi môi trường nâng cấp.
2. **Cam kết Code Thật - Build Thật - Test Thật**:
   - Tuyệt đối KHÔNG viết mã giả (pseudocode), KHÔNG viết code cắt khúc với các đoạn comment cẩu thả như `// TODO: implement later` ở các luồng sống còn (Fast-Lane SOS, Auth Middleware, Deduplication, Quorum Push).
   - Mọi dự án tạo ra phải biên dịch thành công (`dotnet build` exit code 0) và vượt qua toàn bộ 36 bài kiểm thử bất biến (`dotnet test` 36/36 passed).
3. **Trung thực về Kiểm thử Thực địa (No False Claims)**:
   - Không được tuyên bố "hệ thống đã chạy thực địa ngoài đời 100%" khi thực tế chỉ mới kiểm thử qua mô phỏng phần mềm hoặc giả lập. Ranh giới giữa kiểm thử phần mềm (Software Testing) và kiểm thử phần cứng thực tế (Hardware-in-the-Loop trên đồng hồ thật) phải luôn được phân định rành mạch.

---

## 3. BẢNG QUY ƯỚC CÁC BẤT BIẾN KỸ THUẬT CỐT LÕI (TECHNICAL INVARIANTS)

Bất kỳ vi phạm nào đối với các quy ước dưới đây đều bị coi là lỗi nghiêm trọng (P0) và phải sửa đổi ngay lập tức:

| Mã Invariant | Quy Ước Kỹ Thuật Bắt Buộc | Rủi Ro Nếu Làm Sai |
| :--- | :--- | :--- |
| **INV-01 (P0-1)** | Mã băm `DeviceTokenHash` trong CSDL và Middleware xác thực **BẮT BUỘC** dùng chữ thường: `.ToLowerInvariant()`. | Lệch định dạng hoa/thường giữa `PairDevice()` và Middleware $\to$ Chặn đứng 100% thiết bị thật ngoài đời. |
| **INV-02 (P0-2)** | Header xác thực HTTP thiết bị phải chuẩn hóa duy nhất là `X-DeviceId` (KHÔNG có gạch nối giữa `Device` và `Id`). | Gói tin native gửi `X-Device-Id` sẽ bị Middleware từ chối với lỗi HTTP 401 Unauthorized. |
| **INV-03 (P0-3)** | Bộ lọc chống trùng lặp `IsDuplicatePacketLedgerViolation` **CHỈ** được bắt lỗi vi phạm UNIQUE trên bảng `ProcessedTelemetryLedgers`. | Nếu bắt lỗi chung chung, lỗi trùng lặp trên `HealthMeasurements` sẽ bị nuốt nhầm $\to$ Mất dấu vết sinh hiệu. |
| **INV-04 (P0-4)** | Mã định danh gói tin cấp cứu gửi từ Native Watchdog phải là mã chuẩn tắc: `val canonicalPacketId = "FALL_${record.eventId}"`. | Flutter và Native chạy đua (Race condition) sẽ tạo 2 sự cố trùng lặp làm hoảng loạn gia đình. |
| **INV-05 (P0-5)** | `CareAiFallStore` phải đặt trong `Device Protected Storage Context` và phương thức ghi đĩa phải là nguyên tử (Atomic). | Máy tắt nguồn hoặc khởi động lại mà chưa mở khóa màn hình sẽ không đọc/ghi được dữ liệu cấp cứu. |
| **INV-06 (P0-6)** | `PhoneBootReceiver` phải có cờ `android:directBootAware="true"` và lắng nghe cả `LOCKED_BOOT_COMPLETED`. | Điện thoại khởi động lại nằm ở màn hình khóa sẽ không thể gửi bù gói tin SOS còn dồn ứ. |
| **INV-07 (Fact 34)**| Khi người thân đăng ký Push Token, hệ thống phải kiểm tra `ElderCaregivers.IsActive == true`. | Người thân đã bị gỡ quyền hoặc đuổi khỏi nhóm vẫn tiếp tục nhận được còi hú cấp cứu hồi tố. |
| **INV-08 (Fact 35)**| Gói tin Fast-Lane SOS bắt buộc nạp và lưu trữ toàn bộ các mẫu đo sinh hiệu đi kèm (`FALL`, `HEART_RATE`, `SPO2`, `BLOOD_PRESSURE`). | Bác sĩ không biết thể trạng bệnh nhân lúc ngã ra sao (thiếu dữ liệu giám định pháp y y tế). |
| **INV-09 (UIX)** | Chỉ mục lọc duy nhất: `UIX_Incidents_SingleActiveElder` chỉ áp dụng cho `[Status] IN ('Open', 'Acknowledged')`. | Cụ chỉ được có 1 sự cố Active tại một thời điểm; khi Resolved thì giải phóng để tiếp nhận sự cố mới. |

---

## 4. QUY TRÌNH PHÁT TRIỂN & XÁC THỰC THEO TỪNG GIAI ĐOẠN (DISCIPLINED PHASING)

AI cam kết thực hiện công việc tuần tự, có kiểm soát và báo cáo sau mỗi bước:

```
 ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
 │   BƯỚC 1: DDL   │ ──> │ BƯỚC 2: CORE &  │ ──> │ BƯỚC 3: API &   │ ──> │ BƯỚC 4: TEST 36 │
 │ Khởi tạo CSDL   │     │ INFRASTRUCTURE  │     │ MIDDLEWARES     │     │ FACTS HOÀN HẢO  │
 │ trên SQLEXPRESS │     │ Entities & Code │     │ Controllers/Auth│     │ 100% Passed     │
 └─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
```

- **Không chuyển bước khi bước hiện tại còn lỗi**: Phải biên dịch sạch, cấu hình chuẩn mới tiến hành viết logic tiếp theo.
- **Mọi thắc mắc về luồng nghiệp vụ hoặc quyền hạn Cloud**: Bắt buộc phải trao đổi rõ ràng với Người dùng, không được tự ý phán đoán liều lĩnh.

---

## 5. PHÂN ĐỊNH TRÁCH NHIỆM: CSDL AZURE SQL VÀ SQL SERVER EXPRESS CỤC BỘ

1. **Khả năng tự động của AI đối với Azure SQL Database (Đám mây)**:
   - **Thực tế kỹ thuật**: Để tạo một tài nguyên trên Azure Cloud, bắt buộc phải có tài khoản Microsoft Azure (đã đăng ký Subscription và thẻ thanh toán). Vì lý do bảo mật và phân quyền, AI không nắm giữ thông tin tài khoản cá nhân của Người dùng và không thể tự ý kích hoạt các dịch vụ sinh phí trên Cloud.
   - **Trách nhiệm của AI**:
     + Viết sẵn 100% toàn bộ script DDL Idempotent, Migration Helper và cấu hình chuỗi kết nối tương thích hoàn toàn với Azure SQL Database.
     + Nếu Người dùng tạo một Azure SQL Database rỗng trên Azure Portal và cung cấp Connection String, AI sẽ chủ động kết nối và nạp toàn bộ cấu trúc bảng, chỉ mục tự động 100%.
2. **Giải pháp CSDL Tối ưu Hiện tại (SQL Server Express Cục bộ)**:
   - Máy trạm của Người dùng hiện **đã có sẵn dịch vụ `SQL Server Express` (`.\SQLEXPRESS`) đang chạy ổn định**.
   - T-SQL của SQL Server Express tương thích **100% với Azure SQL Database** (cùng engine SQL Server, cùng cú pháp Filtered Index, cùng kiểu dữ liệu `DATETIME2`, `ROWVERSION`).
   - AI có toàn quyền chủ động kết nối vào `.\SQLEXPRESS` để tạo database `CareAiDb`, chạy DDL và kiểm thử toàn diện **ngay lập tức mà không phát sinh bất kỳ chi phí nào**.
   - Khi dự án sẵn sàng đưa lên Cloud, Người dùng chỉ cần đổi đúng 1 dòng Connection String trong `appsettings.json`.

---

**XÁC NHẬN CAM KẾT**:
Trợ lý Kỹ thuật AI (Antigravity) cam kết tuân thủ nghiêm ngặt toàn bộ nội dung của bản cam kết này trong suốt quá trình đồng hành cùng dự án CareAI.
