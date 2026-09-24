# HƯỚNG DẪN CẤU TRÚC THƯ MỤC & PHÂN HỆ HỆ THỐNG CAREAI v111.0
## (CAREAI SYSTEM ARCHITECTURE, DIRECTORY MAPPING & DEVELOPER ORIENTATION)

> **Tài liệu tham chiếu chuẩn cho toàn bộ lập trình viên, kỹ sư tích hợp và người tiếp nhận dự án.**
> Giải thích chi tiết và phân định minh bạch từng phân hệ: Backend, Frontend, App trung gian (Companion App), App đồng hồ (Wear OS), và App người thân (Caregiver App).
> Toàn bộ giải pháp và mã nguồn được đóng gói độc lập trong thư mục riêng: **`CareAI/`**.

---

## 1. BẢNG TRA CỨU NHANH CÁC PHÂN HỆ (QUICK COMPONENT MAPPING)

| STT | Phân Hệ / Thành Phần | Thư Mục Trong Mã Nguồn | Ngôn Ngữ & Công Nghệ | Vai Trò & Thiết Bị Chạy |
| :---: | :--- | :--- | :--- | :--- |
| **0** | **Solution Tập Trung** | `CareAI/CareAI.slnx` | XML .NET Solution | Quản lý cấu trúc Solution liên kết các dự án C# Backend và Kiểm thử tự động. |
| **1** | **Backend Server** | `CareAI/src/`<br>• `CareAI/src/CareAI.API/`<br>• `CareAI/src/CareAI.Core/`<br>• `CareAI/src/CareAI.Infrastructure/` | C# (.NET 9.0 LTS)<br>EF Core 9.0.2<br>ASP.NET Core Kestrel | **Máy chủ điều phối trung tâm** (Sovereign Modular Monolith). Kết nối CSDL SQL Server / Azure SQL Cloud, xử lý 16 Use Case, xác thực Token SHA-256 (`.ToLowerInvariant()`), phân phối Quorum Alerting. Chạy trên máy tính hoặc máy chủ đám mây. |
| **2** | **App Trung Gian Người Già (Companion App)** | `CareAI/companion_app/`<br>• `companion_app/lib/`<br>• `companion_app/android/app/` | Flutter 3.x (Dart)<br>Android Native (Kotlin)<br>Direct Boot Storage | **Trạm trung chuyển cầm tay**. Cài trên điện thoại đặt cạnh người cao tuổi (ví dụ: Samsung Galaxy A55 5G). Thu nhận nhịp tim/SpO2 từ đồng hồ qua Bluetooth, lưu trữ cục bộ Direct Boot (`CareAiFallStore`), hiển thị nút SOS khẩn cấp, phát còi hú 1350Hz ISO 60601-1-8 khi phát hiện ngã. |
| **3** | **App Đồng Hồ Thông Minh (Wear OS Module)** | `CareAI/companion_app/android/wearos/` | Kotlin Native<br>AndroidX Wear OS<br>Google Health Services | **Bộ viễn trắc cổ tay**. Cài trên đồng hồ thông minh (Samsung Galaxy Watch 4/5/6/7 hoặc Wear OS Emulator). Mặc định chạy dịch vụ nền `WearOsFallListenerService` bảo tồn pin 300mAh. Khi phát hiện té ngã, lập tức kích hoạt rung Haptic và bắn gói tin viễn trắc Fast-Lane sang điện thoại. Giao diện dạng tròn (OLED Capsule Pill Shapes). |
| **4** | **App Người Thân / Con Cháu (Caregiver App)** | `CareAI/caregiver_app/`<br>• `caregiver_app/lib/` | Flutter 3.x (Dart)<br>Package ID: `vn.careai.caregiver` | **Ứng dụng theo dõi cho con cháu**. Cài trên điện thoại di động riêng của người thân. Cho phép đăng nhập/đăng ký (UC-01), xem danh sách người cao tuổi và bảng sinh hiệu trực tiếp (BPM, SpO2, Pin), nhận còi hú Quorum tức thì khi có sự cố té ngã (UC-08), bấm Tiếp nhận cứu hộ (ACK) và Đóng sự cố an toàn (Resolve). |
| **5** | **Bộ Kiểm Thử Tự Động (Automated Unit Tests)** | `CareAI/tests/CareAI.UnitTests/` | C# xUnit, FluentAssertions<br>EF Core In-Memory | **Kiểm chứng tính đúng đắn toàn diện** (36/36 Facts Passed). Bảo vệ các bất biến nghiệp vụ, kiểm tra bảo mật BOLA (UC-02), kiểm soát truy cập đồng thời OCC Concurrency `RowVersion`, và chống trùng lặp sự cố (`UIX_Incidents_SingleActiveElder`). |
| **6** | **Tài Liệu Kế Hoạch & Hướng Dẫn Kỹ Thuật** | Thư mục gốc (`/`) | Markdown & Word DOCX | Bao gồm Kế hoạch Master v111.0, Tập 1 & Tập 2 chuẩn pháp lý Non-SaMD, Cẩm nang phân hệ, và Hướng dẫn cài đặt môi trường. |

