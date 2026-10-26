import Foundation
import HealthKit
import Network
import WatchKit
import CoreMotion
import WatchConnectivity

/// Helper điều phối WatchConnectivity chuyển tiếp gói tin cứu nạn sang iPhone Companion (Apple Watch GPS)
final class WatchConnectivityCoordinator: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityCoordinator()
    private var pendingSosPayload: [String: Any]?
    private var pendingTelemetryPayload: [String: Any]?
    private var periodicHeartbeatTimer: Timer?

    override init() {
        super.init()
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        startPeriodicSyncTimer()
        activate()
    }

    func startPeriodicSyncTimer() {
        periodicHeartbeatTimer?.invalidate()
        // Định kỳ 90 giây kiểm tra và phát viễn trắc pin/sạc/đeo sang iPhone ngay cả khi chạy nền
        periodicHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncCurrentBatteryAndWearState()
            }
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
        }
        if session.activationState == .notActivated {
            session.activate()
        } else if session.activationState == .activated {
            let reachable = session.isReachable
            DispatchQueue.main.async {
                HealthSync.shared?.isPhoneReachable = reachable
                if (HealthSync.shared?.pendingCount ?? 0) > 0 {
                    HealthSync.shared?.flush(force: true)
                }
            }
            if !session.receivedApplicationContext.isEmpty {
                handleIncomingCredentials(session.receivedApplicationContext)
            }
            sendWatchDeviceInfo()
            syncCurrentBatteryAndWearState()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            let reachable = session.isReachable
            DispatchQueue.main.async {
                HealthSync.shared?.isPhoneReachable = reachable
                if (HealthSync.shared?.pendingCount ?? 0) > 0 {
                    HealthSync.shared?.flush(force: true)
                }
            }
            if !session.receivedApplicationContext.isEmpty {
                handleIncomingCredentials(session.receivedApplicationContext)
            }
            sendWatchDeviceInfo()
            syncCurrentBatteryAndWearState()
            if let pending = self.pendingTelemetryPayload {
                self.pendingTelemetryPayload = nil
                Task { @MainActor [weak self] in
                    self?.relayWatchTelemetry(
                        isWorn: pending["isWorn"] as? Bool ?? false,
                        isCharging: pending["isCharging"] as? Bool ?? false,
                        batteryLevel: pending["batteryLevel"] as? Int ?? 100
                    )
                }
            }
            if let pending = self.pendingSosPayload {
                session.transferUserInfo(pending)
                if session.isReachable {
                    session.sendMessage(pending, replyHandler: nil, errorHandler: nil)
                }
                self.pendingSosPayload = nil
                NSLog("[CareAI-Watch] Đã gửi gói SOS cứu nạn tồn đọng sau khi WCSession kích hoạt.")
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            HealthSync.shared?.isPhoneReachable = reachable
            NSLog("[CareAI-Watch] WCSession reachability thay đổi: %d", reachable ? 1 : 0)
            if reachable && (HealthSync.shared?.pendingCount ?? 0) > 0 {
                HealthSync.shared?.flush(force: true)
            }
        }
    }

    func sendWatchDeviceInfo() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let device = WKInterfaceDevice.current()
        let deviceName = device.name
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let machineCode = String(cString: machine)
        let resolvedModel = HealthSync.resolveWatchModelName(machineCode: machineCode, fallbackName: deviceName)

        let isWatchPaired = KeychainToken.load() != nil
        var payload: [String: Any] = [
            "action": "WATCH_DEVICE_INFO",
            "watchName": resolvedModel,
            "rawName": deviceName,
            "machineCode": machineCode,
            "systemVersion": device.systemVersion,
            "isPaired": isWatchPaired
        ]
        if UserDefaults.standard.string(forKey: "deviceId") == nil || KeychainToken.load() == nil {
            payload["needsCredentials"] = true
        }

        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        NSLog("[CareAI-Watch] Đã gửi thông tin phần cứng đồng hồ sang iPhone: %@", resolvedModel)
    }

    func notifyWatchUnpaired() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload: [String: Any] = [
            "action": "WATCH_UNPAIRED",
            "syncType": "UNPAIR"
        ]
        try? session.updateApplicationContext(payload)
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        NSLog("[CareAI-Watch] Đã gửi thông báo WATCH_UNPAIRED sang iPhone Companion.")
    }

    func relayEmergencySos(packetId: String, eventId: String, type: String, triggeredAt: String, hr: Double?, spo2: Double?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        var payload: [String: Any] = [
            "action": "EMERGENCY_SOS",
            "packetId": packetId,
            "eventId": eventId,
            "emergencyType": type,
            "triggeredAt": triggeredAt
        ]
        if let hr = hr, hr > 0 {
            payload["heartRate"] = hr
        }
        if let spo2 = spo2, spo2 > 0 {
            payload["spo2"] = spo2
        }
        if session.activationState == .activated {
            // Chuyển giao bảo đảm (Guaranteed Transfer) trong nền
            session.transferUserInfo(payload)
            // Nếu iPhone đang ở gần và kết nối trực tiếp, gửi tin tức thì 0ms
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }
        } else {
            // Lưu lại để gửi ngay khi kích hoạt xong
            self.pendingSosPayload = payload
            activate()
        }
    }

    @MainActor
    func buildWatchTelemetryPayload(isWorn: Bool, isCharging: Bool, batteryLevel: Int) -> [String: Any] {
        let device = WKInterfaceDevice.current()
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let machineCode = String(cString: machine)
        let resolvedModel = HealthSync.resolveWatchModelName(machineCode: machineCode, fallbackName: device.name)

        var payload: [String: Any] = [
            "action": "WATCH_TELEMETRY",
            "isWorn": isWorn,
            "isCharging": isCharging,
            "batteryLevel": batteryLevel,
            "watchModel": resolvedModel,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let steps = HealthSync.shared?.todaySteps, steps > 0 {
            payload["todaySteps"] = steps
        }
        if let hr = HealthSync.shared?.latestHeartRate, hr > 0 {
            payload["heartRate"] = hr
        }
        if let spo2 = HealthSync.shared?.latestSpo2, spo2 > 0 {
            payload["spo2"] = spo2
        }
        if let sys = HealthSync.shared?.latestBpSystolic, sys > 0 {
            payload["bpSystolic"] = sys
            if let dia = HealthSync.shared?.latestBpDiastolic, dia > 0 {
                payload["bpDiastolic"] = dia
            }
        }
        if let sleep = HealthSync.shared?.lastNightSleepMinutes, sleep > 0 {
            payload["sleepMinutes"] = sleep
        }
        if let deep = HealthSync.shared?.deepSleepMinutes, deep > 0 {
            payload["deepSleepMinutes"] = deep
        }
        if let core = HealthSync.shared?.coreSleepMinutes, core > 0 {
            payload["coreSleepMinutes"] = core
        }
        if let rem = HealthSync.shared?.remSleepMinutes, rem > 0 {
            payload["remSleepMinutes"] = rem
        }
        if let awake = HealthSync.shared?.awakeMinutes, awake > 0 {
            payload["awakeMinutes"] = awake
        }
        if let wake = HealthSync.shared?.wakeCount, wake > 0 {
            payload["wakeCount"] = wake
        }
        if let minHr = HealthSync.shared?.minSleepingHr, minHr > 0 {
            payload["minSleepingHr"] = minHr
        }
        if let avgHr = HealthSync.shared?.avgSleepingHr, avgHr > 0 {
            payload["avgSleepingHr"] = avgHr
        }
        if let minSpo2 = HealthSync.shared?.minNightSpo2, minSpo2 > 0 {
            payload["minNightSpo2"] = minSpo2
        }
        if let dips = HealthSync.shared?.nightSpo2DipsCount, dips > 0 {
            payload["nightSpo2DipsCount"] = dips
        }
        if let apnea = HealthSync.shared?.breathingDisturbances, !apnea.isEmpty {
            payload["breathingDisturbances"] = apnea
        }
        var supported: [String] = ["HEART_RATE", "STEPS"]
        if HealthSync.shared?.hasSpo2Hardware == true || (HealthSync.shared?.latestSpo2 ?? 0) > 0 {
            supported.append("SPO2")
        }
        if HealthSync.shared?.latestBpSystolic != nil {
            supported.append("BLOOD_PRESSURE")
        }
        if HealthSync.shared?.lastNightSleepMinutes != nil {
            supported.append("SLEEP")
        }
        if HealthSync.shared?.deepSleepMinutes != nil || HealthSync.shared?.coreSleepMinutes != nil {
            supported.append("SLEEP_STAGES")
        }
        if HealthSync.shared?.breathingDisturbances != nil || (HealthSync.shared?.nightSpo2DipsCount ?? 0) > 0 {
            supported.append("SLEEP_APNEA")
        }
        payload["supportedMetrics"] = supported
        return payload
    }

    @MainActor
    func relayWatchTelemetry(isWorn: Bool, isCharging: Bool, batteryLevel: Int) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload = buildWatchTelemetryPayload(isWorn: isWorn, isCharging: isCharging, batteryLevel: batteryLevel)

        if session.activationState == .activated {
            do {
                try session.updateApplicationContext(payload)
            } catch {
                NSLog("[CareAI-Watch] updateApplicationContext error: %@", error.localizedDescription)
            }
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: { error in
                    NSLog("[CareAI-Watch] relayWatchTelemetry sendMessage error: %@", error.localizedDescription)
                })
            }
        } else {
            self.pendingTelemetryPayload = payload
            activate()
        }
    }

    func syncCurrentBatteryAndWearState() {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let rawLevel = device.batteryLevel
        let batteryLevel = rawLevel >= 0 ? Int(round(rawLevel * 100)) : 100
        let isCharging = (device.batteryState == .charging || device.batteryState == .full)
        DispatchQueue.main.async {
            let currentWorn = HealthSync.shared?.isWorn ?? false
            // Đã rút sạc chưa chắc gì đã đeo (unplugged != worn).
            // Nếu đang cắm sạc thì chắc chắn không đeo (isWorn = false).
            // Nếu rút sạc và có nhịp tim gần đây (<30 phút) hoặc đang tương tác: coi là đang đeo.
            let hrRecent = (HealthSync.shared?.latestHeartRateAt != nil) &&
                           (Date().timeIntervalSince(HealthSync.shared!.latestHeartRateAt!) < 30 * 60)
            let isWorn: Bool
            if isCharging {
                isWorn = false
            } else if hrRecent || currentWorn {
                isWorn = true
            } else {
                isWorn = UserDefaults.standard.bool(forKey: "careai.isWorn")
            }
            HealthSync.shared?.isCharging = isCharging
            HealthSync.shared?.isWorn = isWorn
            UserDefaults.standard.set(isWorn, forKey: "careai.isWorn")
            self.relayWatchTelemetry(isWorn: isWorn, isCharging: isCharging, batteryLevel: batteryLevel)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let action = applicationContext["action"] as? String {
            if action == "FORCE_REFRESH" {
                NSLog("[CareAI-Watch] Nhận lệnh FORCE_REFRESH qua applicationContext. Ép làm tươi và gửi viễn trắc ngay.")
                sendWatchDeviceInfo()
                syncCurrentBatteryAndWearState()
                Task { @MainActor in
                    await HealthSync.shared?.sendNow()
                }
                return
            }
            if action == "UNPAIR" {
                handleUnpairCommand()
                return
            }
            if action == "INCIDENT_STATUS_CHANGED" {
                let status = applicationContext["status"] as? String ?? "RESOLVED"
                let name = applicationContext["acknowledgedByName"] as? String
                let notes = applicationContext["notes"] as? String
                handleIncidentStatusUpdate(status: status, acknowledgedByName: name, notes: notes)
                return
            }
        }
        handleIncomingCredentials(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let action = userInfo["action"] as? String {
            if action == "FORCE_REFRESH" {
                NSLog("[CareAI-Watch] Nhận lệnh FORCE_REFRESH qua userInfo ngầm. Ép làm tươi và gửi viễn trắc ngay.")
                sendWatchDeviceInfo()
                syncCurrentBatteryAndWearState()
                Task { @MainActor in
                    await HealthSync.shared?.sendNow()
                }
                return
            }
            if action == "REQUEST_DEVICE_INFO" || action == "PING" || action == "REQUEST_TELEMETRY" {
                sendWatchDeviceInfo()
                syncCurrentBatteryAndWearState()
                return
            }
            if action == "UNPAIR" {
                handleUnpairCommand()
                return
            }
            if action == "INCIDENT_STATUS_CHANGED" {
                let status = userInfo["status"] as? String ?? "RESOLVED"
                let name = userInfo["acknowledgedByName"] as? String
                let notes = userInfo["notes"] as? String
                handleIncidentStatusUpdate(status: status, acknowledgedByName: name, notes: notes)
                return
            }
        }
        handleIncomingCredentials(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let action = message["action"] as? String {
            if action == "FORCE_REFRESH" {
                NSLog("[CareAI-Watch] Nhận lệnh FORCE_REFRESH qua sendMessage. Ép làm tươi và gửi viễn trắc ngay.")
                sendWatchDeviceInfo()
                syncCurrentBatteryAndWearState()
                Task { @MainActor in
                    await HealthSync.shared?.sendNow()
                }
                return
            }
            if action == "REQUEST_DEVICE_INFO" || action == "PING" || action == "REQUEST_TELEMETRY" {
                sendWatchDeviceInfo()
                syncCurrentBatteryAndWearState()
                return
            }
            if action == "UNPAIR" {
                handleUnpairCommand()
                return
            }
            if action == "INCIDENT_STATUS_CHANGED" {
                let status = message["status"] as? String ?? "RESOLVED"
                let name = message["acknowledgedByName"] as? String
                let notes = message["notes"] as? String
                handleIncidentStatusUpdate(status: status, acknowledgedByName: name, notes: notes)
                return
            }
        }
        handleIncomingCredentials(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        if let action = message["action"] as? String {
            if action == "FORCE_REFRESH" {
                NSLog("[CareAI-Watch] Nhận lệnh FORCE_REFRESH qua sendMessage (replyHandler). Ép làm tươi và gửi viễn trắc ngay.")
                sendWatchDeviceInfo()
                syncCurrentBatteryAndWearState()
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let dev = WKInterfaceDevice.current()
                    dev.isBatteryMonitoringEnabled = true
                    let raw = dev.batteryLevel
                    let bat = raw >= 0 ? Int(round(raw * 100)) : 100
                    let charging = (dev.batteryState == .charging || dev.batteryState == .full)
                    let hrRecent = (HealthSync.shared?.latestHeartRateAt != nil) &&
                                   (Date().timeIntervalSince(HealthSync.shared!.latestHeartRateAt!) < 30 * 60)
                    let worn = charging ? false : (hrRecent || (HealthSync.shared?.isWorn ?? false))
                    let rep = self.buildWatchTelemetryPayload(isWorn: worn, isCharging: charging, batteryLevel: bat)
                    replyHandler(rep)
                    await HealthSync.shared?.sendNow()
                }
                return
            }
            if action == "REQUEST_DEVICE_INFO" || action == "PING" || action == "REQUEST_TELEMETRY" {
                sendWatchDeviceInfo()
                syncCurrentBatteryAndWearState()
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let dev = WKInterfaceDevice.current()
                    dev.isBatteryMonitoringEnabled = true
                    let raw = dev.batteryLevel
                    let bat = raw >= 0 ? Int(round(raw * 100)) : 100
                    let charging = (dev.batteryState == .charging || dev.batteryState == .full)
                    let hrRecent = (HealthSync.shared?.latestHeartRateAt != nil) &&
                                   (Date().timeIntervalSince(HealthSync.shared!.latestHeartRateAt!) < 30 * 60)
                    let worn = charging ? false : (hrRecent || (HealthSync.shared?.isWorn ?? false))
                    let rep = self.buildWatchTelemetryPayload(isWorn: worn, isCharging: charging, batteryLevel: bat)
                    replyHandler(rep)
                }
                return
            }
            if action == "UNPAIR" {
                handleUnpairCommand()
                replyHandler(["status": "OK"])
                return
            }
            if action == "INCIDENT_STATUS_CHANGED" {
                let status = message["status"] as? String ?? "RESOLVED"
                let name = message["acknowledgedByName"] as? String
                let notes = message["notes"] as? String
                handleIncidentStatusUpdate(status: status, acknowledgedByName: name, notes: notes)
                replyHandler(["status": "OK"])
                return
            }
        }
        handleIncomingCredentials(message)
        replyHandler(["status": "OK"])
    }

    private func handleIncidentStatusUpdate(status: String, acknowledgedByName: String?, notes: String?) {
        NSLog("[CareAI-Watch] Nhận lệnh INCIDENT_STATUS_CHANGED: status=%@, by=%@", status, acknowledgedByName ?? "nil")
        Task { @MainActor in
            guard let sync = HealthSync.shared else { return }
            if status == "ACKNOWLEDGED" {
                let name = (acknowledgedByName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? acknowledgedByName!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : "Người Thân"
                sync.customAlert = "ACKNOWLEDGED"
                sync.acknowledgedByText = name
                sync.status = "🟢 \(name) đã tiếp nhận"
                sync.diagnosticLog = "✅ \(name) đã tiếp nhận hỗ trợ"
                WKInterfaceDevice.current().play(.success)

                // Sau 8 giây hiển thị tiếp nhận, tự động xóa cảnh báo nếu không có sự cố mới
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                    if sync.customAlert == "ACKNOWLEDGED" {
                        sync.customAlert = nil
                        sync.acknowledgedByText = nil
                        sync.status = "🟢 Đang Giám Sát Cổ Tay"
                        sync.deactivateEmergencySession()
                    }
                }
            } else if status == "RESOLVED" || status == "CLEAR" {
                sync.stopStandaloneIncidentPolling()
                sync.customAlert = nil
                sync.acknowledgedByText = nil
                sync.status = "🟢 Đang Giám Sát Cổ Tay"
                sync.diagnosticLog = "✅ Sự cố đã kết thúc an toàn"
                WKInterfaceDevice.current().play(.directionUp)
                sync.deactivateEmergencySession()
            }
        }
    }

    private func handleUnpairCommand() {
        NSLog("[CareAI-Watch] Nhận lệnh UNPAIR từ iPhone Companion. Tiến hành hủy ghép nối đồng hồ...")
        Task { @MainActor in
            HealthSync.shared?.unpair(notifyPhone: false)
            WatchConnectivityCoordinator.shared.sendWatchDeviceInfo()
            WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
        }
    }

    private func handleIncomingCredentials(_ payload: [String: Any]) {
        if let token = payload["deviceToken"] as? String, !token.isEmpty {
            KeychainToken.save(token)
            if let backendUrl = payload["backendUrl"] as? String, !backendUrl.isEmpty {
                UserDefaults.standard.set(backendUrl, forKey: "backend")
            }
            if let elderName = payload["elderName"] as? String, !elderName.isEmpty {
                UserDefaults.standard.set(elderName, forKey: "elderName")
            }
            if let deviceId = payload["deviceId"] as? String, !deviceId.isEmpty {
                UserDefaults.standard.set(deviceId, forKey: "deviceId")
            }
            NSLog("[CareAI-Watch] Đã nhận và tự động lưu credentials từ iPhone Companion thành công!")
            sendWatchDeviceInfo()
            syncCurrentBatteryAndWearState()
            Task { @MainActor in
                HealthSync.shared?.onCredentialsReceived()
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

/// Helper điều phối phiên nền WKExtendedRuntimeSession liên tục giữ cảm biến chuyển động hoạt động khi màn hình tắt / hạ cổ tay
private final class FallSessionCoordinator: NSObject, WKExtendedRuntimeSessionDelegate {
    private weak var sync: HealthSync?
    private var session: WKExtendedRuntimeSession?
    private var isRunning = false
    private var consecutiveFailures = 0

    init(sync: HealthSync) {
        self.sync = sync
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        session = s
        s.start()
        isRunning = true
        NSLog("[CareAI-Watch] Đã kích hoạt WKExtendedRuntimeSession duy trì cảm biến ngầm khi màn hình tắt.")
    }

    func stop() {
        guard isRunning else { return }
        session?.invalidate()
        session = nil
        isRunning = false
        NSLog("[CareAI-Watch] Đã dừng WKExtendedRuntimeSession.")
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        consecutiveFailures = 0
        NSLog("[CareAI-Watch] WKExtendedRuntimeSession nền đã kích hoạt thành công.")
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        NSLog("[CareAI-Watch] WKExtendedRuntimeSession sắp hết hạn. Tự động tái vũ trang ngay...")
        Task { @MainActor [weak self] in
            guard let self = self, let sync = self.sync else { return }
            if sync.autoFallDetectionEnabled && sync.isWorn && !sync.isCharging {
                self.stop()
                self.start()
            }
        }
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        NSLog("[CareAI-Watch] WKExtendedRuntimeSession invalidate (mã: %ld, error: %@)", reason.rawValue, String(describing: error))
        isRunning = false
        if let error = error as NSError?, error.code == 8 {
            NSLog("[CareAI-Watch] WKExtendedRuntimeSession chạm hạn mức nền trong ngày. Giữ cảm biến theo chu kỳ nền tiêu chuẩn, không retry dồn dập.")
            consecutiveFailures = 0
            return
        }
        consecutiveFailures += 1
        if consecutiveFailures > 3 {
            NSLog("[CareAI-Watch] WKExtendedRuntimeSession thất bại %ld lần liên tiếp. Tạm dừng tái khởi động trong 15 phút để bảo vệ tiến trình app khỏi bị watchOS kill.", consecutiveFailures)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                self?.consecutiveFailures = 0
                self?.start()
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self = self, let sync = self.sync else { return }
            if sync.autoFallDetectionEnabled && sync.isWorn && !sync.isCharging {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.start()
            }
        }
    }
}

@MainActor
final class HealthSync: ObservableObject {
    nonisolated static func resolveWatchModelName(machineCode: String, fallbackName: String) -> String {
        let clean = machineCode.trimmingCharacters(in: .whitespacesAndNewlines)
        switch clean {
        case "Watch1,1", "Watch1,2": return "Apple Watch (Gen 1)"
        case "Watch2,6", "Watch2,7": return "Apple Watch Series 1"
        case "Watch2,3", "Watch2,4": return "Apple Watch Series 2"
        case "Watch3,1", "Watch3,2", "Watch3,3", "Watch3,4": return "Apple Watch Series 3"
        case "Watch4,1", "Watch4,2", "Watch4,3", "Watch4,4": return "Apple Watch Series 4"
        case "Watch5,1", "Watch5,2", "Watch5,3", "Watch5,4": return "Apple Watch Series 5"
        case "Watch5,9", "Watch5,10", "Watch5,11", "Watch5,12": return "Apple Watch SE (Gen 1)"
        case "Watch6,1", "Watch6,2", "Watch6,3", "Watch6,4": return "Apple Watch Series 6"
        case "Watch6,6", "Watch6,7", "Watch6,8", "Watch6,9": return "Apple Watch Series 7"
        case "Watch6,10", "Watch6,11", "Watch6,12", "Watch6,13": return "Apple Watch SE (Gen 2)"
        case "Watch6,14", "Watch6,15", "Watch6,16", "Watch6,17": return "Apple Watch Series 8"
        case "Watch6,18": return "Apple Watch Ultra"
        case "Watch7,1", "Watch7,2", "Watch7,3", "Watch7,4": return "Apple Watch Series 9"
        case "Watch7,5": return "Apple Watch Ultra 2"
        case "Watch7,8", "Watch7,9", "Watch7,10", "Watch7,11": return "Apple Watch Series 10"
        default:
            if clean.contains("arm64") || clean.contains("x86_64") {
                return fallbackName.isEmpty ? "Apple Watch (Simulator)" : fallbackName
            }
            if !fallbackName.isEmpty && fallbackName != "Apple Watch" {
                return fallbackName
            }
            return clean.isEmpty ? "Apple Watch" : "Apple Watch (\(clean))"
        }
    }

    nonisolated static func isSpo2HardwareSupported(machineCode: String) -> Bool {
        let clean = machineCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.starts(with: "Watch1,") ||
           clean.starts(with: "Watch2,") ||
           clean.starts(with: "Watch3,") ||
           clean.starts(with: "Watch4,") ||
           clean.starts(with: "Watch5,") {
            return false
        }
        if clean == "Watch6,10" || clean == "Watch6,11" || clean == "Watch6,12" || clean == "Watch6,13" {
            return false // Apple Watch SE (Gen 2)
        }
        return true
    }

    static weak var shared: HealthSync?

    @Published var isPaired: Bool = KeychainToken.load() != nil
    @Published var isPhoneReachable: Bool = WCSession.isSupported() && WCSession.default.isReachable
    @Published var isWorn: Bool = true
    @Published var isCharging: Bool = false
    @Published var status = "Set up backend to start"
    @Published var customAlert: String?
    @Published var acknowledgedByText: String?
    @Published var diagnosticLog = "⚡ Cảm biến sẵn sàng"
    @Published var autoFallDetectionEnabled = true
    @Published private(set) var hasSpo2Hardware: Bool = true
    @Published private(set) var latestHeartRate: Double?
    @Published private(set) var latestHeartRateAt: Date?
    @Published private(set) var latestSpo2: Double?
    @Published private(set) var latestSpo2At: Date?
    @Published private(set) var todaySteps: Int?
    @Published private(set) var lastNightSleepMinutes: Int?
    @Published private(set) var deepSleepMinutes: Int?
    @Published private(set) var coreSleepMinutes: Int?
    @Published private(set) var remSleepMinutes: Int?
    @Published private(set) var awakeMinutes: Int?
    @Published private(set) var wakeCount: Int?
    @Published private(set) var minSleepingHr: Double?
    @Published private(set) var avgSleepingHr: Double?
    @Published private(set) var minNightSpo2: Double?
    @Published private(set) var nightSpo2DipsCount: Int?
    @Published private(set) var breathingDisturbances: String?
    @Published private(set) var latestBpSystolic: Double?
    @Published private(set) var latestBpDiastolic: Double?
    @Published private(set) var latestBpAt: Date?
    @Published private(set) var pendingCount = 0
    @Published private(set) var healthAlert: String?
    @Published private(set) var simulatedOffline = false
    @Published var isNetworkSatisfied: Bool = true
    @Published private(set) var demoHeartRateAlert: String?
    @Published private(set) var demoSpo2Alert: String?
    private let healthStore = HKHealthStore()

    var isOnline: Bool {
        if simulatedOffline { return false }
        if isPhoneReachable { return true }
        if WCSession.isSupported() {
            let session = WCSession.default
            if session.activationState == .activated && isPaired {
                return true
            }
        }
        return isNetworkSatisfied
    }
    private let pathMonitor = NWPathMonitor()
    private let outboxURL = FileManager.default.urls(for: .applicationSupportDirectory,
        in: .userDomainMask)[0].appendingPathComponent("healthkit-pending-readings.json")
    private var observers: [HKObserverQuery] = []
    private var queue: [PendingReading] = []
    private var outboxReady = false
    private var isSending = false
    private var retryTimer: Timer?
    private var metrics: [(HKQuantityTypeIdentifier, String, HKUnit, String)] {
        var list: [(HKQuantityTypeIdentifier, String, HKUnit, String)] = [
            (.heartRate, "HEART_RATE", HKUnit.count().unitDivided(by: .minute()), "bpm"),
            (.stepCount, "STEPS", HKUnit.count(), "count"),
            (.oxygenSaturation, "SPO2", HKUnit.percent(), "%"),
            (.bloodPressureSystolic, "BP_SYSTOLIC", HKUnit.millimeterOfMercury(), "mmHg"),
            (.bloodPressureDiastolic, "BP_DIASTOLIC", HKUnit.millimeterOfMercury(), "mmHg")
        ]
        return list
    }

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
    private var fallSessionCoordinator: FallSessionCoordinator?

    init() {
        HealthSync.shared = self
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let machineCode = String(cString: machine)
        self.hasSpo2Hardware = HealthSync.isSpo2HardwareSupported(machineCode: machineCode)
        let dev = WKInterfaceDevice.current()
        dev.isBatteryMonitoringEnabled = true
        let currentCharging = (dev.batteryState == .charging || dev.batteryState == .full)
        self.isCharging = currentCharging
        self.isWorn = currentCharging ? false : UserDefaults.standard.bool(forKey: "careai.isWorn")
        self.fallSessionCoordinator = FallSessionCoordinator(sync: self)

        if WCSession.isSupported() {
            let session = WCSession.default
            self.isPhoneReachable = (session.activationState == .activated && session.isReachable)
        }
        WatchConnectivityCoordinator.shared.activate()
        WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
        latestHeartRate = UserDefaults.standard.object(forKey: "latest.heartRate") as? Double
        latestHeartRateAt = UserDefaults.standard.object(forKey: "latest.heartRateAt") as? Date
        latestSpo2 = UserDefaults.standard.object(forKey: "latest.spo2") as? Double
        latestSpo2At = UserDefaults.standard.object(forKey: "latest.spo2At") as? Date
        updateHealthAlert()
        loadOutbox()
        if pendingCount > 0 {
            flush(force: true)
        }
        setupFallDetection()
        requestHealthKitAuthorization()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkSatisfied = (path.status == .satisfied)
            }
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.flush(force: false) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "careai.watch.network"))
        // Chu kỳ đồng bộ nền gom lô sinh hiệu định kỳ (1-2 tiếng một lần theo chuẩn watchOS để tiết kiệm pin)
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHealthAlert()
                self?.flush(force: false)
                WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
            }
        }
        if UserDefaults.standard.string(forKey: "backend") != nil,
           KeychainToken.load() != nil {
            Task { @MainActor in self.start() }
        }
    }

    func onCredentialsReceived() {
        self.isPaired = true
        self.status = "🟢 Đang Giám Sát Cổ Tay"
        self.diagnosticLog = "⚡ Đã nhận diện credentials từ iPhone"
        self.start()
    }

    func unpair(notifyPhone: Bool = true) {
        UserDefaults.standard.removeObject(forKey: "deviceId")
        UserDefaults.standard.removeObject(forKey: "backend")
        KeychainToken.save("")
        self.isPaired = false
        self.status = "Set up backend to start"
        if notifyPhone {
            WatchConnectivityCoordinator.shared.notifyWatchUnpaired()
        }
    }

    func requestHealthKitAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "HealthKit unavailable"
            return
        }
        var types: Set<HKObjectType> = Set(metrics.compactMap { HKObjectType.quantityType(forIdentifier: $0.0) })
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let sys = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic) {
            types.insert(sys)
        }
        if let dia = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            types.insert(dia)
        }
        healthStore.requestAuthorization(toShare: [], read: types) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.status = "HealthKit: \(error.localizedDescription)"
                    return
                }
                self.registerObservers()
                self.fetchLatestSamples()
            }
        }
    }

    func fetchLatestSamples() {
        for (identifier, _, _, _) in metrics {
            fetchLatestSample(for: identifier)
        }
        fetchTodaySteps()
        fetchLastNightSleep()
        fetchLatestBloodPressure()
    }

    func fetchTodaySteps() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, _ in
            guard let sum = result?.sumQuantity() else { return }
            let steps = Int(sum.doubleValue(for: .count()))
            Task { @MainActor in
                self?.todaySteps = steps
                if steps > 0 {
                    WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
                }
            }
        }
        healthStore.execute(query)
    }

    func fetchLastNightSleep() {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let now = Date()
        guard let startOfYesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now)) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 300, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, _ in
            guard let self = self, let samples = samples as? [HKCategorySample], !samples.isEmpty else { return }
            var totalSeconds: TimeInterval = 0
            var deepSeconds: TimeInterval = 0
            var coreSeconds: TimeInterval = 0
            var remSeconds: TimeInterval = 0
            var awakeSeconds: TimeInterval = 0
            var wakeEpisodes = 0
            var earliestSleep: Date?
            var latestSleep: Date?

            for s in samples {
                let dur = s.endDate.timeIntervalSince(s.startDate)
                guard dur > 0 else { continue }

                if #available(watchOS 9.0, *) {
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deepSeconds += dur
                        totalSeconds += dur
                        earliestSleep = earliestSleep == nil ? s.startDate : min(earliestSleep!, s.startDate)
                        latestSleep = latestSleep == nil ? s.endDate : max(latestSleep!, s.endDate)
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        coreSeconds += dur
                        totalSeconds += dur
                        earliestSleep = earliestSleep == nil ? s.startDate : min(earliestSleep!, s.startDate)
                        latestSleep = latestSleep == nil ? s.endDate : max(latestSleep!, s.endDate)
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        remSeconds += dur
                        totalSeconds += dur
                        earliestSleep = earliestSleep == nil ? s.startDate : min(earliestSleep!, s.startDate)
                        latestSleep = latestSleep == nil ? s.endDate : max(latestSleep!, s.endDate)
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awakeSeconds += dur
                        wakeEpisodes += 1
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        totalSeconds += dur
                        earliestSleep = earliestSleep == nil ? s.startDate : min(earliestSleep!, s.startDate)
                        latestSleep = latestSleep == nil ? s.endDate : max(latestSleep!, s.endDate)
                    default:
                        break
                    }
                } else {
                    if s.value == HKCategoryValueSleepAnalysis.asleep.rawValue {
                        totalSeconds += dur
                        earliestSleep = earliestSleep == nil ? s.startDate : min(earliestSleep!, s.startDate)
                        latestSleep = latestSleep == nil ? s.endDate : max(latestSleep!, s.endDate)
                    }
                }
            }

            let minutes = Int(totalSeconds / 60)
            let deepMin = Int(deepSeconds / 60)
            let coreMin = Int(coreSeconds / 60)
            let remMin = Int(remSeconds / 60)
            let awakeMin = Int(awakeSeconds / 60)

            Task { @MainActor in
                self.lastNightSleepMinutes = minutes > 0 ? minutes : nil
                self.deepSleepMinutes = deepMin > 0 ? deepMin : nil
                self.coreSleepMinutes = coreMin > 0 ? coreMin : nil
                self.remSleepMinutes = remMin > 0 ? remMin : nil
                self.awakeMinutes = awakeMin > 0 ? awakeMin : nil
                self.wakeCount = wakeEpisodes > 0 ? wakeEpisodes : nil

                if let sleepStart = earliestSleep, let sleepEnd = latestSleep, sleepEnd > sleepStart {
                    self.fetchSleepingNightVitals(start: sleepStart, end: sleepEnd)
                } else {
                    WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
                }
            }
        }
        healthStore.execute(query)
    }

    func fetchSleepingNightVitals(start: Date, end: Date) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        // 1. Nhịp tim trong lúc ngủ (Sleeping Heart Rate)
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let hrQuery = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 500, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, _ in
                guard let self = self, let hrSamples = samples as? [HKQuantitySample], !hrSamples.isEmpty else { return }
                var minHr: Double = 999.0
                var totalHr: Double = 0.0
                for s in hrSamples {
                    let bpm = s.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    if bpm > 0 && bpm < minHr { minHr = bpm }
                    totalHr += bpm
                }
                let avgHr = totalHr / Double(hrSamples.count)
                Task { @MainActor in
                    self.minSleepingHr = minHr < 900 ? minHr : nil
                    self.avgSleepingHr = avgHr > 0 ? avgHr : nil
                    WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
                }
            }
            healthStore.execute(hrQuery)
        }

        // 2. Tụt oxy ban đêm (Nighttime SpO2 & Dips)
        if hasSpo2Hardware, let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            let spo2Query = HKSampleQuery(sampleType: spo2Type, predicate: predicate, limit: 200, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, _ in
                guard let self = self, let spo2Samples = samples as? [HKQuantitySample], !spo2Samples.isEmpty else { return }
                var minSpo2: Double = 100.0
                var dips = 0
                for s in spo2Samples {
                    let pct = s.quantity.doubleValue(for: HKUnit.percent()) * 100.0
                    if pct > 0 && pct < minSpo2 { minSpo2 = pct }
                    if pct > 0 && pct < 90.0 { dips += 1 }
                }
                Task { @MainActor in
                    self.minNightSpo2 = minSpo2 <= 100.0 ? minSpo2 : nil
                    self.nightSpo2DipsCount = dips
                    WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
                }
            }
            healthStore.execute(spo2Query)
        }

        // 3. Khám phá các dòng cao cấp (Apple Watch Series 9/10/Ultra 2 trên watchOS 11+): Rối loạn thở khi ngủ (Breathing Disturbances)
        let apneaTypeIdentifier = HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances")
        if let apneaType = HKQuantityType.quantityType(forIdentifier: apneaTypeIdentifier) {
            let apneaQuery = HKSampleQuery(sampleType: apneaType, predicate: predicate, limit: 10, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, _ in
                guard let self = self, let apneaSamples = samples as? [HKQuantitySample], !apneaSamples.isEmpty else { return }
                var isElevated = false
                for s in apneaSamples {
                    let val = s.quantity.doubleValue(for: HKUnit.count())
                    if val >= 5.0 { isElevated = true }
                }
                Task { @MainActor in
                    self.breathingDisturbances = isElevated ? "ELEVATED" : "NORMAL"
                    WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
                }
            }
            healthStore.execute(apneaQuery)
        }
    }

    func fetchLatestBloodPressure() {
        guard let sysType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diaType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: sysType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, _ in
            guard let self = self, let sysSample = samples?.first as? HKQuantitySample else { return }
            let sys = sysSample.quantity.doubleValue(for: HKUnit.millimeterOfMercury())
            let sampleDate = sysSample.endDate

            let diaPredicate = HKQuery.predicateForSamples(
                withStart: sampleDate.addingTimeInterval(-120),
                end: sampleDate.addingTimeInterval(120),
                options: .strictStartDate
            )
            let diaQuery = HKSampleQuery(sampleType: diaType, predicate: diaPredicate, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, diaSamples, _ in
                guard let self = self else { return }
                let dia = (diaSamples?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.millimeterOfMercury()) ?? 80.0
                Task { @MainActor in
                    self.latestBpSystolic = sys
                    self.latestBpDiastolic = dia
                    self.latestBpAt = sampleDate
                    WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
                }
            }
            self.healthStore.execute(diaQuery)
        }
        healthStore.execute(query)
    }

    func fetchLatestSample(for identifier: HKQuantityTypeIdentifier) {
        guard let metric = metrics.first(where: { $0.0 == identifier }),
              let type = HKObjectType.quantityType(forIdentifier: identifier) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            guard let self = self, let sample = samples?.first as? HKQuantitySample else { return }
            let raw = sample.quantity.doubleValue(for: metric.2)
            let value = identifier == .oxygenSaturation ? raw * 100 : raw
            Task { @MainActor in
                if identifier == .heartRate {
                    self.latestHeartRate = value
                    self.latestHeartRateAt = sample.endDate
                    UserDefaults.standard.set(value, forKey: "latest.heartRate")
                    UserDefaults.standard.set(sample.endDate, forKey: "latest.heartRateAt")
                } else if identifier == .oxygenSaturation {
                    self.latestSpo2 = value
                    self.latestSpo2At = sample.endDate
                    UserDefaults.standard.set(value, forKey: "latest.spo2")
                    UserDefaults.standard.set(sample.endDate, forKey: "latest.spo2At")
                }
                self.updateHealthAlert()
            }
        }
        healthStore.execute(query)
    }

    func start() {
        if !outboxReady { loadOutbox() }
        if autoFallDetectionEnabled { setupFallDetection() }
        requestHealthKitAuthorization()
        guard let url = URL(string: UserDefaults.standard.string(forKey: "backend") ?? ""),
              url.scheme == "https", url.host?.isEmpty == false,
              !(UserDefaults.standard.string(forKey: "deviceId") ?? "").isEmpty,
              KeychainToken.load()?.isEmpty == false else {
            status = "Enter HTTPS URL, device ID and device token"
            return
        }
        scheduleBackgroundRefresh()
        self.flush(force: false)
    }

    private func scheduleBackgroundRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(15 * 60),
            userInfo: "careai.healthsync" as NSSecureCoding & NSObjectProtocol
        ) { _ in }
    }

    func refreshInBackground() async {
        scheduleBackgroundRefresh()
        WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
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

    func simulateAcknowledged(name: String = "Người Thân") {
        customAlert = "ACKNOWLEDGED"
        acknowledgedByText = name
        status = "🟢 \(name) đã tiếp nhận"
        diagnosticLog = "⚡ Mô phỏng: \(name) đã tiếp nhận hỗ trợ"
        WKInterfaceDevice.current().play(.success)
    }

    func simulateHighHeartRate() {
        simulateTachycardia()
    }

    func simulateLowSpo2() {
        simulateHypoxia()
    }

    // 5. Nút test Tháo cổ tay (Off-body)
    func simulateUnworn() {
        isWorn = false
        fallSessionCoordinator?.stop()
        status = "🟡 ĐÃ THÁO CỔ TAY"
        diagnosticLog = "⚡ Mô phỏng: Đã tháo thiết bị khỏi cổ tay"
        let raw = WKInterfaceDevice.current().batteryLevel
        let bat = raw >= 0 ? Int(raw * 100) : 100
        WatchConnectivityCoordinator.shared.relayWatchTelemetry(isWorn: false, isCharging: isCharging, batteryLevel: bat)
    }

    // 6. Nút test Đeo vào cổ tay
    func simulateWorn() {
        isWorn = true
        if autoFallDetectionEnabled && !isCharging {
            fallSessionCoordinator?.start()
        }
        status = "🟢 Đang Giám Sát Cổ Tay"
        diagnosticLog = "⚡ Mô phỏng: Đã đeo thiết bị vào cổ tay"
        let raw = WKInterfaceDevice.current().batteryLevel
        let bat = raw >= 0 ? Int(raw * 100) : 100
        WatchConnectivityCoordinator.shared.relayWatchTelemetry(isWorn: true, isCharging: isCharging, batteryLevel: bat)
    }

    // 7. Nút test Cắm sạc / Rút sạc
    func simulateCharging(charging: Bool) {
        isCharging = charging
        isWorn = !charging
        if charging {
            fallSessionCoordinator?.stop()
        } else if autoFallDetectionEnabled {
            fallSessionCoordinator?.start()
        }
        status = charging ? "⚡ Đang Cắm Sạc" : "🟢 Đang Giám Sát Cổ Tay"
        diagnosticLog = charging ? "⚡ Mô phỏng: Đang cắm sạc" : "⚡ Mô phỏng: Đã rút sạc"
        let raw = WKInterfaceDevice.current().batteryLevel
        let bat = raw >= 0 ? Int(raw * 100) : 100
        WatchConnectivityCoordinator.shared.relayWatchTelemetry(isWorn: !charging, isCharging: charging, batteryLevel: bat)
    }

    /// Kích hoạt gửi cảnh báo Cấp Cứu Fast-Lane SOS hoặc Phát hiện Té Ngã (Tuân thủ Bất biến Fact 35)
    @discardableResult
    func triggerEmergencySos(type: String, eventId: String? = nil) async -> (success: Bool, message: String) {
        let baseEventId = eventId ?? "\(type)_\(Int64(Date().timeIntervalSince1970 * 1000))"
        let canonicalPacketId = type == "FALL_DETECTED" ? "FALL_\(baseEventId)" : "SOS_\(baseEventId)"

        // Kích hoạt chuỗi rung xúc giác & chuông báo động khẩn cấp trực tiếp lên cổ tay
        let device = WKInterfaceDevice.current()
        device.play(.failure)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            device.play(.retry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            device.play(.failure)
        }

        if type == "FALL_DETECTED" {
            customAlert = "FALL_DETECTED"
            status = "💥 CẢNH BÁO TÉ NGÃ!"
            diagnosticLog = "Đang gửi cảnh báo té ngã khẩn cấp..."
        } else {
            customAlert = "MANUAL_SOS"
            status = "🆘 ĐÃ BẮN TÍN HIỆU SOS!"
            diagnosticLog = "Đang gửi SOS khẩn cấp..."
        }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timeStr = formatter.string(from: now)

        // BẤT BIẾN FACT 35: Gói tin Fast-Lane SOS lưu toàn bộ mẫu đo sinh hiệu thực tế đi kèm (nếu có, không bịa đặt số liệu giả)
        var samples: [HealthSampleDto] = []
        if let hr = latestHeartRate, hr > 0 {
            samples.append(HealthSampleDto(metricType: "HEART_RATE", value: hr, unit: "bpm", timestamp: timeStr))
        }
        if let spo2 = latestSpo2, spo2 > 0 {
            samples.append(HealthSampleDto(metricType: "SPO2", value: spo2, unit: "%", timestamp: timeStr))
        }

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
            hr: latestHeartRate,
            spo2: latestSpo2
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
                if !isPhoneReachable {
                    startStandaloneIncidentPolling()
                }
                return (true, successMsg)
            } else {
                let failMsg = "⚠️ Máy chủ phản hồi mã \(code ?? 0). Đã lưu đệm."
                diagnosticLog = failMsg
                enqueueDemo(metricType: type == "FALL_DETECTED" ? "FALL" : "SOS", value: 1.0, unit: "event")
                if !isPhoneReachable {
                    startStandaloneIncidentPolling()
                }
                return (false, failMsg)
            }
        } catch {
            let errorMsg = "⚠️ Lỗi mạng: \(error.localizedDescription). Đã lưu đệm."
            diagnosticLog = errorMsg
            enqueueDemo(metricType: type == "FALL_DETECTED" ? "FALL" : "SOS", value: 1.0, unit: "event")
            if !isPhoneReachable {
                startStandaloneIncidentPolling()
            }
            return (false, errorMsg)
        }
    }

    private var standalonePollTimer: Timer?

    func startStandaloneIncidentPolling() {
        standalonePollTimer?.invalidate()
        standalonePollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.pollActiveIncidentStandalone()
            }
        }
        Task { @MainActor in
            await self.pollActiveIncidentStandalone()
        }
    }

    func stopStandaloneIncidentPolling() {
        standalonePollTimer?.invalidate()
        standalonePollTimer = nil
    }

    func pollActiveIncidentStandalone() async {
        guard !isPhoneReachable else { return }
        guard customAlert == "MANUAL_SOS" || customAlert == "FALL_DETECTED" || customAlert == "ACKNOWLEDGED" else {
            stopStandaloneIncidentPolling()
            return
        }
        guard let base = UserDefaults.standard.string(forKey: "backend"),
              let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/devices/active-incident"),
              let deviceId = UserDefaults.standard.string(forKey: "deviceId"),
              let token = KeychainToken.load() else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.setValue(deviceId, forHTTPHeaderField: "X-DeviceId")
        request.setValue(token, forHTTPHeaderField: "X-Device-Token")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let hasActive = json["hasActiveIncident"] as? Bool ?? false
            let statusStr = json["status"] as? String ?? ""
            let name = json["acknowledgedByName"] as? String

            if hasActive && statusStr == "ACKNOWLEDGED" {
                if customAlert != "ACKNOWLEDGED" {
                    customAlert = "ACKNOWLEDGED"
                    let ackName = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? name!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : "Người Thân"
                    acknowledgedByText = ackName
                    status = "🟢 \(ackName) đã tiếp nhận"
                    diagnosticLog = "✅ \(ackName) đã tiếp nhận hỗ trợ (Wi-Fi/LTE)"
                    WKInterfaceDevice.current().play(.success)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
                        guard let self = self else { return }
                        if self.customAlert == "ACKNOWLEDGED" {
                            self.customAlert = nil
                            self.acknowledgedByText = nil
                            self.status = "🟢 Đang Giám Sát Cổ Tay"
                            self.deactivateEmergencySession()
                        }
                    }
                }
            } else if !hasActive && (customAlert == "MANUAL_SOS" || customAlert == "FALL_DETECTED" || customAlert == "ACKNOWLEDGED") {
                stopStandaloneIncidentPolling()
                customAlert = nil
                acknowledgedByText = nil
                status = "🟢 Đang Giám Sát Cổ Tay"
                diagnosticLog = "✅ Sự cố đã kết thúc an toàn (Wi-Fi/LTE)"
                WKInterfaceDevice.current().play(.directionUp)
                deactivateEmergencySession()
            }
        } catch {}
    }

    /// Kích hoạt phiên thực thi mở rộng giữ đồng hồ thức ngầm khi có cấp cứu
    func activateEmergencySession() {
        guard activeEmergencySession == nil || activeEmergencySession?.state == .invalid else { return }
        let session = WKExtendedRuntimeSession()
        session.start()
        activeEmergencySession = session
    }

    func deactivateEmergencySession() {
        activeEmergencySession?.invalidate()
        activeEmergencySession = nil
    }

    private var baselineInterval: TimeInterval {
        batterySaverEnabled ? 0.2 : 0.1 // 5Hz khi bật Tiết kiệm pin thích ứng (giảm 50% CPU wakes), 10Hz khi bình thường
    }

    func applyBatteryPolicy() {
        if autoFallDetectionEnabled {
            setupFallDetection()
        }
        diagnosticLog = batterySaverEnabled ? "🔋 Đã bật Tiết Kiệm Pin Thích Ứng (5Hz/40Hz Burst)" : "⚡ Đã bật Giám Sát Hiệu Năng Cao (10Hz)"
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
            fallSessionCoordinator?.stop()
            motionManager.stopAccelerometerUpdates()
            diagnosticLog = "⚡ Đã tắt tự động phát hiện té ngã"
            return
        }

        if isWorn && !isCharging {
            fallSessionCoordinator?.start()
        }

        // 🛡️ BẢO VỆ TỰ CHỦ QUA COREMOTION (CMMotionManager):
        // Lưu ý: Không gọi CMFallDetectionManager.isAvailable vì API này kích hoạt
        // NSAssert trong CMFallDetectionManager.mm:116 làm crash app lập tức nếu thiếu Entitlement đặc quyền của Apple.
        startMotionFallDetectionFallback()
        diagnosticLog = batterySaverEnabled ? "🔋 Cảm biến CoreMotion (Tiết kiệm pin 10Hz)" : "⚡ Cảm biến CoreMotion (20Hz)"
    }

    private func startMotionFallDetectionFallback() {
        guard motionManager.isAccelerometerAvailable else { return }
        if isWorn && !isCharging {
            fallSessionCoordinator?.start()
        }
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
        // Tận dụng luồng CoreMotion đang chạy nền (0% tốn thêm pin) để phát hiện tức thì thao tác cắm/rút sạc
        let dev = WKInterfaceDevice.current()
        let currentCharging = (dev.batteryState == .charging || dev.batteryState == .full)
        if currentCharging != self.isCharging {
            self.isCharging = currentCharging
            if currentCharging {
                self.isWorn = false
                UserDefaults.standard.set(false, forKey: "careai.isWorn")
            }
            WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
        }

        let now = Date()
        // Chống spam: Mỗi sự cố ngã cách nhau tối thiểu 15 giây
        if let last = lastMotionFallDetectedAt, now.timeIntervalSince(last) < 15.0 {
            return
        }

        // Tối ưu pin thích ứng: Khi phát hiện dấu hiệu gia tốc bất thường (<0.65g hoặc >1.4g), tự động tăng tần số lên 40Hz
        if (g < 0.65 || g > 1.4) && !isBurstSampling {
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
        // Gửi ngay pin/trạng thái đeo và các chỉ số sinh hiệu vừa quét sang iPhone
        WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
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
                    if identifier == .stepCount {
                        if value <= 0 { continue }
                        self.fetchTodaySteps()
                    }
                    if identifier == .heartRate,
                       sample.endDate > (self.latestHeartRateAt ?? .distantPast) {
                        self.latestHeartRate = value
                        self.latestHeartRateAt = sample.endDate
                        UserDefaults.standard.set(value, forKey: "latest.heartRate")
                        UserDefaults.standard.set(sample.endDate, forKey: "latest.heartRateAt")
                        // Cảm biến quang học ghi nhận nhịp tim sinh học thực tế -> Xác nhận đồng hồ đang được đeo trên cổ tay
                        if !self.isWorn {
                            self.isWorn = true
                            UserDefaults.standard.set(true, forKey: "careai.isWorn")
                            WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
                        }
                    } else if identifier == .oxygenSaturation,
                              sample.endDate > (self.latestSpo2At ?? .distantPast) {
                        self.latestSpo2 = value
                        self.latestSpo2At = sample.endDate
                        UserDefaults.standard.set(value, forKey: "latest.spo2")
                        UserDefaults.standard.set(sample.endDate, forKey: "latest.spo2At")
                    } else if identifier == .bloodPressureSystolic,
                              sample.endDate > (self.latestBpAt ?? .distantPast) {
                        self.latestBpSystolic = value
                        self.latestBpAt = sample.endDate
                        WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
                    } else if identifier == .bloodPressureDiastolic {
                        self.latestBpDiastolic = value
                        WatchConnectivityCoordinator.shared.syncCurrentBatteryAndWearState()
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

    func flush(force: Bool = true) {
        // Tối ưu năng lượng vô tuyến (Radio Coalescing):
        // Nếu không ép buộc và không có cảnh báo y tế khẩn cấp, chỉ đánh thức modem mạng khi gom đủ ít nhất 10 mẫu
        if !force && healthAlert == nil && customAlert == nil && queue.count < 10 {
            return
        }
        Task { await sendPending(maximum: .max) }
    }

    private func sendPending(maximum: Int) async {
        guard !simulatedOffline else { return }
        guard outboxReady, !isSending else { return }
        isSending = true
        defer { isSending = false }
        var sent = 0
        let batchLimit = 50
        while sent < maximum && !queue.isEmpty {
            if simulatedOffline {
                status = "DEMO offline Â· readings stay on watch"
                return
            }
            let chunk = Array(queue.prefix(min(batchLimit, maximum - sent)))
            guard !chunk.isEmpty else { break }

            let batchId = "HK_BATCH_\(Int64(Date().timeIntervalSince1970 * 1000))_\(chunk.count)"

            // KÊNH 1 (ƯU TIÊN): Chuyển tiếp tức thì qua Bluetooth WCSession sang iPhone Companion
            if WCSession.isSupported() {
                let session = WCSession.default
                if session.activationState == .activated {
                    let samplesArray = chunk.map { r -> [String: Any] in
                        return [
                            "sampleId": r.sampleId,
                            "metricType": r.metricType,
                            "value": r.value,
                            "unit": r.unit,
                            "timestamp": r.timestamp
                        ]
                    }
                    let dev = WKInterfaceDevice.current()
                    dev.isBatteryMonitoringEnabled = true
                    let rawLevel = dev.batteryLevel
                    let batteryLevel = rawLevel >= 0 ? Int(rawLevel * 100) : 100
                    let isCharging = (dev.batteryState == .charging || dev.batteryState == .full)
                    var relayPayload: [String: Any] = [
                        "action": "TELEMETRY_BATCH",
                        "batchId": batchId,
                        "samples": samplesArray,
                        "batteryLevel": batteryLevel,
                        "isCharging": isCharging,
                        "isWorn": self.isWorn
                    ]
                    if let devId = UserDefaults.standard.string(forKey: "deviceId"), !devId.isEmpty {
                        relayPayload["deviceId"] = devId
                    }
                    if let token = KeychainToken.load(), !token.isEmpty {
                        relayPayload["deviceToken"] = token
                    }

                    if session.isReachable {
                        let relaySuccess: Bool = await withCheckedContinuation { continuation in
                            var hasResumed = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                if !hasResumed {
                                    hasResumed = true
                                    continuation.resume(returning: false)
                                }
                            }
                            session.sendMessage(relayPayload, replyHandler: { reply in
                                if !hasResumed {
                                    hasResumed = true
                                    let replyStatus = reply["status"] as? String
                                    continuation.resume(returning: replyStatus == "OK")
                                }
                            }, errorHandler: { _ in
                                if !hasResumed {
                                    hasResumed = true
                                    continuation.resume(returning: false)
                                }
                            })
                        }

                        if relaySuccess {
                            let remaining = Array(queue.dropFirst(chunk.count))
                            try? persistQueue(remaining)
                            queue = remaining
                            pendingCount = remaining.count
                            sent += chunk.count
                            status = "Đã gửi \(chunk.count) mẫu qua iPhone · Chờ: \(queue.count)"
                            continue
                        } else {
                            // Dự phòng khi sendMessage timeout: Gửi qua transferUserInfo bảo đảm
                            session.transferUserInfo(relayPayload)
                            let remaining = Array(queue.dropFirst(chunk.count))
                            try? persistQueue(remaining)
                            queue = remaining
                            pendingCount = remaining.count
                            sent += chunk.count
                            status = "Đã chuyển giao ngầm qua iPhone (\(chunk.count) mẫu) · Chờ: \(queue.count)"
                            continue
                        }
                    } else {
                        // iPhone đang ở chế độ nền (Background) hoặc tắt màn hình: Dùng transferUserInfo bảo đảm
                        session.transferUserInfo(relayPayload)
                        let remaining = Array(queue.dropFirst(chunk.count))
                        try? persistQueue(remaining)
                        queue = remaining
                        pendingCount = remaining.count
                        sent += chunk.count
                        status = "Đã chuyển giao ngầm qua iPhone (\(chunk.count) mẫu) · Chờ: \(queue.count)"
                        continue
                    }
                }
            }

            // KÃŠNH 2 (FALLBACK): Gá»­i trá»±c tiáº¿p qua Wi-Fi / LTE cá»§a Apple Watch (náº¿u cÃ³ thÃ´ng tin Ä‘Äƒng nháº­p vÃ  máº¡ng)
            guard let base = UserDefaults.standard.string(forKey: "backend"),
                  let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/telemetry/ingest"),
                  url.scheme == "https",
                  let deviceId = UserDefaults.standard.string(forKey: "deviceId"),
                  let token = KeychainToken.load() else {
                status = "Chá» iPhone káº¿t ná»‘i hoáº·c thiáº¿t láº­p Wi-Fi"
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue(deviceId, forHTTPHeaderField: "X-DeviceId")
            request.setValue(token, forHTTPHeaderField: "X-Device-Token")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder().encode(TelemetryBatch(
                    batchId: batchId, samples: chunk))
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode
                // Cháº¥p nháº­n 200 OK, 201 Created (Ä‘á»“ng bá»™) hoáº·c 202 Accepted (kÃªnh phi khÃ³a Non-Blocking Channel)
                guard code == 200 || code == 201 || code == 202 else {
                    status = "Waiting to send Â· HTTP \(code.map(String.init) ?? "offline")"
                    return
                }
                // Giá»¯ báº£n gá»‘c trÃªn Ä‘Ä©a cho Ä‘áº¿n khi mÃ¡y chá»§ xÃ¡c nháº­n cam káº¿t thÃ nh cÃ´ng
                let remaining = Array(queue.dropFirst(chunk.count))
                try persistQueue(remaining)
                queue = remaining
                pendingCount = remaining.count
                sent += chunk.count
                status = "Sent \(chunk.count) samples Â· queued \(queue.count)"
            } catch {
                // Tháº¥t báº¡i giá»¯ nguyÃªn outbox Ä‘á»ƒ thá»­ láº¡i sau
                status = "Offline or save failed Â· queued \(queue.count)"
                return
            }
        }
    }
}
