import Flutter
import UIKit
import WatchConnectivity
import UserNotifications
import AVFoundation
import CoreBluetooth
#if canImport(workmanager_apple)
import workmanager_apple
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, WCSessionDelegate, CBCentralManagerDelegate {
  private var fallChannel: FlutterMethodChannel?
  private var caregiverAlarmChannel: FlutterMethodChannel?
  private var caregiverAlertChannel: FlutterMethodChannel?
  private var alarmAudioPlayer: AVAudioPlayer?
  private var pendingIncidentId: String?
  private var pendingFallPayload: [String: Any]?
  private var speechSynthesizer: AVSpeechSynthesizer?
  private var centralManager: CBCentralManager?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])

    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }

    UNUserNotificationCenter.current().delegate = self
    var authOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
    if #available(iOS 15.0, *) {
      authOptions.insert(.timeSensitive)
    }
    UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
      if let error = error {
        NSLog("[CareAI-iOS] Lỗi xin quyền thông báo: %@", error.localizedDescription)
      } else {
        NSLog("[CareAI-iOS] Quyền thông báo đã cấp: %d (timeSensitive included)", granted)
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
      setupChannelsIfNeeded(messenger: controller.binaryMessenger)
    }

    drainRelayOutbox()

    return result
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    drainRelayOutbox()
    if WCSession.isSupported() {
      let session = WCSession.default
      if session.activationState == .activated {
        if !session.receivedApplicationContext.isEmpty {
          let ctxTimestamp = self.getInt64(session.receivedApplicationContext["timestamp"]) ?? 0
          let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
          if ctxTimestamp > 0 && (nowMs - ctxTimestamp) <= 45 * 60 * 1000 {
            handleWatchRelay(session.receivedApplicationContext)
          }
        }
        if session.isReachable {
          session.sendMessage(["action": "REQUEST_TELEMETRY"], replyHandler: { [weak self] reply in
            self?.handleWatchRelay(reply)
          }, errorHandler: nil)
        }
      } else {
        session.activate()
      }
    }
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
    // Sử dụng âm thanh chuông báo chuẩn iOS và mức độ ưu tiên Time-Sensitive để phá vỡ chế độ Im lặng / Focus mode
    content.sound = UNNotificationSound.default
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .timeSensitive
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
      self.caregiverAlertChannel?.invokeMethod("openIncident", arguments: incidentId)
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
          if session.activationState != .activated {
            session.activate()
          }
          let isPaired = session.isPaired
          let isReachable = session.isReachable
          let isAppInstalled = session.isWatchAppInstalled
          let isBtOff = self.centralManager?.state == .poweredOff
          let isConnected = isPaired && !isBtOff
          let storedWatchName = UserDefaults.standard.string(forKey: "careai_apple_watch_name")
          let displayWatchName = storedWatchName ?? (isPaired ? "Apple Watch" : nil)

          NSLog("[CareAI-iOS] Flutter gọi getConnectedWatchStatus: btOff=%d, activationState=%ld, paired=%d, reachable=%d, installed=%d, isConnected=%d",
                isBtOff ? 1 : 0, Int(session.activationState.rawValue), isPaired ? 1 : 0, isReachable ? 1 : 0, isAppInstalled ? 1 : 0, isConnected ? 1 : 0)

          // Kiểm tra độ tươi mới của dữ liệu viễn trắc đã lưu (giữ lại trạng thái gần nhất, chỉ xóa nếu quá cũ > 12 giờ)
          let storedTimestamp = self.getInt64(UserDefaults.standard.object(forKey: "careai_watch_telemetry_timestamp")) ?? 0
          let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
          if storedTimestamp > 0 && (nowMs - storedTimestamp) > 12 * 3600 * 1000 {
            // Dữ liệu viễn trắc đã quá cũ (> 12 giờ): Xóa trạng thái sạc/pin cũ để tránh hiển thị sai lệch
            UserDefaults.standard.removeObject(forKey: "careai_watch_battery_level")
            UserDefaults.standard.removeObject(forKey: "careai_watch_is_charging")
            UserDefaults.standard.removeObject(forKey: "careai_watch_is_worn")
          }

          // Xử lý receivedApplicationContext nếu có dữ liệu hợp lệ
          if !session.receivedApplicationContext.isEmpty {
            let ctxTimestamp = self.getInt64(session.receivedApplicationContext["timestamp"]) ?? 0
            if ctxTimestamp == 0 || (nowMs - ctxTimestamp) <= 12 * 3600 * 1000 {
              self.handleWatchRelay(session.receivedApplicationContext)
            }
          }

          // Yêu cầu đồng hồ gửi định danh và viễn trắc mới nhất nếu có thể kết nối
          if isReachable && !isBtOff {
            let group = DispatchGroup()
            group.enter()
            var hasReplied = false
            session.sendMessage(["action": "REQUEST_TELEMETRY"], replyHandler: { [weak self] reply in
              self?.handleWatchRelay(reply)
              if !hasReplied {
                hasReplied = true
                group.leave()
              }
            }, errorHandler: { _ in
              if !hasReplied {
                hasReplied = true
                group.leave()
              }
            })
            // Chờ tối đa 600ms để nhận kết quả trực tiếp qua Bluetooth trước khi trả lời cho Flutter
            _ = group.wait(timeout: .now() + 0.6)
          } else if isPaired && !isBtOff {
            session.transferUserInfo(["action": "REQUEST_TELEMETRY"])
          }

          var resPayload: [String: Any] = [
            "isConnected": isConnected,
            "isNearby": isReachable && !isBtOff,
            "connectedCount": isConnected ? 1 : 0,
            "reason": isBtOff ? "BLUETOOTH_OFF" : (isConnected ? "CONNECTED" : "NOT_PAIRED"),
            "isPaired": isPaired,
            "isWatchAppInstalled": isAppInstalled
          ]
          if let name = displayWatchName {
            resPayload["watchName"] = name
          }
          if isPaired {
            resPayload["nodeId"] = "apple_watch_wcsession"
          }
          if let battery = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_battery_level")) {
            resPayload["batteryLevel"] = battery
          }
          if let worn = self.getBool(UserDefaults.standard.object(forKey: "careai_watch_is_worn")) {
            resPayload["isWorn"] = worn
          }
          if let charging = self.getBool(UserDefaults.standard.object(forKey: "careai_watch_is_charging")) {
            resPayload["isCharging"] = charging
          }
          result(resPayload)
        } else {
          result([
            "isConnected": false,
            "isNearby": false,
            "connectedCount": 0,
            "reason": "NOT_SUPPORTED",
            "isPaired": false,
            "isWatchAppInstalled": false
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
        let args = call.arguments as? [String: Any]
        let eventId = args?["eventId"] as? String
        if let id = eventId, !id.isEmpty {
          let identifiers = [id, "careai_incident_\(id)", "FALL_\(id)", "SOS_\(id)", "FALL_SIM_IOS_\(id)"]
          UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
          UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        } else {
          UNUserNotificationCenter.current().removeAllDeliveredNotifications()
          UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        self.stopAlarmSound()
        result(true)
      case "syncWatchCredentials":
        if WCSession.isSupported() {
          let session = WCSession.default
          if session.activationState != .activated {
            session.activate()
          }
          var context: [String: Any] = [:]
          if let args = call.arguments as? [String: Any] {
            if let backendUrl = args["backendUrl"] as? String, !backendUrl.isEmpty {
              context["backendUrl"] = backendUrl
              UserDefaults.standard.set(backendUrl, forKey: "careai_backend_url")
            }
            if let deviceId = args["deviceId"] as? String, !deviceId.isEmpty {
              context["deviceId"] = deviceId
              UserDefaults.standard.set(deviceId, forKey: "careai_device_id")
            }
            if let deviceToken = args["deviceToken"] as? String, !deviceToken.isEmpty {
              context["deviceToken"] = deviceToken
              UserDefaults.standard.set(deviceToken, forKey: "careai_device_token")
            }
            if let elderName = args["elderName"] as? String, !elderName.isEmpty {
              context["elderName"] = elderName
              UserDefaults.standard.set(elderName, forKey: "careai_elder_name")
            }
          }
          context["syncType"] = "CREDENTIALS"

          // Đồng bộ đa kênh:
          // 1. updateApplicationContext (lưu giữ cho lần khởi động app trên đồng hồ)
          try? session.updateApplicationContext(context)
          // 2. transferUserInfo (hàng đợi chuyển giao bảo đảm qua Bluetooth trong nền)
          session.transferUserInfo(context)
          // 3. sendMessage tức thì 0ms nếu đồng hồ đang mở sáng
          if session.isReachable {
            session.sendMessage(context, replyHandler: nil, errorHandler: nil)
          }
          drainRelayOutbox()
          NSLog("[CareAI-iOS] Đã đồng bộ credentials sang Apple Watch qua 3 kênh WCSession thành công.")
          result(true)
        } else {
          result(false)
        }
      case "unpairWatch":
        // 1. Xóa thông tin đồng hồ đã lưu trong UserDefaults của iOS
        UserDefaults.standard.removeObject(forKey: "careai_backend_url")
        UserDefaults.standard.removeObject(forKey: "careai_device_id")
        UserDefaults.standard.removeObject(forKey: "careai_device_token")
        UserDefaults.standard.removeObject(forKey: "careai_elder_name")
        UserDefaults.standard.removeObject(forKey: "careai_apple_watch_name")
        UserDefaults.standard.removeObject(forKey: "careai_watch_battery_level")
        UserDefaults.standard.removeObject(forKey: "careai_watch_is_worn")
        UserDefaults.standard.removeObject(forKey: "careai_watch_is_charging")
        UserDefaults.standard.removeObject(forKey: "careai_watch_telemetry_timestamp")

        // 2. Gửi lệnh UNPAIR sang Apple Watch qua 3 kênh WCSession
        if WCSession.isSupported() {
          let session = WCSession.default
          if session.activationState != .activated {
            session.activate()
          }
          let payload: [String: Any] = ["action": "UNPAIR", "syncType": "UNPAIR"]
          try? session.updateApplicationContext(payload)
          session.transferUserInfo(payload)
          if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
          }
          NSLog("[CareAI-iOS] Đã gửi lệnh unpairWatch sang Apple Watch qua WCSession thành công.")
        }
        self.notifyWatchConnectionStatus()
        result(true)
      case "getPendingHardwareFall":
        let pending = self.pendingFallPayload
        self.pendingFallPayload = nil
        result(pending)
      case "checkExactAlarmPermission":
        result(true)
      case "notifyIncidentStatusToWatch":
        if WCSession.isSupported() {
          let session = WCSession.default
          if session.activationState != .activated {
            session.activate()
          }
          let args = call.arguments as? [String: Any] ?? [:]
          let status = args["status"] as? String ?? "RESOLVED"
          let name = args["acknowledgedByName"] as? String ?? ""
          let notes = args["notes"] as? String ?? ""
          let incidentId = args["incidentId"] as? String ?? ""

          let payload: [String: Any] = [
            "action": "INCIDENT_STATUS_CHANGED",
            "status": status,
            "acknowledgedByName": name,
            "notes": notes,
            "incidentId": incidentId
          ]

          try? session.updateApplicationContext(payload)
          session.transferUserInfo(payload)
          if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
          }
          NSLog("[CareAI-iOS] Đã gửi INCIDENT_STATUS_CHANGED (%@, by=%@) sang Apple Watch qua WCSession.", status, name)
          result(true)
        } else {
          result(false)
        }
      case "requestWatchForceSync":
        if WCSession.isSupported() {
          let session = WCSession.default
          if session.activationState != .activated {
            session.activate()
          }
          let payload: [String: Any] = ["action": "FORCE_REFRESH"]
          for transfer in session.outstandingUserInfoTransfers {
            if (transfer.userInfo["action"] as? String) == "FORCE_REFRESH" && !transfer.isTransferring {
              transfer.cancel()
            }
          }
          // Luôn gửi transferUserInfo và updateApplicationContext dự phòng khi màn hình tắt
          session.transferUserInfo(payload)
          try? session.updateApplicationContext(payload)

          if session.isReachable {
            let group = DispatchGroup()
            group.enter()
            var hasFinished = false
            session.sendMessage(payload, replyHandler: { [weak self] reply in
              NSLog("[CareAI-iOS] requestWatchForceSync: Nhận phản hồi viễn trắc trực tiếp từ Watch: %@", String(describing: reply["action"]))
              self?.handleWatchRelay(reply)
              if !hasFinished {
                hasFinished = true
                group.leave()
              }
            }, errorHandler: { error in
              NSLog("[CareAI-iOS] requestWatchForceSync sendMessage error: %@", error.localizedDescription)
              if !hasFinished {
                hasFinished = true
                group.leave()
              }
            })

            DispatchQueue.global().async {
              _ = group.wait(timeout: .now() + 1.2)
              DispatchQueue.main.async { [weak self] in
                self?.notifyWatchConnectionStatus()
                result(true)
              }
            }
          } else {
            if !session.receivedApplicationContext.isEmpty {
              self.handleWatchRelay(session.receivedApplicationContext)
            }
            self.notifyWatchConnectionStatus()
            result(true)
          }
          NSLog("[CareAI-iOS] Đã kích hoạt lệnh FORCE_REFRESH sang Apple Watch qua WCSession.")
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var isChannelsInitialized = false

  func setupChannelsIfNeeded(messenger: FlutterBinaryMessenger) {
    guard !isChannelsInitialized else { return }
    isChannelsInitialized = true
    NSLog("[CareAI-iOS] Khởi tạo các MethodChannel ứng dụng với binaryMessenger...")
    setupFallBridgeChannel(messenger: messenger)
    setupCaregiverAlarmChannel(messenger: messenger)
    setupCaregiverAlertChannel(messenger: messenger)
    setupTtsBridgeChannel(messenger: messenger)
    setupLocationSourceChannel(messenger: messenger)
    setupPowerOptimizationChannel(messenger: messenger)

    // Nếu có sự cố ngã phần cứng tồn đọng khi app vừa mở, đẩy ngay lập tức cho Flutter
    if let pendingFall = self.pendingFallPayload {
      self.fallChannel?.invokeMethod("onHardwareFallDetected", arguments: pendingFall)
      self.pendingFallPayload = nil
    }

    // Nếu WCSession đã hoàn tất kích hoạt, thông báo ngay cho Flutter
    if WCSession.isSupported() && WCSession.default.activationState == .activated {
      notifyWatchConnectionStatus()
    }
  }

  // MARK: - Kênh kiểm tra thiết bị mô phỏng Location Source
  private func setupLocationSourceChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "vn.careai.companion/location_source", binaryMessenger: messenger)
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "isEmulator" {
        #if targetEnvironment(simulator)
        result(true)
        #else
        result(false)
        #endif
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Kênh kiểm tra và điều hướng quyền thông báo & chạy ngầm
  private func setupPowerOptimizationChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "vn.careai.companion/power_optimization", binaryMessenger: messenger)
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "isIgnoringBatteryOptimizations":
        result(true)
      case "requestIgnoreBatteryOptimizations":
        result(true)
      case "openAutostartSettings":
        result(true)
      case "getManufacturer":
        result("Apple")
      case "areNotificationsEnabled":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let enabled = settings.authorizationStatus == .authorized ||
                        settings.authorizationStatus == .provisional ||
                        settings.authorizationStatus == .ephemeral
          DispatchQueue.main.async {
            result(enabled)
          }
        }
      case "canRequestDirectNotificationPermission":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          DispatchQueue.main.async {
            result(settings.authorizationStatus == .notDetermined)
          }
        }
      case "requestNotificationPermission":
        var authOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
        if #available(iOS 15.0, *) {
          authOptions.insert(.timeSensitive)
        }
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, _ in
          DispatchQueue.main.async {
            result(granted)
          }
        }
      case "openNotificationSettings":
        DispatchQueue.main.async {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            if UIApplication.shared.canOpenURL(url) {
              UIApplication.shared.open(url, options: [:], completionHandler: nil)
              result(true)
              return
            }
          }
          result(false)
        }
      case "isBackgroundDataRestricted":
        DispatchQueue.main.async {
          let status = UIApplication.shared.backgroundRefreshStatus
          let isRestricted = (status == .denied || status == .restricted)
          result(isRestricted)
        }
      case "openBackgroundDataSettings":
        DispatchQueue.main.async {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            if UIApplication.shared.canOpenURL(url) {
              UIApplication.shared.open(url, options: [:], completionHandler: nil)
              result(true)
              return
            }
          }
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Hướng dẫn Y tế Bằng Giọng nói Native iOS (Medical Voice Guidance TTS)
  private func setupTtsBridgeChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "vn.careai.companion/tts_bridge", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "speak":
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String, !text.isEmpty else {
          result(false)
          return
        }
        if self.speechSynthesizer == nil {
          self.speechSynthesizer = AVSpeechSynthesizer()
        }
        if self.speechSynthesizer?.isSpeaking == true {
          self.speechSynthesizer?.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        self.speechSynthesizer?.speak(utterance)
        result(true)
      case "stop":
        self.speechSynthesizer?.stopSpeaking(at: .immediate)
        result(true)
      case "isLanguageAvailable":
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let hasVi = voices.contains { $0.language.starts(with: "vi") }
        result(hasVi)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    setupChannelsIfNeeded(messenger: messenger)
  }

  // MARK: - CBCentralManagerDelegate: Lắng nghe trạng thái Bluetooth phần cứng thời gian thực (0.1s)
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    NSLog("[CareAI-iOS] [EVENT-DRIVEN] Bluetooth centralManager state changed: %ld", central.state.rawValue)
    notifyWatchConnectionStatus()
  }

  // MARK: - WCSession Notification Helper
  private func notifyWatchConnectionStatus(session: WCSession? = nil) {
    guard WCSession.isSupported() else { return }
    let s = session ?? WCSession.default
    let isPaired = s.isPaired
    let isReachable = s.isReachable
    let isAppInstalled = s.isWatchAppInstalled
    let isBtOff = centralManager?.state == .poweredOff
    let isConnected = isPaired && !isBtOff
    let storedWatchName = UserDefaults.standard.string(forKey: "careai_apple_watch_name")
    let displayWatchName = storedWatchName ?? (isPaired ? "Apple Watch" : nil)

    NSLog("[CareAI-iOS] notifyWatchConnectionStatus: channelReady=%d, btOff=%d, activationState=%ld, paired=%d, isConnected=%d, name=%@",
          self.fallChannel != nil ? 1 : 0, isBtOff ? 1 : 0, Int(s.activationState.rawValue), isPaired ? 1 : 0, isConnected ? 1 : 0, displayWatchName ?? "nil")

    var payload: [String: Any] = [
      "isConnected": isConnected,
      "isNearby": isReachable && !isBtOff,
      "connectedCount": isConnected ? 1 : 0,
      "reason": isBtOff ? "BLUETOOTH_OFF" : (isConnected ? "CONNECTED" : "NOT_PAIRED"),
      "isPaired": isPaired,
      "isWatchAppInstalled": isAppInstalled
    ]
    if let name = displayWatchName {
      payload["watchName"] = name
    }
    if isPaired {
      payload["nodeId"] = "apple_watch_wcsession"
    }
    if let battery = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_battery_level")) {
      payload["batteryLevel"] = battery
    }
    if let worn = self.getBool(UserDefaults.standard.object(forKey: "careai_watch_is_worn")) {
      payload["isWorn"] = worn
    }
    if let charging = self.getBool(UserDefaults.standard.object(forKey: "careai_watch_is_charging")) {
      payload["isCharging"] = charging
    }
    if let steps = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_today_steps")), steps > 0 {
      payload["todaySteps"] = steps
    }
    if let hr = self.getDouble(UserDefaults.standard.object(forKey: "careai_watch_heart_rate")), hr > 0 {
      payload["heartRate"] = hr
    }
    if let spo2 = self.getDouble(UserDefaults.standard.object(forKey: "careai_watch_spo2")), spo2 > 0 {
      payload["spo2"] = spo2
    }
    if let sys = self.getDouble(UserDefaults.standard.object(forKey: "careai_watch_bp_systolic")), sys > 0 {
      payload["bpSystolic"] = sys
    }
    if let dia = self.getDouble(UserDefaults.standard.object(forKey: "careai_watch_bp_diastolic")), dia > 0 {
      payload["bpDiastolic"] = dia
    }
    if let sleep = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_sleep_minutes")), sleep > 0 {
      payload["sleepMinutes"] = sleep
    }
    if let deep = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_deep_sleep_minutes")), deep > 0 {
      payload["deepSleepMinutes"] = deep
    }
    if let core = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_core_sleep_minutes")), core > 0 {
      payload["coreSleepMinutes"] = core
    }
    if let rem = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_rem_sleep_minutes")), rem > 0 {
      payload["remSleepMinutes"] = rem
    }
    if let awake = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_awake_minutes")), awake > 0 {
      payload["awakeMinutes"] = awake
    }
    if let wake = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_wake_count")), wake > 0 {
      payload["wakeCount"] = wake
    }
    if let minHr = self.getDouble(UserDefaults.standard.object(forKey: "careai_watch_min_sleeping_hr")), minHr > 0 {
      payload["minSleepingHr"] = minHr
    }
    if let avgHr = self.getDouble(UserDefaults.standard.object(forKey: "careai_watch_avg_sleeping_hr")), avgHr > 0 {
      payload["avgSleepingHr"] = avgHr
    }
    if let minSpo2 = self.getDouble(UserDefaults.standard.object(forKey: "careai_watch_min_night_spo2")), minSpo2 > 0 {
      payload["minNightSpo2"] = minSpo2
    }
    if let dips = self.getInt(UserDefaults.standard.object(forKey: "careai_watch_night_spo2_dips")), dips > 0 {
      payload["nightSpo2DipsCount"] = dips
    }
    if let apnea = UserDefaults.standard.string(forKey: "careai_watch_breathing_disturbances"), !apnea.isEmpty {
      payload["breathingDisturbances"] = apnea
    }
    if let supported = UserDefaults.standard.object(forKey: "careai_watch_supported_metrics") as? [String] {
      payload["supportedMetrics"] = supported
    }

    DispatchQueue.main.async { [weak self] in
      self?.fallChannel?.invokeMethod("onWatchConnectionChanged", arguments: payload)
    }
  }

  // MARK: - WCSessionDelegate
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    if let error = error {
      NSLog("[CareAI-iOS] WCSession error: %@", error.localizedDescription)
    } else {
      NSLog("[CareAI-iOS] WCSession activation completed: state=%d, paired=%d, installed=%d, reachable=%d",
            activationState.rawValue, session.isPaired, session.isWatchAppInstalled, session.isReachable)
    }
    if !session.receivedApplicationContext.isEmpty {
      let ctxTimestamp = getInt64(session.receivedApplicationContext["timestamp"]) ?? 0
      let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
      if ctxTimestamp > 0 && (nowMs - ctxTimestamp) <= 45 * 60 * 1000 {
        handleWatchRelay(session.receivedApplicationContext)
      }
    }
    notifyWatchConnectionStatus(session: session)
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    NSLog("[CareAI-iOS] [EVENT-DRIVEN] WCSession reachability changed: reachable=%d, paired=%d", session.isReachable, session.isPaired)
    if session.isReachable {
      session.sendMessage(["action": "REQUEST_TELEMETRY"], replyHandler: nil, errorHandler: nil)
    }
    drainRelayOutbox()
    notifyWatchConnectionStatus(session: session)
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    NSLog("[CareAI-iOS] [EVENT-DRIVEN] WCSession watch state changed: reachable=%d, paired=%d", session.isReachable, session.isPaired)
    notifyWatchConnectionStatus(session: session)
  }

