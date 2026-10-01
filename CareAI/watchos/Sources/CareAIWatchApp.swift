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
    @State private var backend = UserDefaults.standard.string(forKey: "backend") ?? ""
    @State private var pin = ""
    @State private var pairing = false
    @State private var pairingError: String?
    @State private var isPaired = KeychainToken.load() != nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("CareAI").font(.headline)
                if !isPaired {
                    TextField("HTTPS backend URL", text: $backend)
                        .textContentType(.URL)
                    TextField("6-digit pairing PIN", text: $pin)
                    Button(pairing ? "Pairing…" : "Pair watch") { Task { await pairWatch() } }
                        .disabled(pairing)
                    if let pairingError { Text(pairingError).font(.footnote).foregroundStyle(.red) }
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("Heart rate").font(.caption)
                        Text(sync.latestHeartRate.map { String(format: "%.0f bpm", $0) } ?? "—")
                        if let at = sync.latestHeartRateAt {
                            Text(at, style: .relative).font(.caption2)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("SpO₂").font(.caption)
                        Text(sync.latestSpo2.map { String(format: "%.0f%%", $0) } ?? "—")
                        if let at = sync.latestSpo2At {
                            Text(at, style: .relative).font(.caption2)
                        }
                    }
                }
                Text(sync.status).font(.footnote)
                if let alert = sync.healthAlert {
                    Text(alert).font(.footnote).foregroundStyle(.orange)
                }
                Text("Saved on watch: \(sync.pendingCount)").font(.caption2)
                if isPaired {
                    Divider()
                    Text("DEMO · simulated values").font(.caption).bold()
                    if sync.simulatedOffline {
                        Text("DEMO OFFLINE · uploads paused")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if let alert = sync.demoHeartRateAlert {
                        Text(alert).font(.footnote).foregroundStyle(.orange)
                    }
                    if let alert = sync.demoSpo2Alert {
                        Text(alert).font(.footnote).foregroundStyle(.orange)
                    }
                    Button("Simulate heart rate ↑") { sync.simulateHighHeartRate() }
                    Button("Simulate SpO₂ ↓") { sync.simulateLowSpo2() }
                    Toggle("Simulate no internet", isOn: Binding(
                        get: { sync.simulatedOffline },
                        set: { sync.setSimulatedOffline($0) }
                    ))
                    Button("Send data now") { Task { await sync.sendNow() } }
                        .disabled(sync.simulatedOffline)
                }
            }.padding()
        }
        .onAppear { if KeychainToken.load() != nil { sync.start() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isPaired { sync.start() }
        }
    }

    private func pairWatch() async {
        let base = backend.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard base.hasPrefix("https://"), let url = URL(string: base + "/api/v1/devices/pair"),
              pin.count == 6, pin.allSatisfy(\.isNumber) else {
            pairingError = "Enter an HTTPS URL and 6-digit PIN"
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
                deviceId: deviceId, pairingPin: pin, deviceType: "AppleWatch"))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                pairingError = "Pairing failed. Check PIN and server."
                return
            }
            let paired = try JSONDecoder().decode(PairResponse.self, from: data)
            guard KeychainToken.save(paired.deviceToken) else {
                pairingError = "Could not save device token"
                return
            }
            UserDefaults.standard.set(base, forKey: "backend")
            UserDefaults.standard.set(paired.deviceId, forKey: "deviceId")
            pin = ""
            pairingError = nil
            isPaired = true
            sync.start()
        } catch {
            pairingError = "Pairing failed: \(error.localizedDescription)"
        }
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
}
