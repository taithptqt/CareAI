# HƯỚNG DẪN THIẾT LẬP MÔI TRƯỜNG & KHỞI CHẠY DỰ ÁN CAREAI v111.0
## (CAREAI DEVELOPER ONBOARDING, ENVIRONMENT SETUP & RUNTIME RUNBOOK)

> **Dành cho**: Thành viên mới tham gia đội ngũ phát triển CareAI, Giảng viên / Hội đồng đánh giá đồ án, hoặc Kỹ sư DevOps muốn clone mã nguồn về máy trạm để tiếp tục lập trình, biên dịch và khởi chạy toàn bộ hệ thống từ đầu.
> **Phiên bản chuẩn**: v111.0 (Production-Hardened Definitive Edition)
> **Kiến trúc cốt lõi**: Sovereign Modular Monolith (.NET 9 LTS · Azure SQL · Kotlin Direct Boot · Flutter Riverpod · Wear OS Native)

---

## MỤC LỤC
1. [Tổng Quan Kiến Trúc & Các Phân Hệ Hệ Thống](#1-tổng-quan-kiến-trúc--các-phân-hệ-hệ-thống)
2. [Yêu Cầu Phần Cứng & Hệ Điều Hành](#2-yêu-cầu-phần-cứng--hệ-điều-hành)
3. [Danh Mục Phần Mềm & SDK Bắt Buộc](#3-danh-mục-phần-mềm--sdk-bắt-buộc)
4. [Cấu Hình Biến Môi Trường (Environment Variables)](#4-cấu-hình-biến-môi-trường-environment-variables)
5. [Thiết Lập Cơ Sở Dữ Liệu (Azure SQL Cloud hoặc Local SQL Server)](#5-thiết-lập-cơ-sở-dữ-liệu-azure-sql-cloud-hoặc-local-sql-server)
6. [Cấu Hình & Khởi Chạy Backend (.NET 9 LTS Kestrel)](#6-cấu-hình--khởi-chạy-backend-net-9-lts-kestrel)
7. [Thiết Lập Thiết Bị Di Động & Giả Lập (Android, Wear OS, iOS)](#7-thiết-lập-thiết-bị-di-động--giả-lập-android-wear-os-ios)
8. [Cấu Hình Mạng Kép Dự Phòng (USB Cable + Cloudflare Internet Tunnel)](#8-cấu-hình-mạng-kép-dự-phòng-usb-cable--cloudflare-internet-tunnel)
9. [Biên Dịch & Cài Đặt Ứng Dụng Di Động (Companion App & Wear OS)](#9-biên-dịch--cài-đặt-ứng-dụng-di-động-companion-app--wear-os)
10. [Quy Trình Kiểm Thử Nhanh Toàn Hệ Thống (End-to-End Verification)](#10-quy-trình-kiểm-thử-nhanh-toàn-hệ-thống-end-to-end-verification)
11. [Sổ Tay 10 Cạm Bẫy Kỹ Thuật Sống Còn Cần Nhớ (Developer Pitfalls)](#11-sổ-tay-10-cạm-bẫy-kỹ-thuật-sống-còn-cần-nhớ-developer-pitfalls)

---

## 1. TỔNG QUAN KIẾN TRÚC & CÁC PHÂN HỆ HỆ THỐNG

Dự án **CareAI** là nền tảng hỗ trợ cảnh báo y tế gia đình từ xa cho người cao tuổi, vận hành theo mô hình kiến trúc **Sovereign Modular Monolith** (không dùng microservices, không Kafka, không Redis để tối ưu chi phí và độ bền bỉ), bao gồm:

```
┌────────────────────────┐         ┌────────────────────────┐
│  GALAXY WATCH WEAR OS  │ (BLE)   │ COMPANION PHONE (A55)  │
│  Thu thập nhịp tim PPG │ ──────> │  Đếm ngược hủy ngã 30s │
│  Bắt gia tốc ngã Edge  │         │  Còi hú y tế 1350Hz RAM│
└────────────────────────┘         └────────────────────────┘
                                               │
                                (USB Cable / Internet Cloudflare)
                                               ▼
                                   ┌────────────────────────┐
                                   │ BACKEND KESTREL .NET 9 │
                                   │  Auth X-DeviceId       │
                                   │  Clinical Rule Engine  │
                                   │  Outbox Push Notif     │
                                   └────────────────────────┘
                                               │
                                               ▼
                                   ┌────────────────────────┐
                                   │ AZURE SQL DATABASE     │
                                   │  UIX Filtered Index    │
                                   │  OCC RowVersion Lock   │
                                   └────────────────────────┘
```

Mã nguồn được tổ chức chuẩn chỉ trong thư mục dự án riêng (`CareAI/`):
- `CareAI/src/CareAI.Core/`: Domain Entities, Enums, Value Objects, Business Invariants.
- `CareAI/src/CareAI.Infrastructure/`: EF Core DbContext, Migration Helper, Clinical Rule Engine, Background Workers.
- `CareAI/src/CareAI.API/`: Kestrel Controllers, Device Token Auth Middleware, Health Checks, Swagger UI.
- `CareAI/tests/CareAI.UnitTests/`: 36 bài kiểm thử xUnit bao phủ 100% các bất biến hệ thống.
- `CareAI/companion_app/`: Ứng dụng di động hợp nhất CareAI (tích hợp cả Chế độ Người cao tuổi và Chế độ Người thân `lib/caregiver/`, cùng module Kotlin Native `:app` Direct Boot và module Native `:wearos` cho đồng hồ).
- `tools/`: Chứa tiện ích đường truyền `cloudflared.exe`.

---

## 2. YÊU CẦU PHẦN CỨNG & HỆ ĐIỀU HÀNH

### 2.1 Yêu Cầu Máy Trạm Phát Triển (Development Workstation)
- **Hệ điều hành**:
  * **Windows 10 / 11 64-bit Pro/Enterprise** *(Khuyến nghị, môi trường chuẩn của dự án)*.
  * **macOS 14+ (Sonoma/Sequoia)** *(Bắt buộc nếu cần biên dịch và chạy trên iPhone / Apple Watch)*.
  * **Linux (Ubuntu 22.04 LTS+)** *(Phù hợp cho máy chủ Backend headless)*.
- **CPU**: Intel Core i5 / AMD Ryzen 5 thế hệ 8 trở lên (tối thiểu 4 nhân vật lý, 8 luồng).
- **RAM**:
  * **Tối thiểu**: 8 GB RAM (chỉ chạy Backend + Cáp USB điện thoại thật).
  * **Khuyến nghị**: **16 GB RAM** (để chạy đồng thời IDE, Backend, và 1 máy ảo Wear OS Emulator).
- **Ổ cứng**: SSD NVMe/SATA còn trống tối thiểu **25 GB** (chứa Android SDK, Flutter SDK, .NET SDK, AVD Images).

---

## 3. DANH MỤC PHẦN MỀM & SDK BẮT BUỘC

Trước khi mở mã nguồn, hãy cài đặt đầy đủ các phần mềm sau theo đúng phiên bản quy định:

| Phần Mềm / SDK | Phiên Bản Chuẩn | Mục Đích Sử Dụng | Đường Dẫn Tải Chính Thức |
| :--- | :--- | :--- | :--- |
| **.NET SDK** | **9.0.3xx LTS** (`net9.0`) | Biên dịch & chạy Backend C# | [dotnet.microsoft.com/download](https://dotnet.microsoft.com/en-us/download/dotnet/9.0) |
| **Java JDK** | **OpenJDK 21 LTS** | Biên dịch Android Gradle / Kotlin 2.x | [adoptium.net (Eclipse Temurin 21)](https://adoptium.net/) |
| **Flutter SDK** | **Flutter 3.x (Dart 3.x)** | Biên dịch Mobile Companion App | [flutter.dev](https://docs.flutter.dev/get-started/install) |
| **Android Studio** | **Ladybug (2024.2+)** hoặc mới hơn | Quản lý Android SDK, AVD Wear OS | [developer.android.com/studio](https://developer.android.com/studio) |
| **Android SDK** | **API Level 34 & 36** | Nền tảng biên dịch Android Native | Cài qua Android Studio SDK Manager |
| **Git** | **Git 2.40+** | Quản lý mã nguồn | [git-scm.com](https://git-scm.com/) |
| **VS Code / Rider / VS**| **Visual Studio 2022 / VS Code**| Biên tập mã nguồn C# và Dart | Tùy chọn theo sở thích của Developer |
| **Cloudflare Tunnel**| `cloudflared.exe` | Tạo HTTPS Tunnel ra Internet | Đã có sẵn trong thư mục `tools/` |

### 3.2 Bảng Tra Cứu & Hướng Dẫn Cài Đặt Toàn Bộ Thư Viện (Dependency Manifest)

Toàn bộ các gói thư viện (packages / dependencies) trong dự án đã được khai báo chính xác với phiên bản tương thích 100%. Lập trình viên không cần tìm kiếm hay tự ý nâng cấp phiên bản ngoài lề.

#### A. Thư Viện Backend .NET 9 LTS (Quản Lý Bằng NuGet)
Được khai báo trong các tệp `.csproj` tại `src/` và `tests/`.

| Tên Package NuGet | Phiên Bản | Phân Hệ Dự Án | Mục Đích Kỹ Thuật |
| :--- | :---: | :--- | :--- |
| `Microsoft.EntityFrameworkCore.SqlServer` | **9.0.2** | Infrastructure | Kết nối ORM với CSDL SQL Server / Azure SQL Cloud. |
| `Microsoft.EntityFrameworkCore.Design` | **9.0.2** | API | Công cụ thiết kế và sinh mã cơ sở dữ liệu EF Core. |
| `Microsoft.EntityFrameworkCore.InMemory` | **9.0.2** | UnitTests | CSDL giả lập trong bộ nhớ RAM để chạy 36 bài test tự động. |
| `Microsoft.AspNetCore.Authentication.JwtBearer`| **9.0.2** | API | Middleware giải mã và xác thực Token JWT của Người thân. |
| `Microsoft.Extensions.Caching.Memory` | **9.0.2** | Infrastructure | Bộ đệm RAM In-Memory Cache (lá chắn bảo vệ chống OOM). |
| `Microsoft.Extensions.Hosting.Abstractions` | **9.0.2** | Infrastructure | Nền tảng điều phối 3 Background Workers chạy ngầm. |
| `Swashbuckle.AspNetCore` | **7.2.0** | API | Tự động sinh tài liệu giao diện Swagger UI thử nghiệm API. |
| `xunit` & `xunit.runner.visualstudio` | **2.9.2** | UnitTests | Khung kiểm thử tự động xUnit cho .NET. |
| `FluentAssertions` | **7.0.0** | UnitTests | Cú pháp khẳng định kết quả kiểm thử mạch lạc, dễ đọc. |

*Lệnh khôi phục tự động toàn bộ thư viện Backend*:
```powershell
# Chạy tại thư mục gốc D:\IT\PRACTICE
dotnet restore CareAI.slnx
```
*(Nếu muốn cài thêm gói mới, bắt buộc chỉ định phiên bản LTS ổn định, ví dụ: `dotnet add package <Ten_Goi> --version 9.0.2`)*.

---

#### B. Thư Viện Mobile Flutter & Dart (Quản Lý Bằng Pub)
Được khai báo trong tệp `companion_app/pubspec.yaml`.

| Tên Package Flutter | Phiên Bản | Mục Đích Sử Dụng |
| :--- | :---: | :--- |
| `http` | `^1.6.0` | Giao tiếp mạng HTTP REST API gửi SOS và Heartbeat lên Backend. |
| `uuid` | `^4.6.0` | Sinh mã UUID định danh phiên làm việc và mã ngẫu nhiên an toàn. |
| `shared_preferences` | `^2.5.5` | Lưu trữ trạng thái cấu hình ghép nối (Device ID, Pairing Token). |
| `sqflite` & `path` | `^2.4.4` | Cơ sở dữ liệu SQLite cục bộ (Bộ đệm Outbox Spool lưu trữ ngoại tuyến 7 ngày). |
| `permission_handler` | `11.3.1` | Yêu cầu cấp quyền động trên Android 14+ và iOS. |
| `connectivity_plus` | `^7.3.1` | Lắng nghe sự kiện thay đổi mạng (Cáp USB, Wi-Fi, 4G, Mất mạng). |
| `sensors_plus` | `^7.1.0` | Đọc dữ liệu gia tốc kế phần cứng phát hiện rung lắc va chạm. |
| `flutter_secure_storage` | `^11.2.0` | Lưu trữ khóa bảo mật trong Android Keystore / iOS Keychain. |
| `workmanager` | `^0.10.10` | Lên lịch tác vụ chạy nền định kỳ quét dữ liệu y tế thụ động. |
| `cupertino_icons` | `^1.0.8` | Bộ biểu tượng giao diện chuẩn iOS. |

*Lệnh cài đặt tự động toàn bộ thư viện Flutter*:
```powershell
cd D:\IT\PRACTICE\companion_app
flutter pub get
```

---

#### C. Thư Viện Android Native & Wear OS (Quản Lý Bằng Gradle)
Được khai báo trong `companion_app/android/app/build.gradle.kts` và `wearos/build.gradle.kts`.

| Thư Viện Native Android | Phiên Bản | Module | Mục Đích Kỹ Thuật |
| :--- | :---: | :---: | :--- |
| `androidx.core:core-ktx` | `1.12.0` | `:app`, `:wearos` | Tiện ích mở rộng Kotlin cho Android API lõi. |
| `androidx.work:work-runtime-ktx` | `2.9.0` | `:app` | WorkManager Native phục vụ gửi bù SOS sau khi khởi động máy (Direct Boot). |
| `com.google.android.gms:play-services-wearable`| `18.1.0` | `:app`, `:wearos` | Wearable Data Layer API (cầu nối Bluetooth DataClient & MessageClient giữa đồng hồ và điện thoại). |
| `org.jetbrains.kotlinx:kotlinx-coroutines-android`| `1.8.0` | `:app`, `:wearos` | Luồng bất đồng bộ Coroutine trên môi trường Android. |
| `androidx.health:health-services-client` | **`1.1.0-rc02`** | `:wearos` | **Google Health Services API**: Bắt sự kiện ngã `FALL_DETECTED` và nhịp tim PPG trên Galaxy Watch. |
| `androidx.concurrent:concurrent-futures-ktx` | `1.2.0` | `:wearos` | Cầu nối bất đồng bộ giữa ListenableFuture của Google và Kotlin Coroutine. |
| `androidx.wear:wear` | `1.3.0` | `:wearos` | Thành phần điều hướng và bố cục màn hình tròn OLED Wear OS. |
| `com.google.guava:guava` | `33.0.0-android` | `:wearos` | Thư viện nền tảng hỗ trợ xử lý luồng dữ liệu cảm biến. |

*Lệnh khôi phục tự động toàn bộ thư viện Android*:
Gradle Wrapper sẽ **tự động tải toàn bộ các tệp `.jar` và `.aar`** từ Google Maven Repository và Maven Central ngay trong lần đầu bạn chạy lệnh build:
```powershell
cd D:\IT\PRACTICE\companion_app
./android/gradlew.bat assembleDebug
```

---

#### D. Thư Viện iOS (Quản Lý Bằng CocoaPods)
Dành cho môi trường macOS khi phát triển với iPhone:
Các Pods native tương ứng (như `FMDB`, `Reachability`, `FlutterSecureStorage`) được CocoaPods tự động phân giải 100% dựa trên các package Flutter:
```bash
cd companion_app/ios
pod install --repo-update
```

---

## 4. CẤU HÌNH BIẾN MÔI TRƯỜNG (ENVIRONMENT VARIABLES)

Để các công cụ dòng lệnh hoạt động trơn tru không bị lỗi xung đột đường dẫn trên Windows, hãy cấu hình các biến môi trường sau trong **System Environment Variables**:

### 4.1 Cấu Hình Bắt Buộc (Critical Variables)

```cmd
:: 1. Java Home trỏ tới OpenJDK 21
JAVA_HOME = C:\Program Files\Eclipse Adoptium\jdk-21.0.7-hotspot (hoặc thư mục cài đặt JDK của bạn)

:: 2. Android SDK Root
ANDROID_HOME = C:\Users\<Tên_User>\AppData\Local\Android\Sdk
ANDROID_SDK_ROOT = C:\Users\<Tên_User>\AppData\Local\Android\Sdk

:: 3. CỰC KỲ QUAN TRỌNG: Flutter Pub Cache (Chống lỗi đa ổ đĩa Windows)
:: Nếu dự án đặt tại ổ D, BẮT BUỘC gán biến PUB_CACHE sang ổ D:
PUB_CACHE = D:\PubCache

:: 4. Bổ sung vào biến PATH hệ thống:
%JAVA_HOME%\bin
%ANDROID_HOME%\platform-tools       <-- Để chạy lệnh adb
%ANDROID_HOME%\cmdline-tools\latest\bin
%ANDROID_HOME%\emulator             <-- Để khởi động máy ảo Wear OS dòng lệnh
D:\flutter\bin                      <-- Thư mục chứa flutter.bat
C:\Program Files\dotnet\            <-- Thư mục chứa dotnet.exe
```

> [!CAUTION]
> **CẠM BẪY ĐA Ổ ĐĨA WINDOWS (`PUB_CACHE`)**:
> Nếu mã nguồn đặt trên ổ `D:` mà biến `PUB_CACHE` để mặc định ở ổ `C:\Users\...\AppData\Local\Pub\Cache`, Gradle sẽ bị lỗi `FileSystemException: Cannot copy file` khi sao chép các plugin native giữa 2 phân vùng ổ cứng. Bắt buộc tạo thư mục `D:\PubCache` và set biến môi trường `PUB_CACHE=D:\PubCache`.

---

## 5. THIẾT LẬP CƠ SỞ DỮ LIỆU (AZURE SQL CLOUD HOẶC LOCAL SQL SERVER)

CareAI hỗ trợ cả 2 môi trường CSDL với cấu trúc bảng Idempotent tự sinh 100%:

### Phương Án A: Dùng CSDL Đám Mây Azure SQL Database (Mặc định hiện tại)
Chuỗi kết nối Azure SQL Cloud đã được cấu hình sẵn trong `src/CareAI.API/appsettings.json`:
```json
"ConnectionStrings": {
  "DefaultConnection": "Server=tcp:garage-server-2026.database.windows.net,1433;Initial Catalog=CareAI;Persist Security Info=False;User ID=admingarage;Password=Admin123;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}
```
*Lưu ý*: Hãy đảm bảo IP máy tính của bạn đã được thêm vào mục **Networking $\to$ Firewall rules** trên Azure Portal nếu bạn sử dụng mạng Wi-Fi mới.

### Phương Án B: Dùng SQL Server Express Cục Bộ Trên Máy Trạm
Nếu muốn chạy offline hoàn toàn:
1. Cài đặt **SQL Server 2022 Express** (tên instance mặc định: `.\SQLEXPRESS`).
2. Mở SSMS hoặc Azure Data Studio, tạo một Database rỗng tên `CareAiDb`:
   ```sql
   CREATE DATABASE CareAiDb;
   ```
3. Sửa `DefaultConnection` trong `src/CareAI.API/appsettings.json` trỏ về:
   ```json
   "DefaultConnection": "Server=.\\SQLEXPRESS;Database=CareAiDb;Integrated Security=True;TrustServerCertificate=True;"
   ```

> [!NOTE]
> Bạn **KHÔNG CẦN** chạy bất kỳ script DDL thủ công nào. Lớp `DatabaseMigrationHelper` trong Backend sẽ tự động kiểm tra và khởi tạo toàn bộ 10 bảng, chỉ mục duy nhất và quan hệ khóa ngoại ngay khi ứng dụng khởi động lần đầu!

---

## 6. CẤU HÌNH & KHỞI CHẠY BACKEND (.NET 9 LTS KESTREL)

### Bước 6.1: Khôi Phục Dependencies & Biên Dịch
Mở PowerShell tại thư mục gốc dự án (`d:/IT/PRACTICE`):
```powershell
# Kiểm tra phiên bản .NET SDK (yêu cầu >= 9.0.100)
dotnet --version

# Khôi phục các gói NuGet
dotnet restore CareAI.slnx

# Biên dịch toàn bộ Solution (phải đạt 0 warning, 0 error)
dotnet build CareAI.slnx
```

### Bước 6.2: Chạy Toàn Bộ Unit Tests Bất Biến (36 Facts)
Bắt buộc chạy test để đảm bảo môi trường máy trạm thỏa mãn 100% các bất biến kỹ thuật:
```powershell
dotnet test --nologo
```
*Kết quả mong đợi*: `Passed! - Failed: 0, Passed: 36, Skipped: 0, Total: 36`.

### Bước 6.3: Khởi Chạy Máy Chủ Backend Kestrel
```powershell
dotnet run --project src/CareAI.API/CareAI.API.csproj
```
Khi hiển thị log:
```
info: Microsoft.Hosting.Lifetime[14]
      Now listening on: http://localhost:5097
```
Kiểm tra sức khỏe hệ thống:
- Mở trình duyệt truy cập: `http://localhost:5097/health` $\to$ Trả về `Healthy`.
- Mở tài liệu Swagger API: `http://localhost:5097/swagger` $\to$ Hiển thị đầy đủ các Endpoint v111.0.

---

## 7. THIẾT LẬP THIẾT BỊ DI ĐỘNG & GIẢ LẬP (ANDROID, WEAR OS, IOS)

### 7.1 Thiết Lập Điện Thoại Android Thật (Samsung Galaxy / Android 10 - 14+)
1. **Bật Chế Độ Nhà Phát Triển (Developer Mode)**:
   - Vào `Cài đặt` $\to$ `Thông tin điện thoại` $\to$ `Thông tin phần mềm` $\to$ Chạm 7 lần liên tục vào `Số hiệu bản tạo (Build number)`.
2. **Kích Hoạt Gỡ Lỗi USB (USB Debugging)**:
   - Vào `Cài đặt` $\to$ `Cài đặt cho người phát triển` $\to$ Bật `Gỡ lỗi USB (USB debugging)`.
3. **Cắm Cáp USB Kết Nối Với Máy Tính**:
   - Trên màn hình điện thoại sẽ hiện hộp thoại hỏi "Cho phép gỡ lỗi USB từ máy tính này?", hãy tích vào ô **"Luôn cho phép từ máy tính này"** và chọn **Cho phép (Allow)**.
4. **Cấp Quyền Hệ Thống Sống Còn (Android 14+ / One UI 6.1)**:
   - **Thông báo**: Cài đặt $\to$ Ứng dụng $\to$ `CareAI Companion` $\to$ Thông báo $\to$ Cho phép thông báo (kèm chuông và rung).
   - **Báo thức & Lời nhắc (`SCHEDULE_EXACT_ALARM`)**: Cài đặt $\to$ Ứng dụng $\to$ `CareAI Companion` $\to$ Báo thức và lời nhắc $\to$ Cho phép.
   - **Cảnh báo toàn màn hình (`USE_FULL_SCREEN_INTENT`)**: Cho phép ứng dụng hiển thị đè lên màn hình khóa khi có sự cố.
   - **Tối ưu hóa Pin**: Cài đặt $\to$ Ứng dụng $\to$ `CareAI Companion` $\to$ Pin $\to$ Chọn **Không hạn chế (Unrestricted)** (để tránh bị hệ điều hành tắt ngầm).

### 7.2 Thiết Lập Máy Ảo Đồng Hồ Wear OS (Wear OS Emulator)
Nếu không có đồng hồ Samsung Galaxy Watch vật lý, hãy tạo đồng hồ ảo trong Android Studio:
1. Mở **Android Studio** $\to$ Chọn menu **Tools $\to$ Device Manager**.
2. Nhấn nút **Create Device (+)**.
3. Trong cột danh mục bên trái, chọn **Wear OS**.
4. Chọn mẫu đồng hồ: **Wear OS Small Round** (hoặc Large Round) $\to$ Nhấn **Next**.
5. Chọn System Image: **Android 13/14 (API 33 hoặc 34) Wear OS with Google APIs (x86_64)** $\to$ Nhấn tải về nếu chưa có $\to$ Nhấn **Next**.
6. Đặt tên AVD (ví dụ: `Wear_OS_Round_API_34`) $\to$ Nhấn **Finish**.
7. Khởi động máy ảo bằng nút Play (▶) hoặc bằng lệnh dòng lệnh:
   ```cmd
   emulator -avd Wear_OS_Round_API_34
   ```

### 7.3 Hướng Dẫn Phát Triển & Khởi Chạy Ứng Dụng Bằng iPhone (iOS Development Runbook)

Mã nguồn ứng dụng di động Flutter trong thư mục `companion_app` là mã nguồn đa nền tảng (Cross-platform), được thiết kế để có thể chạy trên cả **Android** và **iOS (iPhone/iPad)**. 

Tuy nhiên, do chính sách bảo mật và bản quyền của Apple, quy trình phát triển trên iPhone có những đặc thù riêng biệt. Dưới đây là hướng dẫn chi tiết cho từng trường hợp:

#### Trường Hợp A: Developer Có Máy Tính Mac (macOS + iPhone Thật) — Môi Trường Chuẩn

Nếu bạn hoặc thành viên trong nhóm có một chiếc máy tính chạy macOS (MacBook, Mac Mini, Mac Studio):

1. **Cài Đặt Bộ Công Cụ Phát Triển iOS**:
   - Cài đặt **Xcode** (bản 15 hoặc 16) trực tiếp từ Mac App Store.
   - Mở Terminal cài Command Line Tools:
     ```bash
     xcode-select --install
     ```
   - Cài đặt trình quản lý thư viện **CocoaPods**:
     ```bash
     sudo gem install cocoapods
     # Hoặc cài qua Homebrew:
     brew install cocoapods
     ```
   - Cài đặt Flutter SDK cho macOS theo hướng dẫn chính thức từ `flutter.dev`.

2. **Cài Đặt Dependencies Cho Phân Hệ iOS**:
   Mở Terminal tại thư mục `companion_app`:
   ```bash
   cd companion_app
   flutter pub get
   cd ios
   pod install --repo-update
   cd ..
   ```

3. **Bật Chế Độ Nhà Phát Triển Trên iPhone Thật (Từ iOS 16, 17, 18 Trở Lên)**:
   - Cắm cáp kết nối iPhone với máy Mac (chọn "Tin cậy máy tính này" khi có thông báo).
   - Trên iPhone, vào **Cài đặt (Settings)** $\to$ **Quyền riêng tư & Bảo mật (Privacy & Security)** $\to$ Kéo xuống mục dưới cùng chọn **Chế độ Nhà phát triển (Developer Mode)**.
   - Gạt công tắc sang **Bật (Turn On)** $\to$ iPhone sẽ yêu cầu khởi động lại máy.
   - Sau khi iPhone khởi động lại, mở khóa màn hình và nhấn **Bật (Turn On)** $\to$ Nhập mật mã mở khóa của iPhone.

4. **Cấu Hình Ký Số Chứng Chỉ Cá Nhân Miễn Phí (Free Personal Team Signing)**:
   - Mở tệp `companion_app/ios/Runner.xcworkspace` bằng Xcode:
     *(LƯU Ý: Bắt buộc mở file `.xcworkspace`, KHÔNG mở `.xcodeproj` vì các thư viện CocoaPods nằm trong workspace).*
   - Ở cột Navigator bên trái, nhấp chọn dự án gốc **Runner** $\to$ Chọn tab **Signing & Capabilities**.
   - Tại mục **Signing**:
     * Ở ô **Team**: Chọn `Add an Account...` và đăng nhập tài khoản Apple ID cá nhân của bạn (hoàn toàn miễn phí, không cần tài khoản trả phí 99$/năm của Apple).
     * Sau khi đăng nhập, chọn Team mang tên bạn (ví dụ: `Nguyen Van A (Personal Team)`).
     * Ở ô **Bundle Identifier**: Đổi hậu tố thành định danh riêng của bạn để tránh trùng lặp trên Apple Server (ví dụ: đổi `vn.careai.companion` thành `vn.careai.companion.dev`).

5. **Biên Dịch & Chạy Trực Tiếp Lên iPhone**:
   - Tại thanh công cụ trên cùng của Xcode, chọn thiết bị đích là chiếc **iPhone thật** của bạn đã cắm cáp.
   - Nhấn nút **Play / Run (Command + R)** trong Xcode, hoặc chạy lệnh trong Terminal:
     ```bash
     flutter run -d <Tên_iPhone_Của_Bạn>
     ```
   - *Xử lý lỗi chặn chứng chỉ lần đầu trên iPhone*:
     Khi ứng dụng vừa được cài đặt lên iPhone, nếu mở app sẽ xuất hiện cảnh báo "Nhà phát triển không được tin cậy" (Untrusted Developer). Cách xử lý:
     * Trên iPhone, vào **Cài đặt** $\to$ **Cài đặt chung (General)** $\to$ **Quản lý VPN & Thiết bị (VPN & Device Management)**.
     * Nhấn vào email Apple ID của bạn trong mục *Ứng dụng của nhà phát triển*.
     * Nhấn **Tin cậy "[Email của bạn]"** $\to$ Chọn **Tin cậy (Trust)**.
     * Quay lại màn hình chính iPhone và mở app CareAI bình thường!

6. **Kết Nối iPhone Với Backend .NET 9 Kestrel (Không Dùng Được `adb reverse`)**:
   - **Điểm khác biệt quan trọng giữa iOS và Android**: Hệ điều hành iOS của Apple **KHÔNG CÓ** công cụ `adb reverse` để chuyển tiếp cổng `localhost:5097` qua cáp USB như Android.
   - **Giải pháp kết nối**:
     * **Cách 1: Sử dụng Cloudflare Tunnel Toàn Cầu (Khuyên dùng 100%)**:
       Backend chạy lệnh `tools/cloudflared.exe tunnel --url http://localhost:5097`. Lấy link HTTPS (ví dụ `https://xxx.trycloudflare.com`) dán vào biến `internetTunnelUrl` trong `api_service.dart`. Chiếc iPhone kết nối mượt mà qua Wi-Fi hoặc 4G/5G tới máy chủ Backend mà không cần cùng dải mạng.
     * **Cách 2: Sử dụng Địa Chỉ IP Nội Bộ (LAN Wi-Fi)**:
       Cả máy tính chạy Backend và chiếc iPhone cùng kết nối vào một mạng Wi-Fi chung. Tìm địa chỉ IP LAN của máy tính (ví dụ `192.168.1.15`), cấu hình `wifiServerUrl = 'http://192.168.1.15:5097'` trong `api_service.dart`.

---

#### Trường Hợp B: Developer Dùng Máy Tính Windows Nhưng Có iPhone Thật (Cách Xử Lý Thực Tế)

Nếu bạn chỉ có máy tính Windows và một chiếc iPhone, Apple không cho phép chạy Xcode trên Windows để build file native `.ipa`. Bạn có thể áp dụng 3 giải pháp công nghiệp sau:

1. **Giải Pháp 1: Dùng iPhone Làm App Người Thân (Caregiver Web App PWA) — Khuyên Dùng & Siêu Nhẹ ⭐⭐⭐**:
   - Đây là mô hình chuẩn ngoài đời: Cụ già dùng điện thoại Android Samsung A55, còn Con cháu đi làm dùng iPhone.
   - Không cần cài Xcode phức tạp: Mở trình duyệt **Safari trên iPhone**, truy cập vào link Cloudflare Tunnel của hệ thống CareAI.
   - Nhấn nút **Chia sẻ (Share)** ở thanh dưới cùng Safari $\to$ Chọn **Thêm vào MH chính (Add to Home Screen)**.
   - Màn hình iPhone sẽ xuất hiện biểu tượng ứng dụng CareAI độc lập. Khi mở ra, app chạy toàn màn hình không có thanh URL, nhận cảnh báo cấp cứu, xem bản đồ GPS và bấm Tiếp nhận (ACK) cực kỳ mượt mà!

2. **Giải Pháp 2: Biên Dịch Đám Mây Tự Động (GitHub Actions / Cloud CI/CD)**:
   - Đẩy mã nguồn dự án lên kho lưu trữ GitHub riêng tư (Private Repository).
   - Thiết lập một GitHub Actions Workflow chạy trên runner máy ảo `macos-latest` của GitHub.
   - GitHub sẽ tự động biên dịch mã nguồn Flutter ra tệp `.ipa` và xuất ra mục Releases để bạn tải về cài đặt lên iPhone thông qua dịch vụ TestFlight hoặc AltStore / Sideloadly.

3. **Giải Pháp 3: Sử Dụng Máy Ảo macOS Trên Windows (VMware / VirtualBox)**:
   - Cài đặt máy ảo macOS trên Windows 11, chuyển tiếp cổng USB iPhone vào máy ảo để mở Xcode biên dịch trực tiếp.

---

#### Trường Hợp C: Về Apple Watch (watchOS) vs Samsung Galaxy Watch (Wear OS)
- **Lưu ý kiến trúc chuẩn**:
  * Dự án CareAI v111.0 tập trung chính thức vào nền tảng **Google Wear OS** (vận hành trên các dòng **Samsung Galaxy Watch 4, 5, 6, 7** phổ biến). Module Kotlin Native `:wearos` được tối ưu riêng cho Google Health Services.
  * Nếu muốn mở rộng sang Apple Watch trong tương lai, cần xây dựng một target watchOS độc lập bằng ngôn ngữ Swift và framework HealthKit của Apple trên môi trường macOS.

---

---

## 8. CẤU HÌNH MẠNG KÉP DỰ PHÒNG (USB CABLE + CLOUDFLARE INTERNET TUNNEL)

CareAI ứng dụng cơ chế **Chuyển Mạch Mạng Kép (Dual-Network Failover)** độc quyền: Khi cắm cáp USB, hệ thống chạy qua kênh USB siêu tốc độ trễ 0ms; khi rút cáp, hệ thống tự động trượt mượt mà sang Internet Tunnel.

### 8.1 Kênh 1: Cáp USB & Lệnh Chuyển Tiếp Cổng (Cực Kỳ Khuyên Dùng)
Mỗi khi cắm cáp USB, cổng ADB cần chuyển tiếp cổng 5097 từ điện thoại về máy tính:
```powershell
adb reverse tcp:5097 tcp:5097
```
Để không phải gõ lệnh này thủ công mỗi lần rút/cắm lại cáp, dự án đã viết sẵn một script giám sát chạy ngầm:
```powershell
# Chạy script duy trì tự động adb reverse mỗi 2 giây:
powershell -ExecutionPolicy Bypass -File D:\IT\PRACTICE\watch_and_reverse.ps1
```

### 8.2 Kênh 2: Cloudflare Tunnel Ra Toàn Cầu (Dự Phòng Khi Rút Cáp)
Trong thư mục `tools/` đã có sẵn tiện ích `cloudflared.exe`. Mở một cửa sổ PowerShell mới và chạy:
```powershell
D:\IT\PRACTICE\tools\cloudflared.exe tunnel --url http://localhost:5097
```
Đầu ra console sẽ cung cấp một đường link HTTPS công khai, ví dụ:
```
https://levels-digit-converter-beats.trycloudflare.com
```
*Cách cập nhật vào Mobile App*: Mở file `companion_app/lib/services/api_service.dart`, thay thế đường dẫn trên vào biến `internetTunnelUrl`:
```dart
static const String internetTunnelUrl = 'https://<tunnel-id-moi>.trycloudflare.com';
```

---

## 9. BIÊN DỊCH & CÀI ĐẶT ỨNG DỤNG DI ĐỘNG (COMPANION APP & WEAR OS)

### 9.1 Biên Dịch Ứng Dụng Hợp Nhất CareAI (Unified Mobile App)
Di chuyển vào thư mục `CareAI/companion_app`:
```powershell
cd D:\IT\PRACTICE\CareAI\companion_app

# 1. Cài đặt các gói thư viện Flutter
flutter pub get

# 2. Biên dịch tệp APK thật qua Gradle
./android/gradlew.bat assembleDebug
```
*Tệp APK thành phẩm*: `CareAI/companion_app/build/app/outputs/flutter-apk/app-debug.apk` (Dung lượng khoảng 164 MB, tích hợp cả Chế độ Người cao tuổi và Chế độ Người thân).

### 9.2 Cài Đặt Lên Điện Thoại Samsung Galaxy A55 5G
Kiểm tra thiết bị đã kết nối:
```powershell
adb devices
# Kết quả hiển thị: R5CY10M8BZN    device
```
Cài đặt APK trực tiếp:
```powershell
adb -s R5CY10M8BZN install -r build/app/outputs/flutter-apk/app-debug.apk
```

### 9.3 Biên Dịch & Cài Đặt Module Đồng Hồ Wear OS Lên Emulator
Module Wear OS nằm cùng trong cấu trúc multi-module `:wearos`.
```powershell
cd D:\IT\PRACTICE\CareAI\companion_app

# Biên dịch APK Wear OS độc lập
./android/gradlew.bat :wearos:assembleDebug
```
*Tệp APK thành phẩm*: `CareAI/companion_app/build/wearos/outputs/apk/debug/wearos-debug.apk`.

Cài đặt lên đồng hồ ảo Wear OS (`emulator-5554`):
```powershell
adb -s emulator-5554 install -r build/wearos/outputs/apk/debug/wearos-debug.apk

# Khởi động ứng dụng Wear OS trên màn hình đồng hồ tròn
adb -s emulator-5554 shell am start -n vn.careai.companion.wearos/.WearOsMainActivity
```

---

## 10. QUY TRÌNH KIỂM THỬ NHANH TOÀN HỆ THỐNG (END-TO-END VERIFICATION)

Sau khi hoàn tất setup, hãy thực hiện kịch bản kiểm thử mẫu này để nghiệm thu hệ thống hoạt động 100%:

```
[BƯỚC 1: MỞ APP]
      │
      ▼
Màn hình điện thoại hiển thị "🟢 Trực tuyến (Cáp USB)" hoặc "🟢 Trực tuyến (Internet Tunnel)"
      │
      ▼
[BƯỚC 2: GHÉP NỐI PIN]
Nhập mã PIN mẫu: 849201 -> Bấm Ghép nối -> Màn hình nhận diện: Cụ "Nguyễn Văn An"
      │
      ▼
[BƯỚC 3: MÔ PHỎNG NGÃ TACTILE]
Chạm 1 lần vào nút đỏ "[Test Ngã]" trên màn hình điện thoại
      │
      ▼
[BƯỚC 4: HỘP THOẠI ĐẾM NGƯỢC 30s & CÒI HÚ Y TẾ 1350Hz]
- Còi hú y tế ISO 60601-1-8 phát liên tục qua SoundPool không trễ nhịp
- Phím âm lượng bấm giảm vẫn phát còi hú (không tắt còi)
- Có thể bấm "TÔI ỔN" để hủy báo động giả ngay lập tức
- Hoặc để hết 30s -> Tự động chuyển sang trạng thái "ĐÃ GỬI SOS CỨU NẠN"
      │
      ▼
[BƯỚC 5: KIỂM TRA DỮ LIỆU TRÊN AZURE SQL]
Vào CSDL Azure SQL truy vấn bảng Incidents và HealthMeasurements:
SELECT TOP 5 * FROM Incidents ORDER BY CreatedAt DESC;
SELECT TOP 5 * FROM HealthMeasurements ORDER BY Timestamp DESC;
=> Đầy đủ bản ghi sự cố và mẫu đo gia tốc va chạm FALL 3.5G - 4.2G!
```

---

## 11. SỔ TAY 10 CẠM BẪY KỸ THUẬT SỐNG CÒN CẦN NHỚ (DEVELOPER PITFALLS)

Dưới đây là 10 cạm bẫy thực chiến đã được khắc phục và kiểm chứng kỹ càng, bất kỳ lập trình viên nào khi viết thêm code đều phải tuân thủ tuyệt đối:

1. **Băm Mã Token Thiết Bị (`DeviceTokenHash`)**:
   - Luôn sử dụng `.ToLowerInvariant()` khi băm SHA-256 ở cả Client, Middleware và CSDL. Không được so sánh phân biệt hoa thường.
2. **Quy Ước Header HTTP**:
   - Header xác thực thiết bị bắt buộc là `X-DeviceId` (KHÔNG được có dấu gạch ngang giữa `Device` và `Id`).
3. **Còi Hú Cấp Cứu Hardware Zero-Latency (`SoundPool`)**:
   - Tuyệt đối không dùng `MediaPlayer` cho còi hú lặp lại vì bị khựng 150ms buffer reload. Bắt buộc dùng `SoundPool` nạp trước vào RAM (`preload`) với `loop = -1` để đạt độ trễ 0ms liền mạch.
4. **Chặn Phím Giảm Âm Lượng Khi Đang Hú Còi**:
   - Trong `MainActivity.kt`, bắt sự kiện `KEYCODE_VOLUME_DOWN` khi còi đang hú để điều chỉnh luồng `STREAM_ALARM` thay vì để hệ thống tắt ngắt còi hú.
5. **Cấp Cứu Khi Khởi Động Lại Trước Khi Mở Khóa (Direct Boot)**:
   - Kho lưu trữ sự cố `CareAiFallStore` phải đặt trong `createDeviceProtectedStorageContext()` và `PhoneBootReceiver` phải lắng nghe cả `LOCKED_BOOT_COMPLETED` kèm cờ `android:directBootAware="true"`.
6. **Bất Biến Gói Fast-Lane SOS (Fact 35)**:
   - Gói cứu nạn gửi lên API bắt buộc phải lưu toàn bộ các mẫu đo sinh hiệu đi kèm vào bảng `HealthMeasurements`, không được bỏ sót mẫu nào.
7. **Chỉ Mục Lọc Chống Trùng Lặp Cấp Cứu (`UIX_Incidents_SingleActiveElder`)**:
   - Trên CSDL chỉ cho phép duy nhất 1 sự cố Active (`Open` hoặc `Acknowledged`) cho mỗi Cụ. Khi sự cố chuyển sang `Resolved`, chỉ mục tự động giải phóng để nhận sự cố mới.
8. **Kiểm Soát Tương Tranh Lạc Quan (`RowVersion` OCC)**:
   - Thực thể `DeviceClinicalState` và `Incidents` sử dụng `[Timestamp] public byte[]? RowVersion` để chống xung đột dữ liệu khi nhiều người thân cùng thao tác.
9. **Khử Trùng Lặp Sự Kiện Đếm Ngược Ngã**:
   - Sử dụng cờ bảo vệ `lastHandledEventId` trên Native và `_isFallDialogShowing` trên Flutter để ngăn chặn việc mở đè 2 hộp thoại khi có cả Intent lẫn Broadcast.
10. **Biến Môi Trường Flutter `PUB_CACHE` Trên Windows**:
    - Khi làm việc trên ổ đĩa khác ổ `C:`, luôn gán `PUB_CACHE=D:\PubCache` để tránh lỗi đứt gãy biên dịch file hệ thống giữa các phân vùng ổ đĩa.

---
*Tài liệu này được biên soạn bởi Đội ngũ Kỹ thuật Trưởng CareAI. Mọi thắc mắc kỹ thuật vui lòng tra cứu thêm tại `SO_TAY_KINH_NGHIEM_DEV_VA_FIX_LOI_CAREAI.md` và `TIEN_TRINH_DU_AN_CAREAI.md`.*
