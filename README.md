# CareAI - Hệ Thống Y Tế Từ Xa & Cảnh Báo Cấp Cứu Gia Đình

> **Sovereign Modular Monolith (.NET 9 LTS · Azure SQL · Kotlin Direct Boot · Flutter Riverpod · Wear OS)**  
> **Định vị pháp lý**: Nền tảng Hỗ trợ Cảnh báo Chăm sóc Người cao tuổi (Caregiver Assistive Alerting Platform - Non-SaMD)  
> **Phiên bản chuẩn**: v111.0 (Definitive Production-Hardened Edition)

---

## 📖 BẢNG TRA CỨU NHANH CẤU TRÚC THƯ MỤC DỰ ÁN

Để tìm hiểu chi tiết về từng thành phần mã nguồn, vui lòng xem tài liệu:
👉 **[Hướng Dẫn Cấu Trúc Thư Mục & Phân Hệ Hệ Thống (HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md)](./HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md)**

| Phân Hệ | Đường Dẫn Thư Mục | Công Nghệ & Nền Tảng | Vai Trò Chính |
| :--- | :--- | :--- | :--- |
| **Backend Server** | [`src/`](./src/) | C# (.NET 9.0 LTS), EF Core 9.0.2, ASP.NET Core Kestrel | Máy chủ điều phối trung tâm, xử lý 16 Use Case, kết nối CSDL Azure SQL Cloud / SQL Server. |
| **App Trung Gian Cụ Ông / Cụ Bà** | [`companion_app/`](./companion_app/) | Flutter 3.x, Kotlin Native (Direct Boot, AlarmManager RTC_WAKEUP, SoundPool 1350Hz) | Cài trên điện thoại đặt cạnh người cao tuổi (Samsung Galaxy A55 5G), nhận tín hiệu từ đồng hồ, còi hú SOS. |
| **App Đồng Hồ Thông Minh** | [`companion_app/android/wearos/`](./companion_app/android/wearos/) | Kotlin Native, AndroidX Wear OS, Google Health Services | Module đồng hồ chạy trên Samsung Galaxy Watch (Wear OS), cảm biến gia tốc IMU/nhịp tim PPG, giao diện tròn OLED. |
| **App Người Thân / Con Cháu** | [`caregiver_app/`](./caregiver_app/) | Flutter 3.x (Package ID: `vn.careai.caregiver`) | Cài trên điện thoại riêng của con cháu, theo dõi sinh hiệu trực tiếp, nhận Quorum Alerting còi hú khi cụ ngã, tiếp nhận cứu nạn (ACK/Resolve). |
| **Kiểm Thử Tự Động (Unit Tests)** | [`tests/CareAI.UnitTests/`](./tests/CareAI.UnitTests/) | xUnit, FluentAssertions, EF Core In-Memory | 36 bài kiểm thử Facts chuẩn (36/36 Facts Passed 100%) bảo vệ toàn diện các bất biến nghiệp vụ. |

---

## 📚 TÀI LIỆU KẾ HOẠCH & HƯỚNG DẪN KỸ THUẬT

1. **[Tài Liệu Hướng Dẫn Cài Đặt Môi Trường & Chạy Dự Án](./HUONG_DAN_SETUP_MOI_TRUONG_VA_CHAY_DU_AN_CAREAI.md)**: Hướng dẫn trọn gói cài đặt SDK (.NET 9, Java 21, Flutter, Android SDK), biến môi trường, kết nối thiết bị thật Android, máy ảo Wear OS, hướng dẫn môi trường cho iOS/iPhone, và mạng dự phòng kép.
2. **[Hướng Dẫn Cấu Trúc Thư Mục & Phân Hệ Hệ Thống](./HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md)**: Chi tiết về cấu trúc mã nguồn, cách mở và chạy độc lập từng phân hệ.
3. **[Kế Hoạch Master v111.0](./CareAI_Final_Master_Plan_Airtight_Execution_14_2_3_3.md)**: Kế hoạch triển khai tổng thể và cam kết kỹ thuật.
4. **[Tập 1: Chiến Lược, Pháp Lý Non-SaMD & 16 Use Case](./CareAI_Tap_1_Yeu_Cau_Kien_Truc_Phap_Ly_Va_Ke_Hoach_Trien_Khai.docx)**: Tài liệu đặc tả chuẩn nghiệp vụ và pháp lý.
5. **[Tập 2: Chi Tiết CSDL, Mã Nguồn & 8 Kịch Bản HIL Testing](./CareAI_Tap_2_Chi_Tiet_Ma_Nguon_CSDL_Va_Kiem_Thu_HIL.docx)**: Tài liệu kiểm thử thực địa phần cứng.
6. **[Bản Cam Kết Nguyên Tắc Triển Khai CareAI](./CAM_KET_NGUYEN_TAC_TRIEN_KHAI_CAREAI.md)**: 5 điều cấm kỵ và các bất biến kiến trúc kỹ thuật.
7. **[Sổ Tay Kinh Nghiệm Dev & Fix Lỗi Thực Chiến](./SO_TAY_KINH_NGHIEM_DEV_VA_FIX_LOI_CAREAI.md)**: Cẩm nang xử lý lỗi Direct Boot, SoundPool, Mạng kép, Concurrency và Wear OS.
8. **[Bảng Theo Dõi Tiến Trình Dự Án](./TIEN_TRINH_DU_AN_CAREAI.md)**: Nhật ký kiểm toán toàn diện quá trình phát triển dự án.

---

## 🚀 KHỞI CHẠY NHANH (QUICK START)

### 1. Chạy Backend Server
```powershell
dotnet run --project src/CareAI.API/CareAI.API.csproj
```
Kiểm tra sức khỏe hệ thống: `http://localhost:5097/health` -> Trả về `Healthy`.

### 2. Chạy Kiểm Thử Đơn Vị (36/36 Facts)
```powershell
dotnet test --nologo
```

### 3. Chạy App Trung Gian (Companion App)
```powershell
cd companion_app
flutter pub get
flutter run
```

### 4. Chạy App Người Thân (Caregiver App)
```powershell
cd caregiver_app
flutter pub get
flutter run
```

### 5. Biên Dịch Module Đồng Hồ (Wear OS)
```powershell
cd companion_app/android
./gradlew :wearos:assembleDebug
```

---

## 🔒 5 BẤT BIẾN KỸ THUẬT BẮT BUỘC
- **Không Microservices / Overengineering**: Duy trì kiến trúc Sovereign Modular Monolith (.NET 9 LTS).
- **Zero-Preview**: Sử dụng phiên bản ổn định chính thức LTS (EF Core 9.0.2).
- **Lowercase SHA-256 Token**: Mã băm token thiết bị luôn dùng `.ToLowerInvariant()`.
- **Mã định danh HTTP Header**: Bắt buộc là `X-DeviceId` (không có gạch nối giữa Device và Id).
- **Direct Boot & RTC_WAKEUP**: App chạy ngầm sử dụng Device Protected Storage trên Android Native.
