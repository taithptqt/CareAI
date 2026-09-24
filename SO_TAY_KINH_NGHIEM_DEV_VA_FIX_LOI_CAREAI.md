# SỔ TAY KINH NGHIỆM DEV & FIX LỖI THỰC ĐỊA DỰ ÁN CAREAI v111.0
## (CAREAI BATTLE-TESTED ENGINEERING & TROUBLESHOOTING PLAYBOOK)

> **MỤC ĐÍCH TỐI THƯỢNG**:
> Đây là cẩm nang tích lũy toàn bộ kinh nghiệm thực chiến, cạm bẫy kỹ thuật (pitfalls) và giải pháp triệt để đã được kiểm chứng qua các đợt phát triển và thử nghiệm phần cứng thật (Hardware-in-the-Loop) của dự án CareAI.
> **QUY TẮC BẮT BUỘC**:
> 1. Mỗi khi gặp lỗi (build, runtime, mạng, Android, database), AI BẮT BUỘC phải đọc lại file này trước tiên để tra cứu giải pháp.
> 2. Sau mỗi phiên làm việc, nếu phát sinh bài học hoặc giải pháp mới, BẮT BUỘC phải cập nhật ngay vào tài liệu này.

---

## MỤC LỤC
1. [Kiến Trúc Hệ Sinh Thái & Vai Trò Phân Hệ (Wear OS vs Companion Phone)](#1-kiến-trúc-hệ-sinh-thái--vai-trò-phân-hệ-wear-os-vs-companion-phone)
2. [Kinh Nghiệm Backend .NET 9 LTS & SQL Server](#2-kinh-nghiệm-backend-net-9-lts--sql-server)
3. [Kinh Nghiệm Android Native & Direct Boot (Device Protected Storage)](#3-kinh-nghiệm-android-native--direct-boot-device-protected-storage)
4. [Kinh Nghiệm Quyền Hạn Android 14+ (FSI, Alarm, Notifications)](#4-kinh-nghiệm-quyền-hạn-android-14-fsi-alarm-notifications)
5. [Kinh Nghiệm Mạng, Chuyển Mạch Kép & Cloudflare Tunnel](#5-kinh-nghiệm-mạng-chuyển-mạch-kép--cloudflare-tunnel)
6. [Kinh Nghiệm Môi Trường Windows, Flutter SDK & Gradle Build](#6-kinh-nghiệm-môi-trường-windows-flutter-sdk--gradle-build)
7. [Kinh Nghiệm Thử Nghiệm Phần Cứng Thật (HIL Testing trên Samsung Galaxy)](#7-kinh-nghiệm-thử-nghiệm-phần-cứng-thật-hil-testing-trên-samsung-galaxy)
8. [Kinh Nghiệm Phát Triển Phân Hệ Đồng Hồ Wear OS](#8-kinh-nghiệm-phát-triển-phân-hệ-đồng-hồ-wear-os)
9. [Bài Học Thực Chiến Xây Dựng & Biên Dịch Module Wear OS Trong Flutter](#chương-9-bài-học-thực-chiến-xây-dựng--biên-dịch-module-wear-os-trong-dự-án-flutter-multi-module-agp-91--kotlin-2x)
10. [Kinh Nghiệm Triển Khai & Di Trú Cơ Sở Dữ Liệu Azure SQL Database](#chương-10-kinh-nghiệm-triển-khai--di-trú-cơ-sở-dữ-liệu-azure-sql-database-cho-careai)
11. [Kinh Nghiệm Tối Ưu Âm Thanh Còi Hú Phần Cứng & Giao Diện Khẩn Cấp](#11-kinh-nghiệm-tối-ưu-âm-thanh-còi-hú-phần-cứng-chuẩn-hóa-tần-số-y-tế-1350hz-iso-60601-1-8--giao-diện-khẩn-cấp)
12. [Tài Liệu Hướng Dẫn Thiết Lập Môi Trường & Khởi Chạy](#12-tài-liệu-hướng-dẫn-thiết-lập-môi-trường--khởi-chạy-developer-onboarding)
13. [Kinh Nghiệm Phát Triển & Cài Đặt Ứng Dụng Người Thân Độc Lập](#13-kinh-nghiệm-phát-triển--cài-đặt-ứng-dụng-người-thân-độc-lập-caregiver-app-coexistence)

---

## 1. KIẾN TRÚC HỆ SINH THÁI & VAI TRÒ PHÂN HỆ (WEAR OS VS COMPANION PHONE)

### 1.1 Khái Niệm Cốt Lõi: Module Wear OS Là Gì?
- **Định nghĩa**: Wear OS là hệ điều hành chuẩn của Google dành cho thiết bị đeo tay thông minh (Smartwatch), tiêu biểu là dòng **Samsung Galaxy Watch** (Watch 4, 5, 6, 7 chạy Wear OS Powered by Samsung).
- **Module Wear OS (`wearos`)**: Là một ứng dụng con độc lập, được biên dịch riêng biệt để nạp và chạy trực tiếp trên vi xử lý của đồng hồ Galaxy Watch.

### 1.2 Module Wear OS Dùng Để Làm Gì?
1. **Tiếp xúc cơ thể 24/7 (Body Proximity)**: Đồng hồ được đeo trên cổ tay người cao tuổi cả ngày lẫn đêm, kể cả khi vào nhà tắm, đi ngủ, hay ra ngoài sân — những nơi người cao tuổi thường **không cầm theo điện thoại**.
2. **Cảm biến sinh học y tế thực sự (Samsung BioActive Sensor)**:
   - Đo nhịp tim, nồng độ oxy trong máu (SpO2) liên tục qua cảm biến quang học PPG.
   - Đo gia tốc chuyển động 3 trục (3-axis Accelerometer) với tần số lấy mẫu cao.
3. **Phát hiện té ngã tại nguồn (On-Device Edge Detection)**:
   - Sử dụng thư viện chuẩn của Google: **Google Health Services (Passive Monitoring Client)**.
   - Khi phát hiện gia tốc va chạm và đổi hướng cơ thể đặc trưng của cú ngã (`HealthEvent.Type.FALL_DETECTED`), đồng hồ lập tức kích hoạt luồng cứu nạn.
4. **Cầu nối không dây sang điện thoại (Wearable Data Layer API)**:
   - Phát sóng tức thì sang điện thoại người già thông qua kết nối Bluetooth Low Energy (BLE) / Wi-Fi nội bộ bằng 2 kênh song song:
     * **Kênh nhanh Fast-Lane (`MessageClient`)**: Đẩy thông điệp `/careai/fall_detected` với độ trễ < 50ms.
     * **Kênh bền vững Store-and-Forward (`DataClient`)**: Lưu tạm vào bộ nhớ đồng hồ và tự động đồng bộ sang điện thoại ngay khi Bluetooth kết nối lại.

### 1.3 Bảng So Sánh Toàn Diện: Wear OS (Đồng Hồ) vs Companion App (Điện Thoại)

| Tiêu Chí | Phân Hệ Wear OS (Đồng Hồ Galaxy Watch) | Phân Hệ Companion App (Điện Thoại Galaxy A55) |
| :--- | :--- | :--- |
| **Vị trí hoạt động** | Đeo trực tiếp trên cổ tay người cao tuổi. | Cầm tay, bỏ túi áo, hoặc đặt trên bàn/đầu giường. |
| **Vai trò kiến trúc** | **Bộ cảm biến tiền tuyến (Edge Sensor)**: Thu thập sinh hiệu, bắt tín hiệu ngã vật lý tại nguồn. | **Trạm trung chuyển & Còi báo động (Local Gateway & Siren)**: Đếm ngược, phát âm thanh lớn, gửi SOS lên Cloud. |
| **Khả năng kết nối Internet** | Không kết nối trực tiếp Internet (để tiết kiệm pin); chỉ giao tiếp với điện thoại qua Bluetooth/Wi-Fi nội bộ. | Kết nối đa kênh lên máy chủ Backend: Cáp USB, Wi-Fi, 4G/5G Internet. |
| **Xử lý cảnh báo** | Rung và hiển thị thông báo nhẹ trên cổ tay người già. | Bật sáng màn hình khóa (Full-Screen Intent), hú còi cứu nạn âm lượng tối đa (`USAGE_ALARM`), đếm ngược 30 giây. |
| **Năng lực lưu trữ** | Bộ nhớ hạn chế; lưu trữ đệm ngắn hạn bằng `DataClient`. | Lưu trữ bền vững bằng SQLite Spool và Device Protected Storage Outbox. |
| **Giao diện người dùng (UI)** | Giao diện Wear OS tròn nhỏ, tối giản, tiết kiệm năng lượng. | Giao diện Flutter phong phú, màn hình lớn, hiển thị chi tiết sinh hiệu và danh bạ người thân. |

---

## 2. KINH NGHIỆM BACKEND .NET 9 LTS & SQL SERVER

### 2.1 Cạm Bẫy Băm Mã Token Thiết Bị (DeviceTokenHash)
- **Hiện tượng**: API trả về `401 Unauthorized` ngẫu nhiên khi client gửi request hợp lệ.
- **Nguyên nhân**: Client băm chuỗi SHA-256 ra chữ thường (`a-f`), nhưng Backend tính toán ra chữ hoa (`A-F`), dẫn đến so sánh chuỗi bị lệch.
- **Giải pháp triệt để**:
  * Luôn luôn ép kiểu `.ToLowerInvariant()` đối với mọi chuỗi SHA-256 trước khi lưu vào CSDL hoặc so sánh trong Authentication Middleware.
  * Trong xUnit test, luôn có bài test xác minh tính bất biến này (Fact 01).

### 2.2 Quy Ước Header HTTP Thiết Bị
- **Cạm bẫy**: Nhầm lẫn giữa `X-Device-Id` và `X-DeviceId`.
- **Quy tắc bất biến**: Dự án chuẩn hóa dùng **`X-DeviceId`** (không có dấu gạch ngang giữa `Device` và `Id`).

### 2.3 Nguyên Tắc Zero-Preview Dependency
- **Cạm bẫy**: Sử dụng các package preview/rc của .NET (ví dụ: EF Core 10 preview) dẫn đến lỗi xung đột Dependency Injection runtime.
- **Giải pháp**: 100% gói NuGet phải là phiên bản ổn định LTS (`Microsoft.EntityFrameworkCore.SqlServer` phiên bản `9.0.2`, .NET runtime `net9.0`).

### 2.4 Filtered Unique Index Ngăn Trùng Lặp Cấp Cứu
- **Cạm bẫy**: Khi người già ngã, cả đồng hồ và điện thoại đều có thể gửi tín hiệu SOS đồng thời, gây ra nhiều bản ghi sự cố `Open` cho cùng một cụ già.
- **Giải pháp CSDL**: Tạo Filtered Unique Index trên SQL Server:
  ```sql
  CREATE UNIQUE NONCLUSTERED INDEX [UIX_Incidents_SingleActiveElder]
  ON [dbo].[Incidents] ([ElderProfileId])
  WHERE [Status] IN ('Open', 'Acknowledged');
  ```
- **Kinh nghiệm xử lý**: Tầng ứng dụng bắt ngoại lệ `DbUpdateException` / SQL Error `2601` hoặc `2627` và tự động gộp các mẫu viễn trắc mới vào sự cố đang mở thay vì tạo mới.

### 2.5 Bất Biến Gói Fast-Lane SOS (Fact 35)
- **Quy tắc sống còn**: Gói tin cấp cứu SOS gửi lên API không chỉ tạo sự cố mà **bắt buộc phải lưu toàn bộ các mẫu sinh hiệu đi kèm** (nhịp tim, gia tốc impactG) vào bảng `HealthMeasurements` ngay trong cùng một Transaction nguyên tử.

### 2.6 Đồng Bộ Kiểu Dữ Liệu EF Core vs SQL DDL (CaregiverPushTokens.Id)
- **Cạm bẫy từ bản phản biện cũ (P0-2 v101)**: Lệch kiểu dữ liệu giữa EF Core C# Entity (`Guid`) và script SQL DDL (`int` hoặc `nvarchar`). Khi chạy ứng dụng thực tế trên SQL Server, lệnh `INSERT INTO CaregiverPushTokens` sẽ phát sinh lỗi ánh xạ kiểu (Type Mapping Exception).
- **Giải pháp**: Luôn đối chiếu 1:1 giữa C# Entity và DDL Idempotent: `Id uniqueidentifier NOT NULL DEFAULT NEWID() PRIMARY KEY`.

### 2.7 Kiểm Tra Trạng Thái Người Chăm Sóc Khi Đăng Ký Push Token (Fact 34)
- **Cạm bẫy**: Người thân đã bị gỡ quyền hoặc bị chủ hộ đuổi khỏi danh sách chăm sóc (`ElderCaregivers.IsActive = false`) nhưng vẫn tiếp tục nhận được chuông báo động cấp cứu của người già do Token FCM vẫn còn tồn tại.
- **Giải pháp**: Tầng API `RegisterPushToken` và Background Worker phát thông báo Quorum bắt buộc phải kiểm tra điều kiện `ElderCaregivers.IsActive == true`.

### 2.8 Ngữ Nghĩa Trạng Thái Gửi Thông Báo (SENT_PARTIAL & LastError)
- **Cạm bẫy**: Khi gửi còi hú FCM cho nhóm 5 người thân, nếu 3 người nhận được nhưng 2 người rớt mạng, nếu đánh dấu sự cố là `FAILED` sẽ gây hiểu nhầm rằng chưa ai được báo, còn nếu đánh dấu `SENT_ALL` sẽ che giấu rủi ro có người bị sót.
- **Giải pháp**: Chuẩn hóa trạng thái trung gian `SENT_PARTIAL`, đồng thời lưu chi tiết lỗi vào cột `LastError` để kiểm toán kỹ thuật minh bạch.

### 2.9 Thu Hồi Quyền Truy Cập Tức Thì & Invalidate Cache (0ms Delay)
- **Cạm bẫy**: Khi thiết bị bị đánh cắp hoặc người chăm sóc bị thu hồi quyền (`Revoke`), nếu hệ thống phụ thuộc vào bộ nhớ đệm Cache TTL (ví dụ 15 phút), kẻ xấu vẫn có thể truy cập dữ liệu người già trong suốt 15 phút đó.
- **Giải pháp**: Lệnh Revoke phải lập tức xóa sạch khóa trong `IMemoryCache` (0ms delay), vô hiệu hóa quyền truy cập ngay lập tức ở request tiếp theo.

---

## 3. KINH NGHIỆM ANDROID NATIVE & DIRECT BOOT (DEVICE PROTECTED STORAGE)

### 3.1 Cạm Bẫy Chết Người Của SharedPreferences Khi Khởi Động Lại
- **Hiện tượng**: Khi điện thoại khởi động lại và nhận broadcast `LOCKED_BOOT_COMPLETED`, ứng dụng bị crash ngay lập tức với lỗi:
  `java.lang.IllegalStateException: SharedPreferences in credential encrypted storage are not available until user decrypts device`.
- **Nguyên nhân**: Trước khi người dùng nhập mật khẩu/vân tay mở khóa máy, phân vùng dữ liệu người dùng (`Credential Protected Storage`) bị mã hóa hoàn toàn. Lệnh gọi `context.getSharedPreferences()` mặc định sẽ trỏ vào vùng bị khóa.
- **Giải pháp triệt để**:
  ```kotlin
  val storageContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      context.createDeviceProtectedStorageContext()
  } else {
      context
  }
  val prefs = storageContext.getSharedPreferences("careai_fall_records", Context.MODE_PRIVATE)
  ```
  File XML sẽ nằm an toàn tại `/data/user_de/0/vn.careai.companion/shared_prefs/`.

### 3.2 Khai Báo Direct Boot Aware Trong Manifest
- **Quy tắc**: Mọi `BroadcastReceiver` hoặc `Service` muốn chạy trước khi người dùng mở khóa máy bắt buộc phải có thuộc tính `android:directBootAware="true"`.
- **Kinh nghiệm**: Lắng nghe cả hai sự kiện:
  1. `android.intent.action.LOCKED_BOOT_COMPLETED`: Chạy ngay khi nhân Linux nạp xong (Direct Boot).
  2. `android.intent.action.BOOT_COMPLETED`: Chạy sau khi người dùng mở khóa máy.

### 3.3 Outbox-First Lưu Trữ Nguyên Tử
- Khi phát hiện ngã hoặc chuẩn bị phát SOS, **luôn ghi dữ liệu xuống đĩa Device Protected Storage trước khi gọi mạng**. Dùng phương thức `.commit()` (đồng bộ) thay vì `.apply()` (bất đồng bộ) để đảm bảo dữ liệu ghi thành công vào chip nhớ trước khi CPU có thể bị tắt nguồn hoặc tiến trình bị kill.

### 3.4 Triệt Tiêu Race Condition Giữa Flutter Và Native Watchdog (Fact 36)
- **Cạm bẫy từ bản phản biện cũ (P0-4 v111)**: Flutter Fast-Lane sinh `packetId` ngẫu nhiên (UUID), trong khi Native Watchdog sinh `NATIVE_FAILSAFE_<eventId>`. Khi Flutter gửi thành công nhưng ứng dụng bị crash trước khi kịp báo ACK cho Native, 5 giây sau Native Watchdog kích hoạt và gửi gói tin với ID khác $\to$ Backend không nhận diện được gói tin trùng lặp và phát còi hú lần 2 làm hoảng loạn gia đình.
- **Giải pháp**: Đồng nhất mã định danh chuẩn tắc: Cả Flutter lẫn Native Watchdog đều bắt buộc gửi `packetId = "FALL_" + eventId`. Bảng `ProcessedTelemetryLedgers` trên CSDL đóng vai trò chốt chặn Idempotent duy nhất: khi gói tin đến sau, backend nhận diện ngay `FALL_<eventId>` đã xử lý và phản hồi thành công mà không kích hoạt chuông báo động lần hai.

### 3.5 Cập Nhật Trạng Thái Mà Không Phá Hỏng Schema Wrapper
- **Cạm bẫy từ bản phản biện cũ (P0-5 v111)**: Khi cập nhật trạng thái sự cố từ `PENDING_CONFIRMATION` sang `SOS_SENT` trong `CareAiFallStore`, hàm `updateStatus` lấy trực tiếp `rawJson` ghi đè lên bộ nhớ làm mất toàn bộ các trường metadata `deadlineAt`, `timestamp`, `impactG`.
- **Giải pháp**: Cập nhật trực tiếp trên JSON wrapper có sẵn:
  ```kotlin
  val obj = JSONObject(currentJson)
  obj.put("status", newStatus)
  prefs.edit().putString("fall_$eventId", obj.toString()).commit()
  ```

---

## 4. KINH NGHIỆM QUYỀN HẠN ANDROID 14+ (FSI, ALARM, NOTIFICATIONS)

### 4.1 Cạm Bẫy Quyền Báo Thức Chính Xác (`SCHEDULE_EXACT_ALARM`)
- **Hiện tượng**: Gọi `alarmManager.setExactAndAllowWhileIdle(...)` trên Android 13/14 bị văng `SecurityException`.
- **Giải pháp**: Luôn kiểm tra quyền trước khi đặt:
  ```kotlin
  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
      // Fallback an toàn: Dùng setAndAllowWhileIdle thông thường, không bị crash
      alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
  } else {
      alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
  }
  ```

### 4.2 Cạm Bẫy Toàn Màn Hình Khẩn Cấp (`USE_FULL_SCREEN_INTENT`)
- **Hiện tượng**: Bắt đầu từ Android 14, quyền FSI có thể bị hệ điều hành tắt mặc định.
- **Giải pháp**: Nếu bị từ chối, ứng dụng phải tự hạ cấp sang **Heads-Up Notification** có độ ưu tiên cao nhất (`PRIORITY_MAX`, `IMPORTANCE_HIGH`) đi kèm còi hú báo động, tuyệt đối không để mất cảnh báo của người già.

### 4.3 Cạm Bẫy Kênh Thông Báo Bị Chặn (`POST_NOTIFICATIONS` numBlocked > 0)
- **Bài học thực tế từ máy thật Samsung A55**:
  * Khi kiểm tra lệnh `dumpsys notification`, phát hiện thông báo còi hú không kêu vì kênh thông báo khẩn cấp bị hệ thống chặn ngầm (`numBlocked=9`).
  * **Giải pháp**: Kênh thông báo khẩn cấp `careai_emergency_fall_channel` bắt buộc phải được khởi tạo với:
    ```kotlin
    val channel = NotificationChannel("careai_emergency_fall_channel", "Cảnh Báo Cấp Cứu CareAI", NotificationManager.IMPORTANCE_HIGH).apply {
        setSound(alarmSoundUri, AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build())
        enableVibration(true)
        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
    }
    ```

### 4.4 Đánh Thức Màn Hình Đang Tắt & Khóa (Turn Screen On & WakeLock)
- **Kinh nghiệm**: Để màn hình khóa tự động bật sáng khi có sự cố ngã:
  1. Trong Activity:
     ```kotlin
     if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
         setShowWhenLocked(true)
         setTurnScreenOn(true)
     }
     window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                     WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                     WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
     ```
  2. Trong Receiver: Xin một `WakeLock` tạm thời (10 giây) mức `PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE`.

---

## 5. KINH NGHIỆM MẠNG, CHUYỂN MẠCH KÉP & CLOUDFLARE TUNNEL

### 5.1 Cáp USB và Hiện Tượng Rớt `adb reverse`
- **Hiện tượng**: Sau khi điện thoại khởi động lại hoặc rút ra cắm lại cáp, lệnh gọi `http://127.0.0.1:5097` bị `Connection Refused`.
- **Nguyên nhân**: Bản đồ chuyển tiếp cổng của ADB (`adb reverse`) bị xóa sạch khi thiết bị ngắt kết nối.
- **Giải pháp**:
  * Luôn chạy script giám sát nền (`adb_auto_reverse.ps1` hoặc `watch_and_reverse.ps1`) để tự động nạp lại `adb reverse tcp:5097 tcp:5097` ngay khi phát hiện thiết bị online.
  * Phía Client Flutter/Native luôn cấu hình cơ chế **Dual-Network Failover**: Nếu gọi `127.0.0.1:5097` lỗi timeout (sau 1.5 giây), lập tức chuyển sang URL Cloudflare Tunnel Internet.

### 5.2 Vượt Tường Lửa Bằng Cloudflare Quick Tunnel
- **Bài học thực tế**: Mạng Wi-Fi tại các trường đại học, bệnh viện, hoặc doanh nghiệp thường chặn các cổng lạ (5097, 8080) và chặn kết nối ngang hàng nội bộ (Client Isolation).
- **Giải pháp**: Chạy công cụ `cloudflared.exe` tạo đường hầm miễn phí ra Internet:
  ```powershell
  & "d:\IT\PRACTICE\tools\cloudflared.exe" tunnel --url http://127.0.0.1:5097
  ```
  Đường dẫn `https://<random-subdomain>.trycloudflare.com` đi qua cổng chuẩn HTTPS 443, vượt qua 100% tường lửa mà không cần mở port modem.

### 5.3 Lỗi DNS Của Mạng Wi-Fi Nội Bộ
- **Hiện tượng**: Điện thoại kết nối Wi-Fi nhưng không phân giải được tên miền Cloudflare Tunnel.
- **Giải pháp**: Thiết lập DNS thủ công trên điện thoại (ví dụ: Google DNS `8.8.8.8` hoặc Cloudflare DNS `1.1.1.1`) hoặc sử dụng 4G/5G khi thực hiện kiểm thử thực địa không dây.

### 5.4 Vòng Đời Quick Tunnel Cloudflare, Kestrel 0.0.0.0 & Rào Cản Wi-Fi AP Isolation
- **Hiện tượng**: Rút cáp USB ra khỏi điện thoại, ứng dụng báo "Ngoại tuyến (Offline)", đường truyền Internet không chạy dù PC và điện thoại đều có mạng.
- **Nguyên nhân gốc rễ**:
  1. Quick Tunnel không dùng tài khoản (`trycloudflare.com`) sẽ cấp một URL subdomain ngẫu nhiên mới mỗi lần khởi động lại tiến trình `cloudflared.exe`. Nếu APK biên dịch trước đó vẫn lưu URL cũ thì kết nối Internet sẽ vào subdomain chết.
  2. Kestrel nếu chỉ bind `http://localhost:5097` thì sẽ từ chối mọi yêu cầu từ IP LAN nội bộ (`192.168.0.x`).
  3. Router Wi-Fi bật tính năng **AP Isolation** (Client Isolation) chặn gói tin giữa điện thoại và máy tính trong cùng mạng Wi-Fi, khiến kênh LAN IP bị Destination Host Unreachable / Timeout.
- **Giải pháp triệt để**:
  1. Cấu hình Kestrel lắng nghe trên `http://0.0.0.0:5097` (trong cả `appsettings.json` và `launchSettings.json`).
  2. Mở cổng Inbound TCP 5097 trên Windows Defender Firewall.
  3. Đồng bộ hằng số `internetTunnelUrl` trong `api_service.dart` và `caregiver_api_service.dart` khớp với link trycloudflare đang chạy.
  4. Biên dịch và nạp APK mới nhất lên máy thật. Khi rút cáp USB, hệ thống tự động nhảy sang Internet Tunnel trong 3 giây.

---

## 6. KINH NGHIỆM MÔI TRƯỜNG WINDOWS, FLUTTER SDK & GRADLE BUILD

### 6.1 Xung Đột Đa Ổ Đĩa (Cross-Drive Pub Cache Pitfall)
- **Hiện tượng**: Mã nguồn nằm trên ổ `D:\IT\PRACTICE`, nhưng Gradle/Flutter báo lỗi không tìm thấy các file `.dart_tool` hoặc quyền truy cập thư mục cache.
- **Nguyên nhân**: Flutter mặc định lưu pub-cache tại `C:\Users\<User>\AppData\Local\Pub\Cache`. Việc liên kết symbol link qua lại giữa 2 ổ đĩa khác nhau trên Windows thường bị chặn quyền NTFS.
- **Giải pháp triệt để**:
  * Chuyển hẳn thư mục Cache về cùng ổ cứng dự án: `set PUB_CACHE=D:\PubCache`.
  * Cấu hình cố định biến môi trường này trong hệ thống Windows.

### 6.2 Cố Định Phiên Bản Java LTS & Gradle
- **Kinh nghiệm**:
  * Flutter 3.x tương thích tối ưu nhất với **Java 17 hoặc Java 21 LTS**.
  * Cấu hình trong `android/app/build.gradle.kts`:
    ```kotlin
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }
    ```

---

## 7. KINH NGHIỆM THỬ NGHIỆM PHẦN CỨNG THẬT (HIL TESTING TRÊN SAMSUNG GALAXY)

### 7.1 Cơ Chế Bảo Vệ Samsung Knox Khi Khởi Động Lại
- **Hiện tượng**: Khi gửi lệnh `adb reboot`, thiết bị mất kết nối và báo `offline` hoặc biến mất khỏi danh sách `adb devices` trong khoảng 20-30 giây.
- **Nguyên nhân**: Samsung Knox kích hoạt cơ chế Secure Boot và kiểm tra tính toàn vẹn phần cứng trước khi mở giao tiếp USB Debugging cho máy tính.
- **Kinh nghiệm**: Tuyệt đối không hoang mang hoặc rút cáp vội vã. Phải chờ 30-45 giây để Knox hoàn thành nạp kernel, thiết bị sẽ tự động chuyển sang trạng thái `device`.

### 7.2 Thu Thập Bằng Chứng Vật Lý Đầy Đủ Ba Tầng
- Để chứng minh một ca thử nghiệm thành công 100% (không phải giả lập):
  1. **Tầng Máy Chủ (Backend Truth)**: Bản ghi trong SQL Server `CareAiDb` kèm timestamp và dữ liệu mẫu đo sinh hiệu thật.
  2. **Tầng Hệ Điều Hành (OS Logcat Truth)**: Logcat hệ thống bắt đúng PID máy thật, tag tên receiver/service, mã sự kiện intent của Android.
  3. **Tầng Người Dùng (Visual Screenshot Truth)**: Chụp trực tiếp màn hình máy thật bằng lệnh `adb exec-out screencap -p` lưu về thư mục artifacts để nghiệm thu bằng mắt.

---

## 8. KINH NGHIỆM PHÁT TRIỂN PHÂN HỆ ĐỒNG HỒ WEAR OS

### 8.1 Tính Trung Thực Của Dữ Liệu Cảm Biến (Sensor Data Truth)
- **Cạm bẫy**: Thư viện Google Health Services khi trả về `HealthEvent.Type.FALL_DETECTED` chỉ báo hiệu sự kiện xác nhận ngã, **không cung cấp số đo gia tốc thô (Raw G)**.
- **Giải pháp**: Tuyệt đối không hardcode giá trị giả mạo (như tự gán 3.2G). Đặt `impactG = null`, gán nhãn `source = "SAMSUNG_GALAXY_WATCH_HARDWARE_SENSOR"` và bật cờ `isHardwareVerified = true`. Điều này đảm bảo tính trung thực 100% theo tiêu chuẩn y tế Non-SaMD.

### 8.2 Kiến Trúc Hai Kênh Song Song Độc Lập (True Concurrent Dual-Channel)
- Không bao giờ để kênh này phụ thuộc hoặc chờ đợi kênh kia.
- **Luồng 1 (Fast-Lane)**: Bắn ngay qua `MessageClient` với timeout ngắn (2000ms) để điện thoại nhận tín hiệu ngay trong tích tắc.
- **Luồng 2 (Store-and-Forward)**: Ghi vào `DataClient` với cờ `.setUrgent()`. Nếu điện thoại ngoài vùng phủ sóng Bluetooth, Google Play Services trên đồng hồ sẽ tự động lưu và bắn lại ngay khi kết nối được phục hồi.

### 8.3 Chống Trùng Lặp Phía Điện Thoại (Idempotent De-duplication)
- Vì đồng hồ phát sự kiện qua cả 2 kênh (`MessageClient` và `DataClient`), điện thoại nhận được cả hai gói tin cho cùng một cú ngã.
- **Giải pháp**: Sử dụng `ConcurrentHashMap.newKeySet<String>()` lưu trữ `eventId`. Gói tin nào tới trước thì xử lý và kích hoạt FSI, gói tin tới sau sẽ bị bỏ qua an toàn với log thông báo: `"Bỏ qua sự kiện ngã trùng lặp"`.

### 8.4 Chiến Lược Mạng Của Đồng Hồ: Tại Sao Không Cho Đồng Hồ Tự Kết Nối Internet Gửi Dữ Liệu Định Kỳ?
- **Khả năng phần cứng**: Đồng hồ Galaxy Watch có chip Wi-Fi (và bản LTE có eSIM), nghĩa là về mặt kỹ thuật phần cứng nó CÓ THỂ tự kết nối Internet trực tiếp.
- **Tại sao Kế hoạch phản biện & Chuẩn Google KHÔNG chọn phương án này?**:
  1. *Khủng hoảng năng lượng pin (Battery Drain)*: Pin đồng hồ rất nhỏ (300-400 mAh, bằng 1/12 điện thoại). Chip Wi-Fi/LTE ngốn điện gấp 15-20 lần Bluetooth BLE. Nếu đồng hồ tự bật Wi-Fi theo chu kỳ (15-30 phút/lần) để handshake HTTPS với Cloud Server, pin sẽ cạn sau 4-6 tiếng $\to$ Người già phải tháo sạc liên tục, vô hiệu hóa việc giám sát ban đêm hoặc lúc tắm.
  2. *Chính sách hệ điều hành Wear OS*: Khi có kết nối Bluetooth với điện thoại, Wear OS **tự động tắt chip Wi-Fi của đồng hồ** để tiết kiệm pin. Nếu app cố ép bật Wi-Fi, hệ thống sẽ đưa vào diện ngốn pin bất thường (App Standby Bucket: Restricted) và kill app.
  3. *Tách bạch luồng dữ liệu thông minh trong CareAI*:
     - **Cấp cứu khẩn cấp (Fast-Lane SOS)**: Đồng hồ đẩy qua Bluetooth `MessageClient` (< 50ms) sang điện thoại $\to$ Điện thoại hú còi to (`USAGE_ALARM`) và phát SOS lên máy chủ.
     - **Sinh hiệu định kỳ (Routine Telemetry)**: Đồng hồ đồng bộ ngầm qua Bluetooth vào **Samsung Health Connect** $\to$ Điện thoại chạy `HealthConnectService` gom mẻ định kỳ gửi lên `POST /api/v1/telemetry/ingest`. Đồng hồ không tốn 1% pin nào để bật sóng Wi-Fi/Internet!
  4. *Cơ chế dự phòng khi mất Bluetooth (Standalone Fallback)*: Nếu đồng hồ mất kết nối Bluetooth với điện thoại trong thời gian dài nhưng có Wi-Fi nhà, Google Play Services sẽ dùng cơ chế Cloud-Sync chuyển tiếp qua hạ tầng Google, hoặc `DataClient` lưu trữ bền vững (Store-and-Forward) để bắn bù ngay khi tái kết nối.

### 8.5 Phương Pháp Kiểm Thử Module Wear OS Khi Không Có Đồng Hồ Thật
Khi phát triển đồ án hoặc nghiên cứu mà chưa có phần cứng Galaxy Watch vật lý, quy trình công nghiệp chuẩn của Google áp dụng 3 cấp độ:
1. **Cấp độ 1: Kiểm thử Cầu nối Giả lập Phần cứng Trên Điện thoại Thật (Fact 25 & Simulated Fall)**:
   - **Chỉ cần DUY NHẤT 1 app trên điện thoại**: Người dùng KHÔNG PHẢI cài 2 app và KHÔNG PHẢI chuyển đổi qua lại giữa 2 app trên điện thoại.
   - **Cơ chế**: Lệnh ADB chạy từ máy tính đóng vai trò là "chiếc đồng hồ ảo" phát tín hiệu vào điện thoại qua cáp USB.
   - Sử dụng `SimulatedFallReceiver` và `WearOsMessageReceiverService` có sẵn trên điện thoại:
     ```bash
     adb shell am broadcast -a vn.careai.companion.ACTION_SIMULATE_FALL --es eventId "FALL_TEST_01" --ed impactG 3.5
     ```
   - Điện thoại kích hoạt toàn bộ chuỗi phản ứng thật: ghi DPS `CareAiFallStore`, vũ trang `AlarmManager RTC_WAKEUP`, bật sáng màn hình khóa Full-Screen Intent, hú còi và gửi SOS lên máy chủ. Người dùng chỉ việc quan sát màn hình điện thoại tự động phản ứng.
2. **Cấp độ 2: Trình Giả lập Google Wear OS Chuẩn Hóa (Wear OS Official Emulator)**:
   - Tạo máy ảo Wear OS (Large Round, API 33/34) trong Android Studio.
   - Ghép nối Bluetooth ảo với điện thoại thật qua `adb forward tcp:5601 tcp:5601` hoặc Wear OS Pairing Assistant.
   - Bơm sự kiện té ngã qua Google Health Services Synthetic Data:
     ```bash
     adb -s <emulator-id> shell am broadcast -a com.google.android.wearable.healthservices.SYNTHETIC_DATA --es "dataType" "FALL_DETECTED"
     ```
   - Đoạn mã `WearOsFallListenerService` trên đồng hồ ảo sẽ nhận sự kiện và bắn Data Layer sang điện thoại thật.
3. **Cấp độ 3: Kiểm thử Đơn vị Khép kín (Unit Tests & Fact 25)**:
   - Unit test xUnit Fact 25 (`Fact_25_WearOsMethodChannel_FallAlertBridgeContract_SensorDataTruth`) xác minh tính toàn vẹn của hợp đồng payload JSON.
   - Unit test Kotlin mô phỏng `HealthEvent.Type.FALL_DETECTED` để kiểm tra logic phát 2 kênh song song.

---

## CHƯƠNG 9: BÀI HỌC THỰC CHIẾN XÂY DỰNG & BIÊN DỊCH MODULE WEAR OS TRONG DỰ ÁN FLUTTER MULTI-MODULE (AGP 9.1 & KOTLIN 2.X)

Trong quá trình đưa phân hệ đồng hồ thông minh Wear OS (`:wearos`) vào cấu trúc dự án Flutter Android, đội ngũ kỹ thuật đã phát hiện và xử lý triệt để 5 vấn đề cốt lõi:

### 9.1 Tránh Vòng Lặp Đánh Giá Dự Án Con (Circular Evaluation)
- **Hiện tượng**: Khi thêm `include(":wearos")` vào `settings.gradle.kts`, tệp `build.gradle.kts` gốc của Flutter chứa lệnh `subprojects { project.evaluationDependsOn(":app") }`. Do `:wearos` là một Application module độc lập không sử dụng Flutter plugin, Gradle sẽ cố đánh giá chéo dẫn đến lỗi cấu hình.
- **Giải pháp**: Thêm điều kiện loại trừ trong `build.gradle.kts`:
  ```kotlin
  subprojects {
      if (project.name != "wearos") {
          project.evaluationDependsOn(":app")
      }
  }
  ```

### 9.2 Lỗi Cú Pháp `kotlinOptions.jvmTarget` Trên Kotlin 2.x & AGP 9.1
- **Hiện tượng**: Việc đặt `kotlinOptions { jvmTarget = "17" }` bên trong khối `android { ... }` gây ra lỗi `ScriptCompilationError: 'var jvmTarget: String' is deprecated. Please migrate to the compilerOptions DSL`.
- **Giải pháp**: Tách khối cấu hình Kotlin ra ngoài khối `android` và dùng cú pháp `compilerOptions`:
  ```kotlin
  kotlin {
      compilerOptions {
          jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
      }
  }
  ```

### 9.3 Tọa Độ Phụ Thuộc Google Health Services & Yêu Cầu `minSdk 30`
- **Hiện tượng 1**: Khai báo `androidx.health.services:health-services-client` bị lỗi `Could not find artifact`.
  * **Khắc phục**: Tọa độ Maven chính xác của Google là `androidx.health:health-services-client:1.1.0-rc02` (groupId là `androidx.health`).
- **Hiện tượng 2**: Thư viện Health Services yêu cầu `minSdkVersion 30` do được thiết kế riêng cho Wear OS 3+ (Android 11+). Nếu để `minSdk 26` như điện thoại thì Gradle Manifest Merger sẽ chặn lại.
  * **Khắc phục**: Thiết lập `minSdk = 30` riêng cho module `:wearos`. Điện thoại Companion App vẫn giữ nguyên `minSdk = 26`.

### 9.4 Await `ListenableFuture` Thay Vì `Tasks.await`
- **Hiện tượng**: `passiveMonitoringClient.setPassiveListenerServiceAsync(...)` trả về `ListenableFuture<Void>` (Guava / AndroidX concurrent), không phải Google Play Services `Task<T>`. Nếu gọi `Tasks.await(...)` sẽ báo lỗi mismatch kiểu dữ liệu và thiếu class `ListenableFuture`.
- **Giải pháp**: Bổ sung hai thư viện:
  ```kotlin
  implementation("androidx.concurrent:concurrent-futures-ktx:1.2.0")
  implementation("com.google.guava:guava:33.0.0-android")
  ```
  Và gọi hàm mở rộng `await()` chính quy trong Coroutine:
  ```kotlin
  import androidx.concurrent.futures.await
  ...
  passiveMonitoringClient.setPassiveListenerServiceAsync(
      WearOsFallListenerService::class.java,
      config
  ).await()
  ```

### 9.6 Chuẩn Hóa Giao Diện Màn Hình Tròn Wear OS Bằng BoxInsetLayout & Nút Bấm Dạng Viên Nhộng (Pill Chips)
- **Vấn đề thực tế**: Trên màn hình tròn của Smartwatch (Samsung Galaxy Watch), các thành phần giao diện hình chữ nhật với `layout_width="match_parent"` thường bị viền bezel tròn của đồng hồ cắt góc nham nhở, đặc biệt là các nút bấm ở trên đỉnh hoặc dưới đáy màn hình.
- **Giải pháp**:
  1. **Sử dụng `BoxInsetLayout` với `app:boxedEdges="left|right"`**:
     * `BoxInsetLayout` tự động tính toán hình vuông nội tiếp bên trong đường tròn ($x = \sqrt{R^2 - y^2}$) và gán lề an toàn ở 2 cạnh bên.
     * Bằng cách đặt `boxedEdges="left|right"`, nội dung không bị giới hạn chiều cao ngột ngạt mà tận dụng trọn vẹn toàn bộ trục dọc của đồng hồ để cuộn mượt mà.
  2. **Thiết kế hình dạng viên nhộng (Pill Shape)**:
     * Dùng Shape drawable với `corners radius="24dp"` cho các nút bấm hành động (`btnSimulateFall`, `btnManualSos`).
     * Dùng `corners radius="18dp"` cho thẻ sinh hiệu (`bg_wear_vitals`).
     * Các góc bo tròn lớn tự nhiên hòa nhập với độ cong viền của mặt kính đồng hồ.
  3. **Thuộc tính `clipToPadding="false"`**:
     * Đặt trên `ScrollView` kết hợp `paddingTop="18dp"` và `paddingBottom="42dp"`.
     * Giúp các phần tử cuộn mượt mà qua các vùng mép cong của màn hình mà không bị cắt cụt đột ngột.

### 9.7 Nguyên Lý Vận Hành Ngầm Của Module Wear OS: Tiết Kiệm Pin Màn Hình & Kích Hoạt Có Điều Kiện
- **Bản chất**: Pin của Smartwatch chỉ có dung lượng ~300mAh đến 425mAh. Màn hình OLED là thành phần tiêu tốn năng lượng lớn nhất.
- **Quy tắc vận hành chuẩn công nghiệp**:
  1. **Bình thường (99.9% thời gian)**:
     * Màn hình đồng hồ chỉ hiển thị **Mặt đồng hồ (Watch Face)** xem giờ thông thường.
     * Ứng dụng CareAI **KHÔNG** giữ màn hình sáng liên tục, mà chạy ngầm 100% qua `WearOsFallListenerService` (kế thừa `PassiveListenerService` của Google Health Services).
     * Cảm biến BioActive trên mặt lưng đồng hồ vẫn liên tục giám sát mạch đập PPG và gia tốc chuyển động 3 trục ở tầng vi xử lý công suất thấp (Ultra-Low Power Sensor Hub).
  2. **Khi nào màn hình ứng dụng mở lên?**:
     * **Người dùng chủ động mở**: Khi cụ hoặc người chăm sóc bấm vào icon ứng dụng `CareAI Wear` trong danh sách ứng dụng trên đồng hồ để xem sinh hiệu hoặc bấm nút SOS thủ công.
     * **Sự cố té ngã xảy ra**: Khi cảm biến phát hiện cú va đập ngã (`FALL_DETECTED`), hệ điều hành đồng hồ rung mạnh cổ tay, phát gói tin qua Bluetooth sang điện thoại người già và điện thoại sẽ lập tức bật sáng màn hình khóa (Full-Screen Intent), hú còi báo động khẩn cấp và đếm ngược 30 giây.

---

## CHƯƠNG 10: KINH NGHIỆM TRIỂN KHAI & DI TRÚ CƠ SỞ DỮ LIỆU AZURE SQL DATABASE CHO CAREAI

Trong quá trình đưa CSDL CareAI từ môi trường máy trạm nội bộ (`.\SQLEXPRESS`) lên nền tảng đám mây Azure SQL Database (`garage-server-2026.database.windows.net`), hệ thống đã kiểm chứng và đúc kết 4 bài học vận hành cốt lõi:

### 10.1 Khả Năng Tương Thích Tuyệt Đối Của Filtered Unique Index Giữa SQL Server & Azure SQL
- **Cơ chế**: Azure SQL Database sử dụng chung SQL Server Engine (Version 12.0.2000.8), hỗ trợ 100% cú pháp Filtered Unique Index mà CareAI yêu cầu:
  ```sql
  CREATE UNIQUE NONCLUSTERED INDEX [UIX_Incidents_SingleActiveElder]
  ON [dbo].[Incidents] ([ElderProfileId])
  WHERE [Status] IN (1, 2);
  ```
- **Kinh nghiệm**: Không cần thay đổi bất kỳ ký tự nào trong script DDL `DatabaseMigrationHelper.DdlScript`. Toàn bộ 10 bảng quan hệ, các khóa chính `uniqueidentifier DEFAULT NEWID()`, cờ `ROWVERSION` Optimistic Concurrency Control (OCC) và các index lọc đều khởi tạo trơn tru chỉ trong 1 lần thực thi duy nhất.

### 10.2 Chuẩn Hóa Chuỗi Kết Nối & Bảo Mật SSL/TLS Trên Azure SQL
- **Đặc thù Azure SQL**: Azure SQL Database bắt buộc kết nối qua cổng 1433 với giao thức mã hóa dữ liệu đường truyền SSL/TLS (`Encrypt=True`).
- **Chuỗi kết nối chuẩn trong `appsettings.json`**:
  ```json
  "ConnectionStrings": {
    "DefaultConnection": "Server=tcp:garage-server-2026.database.windows.net,1433;Initial Catalog=CareAI;Persist Security Info=False;User ID=admingarage;Password=Admin123;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;",
    "LocalSqlServer": "Server=.\\SQLEXPRESS;Database=CareAiDb;Trusted_Connection=True;TrustServerCertificate=True;MultipleActiveResultSets=true"
  }
  ```
- **Lưu ý**: Giữ nguyên `LocalSqlServer` làm kênh dự phòng fallback khi làm việc offline không có Internet.

### 10.3 Nguyên Nhân Ứng Dụng Báo "Ngoại Tuyến (Offline)" Dù Vẫn Đang Cắm Cáp USB
- **Hiện tượng**: Điện thoại Samsung Galaxy A55 5G cắm cáp USB vào máy tính nhưng giao diện Companion App bất ngờ chuyển sang chấm đỏ "Ngoại tuyến (Offline)".
- **Phân tích 3 nguyên nhân cốt lõi**:
  1. **Nguyên nhân 1 (Cáp USB bị lỏng hoặc gián đoạn thoáng qua)**: Khi cáp USB bị xê dịch dù chỉ 0.5 giây, tiến trình ADB Daemon (`adbd`) trên Android sẽ reset kết nối (`no devices/emulators found`). Ngay khi reset, Android tự động xóa sạch toàn bộ danh sách chuyển tiếp cổng `adb reverse` (`adb reverse --list` trở thành rỗng). Khi đó, các request của Flutter gọi đến `http://127.0.0.1:5097` bị rớt ngay lập tức vì không còn cổng hứng trên điện thoại.
  2. **Nguyên nhân 2 (Kênh Internet Tunnel Cloudflare bị tắt giữa các phiên)**: Kênh Cloudflare Tunnel chạy ở chế độ console process, khi tắt cửa sổ hoặc phiên làm việc tạm dừng thì tunnel URL tạm thời bị ngắt, dẫn đến cả kênh Cáp USB và kênh Internet đều mất kết nối cùng lúc.
  3. **Nguyên nhân 3 (Tiến trình Backend Kestrel tạm dừng khi chạy Gradle)**: Trong lúc biên dịch ứng dụng Android/Wear OS bằng Gradle, tài nguyên CPU/RAM cao hoặc lệnh dừng port khiến Kestrel tạm tắt trong chốc lát.
- **Giải pháp triệt để**:
  * Chạy Tunnel Cloudflare ổn định và cập nhật URL trực tiếp vào `api_service.dart`.
  * Luôn kiểm tra và chạy lệnh khôi phục cổng: `adb -s <device_id> reverse tcp:5097 tcp:5097` sau mỗi lần cắm lại cáp hoặc khi thấy `adb reverse --list` rỗng.
  * Bổ sung nút bấm **`[KIỂM TRA NGAY]`** trên UI điện thoại để người dùng ép kích hoạt kiểm tra nhịp tim/kết nối tức thì mà không cần đợi chu kỳ 30 giây.

### 10.4 Hướng Dẫn Thiết Lập & Kiểm Thử Wear OS Emulator Trên Máy Tính
- **Hiện trạng máy trạm**: Công cụ giả lập `emulator.exe` đã có sẵn tại `C:\Users\DELL\AppData\Local\Android\Sdk\emulator\emulator.exe`.
- **Quy trình tạo máy ảo đồng hồ chuẩn**:
  1. Mở **Android Studio** -> Vào menu **Tools** -> **Device Manager**.
  2. Bấm nút **Create Device** (+).
  3. Trong cột danh mục bên trái (Category), chọn **Wear OS**.
  4. Chọn kiểu dáng thiết bị: **Wear OS Small Round** (đường kính chuẩn phù hợp với Samsung Galaxy Watch 4/5/6) hoặc **Wear OS Large Round**. Bấm **Next**.
  5. Tại bước chọn **System Image**: Chọn bản phát hành **Wear OS 4 - Android 13.0 (API 33)** hoặc **Wear OS 3 (API 30)** kiến trúc `x86_64` có nhãn **Google Play**. Bấm biểu tượng mũi tên tải về (Download) nếu chưa có sẵn. Bấm **Next** -> **Finish**.
  6. Khởi động máy ảo bằng nút Play (▶️).
  7. Cài đặt tệp APK Wear OS đã dựng sẵn:
     ```powershell
     adb -s emulator-5554 install D:\IT\PRACTICE\companion_app\build\wearos\outputs\apk\debug\wearos-debug.apk
     ```
  8. Mở ứng dụng `CareAI Wear OS` trên màn hình đồng hồ tròn: Giao diện nền đen OLED hiện đại xuất hiện với nút lớn màu đỏ `[THỬ NGHIỆM TÉ NGÃ]`. Bấm nút để kiểm tra luồng phát cảnh báo sang điện thoại.

### 10.5 Cạm Bẫy Danh Sách Kênh Mạng `_getEndpointsToTry()` Khiến App Bị Kẹt Ở Kênh Internet Dù Đã Cắm Cáp
- **Hiện tượng**: Điện thoại đang cắm cáp USB vào máy tính nhưng trên giao diện App vẫn hiển thị "Trực tuyến (Internet/4G)" thay vì "Trực tuyến (Cáp USB)".
- **Nguyên nhân sâu xa**:
  1. Trong hàm `_getEndpointsToTry()`, danh sách thử nghiệm ban đầu được viết là: `final list = <String>[_activeServerUrl]`. Khi có một thời điểm cáp bị lỏng hoặc Kestrel khởi động lại, `_activeServerUrl` bị đổi thành `internetTunnelUrl`. Kể từ đó, mọi lần gửi Heartbeat hoặc kiểm tra kết nối tiếp theo đều đặt `internetTunnelUrl` lên vị trí đầu tiên. Vì kênh Internet luôn trả về HTTP 200 nên hệ thống không bao giờ quét lại kênh Cáp USB nữa!
  2. Thời gian chờ (Timeout) của kênh Cáp USB trước đó đặt quá thấp (1000ms), khi CPU điện thoại bận render hoặc có ứng dụng nền khác, request nội bộ `http://127.0.0.1:5097/healthz` bị timeout giả.
- **Giải pháp dứt điểm**:
  * Chuẩn hóa danh sách thứ tự ưu tiên tuyệt đối: Cáp USB luôn luôn là số 1:
    ```dart
    List<String> _getEndpointsToTry() {
      return [usbServerUrl, internetTunnelUrl, wifiServerUrl];
    }
    ```
  * Nâng thời gian timeout của Cáp USB lên 2000ms trong `checkServerHealth()`.
  * Luôn có tiến trình daemon ngầm (`watch_and_reverse.ps1`) kiểm tra và khôi phục cổng `adb reverse tcp:5097 tcp:5097` định kỳ 2 giây/lần.

### 10.6 Cạm Bẫy `SingleChildScrollView` Khiến Nút Bấm Khẩn Cấp Và Thanh Footer Bị Trôi Trượt
- **Hiện tượng**: Khi bọc giao diện bằng `SingleChildScrollView` để xử lý tràn viền màn hình (overflow), người dùng chạm hoặc vuốt màn hình thì nút SOS và thanh trạng thái dưới cùng bị di chuyển, trôi trượt lên xuống, mất cảm giác vững chãi của thiết bị y tế.
- **Nguyên lý thiết kế công thái học cho người già (Elderly Ergonomics)**:
  * Màn hình SOS là màn hình **Tĩnh tuyệt đối (Immovable / Rock-solid)**. Người cao tuổi khi gặp sự cố, hoảng loạn hoặc run tay cần một điểm chạm cố định vững chắc, không được phép trôi trượt khi ngón tay tì đè lên màn hình.
  * Thanh Footer (đồng bộ, số gói tin chờ) phải luôn nằm sát đáy màn hình (`docked to bottom`), không được phép lơ lửng ngay dưới nút SOS.
- **Giải pháp kỹ thuật chuẩn mực**:
  1. Loại bỏ hoàn toàn `SingleChildScrollView` trên toàn bộ màn hình SOS chính.
  2. Đưa Thanh Footer vào thuộc tính chính quy **`Scaffold.bottomNavigationBar`**. Thuộc tính này ghim chặt thanh trạng thái vào đáy màn hình của thiết bị, không bao giờ bị trôi khi cuộn hoặc chạm.
  3. Bọc Nút SOS trong **`Expanded -> Center -> FittedBox(fit: BoxFit.scaleDown)`**:
     * `Expanded + Center`: Luôn chiếm trọn vùng không gian trống ở giữa và định vị nút SOS vào đúng tâm quang học của màn hình.
     * `FittedBox`: Tự động co giãn kích thước nút bấm nếu chiều cao màn hình bị thu hẹp (xoay ngang hoặc mở bàn phím), triệt tiêu hoàn toàn lỗi tràn pixel mà không cần đến cuộn trang.

---

## CHƯƠNG 11: BÀI HỌC VỀ TRẢI NGHIỆM CHẠM ĐƠN (SINGLE-TAP) & KHỬ CHỒNG LẮP HỘP THOẠI KHẨN CẤP (MODAL DE-DUPLICATION)

Trong các thiết bị y tế và phần mềm cứu nạn cho người cao tuổi, độ nhạy và tính chuẩn xác của các thao tác chạm bấm (Touch Interaction) mang tính sống còn. Quá trình kiểm thử thực địa đã phát hiện và xử lý triệt để bài toán "phải bấm 2 lần mới tắt được cảnh báo ngã".

### 11.1 Chuẩn An Toàn Quốc Tế Về Hủy Báo Động Giả (False Alarm Cancellation Standard)
- **Tiêu chuẩn thiết kế y tế (FDA / Apple Watch Fall Detection / Samsung SOS)**:
  * Khi phát hiện cú ngã và bước vào chu kỳ đếm ngược (30 giây), nút bấm hủy cảnh báo (**"TÔI ỔN"**) **BẮT BUỘC PHẢI PHẢN HỒI NGAY TRONG 1 LẦN CHẠM DUY NHẤT (Single-Tap)**.
  * **Lý do**: Người cao tuổi sau khi vấp ngã hoặc đánh rơi điện thoại thường ở trạng thái hoảng sợ, run tay, hoặc thị lực suy giảm. Nếu bắt họ phải bấm đúp (double-tap) hoặc thao tác phức tạp, người dùng sẽ không biết xử lý, dẫn đến việc báo động giả bị kích hoạt gửi đi còi hú cho toàn bộ con cháu ngoài ý muốn.
  * Do đó, việc phải bấm 2 lần **KHÔNG PHẢI LÀ CHUẨN AN TOÀN**, mà là một **LỖI KỸ THUẬT CẦN KHẮC PHỤC TRIỆT ĐỂ**.

### 11.2 Phân Tích 3 Nguyên Nhân Kỹ Thuật Gây Lỗi Bấm 2 Lần
Qua mổ xẻ mã nguồn tầng Native Android và Flutter, đội ngũ đã làm rõ 3 nguyên nhân cộng hưởng:
1. **Nguyên nhân cốt lõi (Phát sự kiện kép - Event Duplication)**:
   * Khi ngã xảy ra, tầng Native Kotlin trong `WearOsMessageReceiverService` thực hiện cả 2 luồng:
     * Luồng A: Gọi `context.startActivity(fullScreenIntent)` -> Khiến `MainActivity.onNewIntent()` được gọi và bắn `onHardwareFallDetected` qua Flutter MethodChannel.
     * Luồng B: Gọi `context.sendBroadcast(intent)` -> Lớp `fallEventReceiver` nhận broadcast và bắn tiếp `onHardwareFallDetected` lần thứ 2 chỉ sau vài mili-giây.
   * Tại Flutter `sos_button_screen.dart`, hàm `_showFallCountdownModal(event)` không có cờ kiểm soát (`guard flag`). Hệ thống đã mở liên tiếp **2 HỘP THOẠI `FallCountdownDialog` CHỒNG KHÍT LÊN NHAU**.
   * Khi người dùng bấm lần 1: Nút "TÔI ỔN" của Dialog phía trên đóng lại (`Navigator.pop`), nhưng ngay bên dưới lại lộ ra Dialog thứ 2 giống hệt. Người dùng tưởng nút bấm chưa ăn nên phải bấm thêm lần 2 mới đóng hẳn!
2. **Nguyên nhân rung giật khung hình (`AnimatedBuilder` Churn)**:
   * Trước đây, `AnimatedBuilder` của hiệu ứng viền đập nhịp tim (`_pulseController`) bọc toàn bộ khối `Dialog` bao gồm cả các nút bấm `ElevatedButton`.
   * Khi animation chạy 60 - 120 FPS (trên màn hình 120Hz của Galaxy A55), toàn bộ cây widget và các bộ nhận diện cử chỉ (`GestureRecognizer`) của nút bấm bị tái tạo liên tục từng mili-giây, dẫn đến hiện tượng trượt cảm ứng (dropped pointer events) nếu ngón tay chạm vào đúng thời điểm khung hình đang rebuild.
3. **Thông báo còi hú Native không bị hủy khi đóng popup**:
   * Khi người dùng bấm "TÔI ỔN", ứng dụng chỉ hủy `AlarmManager` mà quên gọi `notificationManager.cancel(eventId.hashCode())`. Banner cảnh báo cấp cứu (Heads-Up Notification) vẫn còn nổi trên thanh trạng thái, gây chiếm quyền lấy nét cảm ứng (Window Touch Focus).

### 11.3 Giải Pháp Kỹ Thuật Toàn Diện Được Áp Dụng
1. **Khử trùng lặp tại tầng Native Kotlin (`MainActivity.kt`)**:
   * Bổ sung cờ `lastHandledEventId`. Nếu cùng một `eventId` được kích hoạt liên tiếp qua cả `onNewIntent` và `BroadcastReceiver`, hệ thống sẽ lập tức bỏ qua lệnh thứ hai:
     ```kotlin
     private fun dispatchFallEvent(eventId: String, timestamp: Long, impactG: Double?, secondsRemaining: Int) {
         if (eventId.isNotEmpty() && lastHandledEventId == eventId) {
             Log.i("CareAI-MainActivity", "Bỏ qua sự kiện ngã trùng lặp: $eventId")
             return
         }
         lastHandledEventId = eventId
         ...
     }
     ```
   * Khi nhận lệnh `cancelFallAlarm` từ Flutter, gọi `notificationManager.cancel(eventId.hashCode())` để lập tức xóa sạch banner còi hú trên khay hệ thống.
2. **Khóa chống mở hộp thoại kép tại tầng Flutter (`sos_button_screen.dart`)**:
   * Bổ sung cờ bảo vệ `_isFallDialogShowing`:
     ```dart
     bool _isFallDialogShowing = false;

     void _showFallCountdownModal(FallEvent event) {
       if (_isFallDialogShowing) return;
       _isFallDialogShowing = true;
       showDialog(...).whenComplete(() {
         _isFallDialogShowing = false;
       });
     }
     ```
3. **Tách biệt Animation và bảo vệ nút bấm tĩnh (`fall_countdown_dialog.dart`)**:
   * Truyền cây widget chứa nút bấm qua tham số `child` của `AnimatedBuilder` để Flutter giữ nguyên vẹn nút bấm trong bộ nhớ, không bị rebuild theo nhịp tim.
   * Thêm cờ `_isActionTaken = true` khi vừa chạm nút, đảm bảo hành động hủy cảnh báo hoặc gửi cứu hộ được thực thi tức thì và an toàn 100% trong đúng 1 lần chạm.

### 11.4 Tối Ưu Nút Bấm Khẩn Cấp Trung Tâm (SOS Button) Trên Màn Hình Chính
- **Vấn đề**: Tương tự như popup đếm ngược, nút bấm SOS trung tâm có hiệu ứng vòng sóng lan tỏa màu đỏ chạy liên tục (`_rippleController`). Ban đầu, toàn bộ cấu trúc nút bấm được viết bên trong khối `builder` của `AnimatedBuilder`, khiến nút bấm bị tạo lại 120 khung hình/giây.
- **Giải pháp**:
  * Tách thân nút bấm SOS chính sang tham số tĩnh `child: Material(...)` với `InkWell(customBorder: CircleBorder())`.
  * Khối `builder` chỉ chịu trách nhiệm render duy nhất vòng tròn sóng lan tỏa (`rippleValue`).
  * Nút bấm chính được bảo toàn nguyên vẹn trong bộ nhớ đệm, đem lại cảm giác nhấn nhạy tuyệt đối, phản hồi hiệu ứng sóng nước Material ngay khi ngón tay vừa chạm vào màn hình.
  * Hộp thoại xác nhận `_ManualSosConfirmDialog` được bổ sung cờ `_hasPopped` để đảm bảo khi người dùng bấm `[GỬI NGAY]` hoặc `[HỦY BỎ]`, hộp thoại lập tức đóng và thực hiện lệnh cứu nạn dứt khoát trong 1 chạm duy nhất.

### 11.5 Cơ Chế Rung Haptic & Âm Thanh Còi Hú Thực Tế Trên Android
- **Tính năng rung mỗi giây (Haptic Feedback)**:
  * Trong suốt 30 giây đếm ngược, hàm `HapticFeedback.vibrate()` được kích hoạt nhịp nhàng mỗi giây một lần.
  * Đây là tính năng công thái học y tế bắt buộc: Giúp người cao tuổi bị choáng, mờ mắt hoặc đánh rơi kính vẫn cảm nhận rõ ràng từng giây đếm ngược trong lòng bàn tay để kịp thời phản ứng.
- **Cơ chế âm thanh còi hú y tế độc quyền (`EmergencySoundPlayer`)**:
  * Để đảm bảo âm thanh mang tính khẩn cấp sinh tồn chuẩn y tế và không bị phụ thuộc vào chuông báo thức thông thường, hệ thống đã chuyển sang phát file âm thanh `careai_emergency_alarm.wav` qua singleton `EmergencySoundPlayer` chạy trên luồng báo động `AudioAttributes.USAGE_ALARM` (`STREAM_ALARM`).
  * Kênh thông báo `careai_emergency_fall_channel_v3` được thiết lập `setSound(null, null)` và `enableVibration(true)` để tránh hiện tượng dội âm/hai luồng âm thanh đè nhau.

### 11.6 Khắc Phục Âm Thanh Còi Báo Động Y Tế Khẩn Cấp, Phím Âm Lượng & Liên Kết Thông Báo Với Trạng Thái Thực Tế
- **Vấn đề 1: Âm thanh báo thức không phù hợp & Nâng cấp sang Nhịp điệu 2 Nhịp (2-Beat Cadence)**:
  * Trước đây, hệ thống sử dụng âm chuông báo thức mặc định của điện thoại (`RingtoneManager.TYPE_ALARM`). Âm thanh này nhẹ nhàng như chuông báo thức buổi sáng, không mang tính khẩn cấp sinh tồn.
  * **Chuẩn hóa sang Còi hú 2 Nhịp**: Tạo file âm thanh còi hú y tế chuyên dụng `careai_emergency_alarm.wav` cấu trúc nhịp đôi chuẩn Monitor cấp cứu:
    * Nhịp 1: Xung 920 Hz kéo dài 160ms.
    * Nghỉ giữa 2 nhịp: 70ms tĩnh lặng.
    * Nhịp 2: Xung 920 Hz kéo dài 160ms.
    * Nghỉ cuối chu kỳ: 410ms tĩnh lặng.
    * Tổng chu kỳ: Đúng 800ms (0.8s), lặp lại nhịp nhàng: *"TÍT - TÍT ... (nghỉ) ... TÍT - TÍT ... (nghỉ) ... TÍT - TÍT ..."*.
    * **Lợi thế tâm lý học lâm sàng (Clinical Advantage)**: Âm thanh đơn kéo dài liên tục dễ làm người cao tuổi hoảng loạn, chói tai; chu kỳ 2 nhịp dồn dập vừa đủ tạo cảm giác khẩn cấp để đánh thức sự chú ý, vừa có khoảng lặng ngắn để não bộ xử lý và giữ bình tĩnh bấm "Tôi ổn".
  * Xây dựng singleton `EmergencySoundPlayer.kt` quản lý `MediaPlayer` phát lặp (`isLooping = true`) chạy trên luồng báo động tối cao `AudioAttributes.USAGE_ALARM` (`STREAM_ALARM`).

- **Vấn đề 2: Bấm phím Giảm âm lượng làm tắt lịm âm thanh cảnh báo & Giải mã Thanh âm lượng**:
  * **Giải mã Thanh âm lượng**: Thanh trượt xuất hiện trên màn hình khi bấm nút giảm âm lượng **KHÔNG PHẢI là thanh âm lượng riêng do ứng dụng tự tạo**, mà chính là **Bảng điều khiển âm lượng hệ thống chuẩn của Samsung One UI** ("Âm lượng chuông báo").
  * **Nguyên nhân**: Mặc định trên Android, khi có báo thức/chuông thông báo đang kêu, cử chỉ bấm phím cứng `Volume Down` hoặc `Volume Up` được hệ điều hành hiểu là thao tác "Tắt chuông khẩn cấp" (Silence Ringer/Alarm) giống như tắt chuông cuộc gọi đến.
  * **Khắc phục**:
    * Trong `MainActivity.kt`, override hàm `onKeyDown` và `onKeyUp`:
    * Khi `EmergencySoundPlayer.isPlaying() == true`:
      * `KEYCODE_VOLUME_DOWN`: Gọi `audioManager.adjustStreamVolume(AudioManager.STREAM_ALARM, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)` và `return true`.
      * `KEYCODE_VOLUME_UP`: Gọi `audioManager.adjustStreamVolume(AudioManager.STREAM_ALARM, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)` và `return true`.
    * Cờ `FLAG_SHOW_UI` yêu cầu Android hiển thị thanh trượt âm lượng gốc của máy. Nhờ trả về `true` (consume event), hệ điều hành không bao giờ ngắt luồng phát âm thanh; âm lượng còi hú được tăng/giảm mượt mà theo từng nấc và người dùng hoàn toàn làm chủ độ to nhỏ.

- **Vấn đề 3: Bản chất của CSDL Direct Boot `CareAiFallStore` (Local Flash Storage, Không phải gọi Cloud/Azure SQL)**:
  * **Bản chất**: `CareAiFallStore` **HOÀN TOÀN KHÔNG PHẢI là gọi lên máy chủ (Cloud/Azure SQL Database)**.
  * Đây là **kho lưu trữ cục bộ 100% trên chip nhớ flash của chiếc điện thoại**, sử dụng phân vùng bảo mật phần cứng đặc biệt của Android gọi là **Device Protected Storage (Direct Boot)**.
  * **Tại sao phải dùng Direct Boot**:
    1. Khi điện thoại vừa khởi động lại mà người dùng **chưa mở khóa màn hình** (màn hình còn đang khóa bằng mật khẩu/vân tay), phân vùng thông thường bị Android mã hóa bằng khóa người dùng (Credential Encrypted Storage), app không thể đọc được.
    2. Phân vùng Device Protected Storage được mã hóa bằng chip phần cứng của máy (Hardware Root-of-Trust). Nhờ đó, ứng dụng đọc/ghi trạng thái sự cố ("PENDING_CONFIRMATION", "CANCELLED_BY_USER") **ngay lập tức trong 0.1 mili-giây**, hoàn toàn ngoại tuyến và độc lập 100% với mạng Internet.
  * **Ứng dụng vào bài toán thông báo**:
    * Khi người dùng bấm vào một thông báo cũ trên khay hệ thống, ứng dụng tra cứu `CareAiFallStore` trên máy trong 0.1ms:
      * Nếu thấy sự cố đã được hủy (`status == "CANCELLED_BY_USER"`), đã gửi cứu hộ (`SOS_SENT`), hoặc thời gian 30s đã hết: App lập tức dọn sạch Intent, hủy thông báo và **chỉ mở màn hình chính bình thường, tuyệt đối không bật popup hay còi hú**.
      * Nếu thấy sự cố vẫn đang đếm ngược thật sự: App tiếp tục duy trì còi hú và hiển thị hộp thoại với đúng số giây còn lại thực tế.
    * Khi người dùng bấm `[TÔI ỔN]` hoặc `[CẦN TRỢ GIÚP - GỬI NGAY]`, hoặc khi hộp thoại bị `dispose`: Hàm `stopEmergencySound` lập tức được kích hoạt để dập tắt hoàn toàn âm thanh còi hú, hủy watchdog và dọn sạch Intent.

---

## 13. KINH NGHIỆM PHÁT TRIỂN & CÀI ĐẶT ỨNG DỤNG NGƯỜI THÂN ĐỘC LẬP (CAREGIVER APP COEXISTENCE)

### 13.1 Chiến Lược Cài Đặt Song Song 2 Ứng Dụng Trên Cùng 1 Điện Thoại Thật
- **Mục tiêu**: Người phát triển hoặc kiểm thử viên chỉ có 1 chiếc điện thoại (Samsung Galaxy A55 5G) nhưng cần thử nghiệm trọn vẹn luồng hai chiều: App Cụ (`companion_app`) phát tín hiệu ngã và App Con cháu (`caregiver_app`) nhận còi hú khẩn cấp.
- **Giải pháp**:
  * Tách biệt hoàn toàn Package ID / `applicationId`:
    - Companion App: `vn.careai.companion` (Tên hiển thị: `CareAI Companion`).
    - Caregiver App: `vn.careai.caregiver` (Tên hiển thị: `CareAI Người Thân`).
  * Nhờ hai `applicationId` khác nhau, hệ điều hành Android coi đây là hai ứng dụng độc lập 100%, có phân vùng dữ liệu riêng, process ID riêng và có thể chạy song song đồng thời trên cùng một thiết bị.

### 13.2 Cạm Bẫy Lệch Thư Mục Package Kotlin (`ClassNotFoundException`)
- **Hiện tượng**: Biên dịch APK thành công (`assembleDebug` exit code 0) nhưng khi khởi chạy app bị văng ngay lập tức với lỗi:
  `java.lang.RuntimeException: Unable to instantiate activity ComponentInfo{vn.careai.caregiver/vn.careai.caregiver.MainActivity}: java.lang.ClassNotFoundException: Didn't find class "vn.careai.caregiver.MainActivity"`.
- **Nguyên nhân**: Khi tạo dự án Flutter bằng lệnh `flutter create --org vn.careai caregiver_app`, Flutter tự động tạo package name là `vn.careai.caregiver_app` (thêm đuôi `_app`). Khi ta sửa `applicationId` và `namespace` trong `build.gradle.kts` thành `vn.careai.caregiver`, tệp `MainActivity.kt` trên đĩa vẫn nằm ở thư mục `kotlin/vn/careai/caregiver_app/MainActivity.kt` với dòng khai báo `package vn.careai.caregiver_app`. Android Manifest tham chiếu `.MainActivity` sẽ tìm `vn.careai.caregiver.MainActivity` và không tìm thấy class trong DEX.
- **Khắc phục**: Di chuyển `MainActivity.kt` sang đúng thư mục `kotlin/vn/careai/caregiver/MainActivity.kt`, khai báo đúng `package vn.careai.caregiver`, xóa thư mục cũ và rebuild APK.

### 13.3 Cạm Bẫy Ký Tự UTF-8 BOM Trong Tệp XML SharedPreferences Của Android
- **Hiện tượng**: Bơm sẵn cấu hình đăng nhập vào tệp `FlutterSharedPreferences.xml` trên thiết bị qua ADB nhưng khi mở app lên, Flutter không đọc được dữ liệu và ứng dụng bị treo hoặc không nhận trạng thái đăng nhập.
- **Nguyên nhân**: Khi dùng PowerShell `Set-Content -Encoding UTF8`, PowerShell tự động chèn 3 byte BOM (Byte Order Mark: `EF BB BF`) vào đầu tệp XML. Trình phân tích cú pháp XML gốc của Android (`XmlPullParser`) bắt buộc tệp XML phải bắt đầu ngay bằng ký tự `<` (`0x3C`), nếu gặp BOM sẽ quăng ngoại lệ cú pháp và hủy toàn bộ dữ liệu cài đặt.
- **Khắc phục**: Khi ghi XML SharedPreferences bằng script, bắt buộc dùng `[System.IO.File]::WriteAllText($path, $xml, (New-Object System.Text.UTF8Encoding($false)))` để đảm bảo tệp hoàn toàn sạch không chứa BOM (`UTF-8 no-BOM`).

### 13.4 Chuyển Mạch Đa Kênh Tự Động (Dual-Network Failover) Cho Caregiver App
- **Yêu cầu**: Ứng dụng người thân phải kết nối được với Backend trong mọi tình huống di chuyển (ở nhà cắm cáp USB `adb reverse tcp:5097`, hoặc ra ngoài đường dùng 4G/Wi-Fi qua Cloudflare Tunnel).
- **Giải pháp**: Xây dựng hàm bao bọc `_executeWithFailover(action)` trong `CaregiverApiService`:
  * Mặc định gọi URL hiện tại.
  * Nếu gặp lỗi kết nối mạng (SocketException, TimeoutException), hệ thống tự động thử URL dự phòng đối ứng (USB -> Cloudflare Tunnel hoặc ngược lại), ghi nhớ URL hoạt động vào `SharedPreferences` và tiếp tục luồng dữ liệu mà không làm gián đoạn trải nghiệm người dùng.

### 13.5 Cấu Trúc DTO System.Text.Json & Mã Hóa Ký Tự Tiếng Việt
- **Lưu ý**: Khi gửi dữ liệu JSON chứa ký tự tiếng Việt có dấu (như tên cụ, địa chỉ, bệnh án) từ client hoặc PowerShell lên ASP.NET Core Kestrel:
  * Phải thiết lập Header `Content-Type: application/json; charset=utf-8`.
  * Các trường DateTime trong DTO C# (ví dụ `DateOfBirth`) bắt buộc phải truyền định dạng ISO 8601 hợp lệ (`YYYY-MM-DDTHH:mm:ssZ`), không được truyền số nguyên hay chuỗi sai định dạng.

---

## 14. KINH NGHIỆM ĐÓNG GÓI MÃ NGUỒN GIT, PHÂN ĐỊNH THƯ MỤC & XÁC THỰC GITHUB PUSH

### 14.1 Cạm Bẫy Đẩy Lên GitHub Gặp Lỗi "Repository not found" (404)
- **Hiện tượng**: Khi chạy `git push -u origin main` hoặc `git ls-remote https://github.com/taithptqt/CareAI.git`, Git báo lỗi:
  `remote: Repository not found.`
  `fatal: repository 'https://github.com/taithptqt/CareAI.git/' not found`
- **Nguyên nhân cốt lõi**:
  1. **Kho lưu trữ chưa được tạo**: Trên tài khoản GitHub `taithptqt`, người dùng chưa tạo một repository trống mang tên `CareAI`.
  2. **Bảo mật của GitHub với Private Repository**: Nếu repository đã được tạo ở chế độ **Private**, bất kỳ truy vấn nào không có token xác thực hoặc xác thực sai tài khoản đều bị GitHub trả về mã `404 Not Found` (thay vì 403 Forbidden) để ngăn kẻ xấu dò quét tên kho riêng tư của người khác.
  3. **Lệch tài khoản trong Windows Credential Manager**: Trên máy tính Windows, Git Credential Manager có thể đang lưu token của một tài khoản GitHub khác (ví dụ: tài khoản trường học hoặc cá nhân khác). Khi push vào repo của `taithptqt`, Git gửi thông tin xác thực cũ và bị GitHub từ chối.
- **Giải pháp xử lý chuẩn xác 100%**:
  1. Người dùng truy cập `https://github.com/new` và tạo repository mang tên `CareAI` (có thể chọn Public hoặc Private).
  2. Nếu là Private, có 2 cách push:
     * **Cách 1 (Khuyên dùng)**: Tạo một **Personal Access Token (PAT)** tại `https://github.com/settings/tokens` (chọn quyền `repo`), sau đó push qua URL có token:
       `git push https://<TOKEN>@github.com/taithptqt/CareAI.git main`
     * **Cách 2**: Chạy lệnh xóa cache credential cũ và đăng nhập lại bằng tài khoản `taithptqt`:
       `cmdkey /delete:LegacyGeneric:target=git:https://github.com`
       Sau đó chạy lại `git push -u origin main` để trình duyệt hiện popup đăng nhập tài khoản `taithptqt`.

### 14.2 Chiến Lược .gitignore Cho Hệ Sinh Thái Đa Nền Tảng (Dotnet + Flutter + Wear OS)
- **Vấn đề**: Dự án CareAI tích hợp cả C# .NET 9, Flutter, Android Native và tài liệu Word/Markdown trong cùng 1 workspace. Nếu `git add .` thiếu chọn lọc, repository sẽ bị phình to hàng trăm MB bởi:
  * Thư mục `bin/`, `obj/` của .NET.
  * Thư mục `.dart_tool/`, `build/` của Flutter.
  * Thư mục `.gradle/` và các file `*.apk` (bản debug có thể nặng 150MB+).
  * Dự án ngoài lề không thuộc CareAI (như `AcademicManagement/`).
  * File công cụ ngoài lề như `tools/cloudflared.exe` (80MB).
- **Quy chuẩn**: Bắt buộc tạo tệp `.gitignore` chuẩn ở thư mục gốc để lọc sạch toàn bộ các thư mục tạm này trước khi commit. Nhờ đó, repository Git giữ được dung lượng cực kỳ gọn gàng, tải về nhanh chóng và chuẩn mực kiến trúc doanh nghiệp.

---

## 15. KINH NGHIỆM HỢP NHẤT ỨNG DỤNG DI ĐỘNG (UNIFIED MOBILE APP) & KỸ THUẬT DỌN DẸP THƯ MỤC LỒNG SÂU TRÊN WINDOWS

### 15.1 Kiến Trúc Hợp Nhất Ứng Dụng Di Động Đa Vai Trò (Role-Based Mobile Routing)
- **Bối cảnh & Bài toán**: Ban đầu, dự án có 2 ứng dụng di động riêng: `companion_app` (cho người cao tuổi) và `caregiver_app` (cho người thân). Việc duy trì 2 app riêng biệt gây lãng phí tài nguyên phát triển, nhân đôi thời gian biên dịch Gradle và khiến người nhà gặp khó khăn khi muốn chuyển đổi chế độ kiểm tra sức khỏe trên cùng 1 điện thoại.
- **Giải pháp Hợp nhất Chuẩn mực**:
  * Tích hợp toàn bộ mã nguồn phân hệ Người thân vào `companion_app` dưới namespace biệt lập `lib/caregiver/` (gồm `models/`, `services/`, `screens/`).
  * Xây dựng `RoleSelectionScreen` cho phép người dùng chọn vai trò ngay khi khởi chạy lần đầu:
    - **Chế độ Người cao tuổi**: Màn hình SOS khẩn cấp, phát hiện té ngã, đo nhịp tim, kết nối Galaxy Watch.
    - **Chế độ Người thân / Con cháu**: Bảng điều khiển từ xa, nhận cảnh báo Quorum SLA 60s, xác nhận tiếp nhận cứu hộ (ACK), đóng sự cố (Resolve), quản lý nhóm gia đình.
  * Ghi nhớ lựa chọn vào `SharedPreferences` với khóa `careai_selected_role` (`'elder'` hoặc `'caregiver'`).
  * Hỗ trợ đổi vai trò 2 chiều tức thì:
    - Từ Chế độ Người cao tuổi: Bấm icon đổi vai trò (`Icons.swap_horiz_rounded`) trên AppBar -> Xác nhận -> Chuyển sang Người thân.
    - Từ Chế độ Người thân: Vào tab Tài khoản -> Bấm "Chuyển sang Chế độ Người cao tuổi" hoặc "Màn hình chọn vai trò" -> Chuyển tức thì.

### 15.2 Bảo Toàn Tuyệt Đối Các Thành Phần Native Android Direct Boot & Wear OS
- **Bất biến kỹ thuật sống còn**: Khi hợp nhất mã nguồn Flutter, toàn bộ hạ tầng Native Android ở tầng dưới **bắt buộc phải giữ nguyên vẹn 100%**:
  * Package ID giữ nguyên là `vn.careai.companion`.
  * Lớp bảo vệ Direct Boot `PhoneBootReceiver` và `CareAiFallStore` trên phân vùng Device Protected Storage vẫn kích hoạt ngay cả khi máy chưa mở khóa màn hình.
  * Còi hú cấp cứu ICU 1350Hz phần cứng `SoundPool`, bộ đếm giờ phần cứng `AlarmManager.RTC_WAKEUP` và kênh đồng bộ Galaxy Watch (`:wearos`) gắn trực tiếp vào Android Host OS, hoạt động bền bỉ trong nền bất kể giao diện Flutter đang ở vai trò nào.

### 15.3 Cạm Bẫy Đường Dẫn Quá Dài (Long Path Limit 260 Ký Tự) Trên Windows & Giải Pháp Robocopy Mirror
- **Hiện tượng**: Khi tiến hành xóa thư mục dự án cũ (ví dụ `caregiver_app`), các lệnh thông thường trên Windows như:
  * PowerShell: `Remove-Item -Recurse -Force .\caregiver_app`
  * Command Prompt: `rmdir /s /q caregiver_app`
  đều bị thất bại và ném lỗi: `PathTooLongException` hoặc `The filename or extension is too long`.
- **Nguyên nhân sâu xa**: Bộ nhớ đệm biên dịch Gradle của Android (`.transformed/...bundleLibRuntimeToDirDebug_global-synthetics...`) tạo ra cấu trúc thư mục lồng nhau hàng chục tầng, vượt quá giới hạn 260 ký tự chuẩn (`MAX_PATH`) của API Windows Win32.
- **Giải pháp Tuyệt đối & Tức thì bằng Robocopy (Robust File Copy)**:
  * Công cụ gốc `robocopy.exe` của Windows hỗ trợ đường dẫn Unicode dài tới 32,767 ký tự.
  * Quy trình dọn sạch thư mục lồng sâu chỉ trong 2 lệnh PowerShell/CMD:
    ```powershell
    # 1. Tạo một thư mục trống tạm thời
    New-Item -ItemType Directory -Path "$env:TEMP\empty_purge" -Force
    # 2. Dùng Robocopy với cờ /MIR (Mirror) để đồng bộ hóa thư mục rỗng vào thư mục cần xóa
    robocopy "$env:TEMP\empty_purge" "D:\IT\PRACTICE\CareAI\caregiver_app" /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS
    # 3. Sau khi Robocopy dọn sạch ruột thư mục, xóa vỏ thư mục rỗng
    Remove-Item -Path "D:\IT\PRACTICE\CareAI\caregiver_app" -Force
    Remove-Item -Path "$env:TEMP\empty_purge" -Force
    ```
  * Kết quả: Thư mục hàng trăm MB với hàng ngàn file lồng sâu được xóa sạch bong chỉ trong 1 giây mà không gặp bất kỳ lỗi PathTooLong nào.

---

## 16. KINH NGHIỆM THIẾT KẾ BRANDING, ICON VÀ KHẮC PHỤC TRIỆT ĐỂ MÀN HÌNH KHỞI ĐỘNG (SPLASH SCREEN) TRÊN ANDROID 12+

### 16.1 Quy Chuẩn Mặt Nạ Tròn 160dp Của Android 12+ (API 31+) & Cạm Bẫy Viền Bị Cắt Xén
- **Hiện tượng**: Khi tạo biểu tượng màn hình khởi động (Splash Screen) có khung viền squircle/hộp chữ nhật bao quanh biểu tượng, màn hình khởi động 1 giây hiển thị một hình ô-van kì dị với 4 góc bị cắt cụt nham nhở, viền sát rạt với logo bên trong.
- **Nguyên nhân gốc rễ**:
  * Từ Android 12 (API 31) trở lên (ví dụ Android 14 trên Samsung Galaxy A55 5G), Google chuẩn hóa API SplashScreen toàn hệ thống.
  * Toàn bộ khung Canvas của splash icon là **288 × 288 dp**.
  * Tuy nhiên, hệ điều hành Android tự động áp dụng một **Mặt nạ tròn (Circular Mask) đường kính 160 dp** (tương đương 55.5% bề rộng) ngay tại tâm. Bất kỳ pixel nào nằm ngoài bán kính 80dp đều bị OS cắt bỏ hoàn toàn!
  * Do đó, nếu đưa một hình squircle hoặc hình vuông lấp đầy khung 288x288 dp, hệ điều hành sẽ cắt phăng 4 góc, biến biểu tượng thành hình tròn méo mó hoặc cọ sát sát mép viền.
- **Giải pháp Chuẩn mực**:
  * **Phương án Pure Floating Glyph (Biểu tượng nổi không nền)**: Không dùng khối hộp hoặc viền nền bao quanh icon splash. Bóc tách phần biểu tượng (Glyph) chính đặt trên nền **100% trong suốt (Transparent)**.
  * Định cỡ biểu tượng Glyph nằm gọn trong khoảng **140dp - 150dp** ở chính giữa khung 288x288 dp.
  * Kết quả: Biểu tượng nằm hoàn toàn 100% bên trong vùng an toàn tròn 160dp của Android, nổi bật tự nhiên và thanh thoát trên màu nền `windowSplashScreenBackground`.

### 16.2 Khắc Phục Triệt Để Màn Hình Khởi Động Nền Trắng Bằng `values-v31/styles.xml`
- **Hiện tượng**: Mặc dù trong Flutter và `launch_background.xml` đã cấu hình màu nền tối `#0F172A`, khi bấm mở app trên Android 12+, máy vẫn nhấp nháy 1 giây màn hình nền trắng tinh chói mắt trước khi vào giao diện ứng dụng.
- **Nguyên nhân**: Android 12+ bỏ qua hoàn toàn `launch_background.xml` thông thường và buộc ứng dụng sử dụng theme Splash Screen cấp hệ thống. Nếu không có cấu hình dành riêng cho API 31+, OS tự động dùng `Theme.Light` (màu trắng `#FFFFFF`).
- **Giải pháp Chuẩn xác**:
  * Tạo tệp `android/app/src/main/res/values-v31/styles.xml`:
    ```xml
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
        <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
            <item name="android:windowSplashScreenBackground">@color/splash_bg</item>
            <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon</item>
            <item name="android:windowSplashScreenIconBackgroundColor">@color/splash_bg</item>
        </style>
        <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
            <item name="android:windowBackground">?android:colorBackground</item>
        </style>
    </resources>
    ```
  * Định nghĩa `@color/splash_bg` là `#0F172A` trong `res/values/colors.xml`.
  * Nhờ vậy, từ mili-giây đầu tiên khi hệ điều hành tải tiến trình, màn hình khởi động đã mang màu xanh đá trầm tối chuẩn y tế, chuyển tiếp mượt mà 0ms vào giao diện Flutter.

### 16.3 Căn Lề An Toàn (Safe Padding 38%) Cho Launcher Icon Ngoài Màn Hình Chủ
- **Bài học thực tế**: Biểu tượng ứng dụng trên màn hình chủ (Launcher Icon `ic_launcher.png`) cần có lề đệm (padding) tối thiểu 30% - 38% xung quanh biểu tượng lõi.
- Nếu không có padding đủ rộng, khi các Launcher của các hãng (Samsung One UI, Google Pixel Launcher, Xiaomi MIUI) tự động cắt theo hình Squircle hoặc Circle, các cánh tim và sóng điện tim sẽ bị đè sát hoặc cắt lẹm vào cạnh biểu tượng.
- Quy chuẩn: Icon 512x512 có kích thước glyph trung tâm là ~240 - 280px, tạo ra lề đệm thoáng đãng, sang trọng và chuẩn công thái học Mobile Design.


