# HealthKit → CareAI → Android

This watchOS app was adapted from PulseNet's HealthKit reader. It reads existing heart rate and oxygen saturation samples on Apple Watch, then sends them to CareAI using the device telemetry API. The Android caregiver dashboard reads the stored samples from CareAI. Android cannot access HealthKit directly.

## Set up

1. On a Mac, install Xcode and XcodeGen, then run `xcodegen generate` in this directory and open `CareAIWatch.xcodeproj`.
2. Use an Apple Developer team with HealthKit capability and deploy to a physical Apple Watch. Set your own bundle identifier/signing team in Xcode.
3. Run the CareAI API at a reachable **HTTPS** address. In the Android caregiver dashboard, generate a device pairing PIN for the elder profile.
4. On the watch, enter the HTTPS base URL and PIN, then tap **Pair watch**. The app registers a separate `AppleWatch` device and stores its device token in the watch Keychain. Grant HealthKit read access for heart rate and blood oxygen when prompted.
5. Open that elder's dashboard in the CareAI Android app. The latest cards and 24 hour heart rate chart show measurements received by the API. While the dashboard is open, it refreshes the latest vitals and charts every 30 seconds; pull down to refresh immediately. An empty chart means no samples were received in that window.

Each HealthKit sample retains its measurement time. The watch queues readings when offline and retries sending. The API associates samples with the elder through the registered device and suppresses repeats for the same device, metric, and timestamp. The watch syncs the last 24 hours on first setup; later samples arrive through HealthKit observation. Availability of blood oxygen samples depends on the watch, region, and user permissions.

## When the watch is offline

The watch saves each new HealthKit heart rate or SpO₂ sample and its original measurement time in a protected local file. It advances the HealthKit query cursor only after that file is written. A sample stays in the queue until the API confirms it has stored the sample. The watch screen shows **Saved on watch** so the parent can see how many readings still need to sync. The app retries when network access returns, while it is open, and during watchOS background refresh. Opening the app also checks HealthKit for samples created while the app was suspended.

For example, after 15 minutes without internet, available HealthKit samples remain on the watch or in HealthKit. Once the watch has a connection and watchOS gives the app time to run, the backlog is sent with its original timestamps. The caregiver's Android dashboard then reads it from CareAI on its next refresh, and eligible alerts can be sent. HealthKit does not promise a sample every minute; watchOS can delay background execution, so neither collection nor caregiver delivery has a strict 15 minute deadline.

## Presentation controls

After pairing, scroll down on the watch to the **DEMO** section. Tap **Simulate heart rate ↑** to queue a 145 bpm demonstration sample, or **Simulate SpO₂ ↓** to queue a 90% demonstration sample. The watch immediately shows a labeled demo warning. **Simulate no internet** temporarily blocks uploads within the app; queue demo samples while it is on, then turn it off to upload them automatically. **Send data now** checks HealthKit and drains the pending queue while simulated offline mode is off. The queue count shows the backlog.

Demo samples use separate `DEMO_HEART_RATE` and `DEMO_SPO2` metric types. The backend stores them for the paired elder and the Android dashboard shows a clearly labeled demonstration warning for one hour after upload. Demo samples are excluded from real vital cards, charts, clinical alerts and weekly health analysis. The simulated offline switch does not disconnect the watch from the internet and resets when the app restarts. To test a real network outage, disconnect the watch from the network instead.

CareAI stores accepted samples in `HealthMeasurements`. Recent abnormal heart rate samples use the existing clinical alert and caregiver FCM path. A fresh SpO₂ measurement of 92% or lower now sends a caregiver notification that asks them to check the person and recheck the measurement. The caregiver dashboard provides cautious, timestamp-aware guidance; weekly reports include SpO₂ aggregates. Routine samples remain available from the backend even when the caregiver phone is offline. The watch's HealthKit background delivery is requested immediately, but watchOS chooses when to wake the app. The device offline rule allows up to three hours without a new Apple Watch sample to avoid false five-minute alerts. FCM delivery depends on network, system scheduling, notification permissions, and valid Firebase credentials; it is not guaranteed to be instantaneous.

The watchOS project cannot be built on Windows; verify signing, HealthKit permissions, background delivery, and end to end sync on a physical watch and Android phone.