func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
    NSLog("[CareAI-iOS] didReceiveApplicationContext: %@", String(describing: applicationContext["action"]))
    handleWatchRelay(applicationContext)
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
    if let action = userInfo["action"] as? String, action == "TELEMETRY_BATCH" {
      relayTelemetryBatch(userInfo, replyHandler: nil)
      return
    }
    handleWatchRelay(userInfo)
  }

  func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
    if let action = message["action"] as? String, action == "TELEMETRY_BATCH" {
      relayTelemetryBatch(message, replyHandler: nil)
      return
    }
    handleWatchRelay(message)
  }

  func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
    if let action = message["action"] as? String, action == "TELEMETRY_BATCH" {
      relayTelemetryBatch(message, replyHandler: replyHandler)
      return
    }
    handleWatchRelay(message)
    replyHandler(["status": "OK"])
  }

  private func relayTelemetryBatch(_ payload: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
    // Lưu ngay trạng thái pin và đeo vào UserDefaults và thông báo tức thì cho Flutter
    let batteryLevel = self.getInt(payload["batteryLevel"])
    let isCharging = self.getBool(payload["isCharging"])
    let isWorn = self.getBool(payload["isWorn"])
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let timestamp = self.getInt64(payload["timestamp"]) ?? nowMs

    if let batteryLevel = batteryLevel {
      UserDefaults.standard.set(batteryLevel, forKey: "careai_watch_battery_level")
      UserDefaults.standard.set(timestamp, forKey: "careai_watch_telemetry_timestamp")
    }
    if let isCharging = isCharging {
      UserDefaults.standard.set(isCharging, forKey: "careai_watch_is_charging")
    }
    if let isWorn = isWorn {
      UserDefaults.standard.set(isWorn, forKey: "careai_watch_is_worn")
    }
    if batteryLevel != nil || isCharging != nil || isWorn != nil {
      DispatchQueue.main.async { [weak self] in
        self?.notifyWatchConnectionStatus()
      }
    }

    enqueueRelayBatch(payload)
    replyHandler?(["status": "OK"])
  }

  // MARK: - Quản lý Hàng Đợi Viễn Trắc Bền Vững (Store-and-Forward Relay Outbox)
  private let relayOutboxQueue = DispatchQueue(label: "vn.careai.relay.outbox")
  private var isDrainingRelayOutbox = false

  private var relayOutboxURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir.appendingPathComponent("careai_relay_outbox.json")
  }

  private func loadRelayOutbox() -> [[String: Any]] {
    guard let data = try? Data(contentsOf: relayOutboxURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }
    return json
  }

  private func saveRelayOutbox(_ list: [[String: Any]]) -> Bool {
    do {
      let data = try JSONSerialization.data(withJSONObject: list, options: [])
      try data.write(to: relayOutboxURL, options: .atomic)
      return true
    } catch {
      NSLog("[CareAI-iOS] [RELAY_OUTBOX] Lỗi lưu đĩa hàng đợi viễn trắc: %@", error.localizedDescription)
      return false
    }
  }

  private func enqueueRelayBatch(_ payload: [String: Any]) {
    relayOutboxQueue.async { [weak self] in
      guard let self = self else { return }
      var current = self.loadRelayOutbox()
      let batchId = payload["batchId"] as? String ?? ""
      if !batchId.isEmpty && current.contains(where: { ($0["batchId"] as? String) == batchId }) {
        return
      }
      current.append(payload)
      _ = self.saveRelayOutbox(current)
      self.drainRelayOutboxLocked()
    }
  }

  func drainRelayOutbox() {
    relayOutboxQueue.async { [weak self] in
      self?.drainRelayOutboxLocked()
    }
  }

  private func drainRelayOutboxLocked() {
    guard !isDrainingRelayOutbox else { return }
    isDrainingRelayOutbox = true
    processNextRelayBatchLocked()
  }

  private func processNextRelayBatchLocked() {
    let current = loadRelayOutbox()
    guard let batch = current.first else {
      isDrainingRelayOutbox = false
      return
    }

    let batchId = batch["batchId"] as? String ?? "UNKNOWN"
    let samples = batch["samples"] as? [[String: Any]] ?? []

    // Cập nhật trạng thái pin và đeo nếu có đính kèm trong batch viễn trắc
    let batteryLevel = self.getInt(batch["batteryLevel"])
    let isCharging = self.getBool(batch["isCharging"])
    let isWorn = self.getBool(batch["isWorn"])
    if let batteryLevel = batteryLevel { UserDefaults.standard.set(batteryLevel, forKey: "careai_watch_battery_level") }
    if let isCharging = isCharging { UserDefaults.standard.set(isCharging, forKey: "careai_watch_is_charging") }
    if let isWorn = isWorn { UserDefaults.standard.set(isWorn, forKey: "careai_watch_is_worn") }
    if batteryLevel != nil || isCharging != nil || isWorn != nil {
      let storedWatchName = UserDefaults.standard.string(forKey: "careai_apple_watch_name") ?? "Apple Watch"
      self.syncWatchStateToAzure(
        watchModel: storedWatchName,
        batteryLevel: batteryLevel,
        isCharging: isCharging,
        isWorn: isWorn
      )
      DispatchQueue.main.async { [weak self] in
        self?.notifyWatchConnectionStatus()
      }
    }

    guard !samples.isEmpty else {
      var remaining = current
      remaining.removeAll { ($0["batchId"] as? String) == batchId }
      _ = saveRelayOutbox(remaining)
      processNextRelayBatchLocked()
      return
    }

    let userDefaults = UserDefaults.standard
    let serverUrl = userDefaults.string(forKey: "careai_backend_url")
      ?? userDefaults.string(forKey: "flutter.server_base_url")
      ?? userDefaults.string(forKey: "flutter.caregiver_server_url")
      ?? "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"

    var deviceId = (batch["deviceId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if deviceId.isEmpty {
      deviceId = userDefaults.string(forKey: "careai_device_id")
        ?? userDefaults.string(forKey: "flutter.device_id")
        ?? ""
    }

    var deviceToken = (batch["deviceToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if deviceToken.isEmpty {
      deviceToken = userDefaults.string(forKey: "careai_device_token")
        ?? userDefaults.string(forKey: "flutter.device_token")
        ?? ""
    }

    let trimmedServerUrl = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !deviceId.isEmpty, !deviceToken.isEmpty,
          let url = URL(string: "\(trimmedServerUrl)/api/v1/telemetry/ingest") else {
      NSLog("[CareAI-iOS] [RELAY_OUTBOX] Chưa có thông tin xác thực để gửi mẻ %@, giữ lại đĩa iPhone chờ xác thực.", batchId)
      isDrainingRelayOutbox = false
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue(deviceId, forHTTPHeaderField: "X-DeviceId")
    request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let bodyJson: [String: Any] = [
      "batchId": batchId,
      "samples": samples
    ]

    var bgTaskId: UIBackgroundTaskIdentifier = .invalid
    bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "CareAI-Drain-RelayOutbox") {
      if bgTaskId != .invalid {
        UIApplication.shared.endBackgroundTask(bgTaskId)
        bgTaskId = .invalid
      }
    }

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: bodyJson)
      let config = URLSessionConfiguration.ephemeral
      config.waitsForConnectivity = true
      let session = URLSession(configuration: config)
      let task = session.dataTask(with: request) { [weak self] _, response, error in
        defer {
          if bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = .invalid
          }
        }
        guard let self = self else { return }
        self.relayOutboxQueue.async {
          if let httpRes = response as? HTTPURLResponse, (httpRes.statusCode == 200 || httpRes.statusCode == 201 || httpRes.statusCode == 202) {
            NSLog("[CareAI-iOS] [RELAY_OUTBOX] Đã nạp thành công mẻ %@ (%d mẫu) lên Azure (HTTP %d). Xóa khỏi đĩa iPhone.", batchId, samples.count, httpRes.statusCode)
            var currentList = self.loadRelayOutbox()
            currentList.removeAll { ($0["batchId"] as? String) == batchId }
            _ = self.saveRelayOutbox(currentList)
            self.processNextRelayBatchLocked()
          } else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            NSLog("[CareAI-iOS] [RELAY_OUTBOX] Gửi mẻ %@ lên Azure thất bại (HTTP %d): %@. Giữ lại trên đĩa iPhone chờ retry.", batchId, code, error?.localizedDescription ?? "HTTP error")
            self.isDrainingRelayOutbox = false
          }
        }
      }
      task.resume()
    } catch {
      if bgTaskId != .invalid {
        UIApplication.shared.endBackgroundTask(bgTaskId)
        bgTaskId = .invalid
      }
      NSLog("[CareAI-iOS] [RELAY_OUTBOX] Lỗi đóng gói JSON batch: %@", error.localizedDescription)
      isDrainingRelayOutbox = false
    }
  }

  // MARK: - Native Azure Cloud Relay for Watch Status (Background Capable)
  private func syncWatchStateToAzure(watchModel: String, batteryLevel: Int?, isCharging: Bool?, isWorn: Bool?, todaySteps: Int? = nil, heartRate: Double? = nil, spo2: Double? = nil) {
    let userDefaults = UserDefaults.standard
    let serverUrl = userDefaults.string(forKey: "careai_backend_url")
      ?? userDefaults.string(forKey: "flutter.server_base_url")
      ?? userDefaults.string(forKey: "flutter.caregiver_server_url")
      ?? "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"

    var deviceId = userDefaults.string(forKey: "careai_device_id")
      ?? userDefaults.string(forKey: "flutter.device_id")
      ?? ""
    var deviceToken = userDefaults.string(forKey: "careai_device_token")
      ?? userDefaults.string(forKey: "flutter.device_token")
      ?? ""

    let trimmedServerUrl = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !deviceId.isEmpty, !deviceToken.isEmpty,
          let url = URL(string: "\(trimmedServerUrl)/api/v1/devices/sync-watch") else {
      NSLog("[CareAI-iOS] [SYNC_WATCH_AZURE] Chưa đủ cấu hình device/url để sync-watch: deviceId=%@", deviceId)
      return
    }

    var bodyMap: [String: Any] = [
      "watchModel": watchModel,
      "isConnected": true
    ]
    if let isWorn = isWorn { bodyMap["isWorn"] = isWorn }
    if let isCharging = isCharging { bodyMap["isCharging"] = isCharging }
    if let batteryLevel = batteryLevel { bodyMap["batteryLevel"] = batteryLevel }
    if let todaySteps = todaySteps, todaySteps > 0 { bodyMap["todaySteps"] = todaySteps }
    if let heartRate = heartRate, heartRate > 0 { bodyMap["heartRate"] = heartRate }
    if let spo2 = spo2, spo2 > 0 { bodyMap["spo2"] = spo2 }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 10
    request.setValue(deviceId, forHTTPHeaderField: "X-DeviceId")
    request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var bgTaskId: UIBackgroundTaskIdentifier = .invalid
    bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "CareAI-NativeSyncWatchState") {
      if bgTaskId != .invalid {
        UIApplication.shared.endBackgroundTask(bgTaskId)
        bgTaskId = .invalid
      }
    }

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: bodyMap)
      let config = URLSessionConfiguration.ephemeral
      let session = URLSession(configuration: config)
      let task = session.dataTask(with: request) { _, response, error in
        defer {
          if bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = .invalid
          }
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if statusCode == 200 || statusCode == 201 || statusCode == 204 {
          NSLog("[CareAI-iOS] [SYNC_WATCH_AZURE] Đã đồng bộ trạng thái Apple Watch lên Azure thành công: HTTP %d (pin=%@, sạc=%@, đeo=%@)",
                statusCode, String(describing: batteryLevel), String(describing: isCharging), String(describing: isWorn))
        } else {
          NSLog("[CareAI-iOS] [SYNC_WATCH_AZURE] Đồng bộ trạng thái Apple Watch thất bại (HTTP %d): %@", statusCode, error?.localizedDescription ?? "HTTP error")
        }
      }
      task.resume()
    } catch {
      if bgTaskId != .invalid {
        UIApplication.shared.endBackgroundTask(bgTaskId)
        bgTaskId = .invalid
      }
      NSLog("[CareAI-iOS] [SYNC_WATCH_AZURE] Lỗi đóng gói JSON sync-watch: %@", error.localizedDescription)
    }
  }

  private func getInt64(_ val: Any?) -> Int64? {
    if let num = val as? NSNumber { return num.int64Value }
    if let i = val as? Int64 { return i }
    if let i = val as? Int { return Int64(i) }
    return nil
  }

  private func getInt(_ val: Any?) -> Int? {
    if let num = val as? NSNumber { return num.intValue }
    if let i = val as? Int { return i }
    return nil
  }

  private func getBool(_ val: Any?) -> Bool? {
    if let num = val as? NSNumber { return num.boolValue }
    if let b = val as? Bool { return b }
    return nil
  }

  private func getDouble(_ val: Any?) -> Double? {
    if let num = val as? NSNumber { return num.doubleValue }
    if let d = val as? Double { return d }
    if let f = val as? Float { return Double(f) }
    return nil
  }

  private func handleWatchRelay(_ payload: [String: Any]) {
    guard let action = payload["action"] as? String else { return }

    if action == "WATCH_TELEMETRY" {
      let incomingTimestamp = getInt64(payload["timestamp"]) ?? 0
      let storedTimestamp = getInt64(UserDefaults.standard.object(forKey: "careai_watch_telemetry_timestamp")) ?? 0
      let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

      // Bỏ qua nếu payload cũ hơn timestamp đã được ghi nhận trước đó (cho phép lệch tối đa 60 giây do trôi đồng hồ)
      if incomingTimestamp > 0 && storedTimestamp > 0 && (storedTimestamp - incomingTimestamp) > 60 * 1000 {
        NSLog("[CareAI-iOS] [WATCH_TELEMETRY] Bỏ qua payload cũ: incoming=%lld < stored=%lld", incomingTimestamp, storedTimestamp)
        return
      }

      // Bỏ qua nếu context quá hạn (> 12 giờ)
      if incomingTimestamp > 0 && (nowMs - incomingTimestamp) > 12 * 3600 * 1000 {
        NSLog("[CareAI-iOS] [WATCH_TELEMETRY] Bỏ qua context quá hạn: tuổi = %lld giây", (nowMs - incomingTimestamp) / 1000)
        return
      }

      let effectiveTimestamp = incomingTimestamp > 0 ? incomingTimestamp : nowMs
      UserDefaults.standard.set(effectiveTimestamp, forKey: "careai_watch_telemetry_timestamp")

      let isWorn = getBool(payload["isWorn"])
      let isCharging = getBool(payload["isCharging"])
      let batteryLevel = getInt(payload["batteryLevel"])
      let todaySteps = getInt(payload["todaySteps"])
      let heartRate = getDouble(payload["heartRate"])
      let spo2 = getDouble(payload["spo2"])
      let bpSystolic = getDouble(payload["bpSystolic"])
      let bpDiastolic = getDouble(payload["bpDiastolic"])
      let sleepMinutes = getInt(payload["sleepMinutes"])
      let deepSleepMinutes = getInt(payload["deepSleepMinutes"])
      let coreSleepMinutes = getInt(payload["coreSleepMinutes"])
      let remSleepMinutes = getInt(payload["remSleepMinutes"])
      let awakeMinutes = getInt(payload["awakeMinutes"])
      let wakeCount = getInt(payload["wakeCount"])
      let minSleepingHr = getDouble(payload["minSleepingHr"])
      let avgSleepingHr = getDouble(payload["avgSleepingHr"])
      let minNightSpo2 = getDouble(payload["minNightSpo2"])
      let nightSpo2DipsCount = getInt(payload["nightSpo2DipsCount"])
      let breathingDisturbances = payload["breathingDisturbances"] as? String
      let supportedMetrics = payload["supportedMetrics"] as? [String]

      let storedWatchName = UserDefaults.standard.string(forKey: "careai_apple_watch_name")
      let rawWatchModel = payload["watchModel"] as? String
      let watchModel = (rawWatchModel != nil && rawWatchModel != "Apple Watch" && !rawWatchModel!.isEmpty)
        ? rawWatchModel!
        : (storedWatchName ?? rawWatchModel ?? "Apple Watch")
      if watchModel != "Apple Watch" {
        UserDefaults.standard.set(watchModel, forKey: "careai_apple_watch_name")
      }
      NSLog("[CareAI-iOS] [WATCH_TELEMETRY] Received: model=%@, worn=%@, charging=%@, battery=%@, steps=%@, hr=%@, spo2=%@, bp=%@/%@, sleep=%@, deep=%@, apnea=%@",
            watchModel, String(describing: isWorn), String(describing: isCharging), String(describing: batteryLevel),
            String(describing: todaySteps), String(describing: heartRate), String(describing: spo2),
            String(describing: bpSystolic), String(describing: bpDiastolic), String(describing: sleepMinutes),
            String(describing: deepSleepMinutes), String(describing: breathingDisturbances))

      if let isWorn = isWorn { UserDefaults.standard.set(isWorn, forKey: "careai_watch_is_worn") }
      if let isCharging = isCharging { UserDefaults.standard.set(isCharging, forKey: "careai_watch_is_charging") }
      if let batteryLevel = batteryLevel { UserDefaults.standard.set(batteryLevel, forKey: "careai_watch_battery_level") }
      if let todaySteps = todaySteps, todaySteps > 0 { UserDefaults.standard.set(todaySteps, forKey: "careai_watch_today_steps") }
      if let heartRate = heartRate, heartRate > 0 { UserDefaults.standard.set(heartRate, forKey: "careai_watch_heart_rate") }
      if let spo2 = spo2, spo2 > 0 { UserDefaults.standard.set(spo2, forKey: "careai_watch_spo2") }
      if let bpSystolic = bpSystolic, bpSystolic > 0 { UserDefaults.standard.set(bpSystolic, forKey: "careai_watch_bp_systolic") }
      if let bpDiastolic = bpDiastolic, bpDiastolic > 0 { UserDefaults.standard.set(bpDiastolic, forKey: "careai_watch_bp_diastolic") }
      if let sleepMinutes = sleepMinutes, sleepMinutes > 0 { UserDefaults.standard.set(sleepMinutes, forKey: "careai_watch_sleep_minutes") }
      if let deepSleepMinutes = deepSleepMinutes, deepSleepMinutes > 0 { UserDefaults.standard.set(deepSleepMinutes, forKey: "careai_watch_deep_sleep_minutes") }
      if let coreSleepMinutes = coreSleepMinutes, coreSleepMinutes > 0 { UserDefaults.standard.set(coreSleepMinutes, forKey: "careai_watch_core_sleep_minutes") }
      if let remSleepMinutes = remSleepMinutes, remSleepMinutes > 0 { UserDefaults.standard.set(remSleepMinutes, forKey: "careai_watch_rem_sleep_minutes") }
      if let awakeMinutes = awakeMinutes, awakeMinutes > 0 { UserDefaults.standard.set(awakeMinutes, forKey: "careai_watch_awake_minutes") }
      if let wakeCount = wakeCount, wakeCount > 0 { UserDefaults.standard.set(wakeCount, forKey: "careai_watch_wake_count") }
      if let minSleepingHr = minSleepingHr, minSleepingHr > 0 { UserDefaults.standard.set(minSleepingHr, forKey: "careai_watch_min_sleeping_hr") }
      if let avgSleepingHr = avgSleepingHr, avgSleepingHr > 0 { UserDefaults.standard.set(avgSleepingHr, forKey: "careai_watch_avg_sleeping_hr") }
      if let minNightSpo2 = minNightSpo2, minNightSpo2 > 0 { UserDefaults.standard.set(minNightSpo2, forKey: "careai_watch_min_night_spo2") }
      if let nightSpo2DipsCount = nightSpo2DipsCount, nightSpo2DipsCount > 0 { UserDefaults.standard.set(nightSpo2DipsCount, forKey: "careai_watch_night_spo2_dips") }
      if let breathingDisturbances = breathingDisturbances, !breathingDisturbances.isEmpty { UserDefaults.standard.set(breathingDisturbances, forKey: "careai_watch_breathing_disturbances") }
      if let supportedMetrics = supportedMetrics { UserDefaults.standard.set(supportedMetrics, forKey: "careai_watch_supported_metrics") }

      // Đồng bộ trực tiếp lên Azure Database ở tầng Native nền (không phụ thuộc vào việc người già mở app hay unlock iPhone)
      self.syncWatchStateToAzure(
        watchModel: watchModel,
        batteryLevel: batteryLevel,
        isCharging: isCharging,
        isWorn: isWorn,
        todaySteps: todaySteps,
        heartRate: heartRate,
        spo2: spo2
      )

      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        var map: [String: Any] = [
          "isConnected": true,
          "watchName": watchModel,
          "nodeId": "apple_watch_wcsession",
          "isNearby": true,
          "connectedCount": 1,
          "reason": "CONNECTED",
          "isPaired": true
        ]
        if let isWorn = isWorn { map["isWorn"] = isWorn }
        if let isCharging = isCharging { map["isCharging"] = isCharging }
        if let batteryLevel = batteryLevel { map["batteryLevel"] = batteryLevel }
        if let todaySteps = todaySteps, todaySteps > 0 { map["todaySteps"] = todaySteps }
        if let heartRate = heartRate, heartRate > 0 { map["heartRate"] = heartRate }
        if let spo2 = spo2, spo2 > 0 { map["spo2"] = spo2 }
        if let bpSystolic = bpSystolic, bpSystolic > 0 { map["bpSystolic"] = bpSystolic }
        if let bpDiastolic = bpDiastolic, bpDiastolic > 0 { map["bpDiastolic"] = bpDiastolic }
        if let sleepMinutes = sleepMinutes, sleepMinutes > 0 { map["sleepMinutes"] = sleepMinutes }
        if let deepSleepMinutes = deepSleepMinutes, deepSleepMinutes > 0 { map["deepSleepMinutes"] = deepSleepMinutes }
        if let coreSleepMinutes = coreSleepMinutes, coreSleepMinutes > 0 { map["coreSleepMinutes"] = coreSleepMinutes }
        if let remSleepMinutes = remSleepMinutes, remSleepMinutes > 0 { map["remSleepMinutes"] = remSleepMinutes }
        if let awakeMinutes = awakeMinutes, awakeMinutes > 0 { map["awakeMinutes"] = awakeMinutes }
        if let wakeCount = wakeCount, wakeCount > 0 { map["wakeCount"] = wakeCount }
        if let minSleepingHr = minSleepingHr, minSleepingHr > 0 { map["minSleepingHr"] = minSleepingHr }
        if let avgSleepingHr = avgSleepingHr, avgSleepingHr > 0 { map["avgSleepingHr"] = avgSleepingHr }
        if let minNightSpo2 = minNightSpo2, minNightSpo2 > 0 { map["minNightSpo2"] = minNightSpo2 }
        if let nightSpo2DipsCount = nightSpo2DipsCount, nightSpo2DipsCount > 0 { map["nightSpo2DipsCount"] = nightSpo2DipsCount }
        if let breathingDisturbances = breathingDisturbances, !breathingDisturbances.isEmpty { map["breathingDisturbances"] = breathingDisturbances }
        if let supportedMetrics = supportedMetrics { map["supportedMetrics"] = supportedMetrics }
        self.fallChannel?.invokeMethod("onWatchConnectionChanged", arguments: map)
      }
      return
    }

    if action == "WATCH_UNPAIRED" {
      UserDefaults.standard.removeObject(forKey: "careai_apple_watch_name")
      UserDefaults.standard.removeObject(forKey: "careai_watch_battery_level")
      UserDefaults.standard.removeObject(forKey: "careai_watch_is_worn")
      UserDefaults.standard.removeObject(forKey: "careai_watch_is_charging")
      UserDefaults.standard.removeObject(forKey: "careai_watch_telemetry_timestamp")
      UserDefaults.standard.removeObject(forKey: "careai_watch_today_steps")
      UserDefaults.standard.removeObject(forKey: "careai_watch_heart_rate")
      UserDefaults.standard.removeObject(forKey: "careai_watch_spo2")
      UserDefaults.standard.removeObject(forKey: "careai_watch_bp_systolic")
      UserDefaults.standard.removeObject(forKey: "careai_watch_bp_diastolic")
      UserDefaults.standard.removeObject(forKey: "careai_watch_sleep_minutes")
      UserDefaults.standard.removeObject(forKey: "careai_watch_deep_sleep_minutes")
      UserDefaults.standard.removeObject(forKey: "careai_watch_core_sleep_minutes")
      UserDefaults.standard.removeObject(forKey: "careai_watch_rem_sleep_minutes")
      UserDefaults.standard.removeObject(forKey: "careai_watch_awake_minutes")
      UserDefaults.standard.removeObject(forKey: "careai_watch_wake_count")
      UserDefaults.standard.removeObject(forKey: "careai_watch_min_sleeping_hr")
      UserDefaults.standard.removeObject(forKey: "careai_watch_avg_sleeping_hr")
      UserDefaults.standard.removeObject(forKey: "careai_watch_min_night_spo2")
      UserDefaults.standard.removeObject(forKey: "careai_watch_night_spo2_dips")
      UserDefaults.standard.removeObject(forKey: "careai_watch_breathing_disturbances")
      UserDefaults.standard.removeObject(forKey: "careai_watch_supported_metrics")
      NSLog("[CareAI-iOS] Nhận thông báo WATCH_UNPAIRED từ Apple Watch. Đã xóa trạng thái ghép nối đồng hồ.")
      notifyWatchConnectionStatus()
      return
    }

    if action == "WATCH_DEVICE_INFO" {
      let rawWatchName = payload["watchName"] as? String
      let rawName = payload["rawName"] as? String
      let chosenName = (rawWatchName != nil && !rawWatchName!.isEmpty && rawWatchName != "Apple Watch")
        ? rawWatchName!
        : ((rawName != nil && !rawName!.isEmpty && rawName != "Apple Watch") ? rawName! : nil)

      if let validName = chosenName {
        UserDefaults.standard.set(validName, forKey: "careai_apple_watch_name")
        NSLog("[CareAI-iOS] Đã nhận diện và lưu tên phần cứng Apple Watch từ watchOS: %@", validName)
      }
      if let bat = self.getInt(payload["batteryLevel"]) {
        UserDefaults.standard.set(bat, forKey: "careai_watch_battery_level")
      }
      if let worn = self.getBool(payload["isWorn"]) {
        UserDefaults.standard.set(worn, forKey: "careai_watch_is_worn")
      }
      if let charging = self.getBool(payload["isCharging"]) {
        UserDefaults.standard.set(charging, forKey: "careai_watch_is_charging")
      }
      notifyWatchConnectionStatus()

      let needsCreds = payload["needsCredentials"] as? Bool ?? false
      if needsCreds {
        let userDefaults = UserDefaults.standard
        let devId = userDefaults.string(forKey: "careai_device_id") ?? userDefaults.string(forKey: "flutter.device_id") ?? ""
        let devToken = userDefaults.string(forKey: "careai_device_token") ?? userDefaults.string(forKey: "flutter.device_token") ?? ""
        let serverUrl = userDefaults.string(forKey: "careai_backend_url") ?? userDefaults.string(forKey: "flutter.server_base_url") ?? "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"
        let elderName = userDefaults.string(forKey: "careai_elder_name") ?? userDefaults.string(forKey: "flutter.elder_name") ?? ""

        if !devId.isEmpty && !devToken.isEmpty && WCSession.isSupported() {
          let credPayload: [String: Any] = [
            "syncType": "CREDENTIALS",
            "deviceId": devId,
            "deviceToken": devToken,
            "backendUrl": serverUrl,
            "elderName": elderName
          ]
          let session = WCSession.default
          try? session.updateApplicationContext(credPayload)
          session.transferUserInfo(credPayload)
          if session.isReachable {
            session.sendMessage(credPayload, replyHandler: nil, errorHandler: nil)
          }
          NSLog("[CareAI-iOS] Đã tự động đồng bộ credentials sang Apple Watch theo yêu cầu (needsCredentials=true).")
        }
      }
      return
    }

    guard action == "EMERGENCY_SOS" else { return }

    let packetId = payload["packetId"] as? String ?? "SOS_WATCH_\(Int64(Date().timeIntervalSince1970 * 1000))"
    let eventId = payload["eventId"] as? String ?? packetId
    let emergencyType = payload["emergencyType"] as? String ?? "FALL_DETECTED"
    let triggeredAt = payload["triggeredAt"] as? String ?? ISO8601DateFormatter().string(from: Date())
    let hr = payload["heartRate"] as? Double
    let spo2 = payload["spo2"] as? Double

    // Cảnh báo cục bộ trên iPhone
    let content = UNMutableNotificationContent()
    content.title = "🚨 CẢNH BÁO TỪ APPLE WATCH!"
    content.body = emergencyType == "FALL_DETECTED"
      ? "Phát hiện té ngã trên đồng hồ! Đang chuyển tiếp cấp cứu..."
      : "Tín hiệu SOS khẩn cấp từ đồng hồ!"
    content.sound = UNNotificationSound.default
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .timeSensitive
    }
    let req = UNNotificationRequest(identifier: packetId, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)

    let userDefaults = UserDefaults.standard
    let serverUrl = userDefaults.string(forKey: "careai_backend_url")
      ?? userDefaults.string(forKey: "flutter.server_base_url")
      ?? "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"
    let deviceId = userDefaults.string(forKey: "careai_device_id")
      ?? userDefaults.string(forKey: "flutter.device_id") ?? ""
    let deviceToken = userDefaults.string(forKey: "careai_device_token")
      ?? userDefaults.string(forKey: "flutter.device_token") ?? ""

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

    // Bất biến Fact 35: Lưu mẫu đo sinh hiệu thực tế đi kèm (nếu có, không bịa đặt số liệu giả)
    var samples: [[String: Any]] = []
    if emergencyType == "FALL_DETECTED" {
      samples.append(["metricType": "FALL", "value": 2.5, "unit": "G", "timestamp": triggeredAt])
    }
    if let hr = hr, hr > 0 {
      samples.append(["metricType": "HEART_RATE", "value": hr, "unit": "bpm", "timestamp": triggeredAt])
    }
    if let spo2 = spo2, spo2 > 0 {
      samples.append(["metricType": "SPO2", "value": spo2, "unit": "%", "timestamp": triggeredAt])
    }

    let bodyJson: [String: Any] = [
      "packetId": packetId,
      "eventId": eventId,
      "emergencyType": emergencyType == "FALL_DETECTED" ? "FALL" : "MANUAL_SOS",
      "severity": "CRITICAL",
      "triggeredAt": triggeredAt,
      "samples": samples
    ]

    // Chuyển tiếp sự kiện cấp cứu lên giao diện Flutter nếu ứng dụng đang mở và kích hoạt còi hú y tế
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.startAlarmSound()
      if emergencyType == "FALL_DETECTED" {
        let flutterPayload: [String: Any] = [
          "eventId": eventId,
          "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
          "impactG": 2.5,
          "source": "APPLE_WATCH_HARDWARE",
          "isHardwareVerified": true
        ]
        if let channel = self.fallChannel {
          channel.invokeMethod("onHardwareFallDetected", arguments: flutterPayload)
        } else {
          self.pendingFallPayload = flutterPayload
        }
      } else {
        // Cấp cứu SOS thủ công từ Apple Watch: chuyển trực tiếp trạng thái khẩn cấp không qua đếm ngược 30s té ngã
        let flutterPayload: [String: Any] = [
          "packetId": packetId,
          "eventId": eventId,
          "emergencyType": "MANUAL_SOS",
          "triggeredAt": triggeredAt
        ]
        self.fallChannel?.invokeMethod("onManualSosTriggered", arguments: flutterPayload)
      }
    }

    // Bảo vệ tiến trình nền (Background Task): Đảm bảo iOS không suspend app giữa chừng khi đang gửi HTTP SOS
    var bgTaskId: UIBackgroundTaskIdentifier = .invalid
    bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "CareAI-WatchRelay-SOS") {
      if bgTaskId != .invalid {
        UIApplication.shared.endBackgroundTask(bgTaskId)
        bgTaskId = .invalid
      }
    }

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: bodyJson)
      let config = URLSessionConfiguration.ephemeral
      config.waitsForConnectivity = true
      let session = URLSession(configuration: config)
      let task = session.dataTask(with: request) { _, response, error in
        defer {
          if bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = .invalid
          }
        }
        if let httpRes = response as? HTTPURLResponse, (httpRes.statusCode == 200 || httpRes.statusCode == 201) {
          NSLog("[CareAI-iOS] Đã chuyển tiếp SOS từ Apple Watch thành công: HTTP %d", httpRes.statusCode)
        } else {
          NSLog("[CareAI-iOS] Chuyển tiếp SOS lỗi: %@", error?.localizedDescription ?? "HTTP error")
        }
      }
      task.resume()
    } catch {
      if bgTaskId != .invalid {
        UIApplication.shared.endBackgroundTask(bgTaskId)
        bgTaskId = .invalid
      }
      NSLog("[CareAI-iOS] Lỗi đóng gói JSON SOS: %@", error.localizedDescription)
    }
  }
}