---

## 2. SƠ ĐỒ KIẾN TRÚC DÒNG DỮ LIỆU GIỮA CÁC THƯ MỤC

```mermaid
flowchart TD
    subgraph Wearable["1. ĐỒNG HỒ THÔNG MINH (Wear OS)"]
        W[CareAI/companion_app/android/wearos<br>• Cảm biến gia tốc IMU & Nhịp tim PPG<br>• Dịch vụ ngầm WearOsFallListenerService<br>• Giao diện tròn OLED Pill Shapes]
    end

    subgraph Companion["2. ĐIỆN THOẠI TRUNG GIAN (Companion Phone)"]
        CP[CareAI/companion_app<br>• Flutter UI cho người cao tuổi<br>• Kotlin Native Direct Boot Watchdog<br>• Còi hú y tế 1350Hz SoundPool<br>• Bộ đệm khẩn cấp Outbox-First DPS]
    end

    subgraph Backend["3. MÁY CHỦ TRUNG TÂM (Central Backend)"]
        API[CareAI/src/CareAI.API<br>RESTful Web API .NET 9 LTS]
        Core[CareAI/src/CareAI.Core<br>Domain Entities, Use Cases & Interfaces]
        Infra[CareAI/src/CareAI.Infrastructure<br>EF Core 9.0.2, Azure SQL DB & Repository]
    end

    subgraph Caregiver["4. ĐIỆN THOẠI NGƯỜI THÂN (Caregiver Phone)"]
        CG[CareAI/caregiver_app<br>• Flutter Mobile App độc lập<br>• Package ID: vn.careai.caregiver<br>• Giám sát sinh hiệu trực tiếp<br>• Nhận Quorum Alerting còi hú cấp cứu<br>• Tiếp nhận cứu hộ ACK & Resolve]
    end

    W -- "Bluetooth Low Energy / Fast-Lane (Port 5097)" --> CP
    CP -- "Kênh kép: Cáp USB (adb reverse) HOẶC Cloudflare Internet Tunnel" --> API
    API --> Core
    API --> Infra
    Infra -- "SQL Server / Azure SQL Cloud" --> DB[(Database: CareAiDb)]
    API -- "Thông báo Quorum SOS & Đồng bộ Sinh hiệu" --> CG
```

---

## 3. HƯỚNG DẪN CHI TIẾT TỪNG THÀNH PHẦN

### 3.1 Thư mục Backend (`CareAI/src/`)
- **Vị trí**:
  - `CareAI/src/CareAI.API`: Điểm vào ứng dụng (Entry point), chứa Controllers, Middlewares xác thực thiết bị `X-DeviceId` và SHA-256 token hashing, cấu hình Dependency Injection, và Swagger UI.
  - `CareAI/src/CareAI.Core`: Lớp trung tâm Domain, chứa các thực thể nghiệp vụ (`ElderProfile`, `DeviceRegistration`, `Incident`, `BiometricTelemetry`), các DTOs, và các Interfaces.
  - `CareAI/src/CareAI.Infrastructure`: Lớp hạ tầng, chứa `AppDbContext`, EF Core 9.0.2 Mappings, Filtered Unique Index `UIX_Incidents_SingleActiveElder`, và Triển khai các Repository.
  - File Solution chính: `CareAI/CareAI.slnx`.
- **Cách mở và làm việc**:
  - Dùng **Visual Studio 2022** mở file `CareAI/CareAI.slnx`.
  - Hoặc dùng **VS Code** mở thư mục `CareAI` và dùng extension C# Dev Kit.
