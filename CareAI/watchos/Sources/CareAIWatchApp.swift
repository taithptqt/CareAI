import SwiftUI

@main
struct CareAIWatchApp: App {
    @StateObject private var sync = HealthSync()

    var body: some Scene {
        WindowGroup {
            ContentView(sync: sync)
        }
        .backgroundTask(.appRefresh("careai.healthsync")) { _ in
            await sync.refreshInBackground()
        }
    }
}

struct ContentView: View {
    @ObservedObject var sync: HealthSync
    @Environment(\.scenePhase) private var scenePhase
    // Cấu hình URL Azure App Service mặc định
    @State private var backend = UserDefaults.standard.string(forKey: "backend") ?? "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"
    @State private var pin = ""
    @State private var pairing = false
    @State private var pairingError: String?
    private var isPaired: Bool {
        sync.isPaired
    }
    @State private var showSettings = false

    private var pinChars: [Character] { Array(pin) }

    private var statusColor: Color {
        if sync.customAlert == "FALL_DETECTED" || sync.customAlert == "MANUAL_SOS" || sync.customAlert == "TACHYCARDIA" || (sync.latestHeartRate ?? 0) >= 140 {
            return Color(red: 0.94, green: 0.27, blue: 0.27) // Red
        } else if sync.customAlert == "BRADYCARDIA" || ((sync.latestHeartRate ?? 100) <= 45 && (sync.latestHeartRate ?? 0) > 0) {
            return Color(red: 0.96, green: 0.62, blue: 0.04) // Amber
        } else if sync.customAlert == "HYPOXIA" || (sync.latestSpo2 ?? 100) <= 90.0 {
            return Color(red: 0.66, green: 0.33, blue: 0.97) // Purple
        } else {
            return Color(red: 0.06, green: 0.73, blue: 0.51) // Green
        }
    }

