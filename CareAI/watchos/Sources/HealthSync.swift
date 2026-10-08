import Foundation
import HealthKit
import Network
import WatchKit
import CoreMotion
import WatchConnectivity

/// Helper điều phối WatchConnectivity chuyển tiếp gói tin cứu nạn sang iPhone Companion (Apple Watch GPS)
private final class WatchConnectivityCoordinator: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityCoordinator()

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func relayEmergencySos(packetId: String, eventId: String, type: String, triggeredAt: String, hr: Double, spo2: Double) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload: [String: Any] = [
            "action": "EMERGENCY_SOS",
            "packetId": packetId,
            "eventId": eventId,
            "emergencyType": type,
            "triggeredAt": triggeredAt,
            "heartRate": hr,
            "spo2": spo2
        ]
        if session.activationState == .activated {
            // Chuyển giao bảo đảm (Guaranteed Transfer) trong nền
            session.transferUserInfo(payload)
            // Nếu iPhone đang ở gần và kết nối trực tiếp, gửi tin tức thì 0ms
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }
        }
    }
}

private struct PendingReading: Codable {
    let sampleId: String
    let metricType: String
    let value: Double
    let unit: String
    let timestamp: String
}

private struct TelemetryBatch: Encodable {
    let batchId: String
    let samples: [PendingReading]
}

private struct HealthSampleDto: Codable {
    let metricType: String
    let value: Double
    let unit: String?
    let timestamp: String
}

private struct SosPacketRequest: Codable {
    let packetId: String
    let eventId: String?
    let emergencyType: String
    let severity: String?
    let triggeredAt: String?
    let gpsLocation: String?
    let samples: [HealthSampleDto]?
    let gpsIsSimulated: Bool?
    let gpsAccuracyMeters: Double?
}

/// Helper điều phối CMFallDetectionDelegate chuẩn Apple Watch
private final class FallDetectionCoordinator: NSObject, CMFallDetectionDelegate {
    private weak var sync: HealthSync?

    init(sync: HealthSync) {
        self.sync = sync
        super.init()
    }

    func fallDetectionManager(
        _ fallDetectionManager: CMFallDetectionManager,
        didDetect event: CMFallDetectionEvent,
        completionHandler handler: @escaping () -> Void
    ) {
        Task { @MainActor [weak self] in
            defer { handler() }
            guard let self, let sync = self.sync else { return }
            if event.resolution == .confirmed || event.resolution == .unresponsive {
                let eventId = "APPLE_FALL_\(Int64(event.date.timeIntervalSince1970 * 1000))"
                await sync.triggerEmergencySos(type: "FALL_DETECTED", eventId: eventId)
            }
        }
    }
}

@MainActor
final class HealthSync: ObservableObject {
    @Published var status = "Set up backend to start"
    @Published var customAlert: String?
    @Published var diagnosticLog = "⚡ Cảm biến sẵn sàng"
    @Published var autoFallDetectionEnabled = true
    @Published private(set) var latestHeartRate: Double?
    @Published private(set) var latestHeartRateAt: Date?
    @Published private(set) var latestSpo2: Double?
    @Published private(set) var latestSpo2At: Date?
    @Published private(set) var pendingCount = 0
    @Published private(set) var healthAlert: String?
    @Published private(set) var simulatedOffline = false
    @Published private(set) var demoHeartRateAlert: String?
    @Published private(set) var demoSpo2Alert: String?
    private let healthStore = HKHealthStore()
    private let pathMonitor = NWPathMonitor()
    private let outboxURL = FileManager.default.urls(for: .applicationSupportDirectory,
        in: .userDomainMask)[0].appendingPathComponent("healthkit-pending-readings.json")
    private var observers: [HKObserverQuery] = []
    private var queue: [PendingReading] = []
    private var outboxReady = false
    private var isSending = false
    private var retryTimer: Timer?
    private let metrics: [(HKQuantityTypeIdentifier, String, HKUnit, String)] = [
        (.heartRate, "HEART_RATE", HKUnit.count().unitDivided(by: .minute()), "bpm"),
        (.oxygenSaturation, "SPO2", HKUnit.percent(), "%")
    ]

