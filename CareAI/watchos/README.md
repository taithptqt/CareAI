# CareAI watchOS App (Apple Watch · HealthKit · Fast-Lane SOS)

Ứng dụng watchOS độc lập cho Apple Watch trong hệ sinh thái CareAI, đồng bộ tính năng và giao diện 100% (feature & UI parity) với phân hệ Wear OS (`vn.careai.companion` Wear OS).

## Tính năng và Năng lực cốt lõi (Tương đương Wear OS)

1. **Giao diện Trực quan Y tế (Medical Watch UI)**:
   - **Tiêu đề**: "CareAI Watch" (màu Cyan `#38BDF8`).
   - **Huy hiệu Trạng thái Thời gian thực (Dynamic Status Badge)**:
     - `🟢 Đang Giám Sát Cổ Tay` (Bình thường, theo dõi HealthKit nền).
     - `🚨 NHỊP NHANH: ... BPM` (Màu đỏ khi nhịp tim $\ge 140$ bpm).
     - `⚠️ NHỊP CHẬM: ... BPM` (Màu hổ phách khi nhịp tim $\le 45$ bpm).
     - `🫁 THIẾU OXY: ...%` (Màu tím khi SpO₂ $\le 90\%$).
     - `💥 CẢNH BÁO TÉ NGÃ!` (Màu đỏ khi phát hiện hoặc mô phỏng té ngã).
     - `🆘 ĐÃ BẮN TÍN HIỆU SOS!` (Màu đỏ khi kích hoạt nút SOS).
   - **Thẻ Sinh Hiệu Trực Tiếp (Vitals Pill Card)**: Hiển thị tức thời `❤️ XX BPM · YY.Y% SpO2`.

2. **Nút Bấm Cấp Cứu Sống Còn (Fast-Lane Emergency SOS)**:
   - **`💥 Mô Phỏng Té Ngã`**: Kích hoạt gửi sự cố té ngã (`FALL_DETECTED`) trực tiếp tới API cấp cứu `POST /api/v1/incidents/sos`.
   - **`🆘 SOS Khẩn Cấp`**: Kích hoạt gửi sự cố SOS bằng tay (`MANUAL_SOS`) trực tiếp tới API cấp cứu.
   - **Tuân thủ Tuyệt đối Bất biến Fact 35 (INV-08)**: Gói tin SOS bắt buộc đính kèm toàn bộ các mẫu đo sinh hiệu tức thời (`HEART_RATE`, `SPO2`) tại thời điểm xảy ra sự cố.

3. **Bộ 4 Nút Thử Nghiệm Lâm Sàng Trực Tiếp Trên Mặt Đồng Hồ (2x2 Grid)**:
   - `🚨 Nhanh 155`: Giả lập nhịp nhanh kịch phát 155 BPM.
   - `⚠️ Chậm 38`: Giả lập nhịp chậm nguy hiểm 38 BPM.
   - `🫁 Oxy 88%`: Giả lập cơn tụt oxy máu sâu SpO₂ 88.0%.
   - `🟢 Chuẩn 75`: Khôi phục trạng thái bình thường 75 BPM và 98.5% SpO₂.

4. **Đồng Bộ Dữ Liệu & Hàng Đợi Ngoại Tuyến (Store-and-Forward)**:
   - Lưu trữ an toàn trong vùng nhớ đĩa (`healthkit-pending-readings.json`) bảo toàn nguyên tử (`.atomic`).
   - Tự động xả hàng đợi khi có kết nối mạng (`NWPathMonitor`, retry timer).
   - Lưu trữ token bảo mật trong Keychain (`KeychainToken.swift`).

5. **Tự Động Phát Hiện Té Ngã Đa Tầng & SOS Kiên Cường (Multi-Tier Fall Detection & Resilient SOS)**:
   - **Tầng 1 (Chính chủ Apple)**: Tích hợp `CMFallDetectionManager` (`CoreMotion`) nhận diện ngã trực tiếp từ mô hình phần cứng Apple Watch Series 4+.
   - **Tầng 2 (Dự phòng gia tốc)**: Thuật toán phân tích chuyển động liên tục qua `CMMotionManager` (20Hz) bắt pha rơi tự do ($< 0.35g$) và va chạm mạnh ($> 2.8g$) trong vòng 800ms kèm thời gian hồi chống spam 15 giây.
   - **Phiên thực thi mở rộng (`WKExtendedRuntimeSession`)**: Giữ đồng hồ thức ngầm trong suốt thời gian xảy ra sự cố cấp cứu, chống watchOS đưa app vào trạng thái ngủ đông khi hạ cổ tay.
   - **Đường truyền Fast-Lane kiên cường (`URLSession`)**: Cấu hình `waitsForConnectivity = true` chống rớt gói khi đồng hồ chuyển giao mạng Wi-Fi/Cellular/Bluetooth.

## Hướng dẫn Thiết lập & Biên dịch trên macOS (Xcode)

1. Trên máy Mac, cài đặt Xcode và XcodeGen:
   ```bash
   brew install xcodegen
   cd CareAI/watchos
   xcodegen generate
   open CareAIWatch.xcodeproj
   ```
2. Cấu hình Signing & Capabilities:
   - Chọn Developer Team của bạn.
   - Bật capability HealthKit (Background Delivery) tương ứng file `CareAIWatch.entitlements`.
3. Khởi chạy và Ghép nối:
   - Chạy ứng dụng trên Apple Watch thật hoặc Simulator.
   - Nhập URL HTTPS của máy chủ CareAI Backend và mã PIN 6 số được cấp từ ứng dụng Người thân.
   - Nhấn **Ghép Nối Đồng Hồ** để nhận `deviceId` và `deviceToken`.
