# -*- coding: utf-8 -*-
import sys
import os
import docx_helper

def generate_volume_1():
    sys.stdout.reconfigure(encoding='utf-8')
    print("=== ĐANG KHỞI TẠO TẬP 1: CHIẾN LƯỢC, KIẾN TRÚC, 16 USE CASE & KẾ HOẠCH TRIỂN KHAI ===")
    
    doc = docx_helper.create_styled_document()
    
    # 1. TRANG BÌA
    docx_helper.add_cover_page(
        doc,
        volume_num="1",
        volume_title="QUY HOẠCH CHIẾN LƯỢC, KIẾN TRÚC HỆ THỐNG,\nĐẶC TẢ 16 USE CASE & KẾ HOẠCH TRIỂN KHAI THỰC ĐỊA",
        subtitle="Hệ thống Y tế Từ xa & Cảnh báo Cấp cứu Gia đình Thông minh CareAI v111.0\n(Sovereign Modular Monolith · Assistive Alerting Platform · Field-Hardened)",
        roles_target="Product Owner, Solution Architect, Medical & Legal Advisor, Project Manager, QA Lead, DevOps Lead",
        metadata_list=[
            ("Mã tài liệu", "CAREAI-DOC-VOL1-v111.0"),
            ("Phiên bản", "v111.0 (Definitive Production-Hardened Edition)"),
            ("Ngày hoàn thiện", "23/09/2026"),
            ("Đơn vị phát triển", "CareAI Core Engineering Team"),
            ("Trạng thái", "Chính thức ban hành · Đã đóng sổ 34 điểm kiểm toán"),
            ("Định vị an toàn", "Assistive Alerting Platform (Non-SaMD)")
        ]
    )
    
    # MỤC LỤC TỔNG QUAN
    docx_helper.add_heading_1(doc, "MỤC LỤC TỔNG QUAN TẬP 1")
    toc_items = [
        ("PHẦN I", "TỔNG QUAN CHIẾN LƯỢC, ĐỊNH VỊ SẢN PHẨM & TUYÊN BỐ PHÁP LÝ"),
        ("PHẦN II", "ĐẶC TẢ CHI TIẾT 16 USE CASE CHỨC NĂNG & MA TRẬN SINH HIỆU (USE CASE & METRICS)"),
        ("PHẦN III", "KIẾN TRÚC HỆ THỐNG TỔNG THỂ (BACKEND & FRONTEND ARCHITECTURE)"),
        ("PHẦN IV", "CÔNG NGHỆ, TIÊU CHUẨN KỸ THUẬT & AN TOÀN THÔNG TIN"),
        ("PHẦN V", "KẾ HOẠCH THỰC HIỆN, LỘ TRÌNH TRIỂN KHAI & QUẢN TRỊ DỰ ÁN"),
        ("PHẦN VI", "CÁC KẾ HOẠCH BỔ TRỢ: ĐẢM BẢO CHẤT LƯỢNG (QA), VẬN HÀNH & ĐÀO TẠO")
    ]
    docx_helper.add_styled_table(doc, ["Phần", "Nội dung Trọng tâm"], toc_items, col_widths=[1.5, 5.0])
    doc.add_page_break()
    
    # =========================================================================
    # PHẦN I
    # =========================================================================
    docx_helper.add_heading_1(doc, "PHẦN I: TỔNG QUAN CHIẾN LƯỢC, ĐỊNH VỊ SẢN PHẨM & TUYÊN BỐ PHÁP LÝ")
    
    docx_helper.add_heading_2(doc, "1.1 Tầm Nhìn Dự Án & Tuyên Bố Định Vị Trợ Năng (Non-SaMD Boundary)")
    docx_helper.add_paragraph(doc, 
        "Dự án CareAI được xây dựng với sứ mệnh trở thành người trợ lý số đồng hành cùng gia đình Việt Nam trong việc bảo vệ và chăm sóc sức khỏe người cao tuổi từ xa. Trong bối cảnh già hóa dân số nhanh chóng và khoảng cách địa lý giữa các thế hệ gia đình ngày càng tăng, CareAI cung cấp giải pháp cảnh báo sớm, phát hiện té ngã và giám sát các chỉ số sinh hiệu viễn trắc thông qua sự kết hợp giữa thiết bị đeo thông minh (Samsung Galaxy Watch chạy Wear OS) và điện thoại thông minh (Companion Phone).",
        bold_prefix="Bối cảnh & Tầm nhìn: ")
    
    docx_helper.add_callout(doc, 
        "CareAI là một Nền tảng Hỗ trợ Cảnh báo Chăm sóc Người cao tuổi (Caregiver Assistive Alerting Platform), TUYỆT ĐỐI KHÔNG PHẢI là Thiết bị Y tế Chẩn đoán Chuyên sâu (Not a Software as a Medical Device - SaMD) theo định nghĩa của Cục Quản lý Thực phẩm và Dược phẩm Hoa Kỳ (FDA) và Nghị định 98/2021/NĐ-CP của Chính phủ Việt Nam về quản lý trang thiết bị y tế.\n\n"
        "Mọi dữ liệu sinh hiệu (Nhịp tim, Huyết áp, SpO2, Gia tốc) và các thông báo cảnh báo do hệ thống phát ra chỉ mang tính chất tham khảo trợ giúp người thân đưa ra quyết định can thiệp kịp thời, không có giá trị thay thế cho chẩn đoán y khoa chuyên môn, chỉ định điều trị hoặc phác đồ từ bác sĩ có chứng chỉ hành nghề.",
        title="TUYÊN BỐ RANH GIỚI Y TẾ PHÁP LÝ BẮT BUỘC (MANDATORY NON-SAMD DISCLAIMER)",
        alert_type="danger")
    
    docx_helper.add_heading_2(doc, "1.2 Khung Pháp Lý & Chính Sách Bảo Vệ Dữ Liệu Cá Nhân")
    docx_helper.add_paragraph(doc, 
        "Hệ thống CareAI thiết lập các biện pháp kỹ thuật và tổ chức nhằm tuân thủ chặt chẽ các quy định pháp luật hiện hành về an ninh mạng và bảo vệ dữ liệu:",
        bold_prefix="Cam kết Tuân thủ Pháp luật: ")
    
    docx_helper.add_bullet(doc, "Tuân thủ Nghị định 13/2023/NĐ-CP của Chính phủ Việt Nam về Bảo vệ Dữ liệu Cá nhân (PDPD). Dữ liệu sinh hiệu và hồ sơ y tế người cao tuổi được xếp vào danh mục 'Dữ liệu cá nhân nhạy cảm'. Hệ thống bắt buộc phải thu thập sự đồng thuận minh bạch (Explicit Consent) của Người thân bảo hộ hoặc Người cao tuổi trước khi kích hoạt thu thập viễn trắc.", bold_prefix="Nghị định 13/2023/NĐ-CP: ")
    docx_helper.add_bullet(doc, "Định hướng tiệm cận Quy định Bảo vệ Dữ liệu Chung của Châu Âu (GDPR - General Data Protection Regulation) Điều 9 đối với dữ liệu sức khỏe đặc biệt (Special Category Data), đảm bảo quyền của chủ thể dữ liệu (Quyền được biết, Quyền truy cập, Quyền chỉnh sửa, Quyền xóa bỏ).", bold_prefix="Chuẩn mực GDPR: ")
    docx_helper.add_bullet(doc, "Áp dụng các biện pháp an toàn kỹ thuật tương thích HIPAA Security Safeguards: Mã hóa toàn bộ đường truyền dữ liệu bằng TLS 1.3, mã hóa lưu trữ CSDL Azure SQL bằng Transparent Data Encryption (TDE 256-bit), và phân quyền truy cập nghiêm ngặt dựa trên vai trò (RBAC).", bold_prefix="An toàn Kỹ thuật HIPAA: ")
    
    docx_helper.add_heading_2(doc, "1.3 Điều Khoản Dịch Vụ, Chính Sách Quyền Riêng Tư & Giới Hạn Trách Nhiệm")
    docx_helper.add_paragraph(doc, 
        "Trong thỏa thuận người dùng cuối (EULA) và Điều khoản Dịch vụ (Terms of Service), CareAI quy định rõ ràng:",
        bold_prefix="Điều khoản Trách nhiệm: ")
    docx_helper.add_bullet(doc, "Khi xảy ra sự cố nguy kịch (Người cao tuổi bất tỉnh, ngưng tim, tai biến mạch máu não hoặc chấn thương nặng do ngã), Người thân và người giám hộ phải ngay lập tức liên hệ Tổng đài Cấp cứu Quốc gia (115) hoặc đưa bệnh nhân đến cơ sở y tế gần nhất. CareAI không chịu trách nhiệm đối với bất kỳ sự chậm trễ nào xuất phát từ việc phụ thuộc hoàn toàn vào thông báo của ứng dụng.", bold_prefix="Quy tắc Phản ứng Khẩn cấp 115: ")
    docx_helper.add_bullet(doc, "Hệ thống bảo đảm 100% không thương mại hóa, chia sẻ hoặc bán dữ liệu sinh hiệu của người dùng cho bất kỳ bên thứ ba nào (bao gồm công ty bảo hiểm, tiếp thị dược phẩm hay đơn vị quảng cáo). Dữ liệu chỉ phục vụ mục đích duy nhất là hiển thị cho gia đình và phục vụ thuật toán cảnh báo.", bold_prefix="Chính sách Không Bán Dữ liệu: ")
    docx_helper.add_bullet(doc, "Gia đình có quyền yêu cầu xóa bỏ vĩnh viễn toàn bộ hồ sơ y tế và dữ liệu viễn trắc khỏi hệ thống CSDL đám mây bất kỳ lúc nào thông qua chức năng 'Hủy liên kết & Xóa tài khoản' (Right to be Forgotten).", bold_prefix="Quyền Xóa Vĩnh Viễn Dữ Liệu: ")
    
    docx_helper.add_heading_2(doc, "1.4 Chủ Quyền Dữ Liệu & Chính Sách Vòng Đời Dữ Liệu (Data Retention)")
    docx_helper.add_paragraph(doc, 
        "Do giới hạn dung lượng vật lý 2GB trên gói Azure SQL Serverless / Student Tier và quy định bảo mật chủ quyền dữ liệu, chính sách vòng đời dữ liệu được áp dụng tự động bởi background worker chuyên trách:",
        bold_prefix="Chiến lược Lưu trữ Thông minh: ")
    
    retention_rules = [
        ("Dữ liệu Viễn trắc Thường quy (HealthMeasurements)", "30 ngày", "Tự động cắt tỉa bản ghi cũ hơn 30 ngày theo lô 1000 dòng để tiết kiệm dung lượng RAM/Disk."),
        ("Sổ cái Khử trùng lặp Gói tin (ProcessedTelemetryLedgers)", "7 ngày", "Dữ liệu đối soát trùng lặp gói tin được lưu trữ 7 ngày, sau đó tự động dọn dẹp."),
        ("Hồ sơ Sự cố Cấp cứu (Incidents & Timeline)", "Vĩnh viễn / Đến khi xóa", "Lưu trữ đầy đủ phục vụ kiểm toán y khoa pháp y và đánh giá tiến triển sức khỏe."),
        ("Bộ nhớ Đệm Thiết bị Cục bộ (SQLite & Device Protected Storage)", "7 ngày / Đến khi đồng bộ", "Dữ liệu trên máy nhánh tự giải phóng sau khi nhận được xác nhận HTTP 2xx từ máy chủ.")
    ]
    docx_helper.add_styled_table(doc, ["Loại Thực Thể Dữ Liệu", "Thời Gian Lưu Trữ", "Quy Chuẩn Xử Lý & Dọn Dẹp"], retention_rules, col_widths=[2.2, 1.3, 3.0])
    
    doc.add_page_break()
    
    # =========================================================================
    # PHẦN II
    # =========================================================================
    docx_helper.add_heading_1(doc, "PHẦN II: ĐẶC TẢ CHI TIẾT 16 USE CASE CHỨC NĂNG HỆ THỐNG")
    
    docx_helper.add_heading_2(doc, "2.1 Ma Trận Tổng Hợp 16 Use Case & Phân Bổ Tác Nhân (Actors)")
    docx_helper.add_paragraph(doc, 
        "Hệ thống CareAI chuẩn hóa 16 Use Case chức năng được phân bổ chặt chẽ trên 7 phân hệ nghiệp vụ, phục vụ 6 nhóm tác nhân chính: Người thân chính (Primary Caregiver), Người thân phụ (Secondary Caregiver), Người cao tuổi (Elder), Hệ thống Tự động (System Daemon/Watchdog), Chuyên viên Kiểm toán (Medical Auditor) và Khối Trí tuệ Nhân tạo (AI Analytical Engine).",
        bold_prefix="Cơ cấu Nghiệp vụ: ")
    
    uc_summary = [
        ("UC-01", "Đăng ký, Đăng nhập & Khóa An toàn", "Tài khoản & Ghép nối", "P0", "Primary / Secondary Caregiver"),
        ("UC-02", "Tạo Hồ sơ Người cao tuổi & Sinh PIN", "Tài khoản & Ghép nối", "P0", "Primary Caregiver"),
        ("UC-03", "Ghép nối Companion & Cấp quyền OS", "Tài khoản & Ghép nối", "P0", "Caregiver & Companion Phone"),
        ("UC-04", "Đồng bộ Viễn trắc Thụ động Health Connect", "Thu thập & Đệm Dữ liệu", "P0", "Elder & Companion Phone"),
        ("UC-05", "Lưu trữ theo Lô & Cầu dao RAM Shield", "Thu thập & Đệm Dữ liệu", "P0", "Backend Telemetry Engine"),
        ("UC-06", "Thẩm định Luật Lâm sàng & Leo thang Cấp cứu", "Cảnh báo & Giám sát", "P0", "Backend Clinical Engine"),
        ("UC-07", "Giám sát Mất kết nối Đa thiết bị", "Cảnh báo & Giám sát", "P0", "System Watchdog Daemon"),
        ("UC-08", "Tiếp nhận Sự cố & Xử lý Khẩn cấp", "Phản ứng Cấp cứu", "P0", "Caregivers Quorum"),
        ("UC-09", "Phát Cấp cứu SOS & Báo Ngã Hủy Cục bộ", "Phản ứng Cấp cứu", "P0", "Galaxy Watch, Phone & Cloud"),
        ("UC-10", "Bảng điều khiển Sức khỏe Trực tiếp & Bản đồ", "Phản ứng Cấp cứu", "P1", "Caregivers Mobile App"),
        ("UC-11", "Tùy chỉnh Ngưỡng Lâm sàng Cá nhân hóa", "Cấu hình & Phân quyền", "P1", "Primary Caregiver"),
        ("UC-12", "Quản lý Gia đình & Phân quyền RBAC", "Cấu hình & Phân quyền", "P1", "Primary Caregiver"),
        ("UC-13", "Hủy Liên kết & Instant Kill-Switch", "Vòng đời & Kiểm toán", "P1", "Primary Caregiver"),
        ("UC-14", "Tra cứu Lịch sử & Dấu vết Pháp y", "Vòng đời & Kiểm toán", "P1", "Caregiver & Auditor"),
        ("UC-15", "AI Phát hiện Bất thường Sinh hoạt (Phase 2)", "Trí tuệ Nhân tạo", "P2", "ML.NET Background Worker"),
        ("UC-16", "AI Tổng hợp Báo cáo Sức khỏe Tuần (Phase 2)", "Trí tuệ Nhân tạo", "P2", "LLM Generative AI Service")
    ]
    docx_helper.add_styled_table(doc, ["Mã UC", "Tên Use Case", "Phân Hệ Nghiệp Vụ", "Ưu Tiên", "Tác Nhân Vận Hành"], uc_summary, col_widths=[0.8, 2.3, 1.5, 0.6, 1.3])
    
    # CHI TIẾT TỪNG PHÂN HỆ
    docx_helper.add_heading_2(doc, "2.2 Phân Hệ 1: Quản Trị Tài Khoản & Ghép Nối Thiết Bị (UC-01 $\\to$ UC-03)")
    
    docx_helper.add_heading_3(doc, "UC-01: Đăng Ký, Đăng Nhập & Khóa An Toàn (Caregiver Onboarding)")
    docx_helper.add_bullet(doc, "Caregiver chưa có tài khoản hoặc cần xác thực lại sau khi phiên làm việc hết hạn.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Người dùng nhập số điện thoại/email, nhận OTP xác thực. Thiết lập mật khẩu mạnh và mã PIN sinh trắc học (Fingerprint/FaceID). Hệ thống cấp phát JWT Token (thời hạn 24h) kèm Refresh Token an toàn.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Nhập sai mật khẩu liên tiếp 5 lần: Khóa tài khoản tạm thời trong 15 phút và gửi cảnh báo bảo mật qua email.", bold_prefix="Luồng ngoại lệ: ")
    docx_helper.add_bullet(doc, "Caregiver đăng nhập thành công, nạp thông tin danh sách người cao tuổi thuộc quyền quản lý.", bold_prefix="Hậu điều kiện: ")
    
    docx_helper.add_heading_3(doc, "UC-02: Tạo Hồ Sơ Người Cao Tuổi & Sinh Mã PIN Ghép Nối")
    docx_helper.add_bullet(doc, "Caregiver sở hữu quyền Primary Caregiver của gia đình.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Caregiver nhập họ tên, ngày sinh, tiền sử bệnh (tăng huyết áp, tim mạch, tiểu đường), người liên hệ khẩn cấp. Hệ thống lưu vào CSDL và sinh mã PIN ghép nối 6 số (hiệu lực 10 phút).", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Mã PIN hết hạn trước khi ghép nối: Cho phép bấm nút 'Tạo mã mới' mà không làm mất thông tin hồ sơ đã nhập.", bold_prefix="Luồng ngoại lệ: ")
    docx_helper.add_bullet(doc, "Hồ sơ người cao tuổi được khởi tạo với trạng thái 'PENDING_PAIRING'.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_3(doc, "UC-03: Ghép Nối Companion App & Cấp Quyền Hệ Điều Hành Khắt Khe")
    docx_helper.add_bullet(doc, "Điện thoại Companion của cụ đã cài app CareAI Companion, sở hữu mã PIN từ UC-02.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Người thân nhập mã PIN trên điện thoại của cụ. Backend xác thực mã PIN, sinh DeviceId tĩnh và DeviceToken (32-byte Base64, lưu hash SHA-256 chữ thường). Ứng dụng thực hiện chuỗi kiểm tra và xin quyền hệ điều hành: SCHEDULE_EXACT_ALARM, USE_FULL_SCREEN_INTENT, POST_NOTIFICATIONS và READ_HEALTH_DATA_IN_BACKGROUND.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Người dùng từ chối cấp quyền Exact Alarm hoặc Full-Screen Intent: Hệ thống KHÔNG văng lỗi, tự động chuyển sang chế độ an toàn hạ cấp SAFETY_MODE: DEGRADED (Best-Effort Alert) và hiển thị thanh cảnh báo màu hổ phách hướng dẫn mở lại trong cài đặt.", bold_prefix="Luồng ngoại lệ & Hạ cấp: ")
    docx_helper.add_bullet(doc, "Thiết bị được lưu trong SharedPreferences và kích hoạt các dịch vụ thu thập nền.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_2(doc, "2.3 Phân Hệ 2: Thu Thập & Đệm Dữ Liệu Viễn Trắc Vi Mô (UC-04 $\\to$ UC-05)")
    
    docx_helper.add_heading_3(doc, "UC-04: Đồng Bộ Viễn Trắc Thụ Động Qua Health Connect (Batch-Lane)")
    docx_helper.add_bullet(doc, "Đồng hồ Galaxy Watch liên tục ghi nhận dữ liệu nhịp tim, bước chân, SpO2 vào Health Connect.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Mỗi 15 phút, WorkManager trên điện thoại Companion thức dậy, truy vấn dữ liệu chênh lệch (Changes Token) từ Health Connect Android 14+. Dữ liệu được gói vào gói tin JSON và nén gửi lên endpoint `/api/v1/telemetry/batch`. Nếu mất mạng, gói tin được đưa vào hàng đợi SQLite Spooling cục bộ.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Mất sóng 4G/WiFi: SQLite Spool lưu trữ tối đa 10.000 điểm đo. Khi có mạng trở lại, WorkManager tự động đẩy bù theo trật tự FIFO.", bold_prefix="Luồng ngoại lệ: ")
    docx_helper.add_bullet(doc, "Hàng nghìn mẫu đo sinh hiệu được đồng bộ lên đám mây mà không tiêu tốn quá 3% pin mỗi ngày.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_3(doc, "UC-05: Lưu Trữ Theo Lô & Mạch Cầu Dao Bảo Vệ RAM (Batch Ingestion & RAM Shield)")
    docx_helper.add_bullet(doc, "Gói tin Batch gửi tới Backend ASP.NET Core Kestrel.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Bộ kiểm tra cầu dao kiểm tra tỷ lệ đầy của hàng đợi RAM. Nếu an toàn, dữ liệu được ghi nhận vào Sổ cái `ProcessedTelemetryLedgers` (tránh trùng lặp) và lưu vào bảng `HealthMeasurements` theo khối 1000 bản ghi trong 1 Database Transaction duy nhất.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Hàng đợi RAM vượt ngưỡng 80% (nguy cơ tràn bộ nhớ): Mạch cầu dao Circuit Breaker bật sang trạng thái OPEN, phản hồi HTTP 429 Too Many Requests kèm chỉ dẫn `Retry-After: 30` để bảo vệ an toàn sống còn cho Kestrel.", bold_prefix="Luồng bảo vệ: ")
    docx_helper.add_bullet(doc, "Toàn bộ mẫu đo được lưu trữ toàn vẹn, cập nhật chỉ số đo lường mới nhất của người cao tuổi.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_2(doc, "2.4 Phân Hệ 3: Engine Cảnh Báo Lâm Sàng & Giám Sát Hệ Thống (UC-06 $\\to$ UC-07)")
    
    docx_helper.add_heading_3(doc, "UC-06: Thẩm Định Luật Lâm Sàng & Leo Thang Cấp Cứu (Clinical Engine)")
    docx_helper.add_bullet(doc, "Dữ liệu sinh hiệu mới được nạp vào hệ thống.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Engine lâm sàng áp dụng thuật toán cửa sổ trượt (Sliding Window): Chỉ thẩm định các mẫu đo mới (chưa từng được đánh giá lâm sàng). So sánh với ngưỡng sinh lý: Nhịp tim chậm (< 40 bpm), Nhịp tim nhanh (> 120 bpm khi nghỉ), Huyết áp tâm thu/tâm trương bất thường, SpO2 hạ thấp (< 90%). Nếu vi phạm kéo dài, tự động tạo Sự cố Incident và lập tức xếp hàng thông báo còi hú.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Đang có sự cố Active cùng loại: Hệ thống tự động ghép nối vào Sự cố hiện hữu, ghi nhận sự kiện Timeline mới mà không tạo trùng lặp Incident (bảo vệ Filtered Unique Index UIX_Incidents_SingleActiveElder).", bold_prefix="Khử trùng lặp: ")
    docx_helper.add_bullet(doc, "Sự cố được kích hoạt, đồng hồ đếm ngược phản hồi của gia đình bắt đầu chạy.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_3(doc, "UC-07: Giám Sát Mất Kết Nối Đa Thiết Bị (Multi-Device Watchdog)")
    docx_helper.add_bullet(doc, "Thiết bị của cụ đang hoạt động bình thường trên hệ thống.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Mỗi 60 giây, Watchdog Background Worker quét bảng `DeviceRegistrations`. Nếu `LastHeartbeat` của thiết bị vượt quá ngưỡng cho phép (15 phút đối với điện thoại, 30 phút đối với đồng hồ), hệ thống tự động sinh sự cố `STALE_OFFLINE` và gửi thông báo nhắc nhở người thân kiểm tra pin hoặc kết nối của cụ.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Nhiều thiết bị cùng rớt mạng một lúc: Watchdog gom nhóm theo hồ sơ người già, tránh dội hàng chục thông báo riêng lẻ cho cùng một cụ.", bold_prefix="Tối ưu thông báo: ")
    docx_helper.add_bullet(doc, "Gia đình nắm bắt tức thời tình trạng thiết bị của người già bị hết pin hoặc mất sóng.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_2(doc, "2.5 Phân Hệ 4: Phản Ứng Sự Cố Cấp Cứu Khẩn Cấp & Fast-Lane SOS (UC-08 $\\to$ UC-10)")
    
    docx_helper.add_heading_3(doc, "UC-08: Tiếp Nhận Sự Cố & Xử Lý Khẩn Cấp (Acknowledge & Resolution Quorum)")
    docx_helper.add_bullet(doc, "Sự cố đang ở trạng thái `Open` và gửi còi hú tới điện thoại các người thân.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Người thân nhận được thông báo còi hú, mở ứng dụng và bấm 'XÁC NHẬN ĐÃ TIẾP NHẬN' (Acknowledge). Hệ thống cập nhật trạng thái sự cố sang `Acknowledged`, ghi nhận người tiếp nhận và phát tín hiệu dừng còi hú cho các máy còn lại. Sau khi can thiệp xong, bấm 'ĐÓNG SỰ CỐ' (Resolved) kèm ghi chú nguyên nhân.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Xung đột đồng thời (2 người thân cùng bấm nút xác nhận): Hệ thống áp dụng cơ chế Khóa Lạc quan (Optimistic Concurrency Control qua RowVersion), người bấm trước được ghi nhận, người bấm sau nhận thông báo 'Sự cố đã được xử lý bởi [Tên người thân 1]'.", bold_prefix="Xung đột đồng thời: ")
    docx_helper.add_bullet(doc, "Sự cố chuyển sang trạng thái Resolved, toàn bộ tiến trình can thiệp được lưu vết vĩnh viễn.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_3(doc, "UC-09: Phát Cấp Cứu SOS & Cảnh Báo Ngã Kèm Hủy Cục Bộ (Fast-Lane Emergency)")
    docx_helper.add_bullet(doc, "Cụ bấm nút SOS hoặc Galaxy Watch phát hiện gia tốc rơi tự do vượt ngưỡng kèm bất động.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Quy trình thực thi chuẩn công nghiệp khép kín:\n"
        "1. Đồng hồ Galaxy Watch bắn đồng thời 2 kênh: Fast-Lane MessageClient (Bluetooth tốc độ cao) và Store-and-Forward DataClient sang điện thoại Companion.\n"
        "2. Điện thoại nhận được sự kiện, ghi đĩa nguyên tử `CareAiFallStore` trong Device Protected Storage, vũ trang `AlarmManager.RTC_WAKEUP` thời hạn 35 giây, và bung màn hình cứu hộ Full-Screen Intent đếm ngược 30 giây.\n"
        "3. Nếu cụ an toàn và bấm 'TÔI ỔN / HỦY BỎ': Điện thoại hủy báo động, giải giáp AlarmManager, cập nhật trạng thái `CANCELLED_BY_USER`, máy chủ không bị đánh động.\n"
        "4. Nếu hết 30 giây cụ không bấm hủy: Flutter gọi mạng gửi SOS. Nếu Flutter bị crash hoặc kill, đúng giây 35 nhân hệ điều hành đánh thức `NativeFallWatchdogReceiver`, kích hoạt quy trình Strict Outbox-First bắn bù SOS lên đám mây với mã định danh chuẩn tắc `FALL_<eventId>`.", bold_prefix="Luồng thực thi: ")
    docx_helper.add_bullet(doc, "Mất sóng tại thời điểm ngã: Sự cố nằm an toàn trong Outbox đĩa (Device Protected Storage). WorkManager tự động thực thi gửi bù ngay khi có kết nối trở lại.", bold_prefix="Khắc phục rớt mạng: ")
    docx_helper.add_bullet(doc, "Hệ thống bảo đảm 100% không bỏ sót bất kỳ cú ngã nào, dù điện thoại bị kill app, hết pin khởi động lại hay rớt mạng.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_3(doc, "UC-10: Bảng Điều Khiển Sức Khỏe Trực Tiếp & Bản Đồ Vị Trí (Live Dashboard)")
    docx_helper.add_bullet(doc, "Caregiver mở ứng dụng di động CareAI.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Ứng dụng hiển thị các thẻ sinh hiệu mới nhất (Nhịp tim, Huyết áp, SpO2, Bước chân) kèm mã màu trực quan (Xanh: Bình thường, Vàng: Chú ý, Đỏ: Nguy hiểm). Hiển thị vị trí GPS gần nhất của cụ trên bản đồ số kèm thời gian cập nhật.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Dữ liệu bị cũ quá 2 giờ: Hiển thị trạng thái mờ và cảnh báo 'Dữ liệu chưa được làm mới gần đây'.", bold_prefix="Luồng ngoại lệ: ")
    docx_helper.add_bullet(doc, "Người thân an tâm theo dõi tình trạng sức khỏe của cha mẹ mọi lúc mọi nơi.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_2(doc, "2.6 Phân Hệ 5: Cấu Hình Lâm Sàng & Phân Quyền Gia Đình (UC-11 $\\to$ UC-12)")
    
    docx_helper.add_heading_3(doc, "UC-11: Tùy Chỉnh Ngưỡng Lâm Sàng Cá Nhân Hóa (Medical Configuration)")
    docx_helper.add_bullet(doc, "Primary Caregiver có tham vấn ý kiến của bác sĩ điều trị.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Caregiver điều chỉnh ngưỡng nhịp tim trên/dưới, huyết áp tâm thu tối đa/tối thiểu cho phù hợp với bệnh lý nền riêng biệt của cụ. Hệ thống lưu cấu hình và lập tức áp dụng cho Clinical Engine.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Nhập ngưỡng phi lý (ví dụ: nhịp tim tối đa < nhịp tim tối thiểu): Hệ thống từ chối lưu và báo lỗi validation rõ ràng.", bold_prefix="Validation: ")
    docx_helper.add_bullet(doc, "Quy tắc lâm sàng được cá nhân hóa chính xác theo thể trạng của người già.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_3(doc, "UC-12: Quản Lý Thành Viên Gia Đình & Phân Quyền RBAC (Family Management)")
    docx_helper.add_bullet(doc, "Primary Caregiver muốn mời thêm anh/chị/em trong gia đình cùng giám sát cụ.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Primary Caregiver nhập số điện thoại người thân cần mời, phân vai trò (Secondary Caregiver - chỉ nhận cảnh báo và xem sinh hiệu; hoặc Primary Caregiver ủy quyền). Người được mời nhận thông báo và chấp thuận tham gia mạng lưới bảo hộ.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Thu hồi quyền: Primary Caregiver có quyền xóa thành viên khỏi nhóm bảo hộ bất kỳ lúc nào. Hệ thống ngay lập tức thu hồi quyền truy cập và vô hiệu hóa nhận cảnh báo còi hú.", bold_prefix="Thu hồi quyền: ")
    docx_helper.add_bullet(doc, "Mạng lưới chăm sóc gia đình được mở rộng đồng bộ và phân quyền an toàn.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_2(doc, "2.7 Phân Hệ 6: Quản Trị Vòng Đời Dữ Liệu & Kiểm Toán (UC-13 $\\to$ UC-14)")
    
    docx_helper.add_heading_3(doc, "UC-13: Hủy Liên Kết Thiết Bị & Instant Kill-Switch")
    docx_helper.add_bullet(doc, "Điện thoại hoặc đồng hồ bị thất lạc, hỏng hóc hoặc người thân đổi thiết bị mới.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Primary Caregiver gọi lệnh `POST /api/v1/devices/{deviceId}/revoke`. Hệ thống đánh dấu `IsActive = false` trong CSDL, đồng thời kích hoạt `DeviceTokenAuthMiddleware.InvalidateDevice(cache, deviceId)` xóa sạch cache xác thực với độ trễ 0ms. Bất kỳ gói tin nào gửi từ thiết bị cũ sau thời điểm này đều bị chặn đứng với mã HTTP 401.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Thiết bị bị đánh cắp hoàn toàn mất khả năng gửi dữ liệu rác hoặc truy cập thông tin gia đình.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_3(doc, "UC-14: Tra Cứu Lịch Sử Sự Cố & Dấu Vết Kiểm Toán Pháp Y (Forensic Audit Trail)")
    docx_helper.add_bullet(doc, "Caregiver hoặc Bác sĩ cần đối soát lại diễn biến một sự cố ngã hoặc cấp cứu trong quá khứ.", bold_prefix="Tiền điều kiện: ")
    docx_helper.add_bullet(doc, "Truy vấn lịch sử sự cố theo khoảng thời gian. Hệ thống trích xuất dòng thời gian sự kiện chi tiết (Incident Timeline): Thời điểm ngã, thời điểm báo động máy nhánh, thời điểm máy chủ tiếp nhận, danh sách token người thân đã nhận push, người đầu tiên bấm Acknowledge và ghi chú xử lý của bác sĩ.", bold_prefix="Luồng chính: ")
    docx_helper.add_bullet(doc, "Bản ghi kiểm toán có chữ ký bảo vệ tính toàn vẹn, phục vụ minh bạch hóa trách nhiệm y tế.", bold_prefix="Hậu điều kiện: ")

    docx_helper.add_heading_2(doc, "2.8 Phân Hệ 7: Trí Tuệ Nhân Tạo Phân Tích Sức Khỏe - Giai Đoạn 2 (UC-15 $\\to$ UC-16)")
    
    docx_helper.add_heading_3(doc, "UC-15: AI Phát Hiện Bất Thường Thói Quen Sinh Hoạt (ML.NET Anomaly Detection)")
    docx_helper.add_paragraph(doc, 
        "Áp dụng mô hình học máy nhẹ (ML.NET Time-Series SSA - Singular Spectrum Analysis) phân tích chuỗi nhịp tim khi ngủ và mật độ bước chân hàng ngày. Nếu cụ giảm vận động đột ngột 50% trong 3 ngày liên tiếp hoặc nhịp tim ban đêm tăng cao bất thường, hệ thống tạo cảnh báo xu hướng sức khỏe suy giảm để người thân chủ động đưa cụ đi khám tổng quát.",
        bold_prefix="Mô tả Kỹ thuật: ")

    docx_helper.add_heading_3(doc, "UC-16: AI Tổng Hợp Báo Cáo Sức Khỏe Hàng Tuần (LLM GenAI Weekly Summary)")
    docx_helper.add_paragraph(doc, 
        "Hàng tuần vào sáng Chủ nhật, mô hình AI tổng hợp toàn bộ các chỉ số sinh hiệu, số bước đi trung bình, các sự kiện cảnh báo trong tuần thành một bản tin vắn ngắn gọn (200 từ), dễ hiểu bằng tiếng Việt thân thiện gửi qua thông báo đẩy cho người thân.",
        bold_prefix="Mô tả Kỹ thuật: ")

    docx_helper.add_heading_2(doc, "2.9 BẢNG MA TRẬN ÁNH XẠ TOÀN DIỆN CHỈ SỐ SINH HIỆU \u2192 CHỨC NĂNG HỆ THỐNG")
    docx_helper.add_paragraph(doc, 
        "Để đảm bảo tính minh bạch tuyệt đối giữa phần cứng thiết bị đeo và logic nghiệp vụ phần mềm của 16 Use Case, bảng dưới đây chuẩn hóa toàn diện 9 chỉ số đo lường sinh hiệu và trạng thái thiết bị, cảm biến vật lý cung cấp, kênh truyền dẫn kiến trúc (Fast-Lane vs Batch-Lane), danh sách Use Case tiếp nhận, ngưỡng kích hoạt lâm sàng, mức độ nghiêm trọng và hành vi ứng phó tự động của hệ thống:",
        bold_prefix="Đặc tả Truy xuất Nguồn gốc (Traceability Matrix): ")

    metrics_matrix_headers = ["Chỉ Số & Ký Hiệu", "Nguồn Cảm Biến", "Kênh Truyền", "Use Case Áp Dụng", "Ngưỡng Kích Hoạt / Tiêu Chí", "Mức Độ & Hành Vi Xử Lý"]
    metrics_matrix_data = [
        ("Té ngã\n(FALL)", 
         "IMU 3-Axis Accel\n+ Gyro + Barometer", 
         "Fast-Lane\n(< 500ms BT)", 
         "• UC-09 (Fast SOS)\n• UC-08 (Quorum ACK)\n• UC-10 (Dashboard)\n• UC-14 (Audit Trail)", 
         "Rơi tự do (~0G) kéo theo va đập > 2.5G - 3.5G, sau đó bất động > 5 giây.", 
         "CRITICAL: Bung đếm ngược 30s tại máy. Nếu không hủy: Ghi DB < 50ms, còi hú FCM Quorum < 3s, lưu vết GPS."),
        ("Nút Cấp cứu\n(MANUAL_SOS)", 
         "Nút cứng đồng hồ /\nNút SOS Companion", 
         "Fast-Lane\n(< 50ms sync)", 
         "• UC-09 (Fast SOS)\n• UC-08 (Quorum ACK)\n• UC-10 (Dashboard)\n• UC-14 (Audit Trail)", 
         "Bấm giữ nút khẩn cấp >= 2 giây trên đồng hồ hoặc điện thoại.", 
         "CRITICAL: Bỏ qua đếm ngược 30s, kích hoạt còi hú Quorum tức thì, ghim vị trí GPS trên bản đồ người thân."),
        ("Nhịp tim\n(HEART_RATE\n- bpm)", 
         "Quang học PPG\n(Samsung BioActive)", 
         "Batch (15m)\n+ Kèm Fast-Lane", 
         "• UC-04, 05 (Batch)\n• UC-06 (Clinical)\n• UC-09 (Fast-Lane)\n• UC-10 (Dashboard)\n• UC-11 (Config)\n• UC-14 (Forensic)\n• UC-15, 16 (AI)", 
         "• Nguy kịch: HR >= 180 hoặc <= 35 bpm\n• Nhịp nhanh: HR > 120 bpm (nghỉ)\n• Nhịp chậm: HR < 40 bpm\n• Đột biến (Surge): ΔHR >= 15 bpm khi Steps = 0", 
         "CRITICAL / HIGH / WARNING: Bắn còi hú FCM ưu tiên cao, lưu vết 15p trước/sau ngã. Học baseline ban đêm qua ML.NET."),
        ("Huyết áp\n(BLOOD_PRESSURE\n- mmHg)", 
         "Samsung BioActive\n(Pulse Wave Analysis)", 
         "Batch-Lane\n(Định kỳ theo lần đo)", 
         "• UC-04, 05 (Batch)\n• UC-06 (Clinical)\n• UC-10 (Dashboard)\n• UC-11 (Config)\n• UC-16 (AI Weekly)", 
         "• Cơn tăng HA: Sys >= 180 hoặc Dia >= 120 mmHg\n• Tăng HA độ 2: Sys >= 160 hoặc Dia >= 100 mmHg\n• Tụt HA: Sys < 90 hoặc Dia < 60 mmHg", 
         "HIGH / MEDIUM: Tạo sự cố HYPERTENSION, hiển thị thẻ màu Dashboard, thống kê % thời gian trong ngưỡng an toàn."),
        ("Oxy máu\n(SPO2 - %)", 
         "Đèn LED Đỏ & IR PPG\n(Samsung BioActive)", 
         "Batch-Lane\n(15-30m & khi ngủ)", 
         "• UC-04, 05 (Batch)\n• UC-06 (Clinical)\n• UC-10 (Dashboard)\n• UC-15 (Sleep Apnea)\n• UC-16 (AI Weekly)", 
         "• Suy hô hấp cấp: SpO2 < 90%\n• Thiếu oxy nhẹ: 90% <= SpO2 < 94%\n• Ngưng thở khi ngủ: Tụt ngắt quãng >= 4% lặp lại ban đêm", 
         "HIGH / WARNING: Cảnh báo nguy cơ thiếu oxy, kích hoạt còi hú nếu SpO2 < 90%, AI nhận định chất lượng giấc ngủ."),
        ("Bước chân\n(STEPS - bước)", 
         "Gia tốc kế đếm bước\n(Hardware Pedometer)", 
         "Batch-Lane\n(Tích lũy 15 phút)", 
         "• UC-04, 05 (Batch)\n• UC-06 (Lọc ngữ cảnh)\n• UC-10 (Dashboard)\n• UC-15, 16 (AI)", 
         "• Lọc ngữ cảnh: Steps > 60 -> Nhịp nhanh sinh lý\n• Suy giảm vận động: Giảm > 50% bước chân trong 3 ngày liên tiếp", 
         "INFO / LOW WARNING: Khử báo động giả tim mạch khi đang chạy/leo dốc. AI cảnh báo người già bị ốm đau/liệt nhẹ."),
        ("Giấc ngủ\n(SLEEP - phút)", 
         "PPG + IMU\n(Phân tích cử động & HRV)", 
         "Batch-Lane\n(Đồng bộ mẻ sáng 06:00)", 
         "• UC-04, 05 (Batch)\n• UC-10 (Dashboard)\n• UC-15, 16 (AI)", 
         "• Thiếu ngủ trầm trọng: Tổng thời gian < 4 giờ/đêm\n• Thức giấc bất thường: Thức giấc > 5 lần/đêm", 
         "INFO / INSIGHT: Chấm điểm Sleep Score, tổng hợp báo cáo tuần gửi người thân lưu ý sức khỏe tâm lý/thần kinh."),
        ("Trạng thái Đeo\n(ON_BODY - Bool)", 
         "Điện dung / Tiếp xúc da\n(Capacitive & Optical)", 
         "Fast-Lane &\nBatch-Lane", 
         "• UC-09 (Lọc ngã giả)\n• UC-07 (Watchdog)\n• UC-10 (Dashboard)", 
         "• Rời tay (False -> Đang sạc/đặt bàn)\n• Trên tay (True -> Đang đeo)", 
         "FILTER INVARIANT: Nếu ON_BODY = false -> HỦY kích hoạt ngã (tránh rớt đồng hồ từ bàn). Watchdog không báo mất mạng sai."),
        ("Dung lượng Pin\n(BATTERY - %)", 
         "PMIC Battery Fuel Gauge", 
         "Đi kèm mọi gói tin\nHeartbeat & Batch", 
         "• UC-07 (Watchdog)\n• UC-10 (Dashboard)", 
         "Pin thiết bị < 15% (Đồng hồ hoặc Điện thoại Companion).", 
         "LOW / REMINDER: Gửi thông báo đẩy nhắc người nhà nhắc cụ cắm sạc, phòng ngừa gián đoạn bảo vệ sinh mạng.")
    ]
    docx_helper.add_styled_table(doc, metrics_matrix_headers, metrics_matrix_data, col_widths=[1.0, 1.1, 0.8, 1.1, 1.2, 1.3])
    
    doc.add_page_break()

    # =========================================================================
    # PHẦN III
    # =========================================================================
    docx_helper.add_heading_1(doc, "PHẦN III: KIẾN TRÚC HỆ THỐNG TỔNG THỂ (BACKEND & FRONTEND ARCHITECTURE)")
    
    docx_helper.add_heading_2(doc, "3.1 Mô Hình Kiến Trúc Bất Biến: Sovereign Modular Monolith")
    docx_helper.add_paragraph(doc, 
        "Toàn bộ hệ thống CareAI kiên định triển khai theo mô hình Sovereign Modular Monolith trên nền tảng ASP.NET Core Kestrel và Azure SQL Database. Quyết định kiến trúc này được bảo vệ dựa trên các luận cứ thực chiến:",
        bold_prefix="Tư duy Thiết kế: ")
    
    arch_reasons = [
        ("Loại bỏ Hoàn toàn Microservices", "Microservices làm phát sinh độ trễ mạng phân tán (RPC overhead), bài toán phân tán dữ liệu phức tạp (Saga, 2PC) và chi phí hạ tầng đắt đỏ (tối thiểu $200-$500/tháng cho các cụm cluster). Đối với quy mô Pilot gia đình, Monolith tối ưu chi phí ở mức ~$18/tháng mà vẫn đảm bảo độ tin cậy tuyệt đối."),
        ("Loại bỏ Kafka / RabbitMQ", "Message Broker yêu cầu duy trì máy chủ riêng biệt, tăng bề mặt lỗi và nguy cơ mất tin nếu cấu hình ack sai. Hệ thống sử dụng trực tiếp Bảng Outbox trong Azure SQL kết hợp Background Workers nội tại với Transaction đồng bộ, đảm bảo tính bền vững (Durability) chuẩn ACID."),
        ("Loại bỏ Redis Cluster", "Caching phân tán không cần thiết cho quy mô pilot. Hệ thống sử dụng MemoryCache in-process có bảo vệ kiểm tra phiên bản và hàm Invalidate tức thì (0ms delay), loại bỏ hoàn toàn sự cố phân mảnh cache.")
    ]
    docx_helper.add_styled_table(doc, ["Quyết Định Loại Bỏ", "Luận Cứ Kỹ Thuật Thực Chiến & Phân Tích Lợi Ích"], arch_reasons, col_widths=[2.5, 4.0])

    docx_helper.add_heading_2(doc, "3.2 Kiến Trúc Backend Dual-Lane (Fast-Lane SOS vs Batch-Lane Telemetry)")
    docx_helper.add_paragraph(doc, 
        "Backend CareAI giải quyết triệt để sự xung đột tài nguyên giữa việc thu thập dữ liệu viễn trắc khối lượng lớn và việc tiếp nhận cảnh báo cấp cứu khẩn cấp bằng kiến trúc phân luồng vật lý Dual-Lane:",
        bold_prefix="Thiết kế Dual-Lane Độc lập: ")
    
    dual_lane_specs = [
        ("Đặc tính Kỹ thuật", "Fast-Lane Emergency (Khẩn cấp)", "Batch-Lane Telemetry (Thường quy)"),
        ("Endpoint API", "POST /api/v1/incidents/sos", "POST /api/v1/telemetry/batch"),
        ("Mục tiêu SLA", "Độ trễ < 1.0 giây, Sẵn sàng 99.99%", "Thông lượng cao, Chấp nhận trễ 1-5 phút"),
        ("Bảo vệ Idempotency", "Bảng ProcessedTelemetryLedgers (FALL_<eventId>)", "Bảng ProcessedTelemetryLedgers (BatchId)"),
        ("Chiến lược Lưu trữ", "Ghi ngay lập tức vào CSDL trong Transaction", "Ghi theo mẻ 1000 bản ghi qua EF Core"),
        ("Hành vi khi Quá tải", "Ưu tiên tối thượng, không bao giờ ngắt", "Mạch cầu dao Circuit Breaker bật HTTP 429"),
        ("Hạ tầng Cảnh báo", "Bắn ngay FCM High-Priority Data Siren", "Lưu trữ thẩm định nền (Clinical Engine)")
    ]
    docx_helper.add_styled_table(doc, dual_lane_specs[0], dual_lane_specs[1:], col_widths=[1.8, 2.3, 2.4])

    docx_helper.add_heading_2(doc, "3.3 Kiến Trúc Frontend Đa Tầng (Flutter + Native Android + Wear OS)")
    docx_helper.add_paragraph(doc, 
        "Kiến trúc ứng dụng máy khách kết hợp giữa tầng giao diện cấp cao bằng Flutter (cho trải nghiệm mượt mà, đa nền tảng) và tầng cầu nối Native Kernel Hardened bằng Kotlin (để làm chủ tuyệt đối các API nhạy cảm của hệ điều hành Android):",
        bold_prefix="Phân tầng Công nghệ: ")
    
    docx_helper.add_bullet(doc, "Tầng Flutter UI & Riverpod State Management: Quản lý luồng giao diện người dùng, đếm ngược 30 giây trực quan, xác thực sinh trắc học và hiển thị bản đồ số.", bold_prefix="Tầng Trình diễn (UI): ")
    docx_helper.add_bullet(doc, "Tầng Native Platform Bridge (MethodChannel): Cầu nối 2 chiều giữa Flutter và nhân Android. Lắng nghe tín hiệu ngã từ đồng hồ, quản lý vũ trang AlarmManager RTC_WAKEUP, và kích hoạt Full-Screen Intent đánh thức màn hình khóa.", bold_prefix="Tầng Cầu nối Hệ điều hành: ")
    docx_helper.add_bullet(doc, "Tầng Galaxy Watch (Wear OS): Sử dụng Passive Data Services lắng nghe cảm biến gia tốc và nhịp tim. Khi phát hiện ngã, kích hoạt đồng thời 2 luồng độc lập có bảo vệ timeout (Kênh 1: MessageClient fast-lane 2000ms; Kênh 2: DataClient persistent store-and-forward 3000ms), loại bỏ hoàn toàn sự cố nghẽn luồng đơn.", bold_prefix="Tầng Cảm biến Đồng hồ: ")

    docx_helper.add_heading_2(doc, "3.4 Chuỗi Bảo Vệ Khởi Động Máy Direct Boot & Outbox Cục Bộ")
    docx_helper.add_paragraph(doc, 
        "Nhằm giải quyết triệt để trường hợp điện thoại của cụ bị tắt nguồn hoặc khởi động lại nhưng đang nằm ở màn hình khóa chưa mở (Before User Unlock), CareAI ứng dụng công nghệ Direct Boot của Android:",
        bold_prefix="Cơ chế Direct Boot: ")
    docx_helper.add_bullet(doc, "Sử dụng Device Protected Storage Context (`context.createDeviceProtectedStorageContext()`): Cho phép đọc và ghi dữ liệu khẩn cấp ngay cả khi bộ nhớ máy vẫn đang bị mã hóa theo mật khẩu người dùng.", bold_prefix="Bộ nhớ Đĩa Bảo vệ: ")
    docx_helper.add_bullet(doc, "Đăng ký `PhoneBootReceiver` với cờ `android:directBootAware=\"true\"` trong AndroidManifest, đồng thời đón nhận cả 2 sự kiện: `LOCKED_BOOT_COMPLETED` (trước mở khóa) và `BOOT_COMPLETED` (sau mở khóa). Quét sạch các sự cố tồn đọng và lập tức bắn bù Outbox SOS lên đám mây.", bold_prefix="Tiếp nhận Khởi động Sớm: ")

    doc.add_page_break()

    # =========================================================================
    # PHẦN IV
    # =========================================================================
    docx_helper.add_heading_1(doc, "PHẦN IV: CÔNG NGHỆ, TIÊU CHUẨN KỸ THUẬT & AN TOÀN THÔNG TIN")
    
    docx_helper.add_heading_2(doc, "4.1 Danh Mục Công Nghệ Nền Tảng (Technology Stack Selection)")
    docx_helper.add_paragraph(doc, "Hệ thống lựa chọn các công nghệ hiện đại, ổn định (LTS) và được chứng minh thực tế:", bold_prefix="Chuẩn hóa Công nghệ: ")
    
    tech_stack = [
        ("Thành phần", "Công nghệ Lựa chọn", "Phiên bản", "Lý do Kỹ thuật Lựa chọn"),
        ("Backend Framework", "ASP.NET Core Kestrel", ".NET 9 LTS (C# 13)", "Hiệu năng xử lý HTTP I/O hàng đầu thế giới, quản lý bộ nhớ Native AOT/Span<T>."),
        ("ORM / Data Access", "Entity Framework Core", "9.0.2 (LTS Ổn định)", "Hỗ trợ Filtered Index, Temporal Tables, Bulk Operations, loại bỏ bản preview lỗi."),
        ("Cơ sở Dữ liệu", "Azure SQL Database", "General Purpose / Serverless", "Tuân thủ chuẩn ACID tuyệt đối, chỉ mục không gian địa lý, tương thích 100% T-SQL."),
        ("Ứng dụng Di động", "Flutter Framework", "3.29+ (Dart 3.7+)", "Một mã nguồn cho cả iOS và Android, quản lý trạng thái bằng Riverpod reactive."),
        ("Cầu nối Hệ điều hành", "Android Native (Kotlin)", "Kotlin 2.0 / Android 14+", "Truy cập trực tiếp kernel AlarmManager, Direct Boot, Full-Screen Intent."),
        ("Thiết bị Đeo", "Wear OS SDK / Health Services", "API 34+ (Samsung GW6)", "Đo đạc gia tốc và sinh hiệu liên tục qua Passive Data Binding tiết kiệm pin."),
        ("Đẩy Thông báo", "Firebase Cloud Messaging", "FCM HTTP v1 API", "Thông báo Data Message độ ưu tiên cao (High-Priority), đánh thức ứng dụng ngầm.")
    ]
    docx_helper.add_styled_table(doc, tech_stack[0], tech_stack[1:], col_widths=[1.5, 1.8, 1.4, 1.8])

    docx_helper.add_heading_2(doc, "4.2 Tiêu Chuẩn Thiết Kế Trợ Năng Cho Người Cao Tuổi (WCAG 2.1 AA)")
    docx_helper.add_paragraph(doc, 
        "Nhằm bảo đảm người cao tuổi (thị lực suy giảm, ngón tay run, phản xạ chậm) có thể sử dụng ứng dụng dễ dàng, giao diện CareAI tuân thủ nghiêm ngặt Hướng dẫn Tiếp cận Nội dung Web (WCAG 2.1 Level AA):",
        bold_prefix="Quy chuẩn Trợ năng UI: ")
    docx_helper.add_bullet(doc, "Tỷ lệ tương phản màu chữ và nền đạt tối thiểu 4.5:1 đối với văn bản thông thường và 7:1 đối với các nút bấm cảnh báo khẩn cấp.", bold_prefix="Độ tương phản Màu sắc: ")
    docx_helper.add_bullet(doc, "Diện tích vùng chạm tương tác (Touch Target Size) đạt tối thiểu 48x48 dp (khuyến nghị 64x64 dp cho nút HỦY BÁO ĐỘNG NGÃ) để tránh bấm nhầm.", bold_prefix="Kích thước Vùng chạm: ")
    docx_helper.add_bullet(doc, "Không phụ thuộc đơn thuần vào màu sắc để truyền đạt thông tin: Luôn đi kèm biểu tượng (Icon), nhãn chữ rõ ràng và phản hồi rung xúc giác (Haptic Feedback) đa tầng.", bold_prefix="Đa giác quan: ")

    docx_helper.add_heading_2(doc, "4.3 Chuẩn Dữ Liệu Y Tế HL7 FHIR R4 Alignment")
    docx_helper.add_paragraph(doc, 
        "Mặc dù là nền tảng trợ năng phi lâm sàng (Non-SaMD), CareAI cấu trúc hóa toàn bộ dữ liệu sinh hiệu tương thích với Chuẩn trao đổi dữ liệu y tế quốc tế HL7 FHIR R4 (Fast Healthcare Interoperability Resources). Mỗi mẫu đo được ánh xạ tới tài nguyên `Observation` (ví dụ: LOINC code `8867-4` cho Nhịp tim, `8480-6` cho Huyết áp tâm thu, `2708-6` cho SpO2), sẵn sàng cho việc xuất dữ liệu khám bệnh cho bác sĩ gia đình trong tương lai.",
        bold_prefix="Tương thích Y tế Quốc tế: ")

    docx_helper.add_heading_2(doc, "4.4 Tiêu Chuẩn Mã Hóa & An Toàn Thông Tin Mạng")
    docx_helper.add_paragraph(doc, "Bảo vệ toàn vẹn và chống nghe lén dữ liệu trên toàn bộ hành trình:", bold_prefix="Cơ chế Bảo mật Đa tầng: ")
    docx_helper.add_bullet(doc, "Toàn bộ API yêu cầu kết nối HTTPS bắt buộc với giao thức mã hóa TLS 1.3 và bộ mã hóa ciphersuites hiện đại.", bold_prefix="Mã hóa Kênh truyền: ")
    docx_helper.add_bullet(doc, "Xác thực thiết bị bằng API Token ngẫu nhiên 32-byte độ hỗn loạn cao (Cryptographic RNG), lưu mã băm SHA-256 chữ thường nhất quán trên CSDL, đối soát bằng thuật toán so sánh thời gian bất biến `FixedTimeEquals` chống tấn công Timing Attack.", bold_prefix="Mã hóa Khóa Thiết bị: ")
    docx_helper.add_bullet(doc, "Chống tấn công Broken Object Level Authorization (BOLA): Mọi yêu cầu truy vấn hay gửi dữ liệu đều được kiểm tra chéo quyền sở hữu giữa Caregiver, Device và ElderProfile trong CSDL.", bold_prefix="Chống BOLA / IDOR: ")

    doc.add_page_break()

    # =========================================================================
    # PHẦN V
    # =========================================================================
    docx_helper.add_heading_1(doc, "PHẦN V: KẾ HOẠCH THỰC HIỆN, LỘ TRÌNH TRIỂN KHAI & QUẢN TRỊ DỰ ÁN")
    
    docx_helper.add_heading_2(doc, "5.1 Lộ Trình Thực Hiện 5 Giai Đoạn (5-Phase Phased Roadmap)")
    docx_helper.add_paragraph(doc, "Lộ trình triển khai dự án được tổ chức khoa học, chia thành 5 giai đoạn cuốn chiếu:", bold_prefix="Phân kỳ Triển khai: ")
    
    roadmap_phases = [
        ("Giai đoạn 1", "Khởi tạo Nền tảng & Onboarding Ghép nối", "Tuần 1 - Tuần 3", "Dựng CSDL Azure SQL, triển khai Kestrel API, viết màn hình Onboarding và cấp quyền Android Native."),
        ("Giai đoạn 2", "Hoàn thiện Dual-Lane Telemetry & Watchdog", "Tuần 4 - Tuần 6", "Lập trình Fast-Lane SOS, Batch-Lane Health Connect, SQLite Spool, và kernel AlarmManager watchdog."),
        ("Giai đoạn 3", "FCM Quorum Siren & Clinical Engine", "Tuần 7 - Tuần 9", "Tích hợp còi hú FCM đa người thân, logic Acknowledge đồng thời, và thuật toán cảnh báo lâm sàng."),
        ("Giai đoạn 4", "Kiểm thử Thực địa HIL & Đóng sổ Lỗ hổng", "Tuần 10 - Tuần 12", "Chạy toàn bộ 8 kịch bản kiểm thử phần cứng HIL với ADB, đóng sổ 34 điểm kiểm toán, tối ưu tài nguyên."),
        ("Giai đoạn 5", "Triển khai Pilot Thực tế & Bàn giao", "Tuần 13 - Tuần 14", "Đưa vào vận hành thử nghiệm cho 5-10 hộ gia đình, theo dõi chỉ số SLO/SLA, hoàn thiện báo cáo nghiệm thu.")
    ]
    docx_helper.add_styled_table(doc, ["Giai Đoạn", "Nội Dung Công Việc Trọng Tâm", "Thời Gian", "Kết Quả Đầu Ra (Deliverables)"], roadmap_phases, col_widths=[1.2, 2.3, 1.2, 1.8])

    docx_helper.add_heading_2(doc, "5.2 Ma Trận Phân Công Trách Nhiệm RACI Matrix")
    docx_helper.add_paragraph(doc, "Phân định rõ ràng trách nhiệm giữa các vai trò trong nhóm phát triển (R: Thực hiện, A: Trách nhiệm giải trình, C: Tham vấn, I: Nhận thông tin):", bold_prefix="Quản trị Nhân sự RACI: ")
    
    raci_data = [
        ("Hạng mục Công việc", "PO", "Architect", "Backend", "Mobile/Native", "QA/Test", "Legal"),
        ("Đặc tả Use Case & Yêu cầu", "A", "C", "I", "I", "C", "C"),
        ("Thiết kế Kiến trúc Dual-Lane", "I", "A", "R", "R", "C", "I"),
        ("Lập trình Kestrel Backend & CSDL", "I", "C", "A/R", "I", "C", "I"),
        ("Lập trình Mobile Flutter & Wear OS", "I", "C", "I", "A/R", "C", "I"),
        ("Kiểm thử Tự động & HIL Matrix", "I", "C", "R", "R", "A/R", "I"),
        ("Soát xét Pháp lý Non-SaMD & PDPD", "C", "C", "I", "I", "I", "A/R"),
        ("Triển khai Đám mây & Vận hành", "I", "C", "A/R", "I", "C", "I")
    ]
    docx_helper.add_styled_table(doc, raci_data[0], raci_data[1:], col_widths=[2.3, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7])

    docx_helper.add_heading_2(doc, "5.3 Ma Trận Phân Định Thứ Bậc Hạ Tầng: Sandbox (F1) vs Pilot Production (B1)")
    docx_helper.add_paragraph(doc, 
        "CareAI phân định minh bạch tuyệt đối 2 cấp độ hạ tầng, tránh nhầm lẫn giữa môi trường chấm đồ án và môi trường vận hành bảo vệ sinh mạng thực tế:",
        bold_prefix="Định mức Hạ tầng & Chi phí: ")
    
    infra_matrix = [
        ("Tiêu chí Đánh giá", "Tầng 1: Capstone / Sandbox Tier", "Tầng 2: Assistive Pilot Production Tier"),
        ("Mục tiêu Sử dụng", "Bảo vệ đồ án tốt nghiệp, chạy test tự động, demo.", "Thử nghiệm thực địa bảo vệ người cao tuổi gia đình."),
        ("Azure App Service", "Free Tier (F1) - 60 phút CPU/ngày.", "Basic Tier (B1) - 1 Core, 1.75GB RAM, Always On."),
        ("Cam kết SLA", "Không có cam kết SLA (0% SLA).", "99.95% SLA chính thức từ Microsoft Azure."),
        ("Hành vi Background", "App Service tự sleep sau 20 phút không request.", "Always On hoạt động liên tục 24/7 không bao giờ tắt."),
        ("Chi phí Vận hành", "0 VND / tháng (Hoàn toàn miễn phí).", "~$18 USD / tháng (~450.000 VND / tháng)."),
        ("Mức độ An toàn Thực tế", "KHÔNG ĐỦ ĐIỀU KIỆN vận hành bảo vệ người thật.", "ĐỦ ĐIỀU KIỆN vận hành pilot gia đình an toàn.")
    ]
    docx_helper.add_styled_table(doc, infra_matrix[0], infra_matrix[1:], col_widths=[1.8, 2.3, 2.4])

    docx_helper.add_heading_2(doc, "5.4 Kế Hoạch Dự Phòng Rủi Ro & Chiến Lược Rollback")
    docx_helper.add_paragraph(doc, "Quy trình ứng phó các sự cố hạ tầng và lỗi phần mềm trong quá trình vận hành:", bold_prefix="Quản trị Rủi ro: ")
    docx_helper.add_bullet(doc, "Nếu bản cập nhật Backend phát sinh lỗi nghiêm trọng: Kích hoạt tính năng Deployment Slots trên Azure App Service để tráo đổi (Swap) về phiên bản trước đó trong thời gian dưới 10 giây mà không gián đoạn kết nối.", bold_prefix="Rollback Backend 0-Downtime: ")
    docx_helper.add_bullet(doc, "Toàn bộ script DDL thay đổi lược đồ đều được viết theo nguyên tắc Tương thích Ngược (Backward Compatible) và Có tính lũy biến (Idempotent), bảo đảm CSDL phiên bản mới vẫn phục vụ tốt phiên bản app cũ.", bold_prefix="Idempotent Database Migration: ")
    docx_helper.add_bullet(doc, "Nếu dịch vụ Firebase Cloud Messaging bị sự cố diện rộng: Hệ thống tự động chuyển đổi sang kênh dự phòng gửi tin nhắn SMS khẩn cấp qua cổng Twilio / Brandname SMS.", bold_prefix="Kênh Cảnh báo Dự phòng SMS: ")

    doc.add_page_break()

    # =========================================================================
    # PHẦN VI
    # =========================================================================
    docx_helper.add_heading_1(doc, "PHẦN VI: CÁC KẾ HOẠCH BỔ TRỢ: ĐẢM BẢO CHẤT LƯỢNG (QA), VẬN HÀNH & ĐÀO TẠO")
    
    docx_helper.add_heading_2(doc, "6.1 Kế Hoạch Đảm Bảo Chất Lượng (Quality Assurance & Test Strategy)")
    docx_helper.add_paragraph(doc, 
        "Hệ thống CareAI áp dụng mô hình Kim tự tháp Kiểm thử (Testing Pyramid) với 4 tầng kiểm định độc lập:",
        bold_prefix="Chiến lược QA Toàn diện: ")
    docx_helper.add_bullet(doc, "Tầng Unit Testing (36 Facts xUnit): Kiểm chứng 100% các bất biến vật lý của hệ thống: từ tính nguyên tử của Outbox, tính nhất quán của mã băm Lowercase, khử trùng lặp đa thiết bị, cho đến logic chuyển trạng thái Watchdog.", bold_prefix="1. Kiểm thử Đơn vị Cốt lõi: ")
    docx_helper.add_bullet(doc, "Tầng Integration Testing: Kiểm thử luồng gửi dữ liệu viễn trắc xuyên suốt từ Kestrel API xuống CSDL Azure SQL và đo lường thời gian phản hồi.", bold_prefix="2. Kiểm thử Tích hợp: ")
    docx_helper.add_bullet(doc, "Tầng Hardware-in-the-Loop (HIL Matrix 8 kịch bản): Dùng điện thoại và đồng hồ thật kết nối công cụ ADB giả lập toàn bộ các tình huống ngặt nghèo của hệ điều hành (Doze mode, Kill app, Airplane mode, Reboot).", bold_prefix="3. Kiểm thử Phần cứng Thực địa: ")
    docx_helper.add_bullet(doc, "Tầng User Acceptance Testing (UAT): Người thân và người già trực tiếp trải nghiệm thao tác trên giao diện app, đánh giá độ nhạy và mức độ hài lòng.", bold_prefix="4. Kiểm thử Chấp nhận Người dùng: ")

    docx_helper.add_heading_2(doc, "6.2 Kế Hoạch Vận Hành & Giám Sát Hệ Thống (Operations & Observability)")
    docx_helper.add_paragraph(doc, "Đảm bảo tính sẵn sàng và khả năng quan sát sâu vào hệ thống đang chạy:", bold_prefix="Giám sát Chủ động: ")
    docx_helper.add_bullet(doc, "Cung cấp sẵn 2 endpoint kiểm tra sức khỏe độc lập `/health` (Health Probe tổng thể) và `/healthz` (Liveness Probe cho máy chủ đám mây). Cả 2 endpoint được cấu hình bypass middleware xác thực để Azure App Service giám sát 24/7 mà không bị chặn 401.", bold_prefix="Health Check Probes: ")
    docx_helper.add_bullet(doc, "Tích hợp Application Insights và Structured Logging (Serilog) ghi vết toàn bộ các sự kiện quan trọng (Ghép nối thiết bị, Phát SOS, Cảnh báo ngã, Quá tải hàng đợi RAM).", bold_prefix="Nhật ký Có cấu trúc: ")
    docx_helper.add_bullet(doc, "Thiết lập cảnh báo tự động về điện thoại của DevOps Lead nếu tỷ lệ lỗi HTTP 5xx vượt quá 1% trong 5 phút liên tục.", bold_prefix="Cảnh báo Tự động: ")

    docx_helper.add_heading_2(doc, "6.3 Kế Hoạch Đào Tạo & Bàn Giao Hướng Dẫn Sử Dụng")
    docx_helper.add_paragraph(doc, "Kế hoạch hỗ trợ người dùng cuối làm chủ hệ thống trong tuần đầu tiên tiếp nhận:", bold_prefix="Chuyển giao Công nghệ: ")
    docx_helper.add_bullet(doc, "Tài liệu Hướng dẫn Người thân (Caregiver Quickstart Guide): Cung cấp tài liệu minh họa trực quan 4 bước ghép nối thiết bị, cấu hình ngưỡng nhịp tim và quy trình phân vai ứng phó khi có chuông còi hú cấp cứu.", bold_prefix="Cẩm nang Gia đình: ")
    docx_helper.add_bullet(doc, "Thẻ Hướng dẫn Đeo Đồng hồ Cho Người Cao Tuổi: Thẻ gấp gọn khổ A6 in màu chữ to, hướng dẫn cụ cách đeo đồng hồ vừa vặn cổ tay (để cảm biến quang học đo chính xác), cách cắm sạc nam châm mỗi tối và cách bấm nút SOS khi cần trợ giúp.", bold_prefix="Cẩm nang Người già: ")
    docx_helper.add_bullet(doc, "Đường dây Nóng Hỗ trợ Kỹ thuật: Thiết lập nhóm Zalo hỗ trợ kỹ thuật trực tiếp cho các hộ gia đình tham gia đợt thử nghiệm Pilot.", bold_prefix="Kênh Hỗ trợ 24/7: ")

    # LƯU FILE WORD
    output_filename = "CareAI_Tap_1_Yeu_Cau_Kien_Truc_Phap_Ly_Va_Ke_Hoach_Trien_Khai.docx"
    doc.save(output_filename)
    print(f"XUẤT BẢN THÀNH CÔNG TẬP 1: {output_filename} (Kích thước: {os.path.getsize(output_filename):,} bytes)")

if __name__ == '__main__':
    generate_volume_1()