    // Cảm biến chuyển động & Phát hiện té ngã
    @Published var batterySaverEnabled = true
    private var fallCoordinator: FallDetectionCoordinator?
    private var fallDetectionManager: CMFallDetectionManager?
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "vn.careai.watch.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()
    private var lastMotionFallDetectedAt: Date?
    private var isFreeFallDetected = false
    private var freeFallStartTime: Date?
    private var isBurstSampling = false
    private var burstResetWorkItem: DispatchWorkItem?
    private var activeEmergencySession: WKExtendedRuntimeSession?

    init() {
        latestHeartRate = UserDefaults.standard.object(forKey: "latest.heartRate") as? Double
        latestHeartRateAt = UserDefaults.standard.object(forKey: "latest.heartRateAt") as? Date
        latestSpo2 = UserDefaults.standard.object(forKey: "latest.spo2") as? Double
        latestSpo2At = UserDefaults.standard.object(forKey: "latest.spo2At") as? Date
        updateHealthAlert()
        loadOutbox()
        setupFallDetection()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.flush(force: false) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "careai.watch.network"))
        // Tối ưu pin: Chu kỳ quét nền gom lô giãn ra 300 giây (5 phút) thay vì 60 giây
        retryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHealthAlert()
                self?.flush(force: true)
            }
        }
        if UserDefaults.standard.string(forKey: "backend") != nil,
           KeychainToken.load() != nil {
            Task { @MainActor in self.start() }
        }
    }

    func start() {
        if !outboxReady { loadOutbox() }
        if autoFallDetectionEnabled { setupFallDetection() }
        guard HKHealthStore.isHealthDataAvailable() else { status = "HealthKit unavailable"; return }
        guard let url = URL(string: UserDefaults.standard.string(forKey: "backend") ?? ""),
              url.scheme == "https", url.host?.isEmpty == false,
              !(UserDefaults.standard.string(forKey: "deviceId") ?? "").isEmpty,
              KeychainToken.load()?.isEmpty == false else {
            status = "Enter HTTPS URL, device ID and device token"
            return
        }
        scheduleBackgroundRefresh()
        let types = Set(metrics.map { HKObjectType.quantityType(forIdentifier: $0.0)! })
        healthStore.requestAuthorization(toShare: [], read: types) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.status = "HealthKit: \(error.localizedDescription)"; return }
                self.registerObservers()
                self.flush(force: false)
            }
        }
    }

    private func scheduleBackgroundRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(15 * 60),
            userInfo: "careai.healthsync" as NSSecureCoding & NSObjectProtocol
        ) { _ in }
    }

    func refreshInBackground() async {
        scheduleBackgroundRefresh()
        if !outboxReady { loadOutbox() }
        guard outboxReady, KeychainToken.load() != nil else { return }
        for (identifier, _, _, _) in metrics {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                fetchNew(identifier, completion: { continuation.resume() }, sendAfter: false)
            }
        }
        await sendPending(maximum: 20)
    }

    func setSimulatedOffline(_ enabled: Bool) {
        simulatedOffline = enabled
        status = enabled ? "DEMO offline · readings stay on watch" : "DEMO network restored"
        if !enabled { flush(force: true) }
    }

    // 1. Nút test Nhịp nhanh 155 BPM trực tiếp trên mặt đồng hồ
    func simulateTachycardia() {
        latestHeartRate = 155.0
        latestHeartRateAt = Date()
        customAlert = "TACHYCARDIA"
        status = "🚨 NHỊP NHANH: 155 BPM"
        diagnosticLog = "⚡ Nút bấm: Phát hiện nhịp nhanh 155 BPM!"
        enqueueDemo(metricType: "DEMO_HEART_RATE", value: 155.0, unit: "bpm")
        updateHealthAlert()
    }

    // 2. Nút test Nhịp chậm 38 BPM trực tiếp trên mặt đồng hồ
    func simulateBradycardia() {
        latestHeartRate = 38.0
        latestHeartRateAt = Date()
        customAlert = "BRADYCARDIA"
        status = "⚠️ NHỊP CHẬM: 38 BPM"
        diagnosticLog = "⚡ Nút bấm: Phát hiện nhịp chậm 38 BPM!"
        enqueueDemo(metricType: "DEMO_HEART_RATE", value: 38.0, unit: "bpm")
        updateHealthAlert()
    }

    // 3. Nút test Thiếu oxy SpO2 88% trực tiếp trên mặt đồng hồ
    func simulateHypoxia() {
        latestSpo2 = 88.0
        latestSpo2At = Date()
        customAlert = "HYPOXIA"
        status = "🫁 THIẾU OXY: 88.0%"
        diagnosticLog = "⚡ Nút bấm: Nồng độ SpO2 giảm sâu 88%!"
        enqueueDemo(metricType: "DEMO_SPO2", value: 88.0, unit: "%")
        updateHealthAlert()
    }

    // 4. Nút test Khôi phục bình thường 75 BPM trực tiếp trên mặt đồng hồ
    func simulateNormal() {
        latestHeartRate = 75.0
        latestHeartRateAt = Date()
        latestSpo2 = 98.5
        latestSpo2At = Date()
        customAlert = "NORMAL"
        status = "🟢 Đang Giám Sát Cổ Tay"
        diagnosticLog = "⚡ Nút bấm [75 BPM, 98.5%]"
        enqueueDemo(metricType: "DEMO_HEART_RATE", value: 75.0, unit: "bpm")
        enqueueDemo(metricType: "DEMO_SPO2", value: 98.5, unit: "%")
        updateHealthAlert()
    }

    func simulateHighHeartRate() {
        simulateTachycardia()
    }

    func simulateLowSpo2() {
        simulateHypoxia()
    }

    /// Kích hoạt gửi cảnh báo Cấp Cứu Fast-Lane SOS hoặc Phát hiện Té Ngã (Tuân thủ Bất biến Fact 35)
    @discardableResult
    func triggerEmergencySos(type: String, eventId: String? = nil) async -> (success: Bool, message: String) {
        let baseEventId = eventId ?? "\(type)_\(Int64(Date().timeIntervalSince1970 * 1000))"
        let canonicalPacketId = type == "FALL_DETECTED" ? "FALL_\(baseEventId)" : "SOS_\(baseEventId)"

        if type == "FALL_DETECTED" {
            customAlert = "FALL_DETECTED"
            status = "💥 CẢNH BÁO TÉ NGÃ!"
            diagnosticLog = "Đang gửi cảnh báo té ngã khẩn cấp..."
        } else {
            customAlert = "MANUAL_SOS"
            status = "🆘 ĐÃ BẮN TÍN HIỆU SOS!"
            diagnosticLog = "Đang gửi SOS khẩn cấp..."
        }

        let hr = latestHeartRate ?? 76.0
        let spo2 = latestSpo2 ?? 98.0
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timeStr = formatter.string(from: now)

        // BẤT BIẾN FACT 35: Gói tin Fast-Lane SOS bắt buộc nạp và lưu trữ toàn bộ các mẫu đo sinh hiệu đi kèm
        let samples: [HealthSampleDto] = [
            HealthSampleDto(metricType: "HEART_RATE", value: hr, unit: "bpm", timestamp: timeStr),
            HealthSampleDto(metricType: "SPO2", value: spo2, unit: "%", timestamp: timeStr)
        ]

        let packet = SosPacketRequest(
            packetId: canonicalPacketId,
            eventId: baseEventId,
            emergencyType: type,
            severity: "CRITICAL",
            triggeredAt: timeStr,
            gpsLocation: nil,
            samples: samples,
            gpsIsSimulated: false,
            gpsAccuracyMeters: nil
        )

        // CHUYỂN GIAO SONG SONG QUA WATCHCONNECTIVITY (Cho Apple Watch GPS mượn sóng 4G/LTE của iPhone)
        WatchConnectivityCoordinator.shared.relayEmergencySos(
            packetId: canonicalPacketId,
            eventId: baseEventId,
            type: type,
            triggeredAt: timeStr,
            hr: hr,
            spo2: spo2
        )

        guard !simulatedOffline,
              let base = UserDefaults.standard.string(forKey: "backend"),
              let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/incidents/sos"),
              let deviceId = UserDefaults.standard.string(forKey: "deviceId"),
              let token = KeychainToken.load() else {
            enqueueDemo(metricType: type == "FALL_DETECTED" ? "FALL" : "SOS", value: 1.0, unit: "event")
            let offlineMsg = "⚠️ Ngoại tuyến: Đã lưu SOS vào bộ đệm đồng hồ"
            diagnosticLog = offlineMsg
            return (false, offlineMsg)
        }

        activateEmergencySession()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(deviceId, forHTTPHeaderField: "X-DeviceId")
        request.setValue(token, forHTTPHeaderField: "X-Device-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Sử dụng URLSession cấu hình đợi kết nối (resilient) chống rớt gói khi chuyển Wi-Fi/LTE
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)

        do {
            request.httpBody = try JSONEncoder().encode(packet)
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode
            if code == 200 || code == 201 {
                let successMsg = "✅ Đã gửi \(type == "FALL_DETECTED" ? "cảnh báo ngã" : "SOS") thành công!"
                diagnosticLog = successMsg
                deactivateEmergencySession()
                return (true, successMsg)
            } else {
                let failMsg = "⚠️ Máy chủ phản hồi mã \(code ?? 0). Đã lưu đệm."
                diagnosticLog = failMsg
                enqueueDemo(metricType: type == "FALL_DETECTED" ? "FALL" : "SOS", value: 1.0, unit: "event")
                deactivateEmergencySession()
                return (false, failMsg)
            }
        } catch {
            let errorMsg = "⚠️ Lỗi mạng: \(error.localizedDescription). Đã lưu đệm."
            diagnosticLog = errorMsg
            enqueueDemo(metricType: type == "FALL_DETECTED" ? "FALL" : "SOS", value: 1.0, unit: "event")
            deactivateEmergencySession()
            return (false, errorMsg)
        }
    }

    /// Kích hoạt phiên thực thi mở rộng giữ đồng hồ thức ngầm khi có cấp cứu
    private func activateEmergencySession() {
        guard activeEmergencySession == nil || activeEmergencySession?.state == .invalid else { return }
        let session = WKExtendedRuntimeSession()
        session.start()
        activeEmergencySession = session
    }

    private func deactivateEmergencySession() {
        activeEmergencySession?.invalidate()
        activeEmergencySession = nil
    }

    private var baselineInterval: TimeInterval {
        batterySaverEnabled ? 0.1 : 0.05 // 10Hz khi bật Tiết kiệm pin, 20Hz khi bình thường
    }

    func applyBatteryPolicy() {
        if autoFallDetectionEnabled {
            setupFallDetection()
        }
        diagnosticLog = batterySaverEnabled ? "🔋 Đã bật Tiết Kiệm Pin Thích Ứng (10Hz)" : "⚡ Đã bật Giám Sát Hiệu Năng Cao (20Hz)"
    }

    /// Thiết lập hệ thống phát hiện té ngã 2 tầng kiên cường (Two-Tier Resilient Fall Detection):
    ///
    /// -----------------------------------------------------------------------------------------
    /// 🏥 TẦNG 1: CHIP APPLE MOTION COPROCESSOR (CMFallDetectionManager)
    /// - Khi app có giấy phép Entitlement chính thức từ Apple (`com.apple.developer.coremotion.fall-detection`),
    ///   hệ thống ủy thác toàn bộ cho chip đồng xử lý chuyển động phần cứng của Apple để tiết kiệm >90% pin.
    ///
    /// 🛡️ TẦNG 2: BẢO VỆ DỰ PHÒNG TỰ CHỦ QUA COREMOTION (CMMotionManager)
    /// - Tự động kích hoạt khi chạy trên Simulator, tài khoản Apple cá nhân (Personal Team), hoặc khi
    ///   thiết bị không có Apple Entitlement. Đo gia tốc rơi tự do (<0.35g) và va chạm (>2.8g).
    ///
    /// ⚠️ [GIẢI PHÁP CẦU NỐI BẮT NGOẠI LỆ OBJECTIVE-C]:
    /// Khi gọi CMFallDetectionManager.isAvailable mà app thiếu Entitlement, runtime của Apple sẽ ném một
    /// ngoại lệ cấp thấp NSInternalInconsistencyException làm crash app lập tức (Swift do-catch KHÔNG bắt được).
    /// Ta sử dụng hàm cầu nối `catchException` (Objective-C @try-@catch trong NSExceptionCatcher.h)
    /// để bắt trọn ngoại lệ của Apple một cách êm đẹp, tự động chuyển giao xuống Tầng 2 mà không hề sập app!
    /// -----------------------------------------------------------------------------------------
    func setupFallDetection() {
        guard autoFallDetectionEnabled else {
            motionManager.stopAccelerometerUpdates()
            diagnosticLog = "⚡ Đã tắt tự động phát hiện té ngã"
            return
        }

        var isAppleFallSupported = false
        // Bọc trong cầu nối catchException để triệt tiêu hoàn toàn nguy cơ NSInternalInconsistencyException crash
        let safeExecution = catchException {
            isAppleFallSupported = CMFallDetectionManager.isAvailable
        }

        if safeExecution && isAppleFallSupported {
            // TẦNG 1: Đủ quyền Entitlement của Apple -> Sử dụng chip phần cứng Apple Coprocessor (Tiết kiệm pin tối đa)
            let manager = CMFallDetectionManager()
            let coordinator = FallDetectionCoordinator(sync: self)
            manager.delegate = coordinator
            self.fallDetectionManager = manager
            self.fallCoordinator = coordinator
            // Tắt cập nhật gia tốc phần mềm để nhường toàn bộ cho chip phần cứng
            motionManager.stopAccelerometerUpdates()
            diagnosticLog = "⚡ Apple Fall Detection sẵn sàng (Tiết kiệm pin phần cứng)"
        } else {
            // TẦNG 2: Bắt được ngoại lệ thiếu Entitlement hoặc máy không hỗ trợ -> Tự động chuyển đổi sang CMMotionManager
            startMotionFallDetectionFallback()
            diagnosticLog = batterySaverEnabled ? "🔋 Cảm biến CoreMotion Fallback (Tiết kiệm pin 10Hz)" : "⚡ Cảm biến CoreMotion Fallback (20Hz)"
        }
    }

    private func startMotionFallDetectionFallback() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = baselineInterval
        // Sử dụng OperationQueue nền chuyên dụng để không chiếm luồng UI chính, cho phép CPU ngủ giữa các lần lấy mẫu
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self, let data, self.autoFallDetectionEnabled else { return }
            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            let g = sqrt(x * x + y * y + z * z)
            Task { @MainActor [weak self] in
                self?.processMotionAcceleration(g)
            }
        }
    }

    private func triggerBurstSampling() {
        guard !isBurstSampling else { return }
        isBurstSampling = true
        motionManager.accelerometerUpdateInterval = 0.025 // 40Hz Burst trong 1.5 giây để bắt va chạm sắc nét
        burstResetWorkItem?.cancel()
        let resetItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBurstSampling = false
                self.motionManager.accelerometerUpdateInterval = self.baselineInterval
            }
        }
        burstResetWorkItem = resetItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetItem)
    }

    private func processMotionAcceleration(_ g: Double) {
        let now = Date()
        // Chống spam: Mỗi sự cố ngã cách nhau tối thiểu 15 giây
        if let last = lastMotionFallDetectedAt, now.timeIntervalSince(last) < 15.0 {
            return
        }

        // Tối ưu pin thích ứng: Khi phát hiện dấu hiệu gia tốc bất thường, tự động tăng tần số lên 40Hz
        if (g < 0.4 || g > 1.8) && !isBurstSampling {
            triggerBurstSampling()
        }

        // Giai đoạn 1: Rơi tự do (Trọng lực giảm mạnh < 0.35g)
        if g < 0.35 && !isFreeFallDetected {
            isFreeFallDetected = true
            freeFallStartTime = now
            return
        }

        // Giai đoạn 2: Va chạm mạnh (Gia tốc vượt ngưỡng > 2.8g) trong vòng 800ms sau khi rơi tự do
        if isFreeFallDetected, let start = freeFallStartTime {
            let elapsed = now.timeIntervalSince(start)
            if elapsed <= 0.8 {
                if g > 2.8 {
                    isFreeFallDetected = false
                    freeFallStartTime = nil
                    lastMotionFallDetectedAt = now
                    let eventId = "MOTION_FALL_\(Int64(now.timeIntervalSince1970 * 1000))"
                    Task {
                        await self.triggerEmergencySos(type: "FALL_DETECTED", eventId: eventId)
                    }
                }
            } else {
                isFreeFallDetected = false
                freeFallStartTime = nil
            }
        }
    }

    func sendNow() async {
        if simulatedOffline {
            status = "DEMO offline · turn it off to send"
            return
        }
        if !outboxReady { loadOutbox() }
        guard outboxReady else { return }
        for (identifier, _, _, _) in metrics {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                fetchNew(identifier, completion: { continuation.resume() }, sendAfter: false)
            }
        }
        if queue.isEmpty {
            status = "No readings waiting to send"
            return
        }
        await sendPending(maximum: .max)
    }

    private func enqueueDemo(metricType: String, value: Double, unit: String) {
        if !outboxReady { loadOutbox() }
        guard outboxReady else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let reading = PendingReading(sampleId: UUID().uuidString, metricType: metricType,
                                     value: value, unit: unit, timestamp: formatter.string(from: Date()))
        let updatedQueue = queue + [reading]
        do {
            try persistQueue(updatedQueue)
            queue = updatedQueue
            pendingCount = updatedQueue.count
            if metricType == "DEMO_HEART_RATE" {
                demoHeartRateAlert = "DEMO alert: high heart rate · 145 bpm"
            } else {
                demoSpo2Alert = "DEMO alert: low SpO₂ · 90%"
            }
            status = simulatedOffline ? "DEMO offline · saved on watch" : "DEMO sample queued"
            if !simulatedOffline { flush(force: true) }
        } catch {
            status = "Cannot save demo reading on watch"
        }
    }

    private func updateHealthAlert() {
        let now = Date()
        if let alert = customAlert {
            switch alert {
            case "TACHYCARDIA":
                healthAlert = "🚨 NHỊP NHANH: \(Int(latestHeartRate ?? 155)) BPM"
                return
            case "BRADYCARDIA":
                healthAlert = "⚠️ NHỊP CHẬM: \(Int(latestHeartRate ?? 38)) BPM"
                return
            case "HYPOXIA":
                healthAlert = "🫁 THIẾU OXY: \(String(format: "%.1f", latestSpo2 ?? 88.0))%"
                return
            case "NORMAL":
                healthAlert = nil
                return
            case "FALL_DETECTED":
                healthAlert = "💥 CẢNH BÁO TÉ NGÃ!"
                return
            case "MANUAL_SOS":
                healthAlert = "🆘 ĐÃ BẮN TÍN HIỆU SOS!"
                return
            default:
                break
            }
        }

        if let at = latestSpo2At, now.timeIntervalSince(at) < 10 * 60,
           let value = latestSpo2, value <= 92 {
            healthAlert = String(format: "🫁 THIẾU OXY: %.0f%%", value)
        } else if let at = latestHeartRateAt, now.timeIntervalSince(at) < 10 * 60,
                  let value = latestHeartRate, value > 120 {
            healthAlert = String(format: "🚨 NHỊP NHANH: %.0f BPM", value)
        } else if let at = latestHeartRateAt, now.timeIntervalSince(at) < 10 * 60,
                  let value = latestHeartRate, value < 50 {
            healthAlert = String(format: "⚠️ NHỊP CHẬM: %.0f BPM", value)
        } else {
            healthAlert = nil
        }
    }

    private func registerObservers() {
        if !observers.isEmpty {
            for (identifier, _, _, _) in metrics {
                fetchNew(identifier, completion: {})
            }
            return
        }
        for (identifier, _, _, _) in metrics {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let observer = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in
                    guard let self else { completion(); return }
                    self.fetchNew(identifier, completion: completion)
                }
            }
            observers.append(observer)
            healthStore.execute(observer)
            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
            fetchNew(identifier, completion: {})
        }
        status = "Watching HealthKit · queued \(queue.count)"
    }

    private func fetchNew(_ identifier: HKQuantityTypeIdentifier, completion: @escaping () -> Void,
                          sendAfter: Bool = true) {
        if !outboxReady { loadOutbox() }
        guard outboxReady else { completion(); return }
        guard let metric = metrics.first(where: { $0.0 == identifier }),
              let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion(); return
        }
        let key = "anchor.\(identifier.rawValue)"
        let startKey = "start.\(identifier.rawValue)"
        let start = (UserDefaults.standard.object(forKey: startKey) as? Date)
            ?? Date().addingTimeInterval(-24 * 60 * 60)
        UserDefaults.standard.set(start, forKey: startKey)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil,
                                                     options: .strictStartDate)
        var anchor: HKQueryAnchor?
        if let data = UserDefaults.standard.data(forKey: key) {
            anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
        let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor,
                                           limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, nextAnchor, error in
            Task { @MainActor in
                defer { completion() }
                guard let self else { return }
                if let error { self.status = "HealthKit: \(error.localizedDescription)"; return }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                var updatedQueue = self.queue
                var queuedIds = Set(updatedQueue.map(\.sampleId))
                for sample in samples ?? [] {
                    guard let quantity = sample as? HKQuantitySample else { continue }
                    let raw = quantity.quantity.doubleValue(for: metric.2)
                    let value = identifier == .oxygenSaturation ? raw * 100 : raw
                    if identifier == .heartRate,
                       sample.endDate > (self.latestHeartRateAt ?? .distantPast) {
                        self.latestHeartRate = value
                        self.latestHeartRateAt = sample.endDate
                        UserDefaults.standard.set(value, forKey: "latest.heartRate")
                        UserDefaults.standard.set(sample.endDate, forKey: "latest.heartRateAt")
                    } else if identifier == .oxygenSaturation,
                              sample.endDate > (self.latestSpo2At ?? .distantPast) {
                        self.latestSpo2 = value
                        self.latestSpo2At = sample.endDate
                        UserDefaults.standard.set(value, forKey: "latest.spo2")
                        UserDefaults.standard.set(sample.endDate, forKey: "latest.spo2At")
                    }
                    let reading = PendingReading(sampleId: sample.uuid.uuidString,
                        metricType: metric.1, value: value, unit: metric.3,
                        timestamp: formatter.string(from: sample.endDate))
                    if queuedIds.insert(reading.sampleId).inserted {
                        updatedQueue.append(reading)
                    }
                }
                if updatedQueue.count != self.queue.count {
                    do {
                        try self.persistQueue(updatedQueue)
                        self.queue = updatedQueue
                        self.pendingCount = updatedQueue.count
                    } catch {
                        self.status = "Cannot save readings on watch; will retry HealthKit query"
                        return
                    }
                }
                self.updateHealthAlert()
                // Advance the HealthKit anchor only after all new readings are on disk.
                if let nextAnchor,
                   let data = try? NSKeyedArchiver.archivedData(withRootObject: nextAnchor,
                                                                  requiringSecureCoding: true) {
                    UserDefaults.standard.set(data, forKey: key)
                }
                self.status = "Watching HealthKit · queued \(self.queue.count)"
                if sendAfter { self.flush(force: false) }
            }
        }
        healthStore.execute(query)
    }

    private func loadOutbox() {
        do {
            if FileManager.default.fileExists(atPath: outboxURL.path) {
                queue = try JSONDecoder().decode([PendingReading].self,
                    from: Data(contentsOf: outboxURL))
            } else if let legacy = UserDefaults.standard.data(forKey: "pendingReadings") {
                let restored = try JSONDecoder().decode([PendingReading].self, from: legacy)
                try persistQueue(restored)
                queue = restored
                UserDefaults.standard.removeObject(forKey: "pendingReadings")
            }
            pendingCount = queue.count
            outboxReady = true
        } catch {
            outboxReady = false
            status = "Cannot open saved readings; HealthKit cursor unchanged"
        }
    }

    private func persistQueue(_ readings: [PendingReading]) throws {
        try FileManager.default.createDirectory(at: outboxURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(readings)
        try data.write(to: outboxURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func flush(force: Bool = true) {
        // Tối ưu năng lượng vô tuyến (Radio Coalescing):
        // Nếu không ép buộc và không có cảnh báo y tế khẩn cấp, chỉ đánh thức modem mạng khi gom đủ ít nhất 10 mẫu
        if !force && healthAlert == nil && customAlert == nil && queue.count < 10 {
            return
        }
        Task { await sendPending(maximum: .max) }
    }

    private func sendPending(maximum: Int) async {
        guard !simulatedOffline else { return }
        guard outboxReady, !isSending,
              let base = UserDefaults.standard.string(forKey: "backend"),
              let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/telemetry/ingest"),
              url.scheme == "https",
              let deviceId = UserDefaults.standard.string(forKey: "deviceId"),
              let token = KeychainToken.load() else { return }
        isSending = true
        defer { isSending = false }
        var sent = 0
        let batchLimit = 50
        while sent < maximum && !queue.isEmpty {
            if simulatedOffline {
                status = "DEMO offline · readings stay on watch"
                return
            }
            let chunk = Array(queue.prefix(min(batchLimit, maximum - sent)))
            guard !chunk.isEmpty else { break }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue(deviceId, forHTTPHeaderField: "X-DeviceId")
            request.setValue(token, forHTTPHeaderField: "X-Device-Token")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                let batchId = "HK_BATCH_\(Int64(Date().timeIntervalSince1970 * 1000))_\(chunk.count)"
                request.httpBody = try JSONEncoder().encode(TelemetryBatch(
                    batchId: batchId, samples: chunk))
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode
                // Chấp nhận 200 OK, 201 Created (đồng bộ) hoặc 202 Accepted (kênh phi khóa Non-Blocking Channel)
                guard code == 200 || code == 201 || code == 202 else {
                    status = "Waiting to send · HTTP \(code.map(String.init) ?? "offline")"
                    return
                }
                // Giữ bản gốc trên đĩa cho đến khi máy chủ xác nhận cam kết thành công
                let remaining = Array(queue.dropFirst(chunk.count))
                try persistQueue(remaining)
                queue = remaining
                pendingCount = remaining.count
                sent += chunk.count
                status = "Sent \(chunk.count) samples · queued \(queue.count)"
            } catch {
                // Thất bại giữ nguyên outbox để thử lại sau
                status = "Offline or save failed · queued \(queue.count)"
                return
            }
        }
    }
}
