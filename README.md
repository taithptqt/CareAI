# CareAI - Hệ Thống Y Tế Từ Xa & Cảnh Báo Cấp Cứu Gia Đình

> **Sovereign Modular Monolith (.NET 9 LTS · Azure SQL · Kotlin Direct Boot · Flutter Riverpod · Wear OS)**  
> **Định vị pháp lý**: Nền tảng Hỗ trợ Cảnh báo Chăm sóc Người cao tuổi (Caregiver Assistive Alerting Platform - Non-SaMD)  
> **Phiên bản chuẩn**: v111.0 (Definitive Production-Hardened Edition)

---

## 📖 BẢNG TRA CỨU NHANH CẤU TRÚC MÃ NGUỒN (THƯ MỤC `CareAI/`)

Toàn bộ mã nguồn và giải pháp thực thi của dự án được tập trung chuẩn chỉ trong thư mục riêng: **[`CareAI/`](./CareAI/)**

Để tìm hiểu chi tiết về từng thành phần mã nguồn, vui lòng xem tài liệu:
👉 **[Hướng Dẫn Cấu Trúc Thư Mục & Phân Hệ Hệ Thống (HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md)](./HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md)**

| Phân Hệ | Đường Dẫn Thư Mục | Công Nghệ & Nền Tảng | Vai Trò Chính |
| :--- | :--- | :--- | :--- |
| **Solution File** | [`CareAI/CareAI.slnx`](./CareAI/CareAI.slnx) | XML .NET Solution | Quản lý toàn bộ các dự án Backend và Kiểm thử tự động. |
| **Backend Server** | [`CareAI/src/`](./CareAI/src/) | C# (.NET 9.0 LTS), EF Core 9.0.2, ASP.NET Core Kestrel | Máy chủ điều phối trung tâm, xử lý 16 Use Case, kết nối CSDL Azure SQL Cloud / SQL Server. |
| **App Trung Gian Cụ Ông / Cụ Bà** | [`CareAI/companion_app/`](./CareAI/companion_app/) | Flutter 3.x, Kotlin Native (Direct Boot, AlarmManager RTC_WAKEUP, SoundPool 1350Hz) | Cài trên điện thoại đặt cạnh người cao tuổi (Samsung Galaxy A55 5G), nhận tín hiệu từ đồng hồ, còi hú SOS. |
| **App Đồng Hồ Thông Minh** | [`CareAI/companion_app/android/wearos/`](./CareAI/companion_app/android/wearos/) | Kotlin Native, AndroidX Wear OS, Google Health Services | Module đồng hồ chạy trên Samsung Galaxy Watch (Wear OS), cảm biến gia tốc IMU/nhịp tim PPG, giao diện tròn OLED. |
| **App Người Thân / Con Cháu** | [`CareAI/caregiver_app/`](./CareAI/caregiver_app/) | Flutter 3.x (Package ID: `vn.careai.caregiver`) | Cài trên điện thoại riêng của con cháu, theo dõi sinh hiệu trực tiếp, nhận Quorum Alerting còi hú khi cụ ngã, tiếp nhận cứu nạn (ACK/Resolve). |
| **Kiểm Thử Tự Động (Unit Tests)** | [`CareAI/tests/CareAI.UnitTests/`](./CareAI/tests/CareAI.UnitTests/) | xUnit, FluentAssertions, EF Core In-Memory | 36 bài kiểm thử Facts chuẩn (36/36 Facts Passed 100%) bảo vệ toàn diện các bất biến nghiệp vụ. |

---

## 📚 BỘ TÀI LIỆU KẾ HOẠCH & HƯỚNG DẪN KỸ THUẬT CHUẨN

1. **[Tài Liệu Hướng Dẫn Cài Đặt Môi Trường & Chạy Dự Án](./HUONG_DAN_SETUP_MOI_TRUONG_VA_CHAY_DU_AN_CAREAI.md)**: Hướng dẫn trọn gói cài đặt SDK (.NET 9, Java 21, Flutter, Android SDK), biến môi trường, kết nối thiết bị thật Android, máy ảo Wear OS, hướng dẫn môi trường cho iOS/iPhone, và mạng dự phòng kép.
2. **[Hướng Dẫn Cấu Trúc Thư Mục & Phân Hệ Hệ Thống](./HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md)**: Cẩm nang chi tiết về cấu trúc mã nguồn, cách mở và chạy độc lập từng phân hệ.
3. **[Kế Hoạch Master v111.0](./CareAI_Final_Master_Plan_Airtight_Execution_14_2_3_3.md)**: Kế hoạch triển khai tổng thể và cam kết kỹ thuật chuẩn.
4. **[Tập 1: Chiến Lược, Pháp Lý Non-SaMD & 16 Use Case](./CareAI_Tap_1_Yeu_Cau_Kien_Truc_Phap_Ly_Va_Ke_Hoach_Trien_Khai.docx)**: Tài liệu đặc tả chuẩn nghiệp vụ và pháp lý y tế.
5. **[Tập 2: Chi Tiết CSDL, Mã Nguồn & 8 Kịch Bản HIL Testing](./CareAI_Tap_2_Chi_Tiet_Ma_Nguon_CSDL_Va_Kiem_Thu_HIL.docx)**: Tài liệu kiểm thử thực địa phần cứng máy thật.

---

## 🚀 KHỞI CHẠY NHANH (QUICK START)

### 1. Chạy Backend Server
```powershell
dotnet run --project CareAI/src/CareAI.API/CareAI.API.csproj
```
Kiểm tra sức khỏe hệ thống: `http://localhost:5097/health` -> Trả về `Healthy`.

### 2. Chạy Kiểm Thử Đơn Vị (36/36 Facts)
```powershell
dotnet test CareAI/CareAI.slnx --nologo
```

### 3. Chạy App Trung Gian (Companion App)
```powershell
cd CareAI/companion_app
flutter pub get
flutter run
```

### 4. Chạy App Người Thân (Caregiver App)
```powershell
cd CareAI/caregiver_app
flutter pub get
flutter run
```

### 5. Biên Dịch Module Đồng Hồ (Wear OS)
```powershell
cd CareAI/companion_app/android
./gradlew :wearos:assembleDebug
```

---

## 🔒 5 BẤT BIẾN KỸ THUẬT BẮT BUỘC
- **Không Microservices / Overengineering**: Duy trì kiến trúc Sovereign Modular Monolith (.NET 9 LTS).
- **Zero-Preview**: Sử dụng phiên bản ổn định chính thức LTS (EF Core 9.0.2).
- **Lowercase SHA-256 Token**: Mã băm token thiết bị luôn dùng `.ToLowerInvariant()`.
- **Mã định danh HTTP Header**: Bắt buộc là `X-DeviceId` (không có gạch nối giữa Device và Id).
- **Direct Boot & RTC_WAKEUP**: App chạy ngầm sử dụng Device Protected Storage trên Android Native.
