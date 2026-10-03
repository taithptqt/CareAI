# CareAI Wear OS App (Samsung Galaxy Watch / Wear OS · Health Services · Dual-Channel SOS)

Ứng dụng Wear OS độc lập cho đồng hồ thông minh chạy hệ điều hành Wear OS (Samsung Galaxy Watch 4/5/6/7, Google Pixel Watch) trong hệ sinh thái CareAI. Module này vận hành độc lập hoàn toàn với ứng dụng điện thoại và hỗ trợ kết nối Bluetooth/Wi-Fi thông qua Google Play Services Wearable Data Layer.

## Tính năng và Năng lực cốt lõi

1. **Giao diện Trực quan Y tế (Medical Watch UI - Shape Tròn Chuẩn OLED)**:
   - **Tiêu đề**: "CareAI Watch" (màu Cyan `#38BDF8`).
   - **Huy hiệu Trạng thái Thời gian thực (Dynamic Status Badge)**:
     - `🟢 Đang Giám Sát Cổ Tay` (Bình thường, lắng nghe cảm biến nền).
     - `🚨 NHỊP NHANH: ... BPM` (Màu đỏ khi nhịp tim $\ge 140$ bpm).
     - `⚠️ NHỊP CHẬM: ... BPM` (Màu hổ phách khi nhịp tim $\le 45$ bpm).
     - `🫁 THIẾU OXY: ...%` (Màu tím khi SpO₂ $\le 90\%$).
     - `💥 CẢNH BÁO TÉ NGÃ!` (Màu đỏ khi phát hiện hoặc mô phỏng té ngã).
     - `🆘 ĐÃ BẮN TÍN HIỆU SOS!` (Màu đỏ khi kích hoạt nút SOS).
   - **Thẻ Sinh Hiệu Trực Tiếp (Vitals Pill Card)**: Hiển thị tức thời `❤️ XX BPM · YY.Y% SpO2`.

2. **Nút Bấm Cấp Cứu Sống Còn (Dual-Channel Emergency Dispatch)**:
   - **`💥 Mô Phỏng Té Ngã`**: Kích hoạt gửi sự cố té ngã phần cứng (`FALL_WEAR_...`) sang điện thoại.
   - **`🆘 SOS Khẩn Cấp`**: Kích hoạt gửi sự cố SOS khẩn cấp bằng tay (`SOS_WATCH_...`) sang điện thoại.
   - **Cơ chế Truyền Kép Độc Lập (True Concurrent Dual-Channel)**:
     - **Kênh 1 (MessageClient Fast-Lane)**: Bắn trực tiếp qua Bluetooth với độ trễ < 50ms không đợi ghi đĩa.
     - **Kênh 2 (DataClient Store-and-Forward)**: Ghi vào bộ đệm bền bỉ `/careai/fall_event/...` với cờ `.setUrgent()`, bảo đảm dữ liệu tự động đồng bộ ngay khi thiết bị có lại kết nối.

3. **Bộ 4 Nút Thử Nghiệm Lâm Sàng Trực Tiếp Trên Mặt Đồng Hồ (2x2 Grid)**:
   - `🚨 Nhanh 155`: Giả lập nhịp nhanh kịch phát 155 BPM.
   - `⚠️ Chậm 38`: Giả lập nhịp chậm nguy hiểm 38 BPM.
   - `🫁 Oxy 88%`: Giả lập cơn tụt oxy máu sâu SpO₂ 88.0%.
   - `🟢 Chuẩn 75`: Khôi phục trạng thái bình thường 75 BPM và 98.5% SpO₂.

4. **Tích Hợp Cảm Biến Phần Cứng & Google Health Services**:
   - Tự động đăng ký `Sensor.TYPE_HEART_RATE` (cảm biến BioActive PPG quang học) khi người dùng đeo đồng hồ.
   - Lắng nghe sự kiện ngã phần cứng `HealthEvent.Type.FALL_DETECTED` từ Google Health Services Client qua `WearOsFallListenerService`.
   - Hỗ trợ bộ nhận diện kiểm thử ADB / Synthetic Data Provider (`whs.synthetic.user.SET_HEART_RATE`, `vn.careai.watch.INJECT_VITALS`).

---

## Hướng dẫn Biên dịch & Cài đặt

### 1. Biên dịch file APK Wear OS độc lập
Từ thư mục gốc dự án:
```powershell
cd CareAI/wearos
.\gradlew.bat assembleDebug
```
File APK kết quả được tạo tại: `CareAI/wearos/build/outputs/apk/debug/wearos-debug.apk`.

### 2. Cài đặt lên Thiết bị thật hoặc Thiết bị ảo (Emulator)
Khởi động máy ảo Galaxy Watch qua script `KHOI_DONG_DONG_HO_WEAROS.bat`, sau đó cài đặt qua ADB:
```powershell
adb -s emulator-5554 install -r CareAI/wearos/build/outputs/apk/debug/wearos-debug.apk
```

### 3. Các lệnh ADB Kiểm thử & Bơm dữ liệu cảm biến
* Bơm nhịp nhanh kịch phát 155 BPM:
  ```powershell
  adb -s emulator-5554 shell am broadcast -a vn.careai.watch.INJECT_VITALS --ei heart_rate 155 --es alert_type TACHYCARDIA
  ```
* Bơm nhịp chậm 38 BPM:
  ```powershell
  adb -s emulator-5554 shell am broadcast -a vn.careai.watch.INJECT_VITALS --ei heart_rate 38 --es alert_type BRADYCARDIA
  ```
* Bơm thiếu oxy SpO2 88%:
  ```powershell
  adb -s emulator-5554 shell am broadcast -a vn.careai.watch.INJECT_VITALS --ef spo2 88.0 --es alert_type HYPOXIA
  ```
* Kích hoạt sự cố ngã khẩn cấp từ CLI:
  ```powershell
  adb -s emulator-5554 shell am broadcast -a vn.careai.watch.SIMULATE_FALL
  ```