    private var statusTitle: String {
        if let alert = sync.customAlert {
            switch alert {
            case "TACHYCARDIA": return "🚨 NHỊP NHANH: \(Int(sync.latestHeartRate ?? 155)) BPM"
            case "BRADYCARDIA": return "⚠️ NHỊP CHẬM: \(Int(sync.latestHeartRate ?? 38)) BPM"
            case "HYPOXIA": return "🫁 THIẾU OXY: \(String(format: "%.1f", sync.latestSpo2 ?? 88.0))%"
            case "FALL_DETECTED": return "💥 CẢNH BÁO TÉ NGÃ!"
            case "MANUAL_SOS": return "🆘 ĐÃ BẮN TÍN HIỆU SOS!"
            case "NORMAL": return "🟢 Đang Giám Sát Cổ Tay"
            default: break
            }
        }
        if let hr = sync.latestHeartRate, hr >= 140 {
            return "🚨 NHỊP NHANH: \(Int(hr)) BPM"
        } else if let hr = sync.latestHeartRate, hr <= 45 && hr > 0 {
            return "⚠️ NHỊP CHẬM: \(Int(hr)) BPM"
        } else if let spo2 = sync.latestSpo2, spo2 <= 90.0 {
            return "🫁 THIẾU OXY: \(String(format: "%.1f", spo2))%"
        }
        return "🟢 Đang Giám Sát Cổ Tay"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                // 1. Tiêu đề ứng dụng
                HStack {
                    Text("CareAI Watch")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97)) // #38BDF8
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)

                if !isPaired {
                    // Màn hình ghép nối trực quan với Bàn phím số cảm ứng trực tiếp (Numeric Keypad)
                    VStack(spacing: 5) {
                        Text("Ghép Nối Thiết Bị")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)

                        Text("Nhập mã PIN 6 số tạo từ app người thân")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)

                        // 6 ô hiển thị số PIN
                        HStack(spacing: 4) {
                            ForEach(0..<6, id: \.self) { index in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: 19, height: 23)
                                    if index < pinChars.count {
                                        Text(String(pinChars[index]))
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                    } else {
                                        Circle()
                                            .fill(Color.gray.opacity(0.4))
                                            .frame(width: 4, height: 4)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)

                        // Bàn phím số cảm ứng trực tiếp (Numeric Keypad 3x4)
                        VStack(spacing: 3) {
                            HStack(spacing: 3) {
                                keypadButton("1")
                                keypadButton("2")
                                keypadButton("3")
                            }
                            HStack(spacing: 3) {
                                keypadButton("4")
                                keypadButton("5")
                                keypadButton("6")
                            }
                            HStack(spacing: 3) {
                                keypadButton("7")
                                keypadButton("8")
                                keypadButton("9")
                            }
                            HStack(spacing: 3) {
                                Button(action: clearPin) {
                                    Text("C")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color.orange)
                                        .frame(maxWidth: .infinity, minHeight: 24)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(5)
                                }
                                .buttonStyle(.plain)
                                .disabled(pairing)

                                keypadButton("0")

                                Button(action: deletePinDigit) {
                                    Image(systemName: "delete.left.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color.red.opacity(0.9))
                                        .frame(maxWidth: .infinity, minHeight: 24)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(5)
                                }
                                .buttonStyle(.plain)
                                .disabled(pairing)
                            }
                        }

                        // Nút Ghép Nối
                        Button(action: { Task { await pairWatch() } }) {
                            HStack {
                                if pairing {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("Đang ghép nối…")
                                        .font(.system(size: 10, weight: .bold))
                                } else {
                                    Text("Ghép Nối Đồng Hồ")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(pin.count == 6 && !pairing ? Color.blue : Color.blue.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(pairing || pin.count != 6)

                        if let pairingError {
                            Text(pairingError)
                                .font(.system(size: 8))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                } else {
                    // 2. Badge trạng thái giám sát / cảnh báo
                    Text(statusTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(statusColor.opacity(0.18))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(statusColor.opacity(0.6), lineWidth: 1)
                        )

                    // 3. Card sinh hiệu trực tiếp (Vitals Card)
                    HStack {
                        Text("❤️ \(Int(sync.latestHeartRate ?? 76)) BPM · \(String(format: "%.1f", sync.latestSpo2 ?? 98.0))% SpO2")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.06, green: 0.09, blue: 0.16))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 0.2, green: 0.25, blue: 0.35), lineWidth: 1)
                    )

                    // 4. Nút Cấp Cứu Lớn: Mô Phỏng Té Ngã
                    Button(action: {
                        Task { await sync.triggerEmergencySos(type: "FALL_DETECTED") }
                    }) {
                        HStack {
                            Image(systemName: "figure.fall")
                            Text("💥 Mô Phỏng Té Ngã")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.85, green: 0.15, blue: 0.25))

                    // 5. Nút Cấp Cứu Lớn: SOS Khẩn Cấp
                    Button(action: {
                        Task { await sync.triggerEmergencySos(type: "MANUAL_SOS") }
                    }) {
                        HStack {
                            Image(systemName: "sos.circle.fill")
                            Text("🆘 SOS Khẩn Cấp")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.75, green: 0.10, blue: 0.15))

                    // 6. Tiêu đề mục Thử nghiệm sinh hiệu
                    Text("THỬ NGHIỆM SINH HIỆU")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(Color(red: 0.58, green: 0.64, blue: 0.72))
                        .padding(.top, 2)

                    // 7. Lưới 2x2 nút test lâm sàng
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            Button("🚨 Nhanh 155") { sync.simulateTachycardia() }
                                .font(.system(size: 9, weight: .bold))
                                .buttonStyle(.borderedProminent)
                                .tint(Color(red: 0.85, green: 0.15, blue: 0.25))

                            Button("⚠️ Chậm 38") { sync.simulateBradycardia() }
                                .font(.system(size: 9, weight: .bold))
                                .buttonStyle(.borderedProminent)
                                .tint(Color(red: 0.96, green: 0.62, blue: 0.04))
                        }
                        HStack(spacing: 3) {
                            Button("🫁 Oxy 88%") { sync.simulateHypoxia() }
                                .font(.system(size: 9, weight: .bold))
                                .buttonStyle(.borderedProminent)
                                .tint(Color(red: 0.66, green: 0.33, blue: 0.97))

                            Button("🟢 Chuẩn 75") { sync.simulateNormal() }
                                .font(.system(size: 9, weight: .bold))
                                .buttonStyle(.borderedProminent)
                                .tint(Color(red: 0.06, green: 0.73, blue: 0.51))
                        }
                    }

                    // 8. Kết quả chẩn đoán / Nhật ký truyền
                    Text(sync.diagnosticLog)
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)


                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(sync: sync, backend: $backend, isPaired: isPaired)
        }
        .onAppear {
            if KeychainToken.load() != nil {
                sync.start()
            } else if !backend.isEmpty && pin.count == 6 {
                // Tự động kích hoạt ghép nối khi khởi động nếu đã có sẵn URL và mã PIN hợp lệ
                Task { await pairWatch() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
                if isPaired { sync.start() }
            }
        }
    }

    private func pairWatch() async {
        let trimmedPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPin.count == 6, trimmedPin.allSatisfy(\.isNumber) else {
            pairingError = "Mã PIN phải gồm đúng 6 chữ số"
            return
        }
        let base = backend.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard base.hasPrefix("https://"), let url = URL(string: base + "/api/v1/devices/pair") else {
            pairingError = "Địa chỉ máy chủ HTTPS không hợp lệ"
            return
        }
        pairing = true
        defer { pairing = false }
        do {
            let deviceId = UserDefaults.standard.string(forKey: "deviceId") ?? UUID().uuidString
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(PairRequest(
                deviceId: deviceId, pairingPin: trimmedPin, deviceType: "AppleWatch"))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                pairingError = "Ghép nối thất bại. Kiểm tra PIN và Server."
                return
            }
            let paired = try JSONDecoder().decode(PairResponse.self, from: data)
            guard KeychainToken.save(paired.deviceToken) else {
                pairingError = "Không thể lưu device token vào Keychain"
                return
            }
            UserDefaults.standard.set(base, forKey: "backend")
            UserDefaults.standard.set(paired.deviceId, forKey: "deviceId")
            if let name = paired.fullName, !name.isEmpty {
                UserDefaults.standard.set(name, forKey: "elderName")
            }
            WatchConnectivityCoordinator.shared.sendWatchDeviceInfo()
            WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
            pin = ""
            pairingError = nil
            sync.isPaired = true
            sync.start()
        } catch {
            pairingError = "Lỗi ghép nối: \(error.localizedDescription)"
        }
    }

    private func keypadButton(_ digit: String) -> some View {
        Button(action: { appendPinDigit(digit) }) {
            Text(digit)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(Color.white.opacity(0.12))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .disabled(pairing)
    }

    private func appendPinDigit(_ digit: String) {
        guard pin.count < 6 else { return }
        pin.append(digit)
        pairingError = nil
    }

    private func deletePinDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
        pairingError = nil
    }

    private func clearPin() {
        pin = ""
        pairingError = nil
    }
}

