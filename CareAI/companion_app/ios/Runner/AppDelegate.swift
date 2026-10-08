import Flutter
import UIKit
import WatchConnectivity
import UserNotifications
#if canImport(workmanager_apple)
import workmanager_apple
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, WCSessionDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

    // Đăng ký tác vụ nền cho iOS BGTaskScheduler trước khi hàm didFinishLaunchingWithOptions kết thúc
    // Bắt buộc theo quy định của Apple và plugin workmanager_apple để tránh crash NSInternalInconsistencyException
    #if canImport(workmanager_apple)
    if #available(iOS 13.0, *) {
      WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "careai_periodic_sync_task")
      WorkmanagerPlugin.registerLaunchHandlers()
    }
    #endif

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
