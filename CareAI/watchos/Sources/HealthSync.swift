import Foundation
import HealthKit
import Network
import WatchKit

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

@MainActor
final class HealthSync: ObservableObject {
    @Published var status = "Set up backend to start"
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

    init() {
        latestHeartRate = UserDefaults.standard.object(forKey: "latest.heartRate") as? Double
        latestHeartRateAt = UserDefaults.standard.object(forKey: "latest.heartRateAt") as? Date
        latestSpo2 = UserDefaults.standard.object(forKey: "latest.spo2") as? Double
        latestSpo2At = UserDefaults.standard.object(forKey: "latest.spo2At") as? Date
        updateHealthAlert()
        loadOutbox()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.flush() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "careai.watch.network"))
        retryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHealthAlert()
                self?.flush()
            }
        }
        if UserDefaults.standard.string(forKey: "backend") != nil,
           KeychainToken.load() != nil {
            Task { @MainActor in self.start() }
        }
    }

    func start() {
        if !outboxReady { loadOutbox() }
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
                self.flush()
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
        if !enabled { flush() }
    }

    func simulateHighHeartRate() {
        enqueueDemo(metricType: "DEMO_HEART_RATE", value: 145, unit: "bpm")
    }

    func simulateLowSpo2() {
        enqueueDemo(metricType: "DEMO_SPO2", value: 90, unit: "%")
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
            if !simulatedOffline { flush() }
        } catch {
            status = "Cannot save demo reading on watch"
        }
    }

    private func updateHealthAlert() {
        let now = Date()
        if let at = latestSpo2At, now.timeIntervalSince(at) < 10 * 60,
           let value = latestSpo2, value <= 92 {
            healthAlert = String(format: "Low SpO₂: %.0f%% · check the person and recheck", value)
        } else if let at = latestHeartRateAt, now.timeIntervalSince(at) < 10 * 60,
                  let value = latestHeartRate, value > 120 || value < 50 {
            healthAlert = String(format: "Heart rate: %.0f bpm · check the person", value)
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
                if sendAfter { self.flush() }
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

    private func flush() {
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
        while sent < maximum, let reading = queue.first {
            if simulatedOffline {
                status = "DEMO offline · readings stay on watch"
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
                    batchId: "HK_\(reading.sampleId)", samples: [reading]))
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode
                guard code == 201 else {
                    status = "Waiting to send · HTTP \(code.map(String.init) ?? "offline")"
                    return
                }
                // Keep the original on disk until the server has committed it.
                let remaining = Array(queue.dropFirst())
                try persistQueue(remaining)
                queue = remaining
                pendingCount = remaining.count
                sent += 1
                status = "Sent · queued \(queue.count)"
            } catch {
                // A failed request or disk write leaves the reading in the outbox.
                status = "Offline or save failed · queued \(queue.count)"
                return
            }
        }
    }
}