private struct PairRequest: Encodable {
    let deviceId: String
    let pairingPin: String
    let deviceType: String
}

private struct PairResponse: Decodable {
    let deviceId: String
    let deviceToken: String
    let fullName: String?
}

struct SettingsSheetView: View {
    @ObservedObject var sync: HealthSync
    @Binding var backend: String
    let isPaired: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cài Đặt")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 2)

                if !isPaired {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cấu Hình Máy Chủ Nâng Cao")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        TextField("HTTPS backend URL", text: $backend)
                            .textContentType(.URL)
                            .font(.system(size: 9))
                        Button("Lưu cấu hình") {
                            UserDefaults.standard.set(backend, forKey: "backend")
                            dismiss()
                        }
                        .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                } else {
                    Toggle("Tự động phát hiện té ngã", isOn: $sync.autoFallDetectionEnabled)
                        .font(.system(size: 10))
                        .onChange(of: sync.autoFallDetectionEnabled) { _, _ in
                            sync.setupFallDetection()
                        }

                    Toggle("Tiết Kiệm Pin Thích Ứng", isOn: $sync.batterySaverEnabled)
                        .font(.system(size: 10))
                        .onChange(of: sync.batterySaverEnabled) { _, _ in
                            sync.applyBatteryPolicy()
                        }

                    Toggle("Mô phỏng Mất Mạng", isOn: Binding(
                        get: { sync.simulatedOffline },
                        set: { sync.setSimulatedOffline($0) }
                    ))
                    .font(.system(size: 10))

                    Button("Gửi dữ liệu ngay") { Task { await sync.sendNow() } }
                        .font(.system(size: 10))
                        .disabled(sync.simulatedOffline)

                    Text("Đã đệm trên đồng hồ: \(sync.pendingCount)")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)

                    Button("Hủy ghép nối", role: .destructive) {
                        sync.unpair()
                        dismiss()
                    }
                    .font(.system(size: 10))
                }

                Button("Đóng") {
                    dismiss()
                }
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }
}