- **Lệnh chạy**:
  ```powershell
  dotnet run --project CareAI/src/CareAI.API/CareAI.API.csproj
  ```
- **Kiểm tra trạng thái**: Mở trình duyệt truy cập `http://localhost:5097/health` -> Nhận kết quả `Healthy`.
- **Cấu hình CSDL**: Chỉnh sửa tại `CareAI/src/CareAI.API/appsettings.json` (hỗ trợ chuyển đổi linh hoạt giữa SQL Server Express cục bộ và Azure SQL Database trên Cloud).

---

### 3.2 Thư mục App Trung Gian Người Già (`CareAI/companion_app/`)
- **Vị trí**: `CareAI/companion_app/`
  - `CareAI/companion_app/lib/`: Mã nguồn giao diện Flutter (Giao diện người già, Nút bấm SOS trung tâm, Hộp thoại đếm ngược 30 giây khi té ngã, Quản lý trạng thái bằng Riverpod).
  - `CareAI/companion_app/android/app/src/main/kotlin/vn/careai/companion/`: Lớp bảo vệ Native Android sống còn:
    * `DirectBootFallReceiver.kt`: Bắt sự kiện `LOCKED_BOOT_COMPLETED`, đánh thức tiến trình ngay khi khởi động lại máy dù chưa mở khóa.
    * `FallWatchdogService.kt`: AlarmManager `RTC_WAKEUP` bảo vệ đếm ngược 35 giây phá vỡ Deep Doze Mode.
    * `EmergencySoundPlayer.kt`: Bộ phát còi hú y tế phần cứng `SoundPool` tần số 1350Hz ISO 60601-1-8 độ trễ 0ms.
    * `CareAiFallStore.kt`: Kho lưu trữ trạng thái Direct Boot trên chip nhớ flash phần cứng.
- **Cách mở**:
  - Mở thư mục `CareAI/companion_app` bằng **Android Studio** hoặc **VS Code**.
- **Lệnh chạy thử nghiệm**:
  ```powershell
  cd CareAI/companion_app
  flutter pub get
  flutter run
  ```

---

### 3.3 Thư mục App Đồng Hồ (`CareAI/companion_app/android/wearos/`)
- **Vị trí**: Nằm bên trong thư mục Android của companion_app (`CareAI/companion_app/android/wearos/`).
- **Bản chất**: Đây là một Gradle sub-module độc lập (`:wearos`) chạy trực tiếp trên hệ điều hành Wear OS của đồng hồ thông minh.
  - `WearOsMainActivity.kt`: Màn hình OLED tròn tối ưu năng lượng hiển thị nhịp tim BPM, nồng độ SpO2 và 2 nút bấm thao tác dạng viên nhộng (Capsule Pills).
  - `WearOsFallListenerService.kt`: Dịch vụ nền bắt tín hiệu gia tốc từ chip cảm biến Sensor Hub.
  - `res/layout/activity_wear_main.xml`: Sử dụng `BoxInsetLayout` với thuộc tính `app:boxedEdges="left|right"` đảm bảo không bị viền tròn của đồng hồ cắt lẹm nội dung.
- **Cách biên dịch độc lập cho đồng hồ**:
  ```powershell
  cd CareAI/companion_app/android
  ./gradlew :wearos:assembleDebug
  ```
- **Cài đặt lên đồng hồ (thật hoặc máy ảo Wear OS)**:
  ```powershell
  adb -s emulator-5554 install -r wearos/build/outputs/apk/debug/wearos-debug.apk
  ```

---

### 3.4 Thư mục App Người Thân / Con Cháu (`CareAI/caregiver_app/`)
- **Vị trí**: `CareAI/caregiver_app/`
- **Bản chất**: Ứng dụng di động Flutter **hoàn toàn độc lập** với `companion_app`, sở hữu Package ID riêng là `vn.careai.caregiver`.
  - Giúp con cháu từ xa nhận cảnh báo khẩn cấp, xem vị trí và sinh hiệu của cha mẹ/ông bà.
  - Có thể cài song song trên cùng 1 chiếc điện thoại với `companion_app` để lập trình viên tự kiểm thử luồng cấp cứu 2 chiều mà không cần 2 máy điện thoại thật.
