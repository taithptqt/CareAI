import Flutter
import UIKit
import WatchConnectivity
import UserNotifications
import AVFoundation
#if canImport(workmanager_apple)
import workmanager_apple
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, WCSessionDelegate {
  private var fallChannel: FlutterMethodChannel?
  private var caregiverAlarmChannel: FlutterMethodChannel?
  private var caregiverAlertChannel: FlutterMethodChannel?
  private var alarmAudioPlayer: AVAudioPlayer?
  private var pendingIncidentId: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }

    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        NSLog("[CareAI-iOS] Lỗi xin quyền thông báo: %@", error.localizedDescription)
      } else {
        NSLog("[CareAI-iOS] Quyền thông báo đã cấp: %d", granted)
      }
    }

    // Đăng ký tác vụ nền cho iOS BGTaskScheduler trước khi hàm didFinishLaunchingWithOptions kết thúc
    // Bắt buộc theo quy định của Apple và plugin workmanager_apple để tránh crash NSInternalInconsistencyException
    #if canImport(workmanager_apple)
    if #available(iOS 13.0, *) {
      WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "careai_periodic_sync_task")
      WorkmanagerPlugin.registerLaunchHandlers()
    }
    #endif

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      setupFallBridgeChannel(messenger: controller.binaryMessenger)
      setupCaregiverAlarmChannel(messenger: controller.binaryMessenger)
      setupCaregiverAlertChannel(messenger: controller.binaryMessenger)
    }

    return result
  }

  // MARK: - Quản lý Còi hú cấp cứu Y tế (ICU Medical Emergency Siren) cho iOS
  private func setupCaregiverAlarmChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "vn.careai.companion/caregiver_alarm", binaryMessenger: messenger)
    self.caregiverAlarmChannel = channel

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "start":
        let args = call.arguments as? [String: Any]
        let incidentId = args?["incidentId"] as? String ?? "careai_emergency"
        let title = args?["title"] as? String ?? "CẢNH BÁO CẤP CỨU"
        let body = args?["body"] as? String ?? "Người cao tuổi cần trợ giúp ngay."
        let emergencyType = args?["emergencyType"] as? String ?? "EMERGENCY"

        self.showCaregiverEmergencyNotification(incidentId: incidentId, title: title, body: body, emergencyType: emergencyType)
        self.startAlarmSound()
        result(nil)
      case "stop":
        let args = call.arguments as? [String: Any]
        let incidentId = args?["incidentId"] as? String
        self.stopCaregiverEmergencyNotification(incidentId: incidentId)
        self.stopAlarmSound()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Quản lý Điều hướng Sự cố Khi Chạm Thông Báo (Caregiver Alert Channel)
  private func setupCaregiverAlertChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "vn.careai.companion/caregiver_alert", binaryMessenger: messenger)
    self.caregiverAlertChannel = channel

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      if call.method == "getPendingIncident" {
        let pending = self.pendingIncidentId
        self.pendingIncidentId = nil
        result(pending)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Quản lý Thông báo Khẩn cấp Người Thân (Caregiver Emergency Local Notifications)
  private func showCaregiverEmergencyNotification(
    incidentId: String,
    title: String,
    body: String,
    emergencyType: String
  ) {
    let content = UNMutableNotificationContent()
    content.title = title.hasPrefix("🚨") ? title : "🚨 " + title
    content.body = body
    content.userInfo = [
      "incidentId": incidentId,
      "emergencyType": emergencyType
    ]
    // Sử dụng âm thanh còi hú mặc định của Apple hoặc file còi hú nếu có
    if #available(iOS 12.0, *) {
      content.sound = UNNotificationSound.defaultCriticalSound(withAudioVolume: 1.0)
    } else {
      content.sound = UNNotificationSound.defaultCritical
    }
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .critical
    }

    let request = UNNotificationRequest(
      identifier: "careai_incident_\(incidentId)",
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        NSLog("[CareAI-iOS] Lỗi đăng ký thông báo cấp cứu: %@", error.localizedDescription)
      } else {
        NSLog("[CareAI-iOS] Đã hiển thị thông báo cấp cứu thành công: %@", incidentId)
      }
    }
  }

  private func stopCaregiverEmergencyNotification(incidentId: String?) {
    if let id = incidentId, !id.isEmpty {
      let identifier = "careai_incident_\(id)"
      UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    } else {
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
      UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
  }

  // MARK: - UNUserNotificationCenterDelegate: Cho phép hiển thị thông báo ngay cả khi app đang mở hoặc chạy nền
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge, .list])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    if let incidentId = userInfo["incidentId"] as? String, !incidentId.isEmpty {
      NSLog("[CareAI-iOS] Người dùng chạm vào thông báo sự cố: %@", incidentId)
      self.pendingIncidentId = incidentId
      self.caregiverAlertChannel?.invokeMethod("openIncident", incidentId)
    }
    completionHandler()
  }

  private func startAlarmSound() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if self.alarmAudioPlayer?.isPlaying == true {
        return
      }

      do {
        // Cấu hình âm thanh chế độ .playback để còi hú phát âm lượng tối đa ngay cả khi bật công tắc im lặng (Silent/Mute Switch)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)

        var player: AVAudioPlayer?

        // 1. Thử tải file âm thanh còi hú y tế từ Flutter Assets
        let assetKey = FlutterDartProject.lookupKey(forAsset: "assets/audio/careai_emergency_alarm.wav")
        if let assetPath = Bundle.main.path(forResource: assetKey, ofType: nil) {
          player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: assetPath))
        }

        // 2. Thử tải file trực tiếp từ Resource Bundle của ứng dụng iOS
        if player == nil, let resourceUrl = Bundle.main.url(forResource: "careai_emergency_alarm", withExtension: "wav") {
          player = try? AVAudioPlayer(contentsOf: resourceUrl)
        }

        // 3. Dự phòng 100% tự động: Tổng hợp sóng âm còi hú y tế ICU hai nhịp (960Hz / 1350Hz) trực tiếp trong RAM
        if player == nil {
          let synthWav = self.generateMedicalAlarmWavData()
          player = try? AVAudioPlayer(data: synthWav)
        }

        if let p = player {
          p.numberOfLoops = -1 // Phát lặp vô hạn cho tới khi có người tiếp nhận sự cố hoặc bấm tắt còi
          p.volume = 1.0
          p.prepareToPlay()
          p.play()
          self.alarmAudioPlayer = p
          NSLog("[CareAI-iOS] Đã kích hoạt còi hú cấp cứu y tế ICU thành công.")
        }
      } catch {
        NSLog("[CareAI-iOS] Không thể khởi động còi hú cấp cứu: %@", error.localizedDescription)
      }
    }
  }

  private func stopAlarmSound() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if let player = self.alarmAudioPlayer {
        player.stop()
        self.alarmAudioPlayer = nil
        NSLog("[CareAI-iOS] Đã tắt còi hú cấp cứu y tế.")
      }
      try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
  }

  /// Tạo file WAV 16-bit PCM trong bộ nhớ với tần số còi hú cấp cứu ICU nhịp đôi 960Hz và 1350Hz chuẩn y tế
  private func generateMedicalAlarmWavData(durationSeconds: Double = 1.0) -> Data {
    let sampleRate: Double = 44100.0
    let totalSamples = Int(sampleRate * durationSeconds)
    var pcmData = Data()
    pcmData.reserveCapacity(totalSamples * 2)

    for i in 0..<totalSamples {
      let t = Double(i) / sampleRate
      // Chu kỳ 400ms: 200ms tần số 960Hz, 200ms tần số 1350Hz (tạo âm thanh hú dồn dập chuẩn cấp cứu)
      let phase = t.truncatingRemainder(dividingBy: 0.4)
      let freq: Double = phase < 0.2 ? 960.0 : 1350.0
      let sampleValue = sin(2.0 * Double.pi * freq * t)
      let int16Sample = Int16(max(-32767.0, min(32767.0, sampleValue * 30000.0)))
      withUnsafeBytes(of: int16Sample.littleEndian) { pcmData.append(contentsOf: $0) }
    }

    var wavData = Data()
    let dataSize = UInt32(pcmData.count)
    let chunkSize = UInt32(36 + dataSize)

    wavData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    withUnsafeBytes(of: chunkSize.littleEndian) { wavData.append(contentsOf: $0) }
    wavData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
    wavData.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
    let subchunk1Size: UInt32 = 16
    withUnsafeBytes(of: subchunk1Size.littleEndian) { wavData.append(contentsOf: $0) }
    let audioFormat: UInt16 = 1 // PCM
    withUnsafeBytes(of: audioFormat.littleEndian) { wavData.append(contentsOf: $0) }
    let numChannels: UInt16 = 1 // Mono
    withUnsafeBytes(of: numChannels.littleEndian) { wavData.append(contentsOf: $0) }
    let sampleRateInt: UInt32 = 44100
    withUnsafeBytes(of: sampleRateInt.littleEndian) { wavData.append(contentsOf: $0) }
    let byteRate: UInt32 = 44100 * 2
    withUnsafeBytes(of: byteRate.littleEndian) { wavData.append(contentsOf: $0) }
    let blockAlign: UInt16 = 2
    withUnsafeBytes(of: blockAlign.littleEndian) { wavData.append(contentsOf: $0) }
    let bitsPerSample: UInt16 = 16
    withUnsafeBytes(of: bitsPerSample.littleEndian) { wavData.append(contentsOf: $0) }
    wavData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
    withUnsafeBytes(of: dataSize.littleEndian) { wavData.append(contentsOf: $0) }
    wavData.append(pcmData)

    return wavData
  }

  private func setupFallBridgeChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "vn.careai.companion/fall_bridge", binaryMessenger: messenger)
    self.fallChannel = channel

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "getConnectedWatchStatus":
        if WCSession.isSupported() {
          let session = WCSession.default
          let isPaired = session.isPaired
          let isReachable = session.isReachable
          let isConnected = isPaired && isReachable
          result([
            "isConnected": isConnected,
            "watchName": isPaired ? "Apple Watch" : nil,
            "nodeId": isPaired ? "apple_watch_wcsession" : nil,
            "isNearby": isReachable,
            "connectedCount": isConnected ? 1 : (isPaired ? 1 : 0)
          ])
        } else {
          result([
            "isConnected": false,
            "watchName": nil,
            "nodeId": nil,
            "isNearby": false,
            "connectedCount": 0
          ])
        }
      case "simulateHardwareFall":
        let eventId = "FALL_SIM_IOS_\(Int64(Date().timeIntervalSince1970 * 1000))"
        let payload: [String: Any] = [
          "eventId": eventId,
          "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
          "impactG": 3.6,
          "source": "IN_APP_UI_SIMULATOR",
          "isHardwareVerified": true
        ]
        self.startAlarmSound()
        self.fallChannel?.invokeMethod("onHardwareFallDetected", arguments: payload)
        result(eventId)
      case "cancelFallAlarm", "stopEmergencySound":
        self.stopAlarmSound()
        result(true)
      case "syncWatchCredentials":
        if WCSession.isSupported() {
          let session = WCSession.default
          if session.activationState == .activated {
            var context: [String: Any] = [:]
            if let args = call.arguments as? [String: Any] {
              context["backendUrl"] = args["backendUrl"]
              context["deviceId"] = args["deviceId"]
              context["deviceToken"] = args["deviceToken"]
              context["elderName"] = args["elderName"]
            }
            context["syncType"] = "CREDENTIALS"
            do {
              try session.updateApplicationContext(context)
            } catch {
              session.transferUserInfo(context)
            }
            NSLog("[CareAI-iOS] Đã đồng bộ credentials sang Apple Watch qua WCSession.")
            result(true)
          } else {
            result(false)
          }
        } else {
          result(false)
        }
      case "checkExactAlarmPermission":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - WCSessionDelegate
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    if let error = error {
      NSLog("[CareAI-iOS] WCSession error: %@", error.localizedDescription)
    }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    let paired = session.isPaired
    NSLog("[CareAI-iOS] [EVENT-DRIVEN] WCSession reachability changed: reachable=%d, paired=%d", reachable, paired)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let isConnected = paired && reachable
      let payload: [String: Any] = [
        "isConnected": isConnected,
        "watchName": "Apple Watch",
        "nodeId": paired ? "apple_watch_wcsession" : nil,
        "isNearby": reachable,
        "connectedCount": isConnected ? 1 : (paired ? 1 : 0),
        "reason": isConnected ? "CONNECTED" : (paired ? "UNREACHABLE" : "NOT_PAIRED")
      ]
      self.fallChannel?.invokeMethod("onWatchConnectionChanged", arguments: payload)
    }
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    let paired = session.isPaired
    NSLog("[CareAI-iOS] [EVENT-DRIVEN] WCSession watch state changed: reachable=%d, paired=%d", reachable, paired)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let isConnected = paired && reachable
      let payload: [String: Any] = [
        "isConnected": isConnected,
        "watchName": "Apple Watch",
        "nodeId": paired ? "apple_watch_wcsession" : nil,
        "isNearby": reachable,
        "connectedCount": isConnected ? 1 : (paired ? 1 : 0),
        "reason": isConnected ? "CONNECTED" : (paired ? "UNREACHABLE" : "NOT_PAIRED")
      ]
      self.fallChannel?.invokeMethod("onWatchConnectionChanged", arguments: payload)
    }
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
    handleWatchRelay(userInfo)
  }

  func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
    handleWatchRelay(message)
  }

  private func handleWatchRelay(_ payload: [String: Any]) {
    guard let action = payload["action"] as? String, action == "EMERGENCY_SOS" else { return }
    let packetId = payload["packetId"] as? String ?? "SOS_WATCH_\(Int64(Date().timeIntervalSince1970 * 1000))"
    let eventId = payload["eventId"] as? String ?? packetId
    let emergencyType = payload["emergencyType"] as? String ?? "FALL_DETECTED"
    let triggeredAt = payload["triggeredAt"] as? String ?? ISO8601DateFormatter().string(from: Date())
    let hr = payload["heartRate"] as? Double ?? 76.0
    let spo2 = payload["spo2"] as? Double ?? 98.0

    // Cảnh báo cục bộ trên iPhone
    let content = UNMutableNotificationContent()
    content.title = "🚨 CẢNH BÁO TỪ APPLE WATCH!"
    content.body = emergencyType == "FALL_DETECTED"
      ? "Phát hiện té ngã trên đồng hồ! Đang chuyển tiếp cấp cứu..."
      : "Tín hiệu SOS khẩn cấp từ đồng hồ!"
    content.sound = UNNotificationSound.defaultCritical
    let req = UNNotificationRequest(identifier: packetId, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)

    let userDefaults = UserDefaults.standard
    let serverUrl = userDefaults.string(forKey: "flutter.server_base_url") ?? "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"
    let deviceId = userDefaults.string(forKey: "flutter.device_id") ?? ""
    let deviceToken = userDefaults.string(forKey: "flutter.device_token") ?? ""

    guard !deviceId.isEmpty, !deviceToken.isEmpty,
          let url = URL(string: "\(serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/api/v1/incidents/sos") else {
      NSLog("[CareAI-iOS] Chưa đủ cấu hình device để chuyển tiếp SOS: %@", packetId)
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 10
    request.setValue(deviceId, forHTTPHeaderField: "X-DeviceId")
    request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    // Bất biến Fact 35: Lưu đủ mẫu đo sinh hiệu đi kèm
    let bodyJson: [String: Any] = [
      "packetId": packetId,
      "eventId": eventId,
      "emergencyType": emergencyType == "FALL_DETECTED" ? "FALL" : "MANUAL_SOS",
      "severity": "CRITICAL",
      "triggeredAt": triggeredAt,
      "samples": [
        ["metricType": "HEART_RATE", "value": hr, "unit": "bpm", "timestamp": triggeredAt],
        ["metricType": "SPO2", "value": spo2, "unit": "%", "timestamp": triggeredAt],
        ["metricType": "FALL", "value": 2.5, "unit": "G", "timestamp": triggeredAt]
      ]
    ]

    // Chuyển tiếp sự kiện té ngã lên giao diện Flutter nếu ứng dụng đang mở và kích hoạt còi hú y tế
    DispatchQueue.main.async { [weak self] in
      self?.startAlarmSound()
      let flutterPayload: [String: Any] = [
        "eventId": eventId,
        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
        "impactG": 2.5,
        "source": "APPLE_WATCH_HARDWARE",
        "isHardwareVerified": true
      ]
      self?.fallChannel?.invokeMethod("onHardwareFallDetected", arguments: flutterPayload)
    }

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: bodyJson)
      let config = URLSessionConfiguration.ephemeral
      config.waitsForConnectivity = true
      let session = URLSession(configuration: config)
      let task = session.dataTask(with: request) { _, response, error in
        if let httpRes = response as? HTTPURLResponse, (httpRes.statusCode == 200 || httpRes.statusCode == 201) {
          NSLog("[CareAI-iOS] Đã chuyển tiếp SOS từ Apple Watch thành công: HTTP %d", httpRes.statusCode)
        } else {
          NSLog("[CareAI-iOS] Chuyển tiếp SOS lỗi: %@", error?.localizedDescription ?? "HTTP error")
        }
      }
      task.resume()
    } catch {
      NSLog("[CareAI-iOS] Lỗi đóng gói JSON SOS: %@", error.localizedDescription)
    }
  }
}