- **Tính năng đã triển khai**:
  - `login_screen.dart`: Đăng nhập/Đăng ký tài khoản người thân (UC-01).
  - `caregiver_home_screen.dart`: Bảng điều khiển danh sách cụ, tình trạng nhịp tim, pin, SpO2 (UC-10).
  - `emergency_alert_modal.dart`: Hộp thoại còi hú khẩn cấp Quorum khi cụ gặp sự cố ngã (UC-08).
  - Tiếp nhận xử lý sự cố (ACK) và Đóng sự cố (Resolve) với khóa lạc quan `RowVersion` chống xung đột dữ liệu giữa nhiều người thân.
- **Lệnh chạy**:
  ```powershell
  cd CareAI/caregiver_app
  flutter pub get
  flutter run
  ```

---

### 3.5 Thư mục Kiểm Thử Tự Động (`CareAI/tests/`)
- **Vị trí**: `CareAI/tests/CareAI.UnitTests/`
- **Vai trò**: Chứa toàn bộ 36 bài kiểm thử xUnit Facts bao phủ 16 Use Case sống còn:
  - Fact 01 – Fact 08: Vòng đời sự cố cứu nạn, kiểm soát trạng thái, khóa lọc `UIX_Incidents_SingleActiveElder`.
  - Fact 09 – Fact 14: Xác thực thiết bị `X-DeviceId`, SHA-256 token lowercase, lọc trùng lặp viễn trắc `ProcessedTelemetryLedgers`.
  - Fact 15 – Fact 20: Bảo mật chống leo quyền BOLA, phân quyền Người thân vs Cụ ông.
  - Fact 21 – Fact 36: Đồng bộ dữ liệu Outbox, Khóa lạc quan OCC `RowVersion`, Lưu mẫu sinh hiệu Fast-Lane (Fact 35).
- **Lệnh chạy kiểm thử**:
  ```powershell
  dotnet test CareAI/CareAI.slnx --nologo
  ```
  *(Yêu cầu bắt buộc: 36/36 Facts Passed 100%, 0 Error, 0 Warning).*

---

## 4. DANH MỤC CÁC TỆP TÀI LIỆU KẾ HOẠCH & CHUẨN MỰC BẮT BUỘC

Tại thư mục gốc của repository, các tệp tài liệu được phân loại rõ ràng:

1. **Bộ 3 Tệp Kế Hoạch & Thiết Kế Kiến Trúc Master**:
   - `CareAI_Final_Master_Plan_Airtight_Execution_14_2_3_3.md`: Bản Kế Hoạch Master v111.0 chi tiết hóa toàn bộ các pha triển khai, thông số kỹ thuật và cam kết hệ thống.
   - `CareAI_Tap_1_Yeu_Cau_Kien_Truc_Phap_Ly_Va_Ke_Hoach_Trien_Khai.docx`: Tập 1 chuẩn quy thức – Định vị pháp lý Non-SaMD, Kiến trúc Sovereign Monolith và Đặc tả chi tiết 16 Use Case.
   - `CareAI_Tap_2_Chi_Tiet_Ma_Nguon_CSDL_Va_Kiem_Thu_HIL.docx`: Tập 2 chuẩn quy thức – Chi tiết CSDL quan hệ, mã nguồn từng tầng và 8 kịch bản kiểm thử phần cứng HIL Testing.

2. **Tài Liệu Hướng Dẫn Cài Đặt Môi Trường**:
   - `HUONG_DAN_SETUP_MOI_TRUONG_VA_CHAY_DU_AN_CAREAI.md`: Cẩm nang cài đặt đầy đủ SDK (.NET 9, Java 21, Flutter 3.x, Android SDK 34/36), biến môi trường, thiết bị thật Android (Samsung Galaxy A55 5G), Wear OS Emulator, hướng dẫn môi trường cho iOS/iPhone, và thiết lập mạng kép (Cáp USB + Cloudflare Tunnel).

3. **Cẩm Nang Phân Hệ & Trang Chủ**:
   - `HUONG_DAN_CAU_TRUC_THU_MUC_VA_HE_THONG_CAREAI.md`: Hướng dẫn cấu trúc thư mục và phân định phân hệ.
   - `README.md`: Trang chủ repository trên GitHub.
