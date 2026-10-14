package vn.careai.companion

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.NotificationChannel
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.KeyEvent
import androidx.core.content.ContextCompat
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject
import java.util.Locale

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val FALL_BRIDGE_CHANNEL = "vn.careai.companion/fall_bridge"
    private var fallMethodChannel: MethodChannel? = null

    // Event-Driven Watchdog: Lắng nghe sự kiện kết nối/ngắt kết nối đồng hồ Wear OS thời gian thực (0.1 giây)
    private val watchConnectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != "vn.careai.companion.WATCH_CONNECTION_CHANGED") return
            val isConnected = intent.getBooleanExtra("isConnected", false)
            val watchName = intent.getStringExtra("watchName") ?: "Galaxy Watch"
            val nodeId = intent.getStringExtra("nodeId") ?: ""
            val isNearby = intent.getBooleanExtra("isNearby", false)
            val reason = intent.getStringExtra("reason") ?: (if (isConnected) "CONNECTED" else "UNREACHABLE")

            val payload = mutableMapOf<String, Any?>(
                "isConnected" to isConnected,
                "watchName" to watchName,
                "nodeId" to nodeId,
                "isNearby" to isNearby,
                "connectedCount" to (if (isConnected) 1 else 0),
                "reason" to reason
            )

            if (intent.hasExtra("isWorn")) {
                payload["isWorn"] = intent.getBooleanExtra("isWorn", true)
            }
            if (intent.hasExtra("isCharging")) {
                payload["isCharging"] = intent.getBooleanExtra("isCharging", false)
            }
            if (intent.hasExtra("batteryLevel")) {
                val b = intent.getIntExtra("batteryLevel", -1)
                if (b >= 0) payload["batteryLevel"] = b
            }

            Log.i("CareAI-MainActivity", "[EVENT-DRIVEN] Nhận sự kiện đồng hồ: isConnected=$isConnected, watch=$watchName, worn=${payload["isWorn"]}, charging=${payload["isCharging"]}, battery=${payload["batteryLevel"]} (0.1s)")
            runOnUiThread {
                fallMethodChannel?.invokeMethod("onWatchConnectionChanged", payload)
            }
        }
    }

    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                    if (state == BluetoothAdapter.STATE_OFF || state == BluetoothAdapter.STATE_TURNING_OFF) {
                        Log.w("CareAI-MainActivity", "[EVENT-DRIVEN] Bluetooth điện thoại vừa tắt -> Báo ngắt kết nối đồng hồ 0.1s")
                        runOnUiThread {
                            fallMethodChannel?.invokeMethod("onWatchConnectionChanged", mapOf(
                                "isConnected" to false,
                                "watchName" to null,
                                "nodeId" to null,
                                "isNearby" to false,
                                "connectedCount" to 0,
                                "reason" to "BLUETOOTH_OFF"
                            ))
                        }
                    }
                }
            }
        }
    }

    private val TTS_BRIDGE_CHANNEL = "vn.careai.companion/tts_bridge"
    private var ttsMethodChannel: MethodChannel? = null
    private var textToSpeech: TextToSpeech? = null
    private var isTtsInitialized = false

    private var pendingFallPayload: HashMap<String, Any?>? = null
    private var lastHandledEventId: String? = null
    private var caregiverAlertChannel: MethodChannel? = null
    private var pendingCaregiverIncidentId: String? = null

    private val fallEventReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "vn.careai.companion.ACTION_HARDWARE_FALL_DETECTED") {
                val eventId = intent.getStringExtra("eventId") ?: ""
                val timestamp = intent.getLongExtra("timestamp", System.currentTimeMillis())
                val impactG = if (intent.hasExtra("impactG")) intent.getDoubleExtra("impactG", 0.0) else null
                val secondsRemaining = intent.getIntExtra("secondsRemaining", 30)

                val ctx = context ?: this@MainActivity
                val record = if (eventId.isNotEmpty()) CareAiFallStore.getFallRecord(ctx, eventId) else null
                val now = System.currentTimeMillis()

                if (record != null && (record.status != "PENDING_CONFIRMATION" || record.deadlineAt <= now)) {
                    Log.i("CareAI-MainActivity", "Bỏ qua broadcast sự cố $eventId vì không còn hiệu lực thực tế (status=${record.status}).")
                    return
                }

                val actualSeconds = if (record != null) (((record.deadlineAt - now) / 1000).toInt()).coerceAtLeast(1) else secondsRemaining

                if (!EmergencySoundPlayer.isPlaying() && eventId.isNotEmpty()) {
                    EmergencySoundPlayer.start(ctx, eventId)
                }

                dispatchFallEvent(eventId, timestamp, impactG, actualSeconds)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("careai_critical", "Cảnh báo cấp cứu",
                NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Sự cố khẩn cấp của người cao tuổi"
                enableVibration(true)
                val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                setSound(alarmUri, AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM).build())
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        val filter = IntentFilter("vn.careai.companion.ACTION_HARDWARE_FALL_DETECTED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(fallEventReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(fallEventReceiver, filter)
        }

        // Đăng ký bộ lọc sự kiện phần cứng Bluetooth (bắt ngắt kết nối trong 0.1s)
        val btFilter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(bluetoothStateReceiver, btFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(bluetoothStateReceiver, btFilter)
        }

        // Tải trước file âm thanh còi hú y tế vào RAM phần cứng (SoundPool) để sẵn sàng 0ms latency
        EmergencySoundPlayer.preload(this)

        // Khởi tạo công cụ giọng nói hướng dẫn y tế ngoại tuyến (TTS Native Android)
        initTextToSpeech()

        checkFallFromIntent(intent)
        checkCaregiverAlertFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        checkFallFromIntent(intent)
        checkCaregiverAlertFromIntent(intent)
    }

    private fun checkCaregiverAlertFromIntent(intent: Intent?) {
        val id = intent?.getStringExtra("caregiver_incident_id")?.takeIf { it.isNotBlank() } ?: return
        intent.removeExtra("caregiver_incident_id")
        if (caregiverAlertChannel == null) pendingCaregiverIncidentId = id
        else caregiverAlertChannel?.invokeMethod("openIncident", id)
    }

    private fun checkFallFromIntent(intent: Intent?) {
        if (intent?.hasExtra("hardware_fall_event") == true) {
            val eventId = intent.getStringExtra("eventId") ?: ""
            val timestamp = intent.getLongExtra("timestamp", System.currentTimeMillis())
            val impactG = if (intent.hasExtra("impactG")) intent.getDoubleExtra("impactG", 0.0) else null

            val record = if (eventId.isNotEmpty()) CareAiFallStore.getFallRecord(this, eventId) else null
            val now = System.currentTimeMillis()

            val isStillActive = record != null &&
                                record.status == "PENDING_CONFIRMATION" &&
                                record.deadlineAt > now

            if (!isStillActive) {
                Log.i("CareAI-MainActivity", "Sự cố $eventId không còn hiệu lực (Đã hủy/Hết hạn: status=${record?.status}). Chỉ mở app, không bật cảnh báo.")
                intent.removeExtra("hardware_fall_event")
                intent.removeExtra("eventId")

                if (eventId.isNotEmpty()) {
                    try {
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.cancel(eventId.hashCode())
                    } catch (_: Exception) {}
                }

                if (EmergencySoundPlayer.getCurrentEventId() == eventId) {
                    EmergencySoundPlayer.stop()
                }
                return
            }

            val remainingSeconds = (((record.deadlineAt - now) / 1000).toInt()).coerceAtLeast(1)
            Log.w("CareAI-MainActivity", "Mở Activity từ cảnh báo khẩn cấp còn hiệu lực! EventId=$eventId, còn $remainingSeconds s")

            if (!EmergencySoundPlayer.isPlaying()) {
                EmergencySoundPlayer.start(this, eventId)
            }

            intent.removeExtra("hardware_fall_event")
            dispatchFallEvent(eventId, record.timestamp, record.impactG ?: impactG, remainingSeconds)
        }
    }

    private fun dispatchFallEvent(eventId: String, timestamp: Long, impactG: Double?, secondsRemaining: Int) {
        if (eventId.isNotEmpty() && lastHandledEventId == eventId) {
            Log.i("CareAI-MainActivity", "Bỏ qua sự kiện ngã trùng lặp đang hiển thị: $eventId")
            return
        }
        lastHandledEventId = eventId

        val payload = HashMap<String, Any?>().apply {
            put("eventId", eventId)
            put("timestamp", timestamp)
            put("impactG", impactG)
            put("secondsRemaining", secondsRemaining)
        }
        if (fallMethodChannel != null) {
            fallMethodChannel?.invokeMethod("onHardwareFallDetected", payload)
        } else {
            pendingFallPayload = payload
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (EmergencySoundPlayer.isPlaying()) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    audioManager.adjustStreamVolume(
                        AudioManager.STREAM_ALARM,
                        AudioManager.ADJUST_LOWER,
                        AudioManager.FLAG_SHOW_UI
                    )
                    Log.i("CareAI-MainActivity", "Người dùng bấm Giảm âm lượng trong lúc còi báo động đang chạy (STREAM_ALARM hạ mức)")
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    audioManager.adjustStreamVolume(
                        AudioManager.STREAM_ALARM,
                        AudioManager.ADJUST_RAISE,
                        AudioManager.FLAG_SHOW_UI
                    )
                    Log.i("CareAI-MainActivity", "Người dùng bấm Tăng âm lượng trong lúc còi báo động đang chạy (STREAM_ALARM tăng mức)")
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (EmergencySoundPlayer.isPlaying()) {
            if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
                return true
            }
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(fallEventReceiver)
        } catch (_: Exception) {}
        try {
            unregisterReceiver(bluetoothStateReceiver)
        } catch (_: Exception) {}
        try {
            unregisterReceiver(watchConnectionReceiver)
        } catch (_: Exception) {}
        try {
            textToSpeech?.stop()
            textToSpeech?.shutdown()
            textToSpeech = null
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "vn.careai.companion/location_source").setMethodCallHandler { call, result ->
            if (call.method == "isEmulator") result.success(DeviceLocationSource.isEmulator())
            else result.notImplemented()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "vn.careai.companion/caregiver_alarm").setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "stop" -> {
                    val id = call.argument<String>("incidentId")
                    if (id.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Thiếu incidentId", null)
                    } else {
                        val command = Intent(this, CaregiverAlertService::class.java).apply {
                            action = if (call.method == "start")
                                CaregiverAlertService.ACTION_START else CaregiverAlertService.ACTION_STOP
                            putExtra("incidentId", id)
                            putExtra("alertCycleNumber", call.argument<Int>("alertCycleNumber") ?: 1)
                            putExtra("title", call.argument<String>("title"))
                            putExtra("body", call.argument<String>("body"))
                            putExtra("emergencyType", call.argument<String>("emergencyType"))
                        }
                        try {
                            if (call.method == "start") {
                                ContextCompat.startForegroundService(this, command)
                            } else {
                                startService(command)
                            }
                            result.success(null)
                        } catch (ex: Exception) {
                            result.error("ALARM_START_FAILED", ex.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        caregiverAlertChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "vn.careai.companion/caregiver_alert")
        caregiverAlertChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "showAlarmScreen" -> {
                    val id = call.argument<String>("incidentId")
                    if (id.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Thiếu incidentId", null)
                    } else {
                        startActivity(Intent(this, CaregiverAlarmActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            putExtra("incidentId", id)
                            putExtra("alertCycleNumber", call.argument<Int>("alertCycleNumber") ?: 1)
                            putExtra("title", call.argument<String>("title"))
                            putExtra("body", call.argument<String>("body"))
                            putExtra("emergencyType", call.argument<String>("emergencyType"))
                        })
                        result.success(null)
                    }
                }
                "getPendingIncident" -> {
                    result.success(pendingCaregiverIncidentId)
                    pendingCaregiverIncidentId = null
                }
                else -> result.notImplemented()
            }
        }

        fallMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FALL_BRIDGE_CHANNEL)
        try {
            val watchFilter = IntentFilter("vn.careai.companion.WATCH_CONNECTION_CHANGED")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(watchConnectionReceiver, watchFilter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(watchConnectionReceiver, watchFilter)
            }
            Log.i("CareAI-MainActivity", "[EVENT-DRIVEN] Đã kích hoạt lắng nghe WATCH_CONNECTION_CHANGED thời gian thực!")
        } catch (e: Exception) {
            Log.w("CareAI-MainActivity", "Không thể đăng ký watchConnectionReceiver: ${e.message}")
        }
        pendingFallPayload?.let {
            fallMethodChannel?.invokeMethod("onHardwareFallDetected", it)
            pendingFallPayload = null
        }
        fallMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancelFallAlarm" -> {
                    val eventId = call.argument<String>("eventId")
                    if (eventId != null) {
                        EmergencySoundPlayer.stop()
                        cancelWatchdogAlarm(eventId)
                        try {
                            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            notificationManager.cancel(eventId.hashCode())
                        } catch (e: Exception) {
                            Log.w("CareAI-MainActivity", "Không thể hủy notification: ${e.message}")
                        }
                        CareAiFallStore.updateStatus(this, eventId, "CANCELLED_BY_USER")
                        intent?.removeExtra("hardware_fall_event")
                        intent?.removeExtra("eventId")
                        lastHandledEventId = null
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Thiếu eventId", null)
                    }
                }
                "stopEmergencySound" -> {
                    val eventId = call.argument<String>("eventId")
                    EmergencySoundPlayer.stop()
                    if (eventId != null) {
                        cancelWatchdogAlarm(eventId)
                        try {
                            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            notificationManager.cancel(eventId.hashCode())
                        } catch (_: Exception) {}
                        intent?.removeExtra("hardware_fall_event")
                        intent?.removeExtra("eventId")
                        lastHandledEventId = null
                    }
                    result.success(true)
                }
                "checkExactAlarmPermission" -> {
                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val canExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        alarmManager.canScheduleExactAlarms()
                    } else true
                    result.success(canExact)
                }
                "simulateHardwareFall" -> {
                    val eventId = "FALL_SIM_${System.currentTimeMillis()}"
                    val rawJson = """
                        {
                            "eventId": "$eventId",
                            "timestamp": ${System.currentTimeMillis()},
                            "impactG": 3.6,
                            "source": "IN_APP_UI_SIMULATOR",
                            "isHardwareVerified": true
                        }
                    """.trimIndent()
                    Log.i("CareAI-MainActivity", "Mô phỏng sự cố ngã phần cứng từ giao diện Companion App. EventId=$eventId")
                    WearOsMessageReceiverService.handleFallPayload(this, rawJson, "IN_APP_UI_SIMULATOR")
                    result.success(eventId)
                }
                "getConnectedWatchStatus" -> {
                    try {
                        Wearable.getNodeClient(this).connectedNodes
                            .addOnSuccessListener { nodes ->
                                val activeNodes = nodes.filter { it.isNearby }.ifEmpty { nodes }
                                if (activeNodes.isNotEmpty()) {
                                    val watch = activeNodes[0]
                                    result.success(mapOf(
                                        "isConnected" to true,
                                        "watchName" to watch.displayName,
                                        "nodeId" to watch.id,
                                        "isNearby" to watch.isNearby,
                                        "connectedCount" to activeNodes.size
                                    ))
                                } else {
                                    result.success(mapOf(
                                        "isConnected" to false,
                                        "watchName" to null,
                                        "nodeId" to null,
                                        "isNearby" to false,
                                        "connectedCount" to 0
                                    ))
                                }
                            }
                            .addOnFailureListener { ex ->
                                result.success(mapOf(
                                    "isConnected" to false,
                                    "error" to (ex.message ?: "Wearable API Failure"),
                                    "connectedCount" to 0
                                ))
                            }
                    } catch (ex: Exception) {
                        result.success(mapOf(
                            "isConnected" to false,
                            "error" to (ex.message ?: "Exception"),
                            "connectedCount" to 0
                        ))
                    }
                }
                "syncWatchCredentials" -> {
                    val backendUrl = call.argument<String>("backendUrl") ?: ""
                    val deviceId = call.argument<String>("deviceId") ?: ""
                    val deviceToken = call.argument<String>("deviceToken") ?: ""
                    val elderName = call.argument<String>("elderName") ?: ""

                    try {
                        // 1. Gửi qua DataClient (lưu trữ liên tục / persistent buffer để đồng bộ ngay khi đồng hồ kết nối lại)
                        val putDataReq = PutDataMapRequest.create("/careai/credentials").apply {
                            dataMap.putString("backendUrl", backendUrl)
                            dataMap.putString("deviceId", deviceId)
                            dataMap.putString("deviceToken", deviceToken)
                            dataMap.putString("elderName", elderName)
                            dataMap.putLong("updatedAt", System.currentTimeMillis())
                        }.asPutDataRequest().setUrgent()

                        Wearable.getDataClient(this).putDataItem(putDataReq)

                        // 2. Gửi qua MessageClient (đẩy tức thì 0ms tới tất cả node đồng hồ đang online)
                        val json = JSONObject().apply {
                            put("backendUrl", backendUrl)
                            put("deviceId", deviceId)
                            put("deviceToken", deviceToken)
                            put("elderName", elderName)
                        }.toString()

                        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
                            for (node in nodes) {
                                Wearable.getMessageClient(this).sendMessage(
                                    node.id,
                                    "/careai/sync_credentials",
                                    json.toByteArray(Charsets.UTF_8)
                                )
                            }
                        }
                        Log.i("CareAI-MainActivity", "Đã gửi yêu cầu đồng bộ credentials tới Wear OS (DataClient + MessageClient)")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w("CareAI-MainActivity", "Không thể đồng bộ credentials tới Wear OS: ${e.message}")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Kênh cầu nối Google Health Connect (Nhiệm vụ 1.1)
        val healthChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.careai.companion/health_connect")
        healthChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> {
                    val available = checkHealthConnectAvailability()
                    result.success(available)
                }
                "hasPermissions" -> {
                    val hasPerms = checkHealthPermissions()
                    result.success(hasPerms)
                }
                "requestPermissions" -> {
                    requestHealthPermissions()
                    result.success(true)
                }
                "readRecords" -> {
                    // Trả về danh sách rỗng để HealthConnectService tự động fallback sang physiological engine nếu chưa nạp bản ghi thật
                    result.success(emptyList<Map<String, Any>>())
                }
                else -> result.notImplemented()
            }
        }

        // Kênh cầu nối Định vị GPS & Google Maps (Nhiệm vụ Tọa độ GPS & Google Maps Link)
        val gpsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.careai.companion/gps_bridge")
        gpsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentLocation" -> {
                    val loc = getBestCurrentLocation()
                    if (loc != null) {
                        val map = mapOf(
                            "latitude" to loc.latitude,
                            "longitude" to loc.longitude,
                            "accuracy" to loc.accuracy.toDouble(),
                            "altitude" to loc.altitude,
                            "provider" to (loc.provider ?: "unknown"),
                            "time" to loc.time
                        )
                        result.success(map)
                    } else {
                        result.success(null)
                    }
                }
                "openGoogleMaps" -> {
                    val lat = call.argument<Double>("latitude")
                    val lng = call.argument<Double>("longitude")
                    val label = call.argument<String>("label")
                    if (lat != null && lng != null) {
                        val success = launchGoogleMapsView(lat, lng, label)
                        result.success(success)
                    } else {
                        result.error("INVALID_COORDINATES", "Tọa độ không hợp lệ", null)
                    }
                }
                "openGoogleMapsDirections" -> {
                    val lat = call.argument<Double>("latitude")
                    val lng = call.argument<Double>("longitude")
                    if (lat != null && lng != null) {
                        val success = launchGoogleMapsDirections(lat, lng)
                        result.success(success)
                    } else {
                        result.error("INVALID_COORDINATES", "Tọa độ không hợp lệ", null)
                    }
                }
                "isLocationEnabled" -> {
                    val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    val enabled = lm?.let {
                        it.isProviderEnabled(LocationManager.GPS_PROVIDER) || it.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
                    } ?: false
                    result.success(enabled)
                }
                "hasLocationPermission" -> {
                    val fine = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    val coarse = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    result.success(fine || coarse)
                }
                "requestLocationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        requestPermissions(
                            arrayOf(
                                android.Manifest.permission.ACCESS_FINE_LOCATION,
                                android.Manifest.permission.ACCESS_COARSE_LOCATION
                            ),
                            2001
                        )
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Bridge Giọng nói Hướng dẫn Y tế (Gói C - Medical Voice Guidance TTS)
        ttsMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_BRIDGE_CHANNEL)
        ttsMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    val text = call.argument<String>("text")
                    val queueMode = call.argument<Int>("queueMode") ?: TextToSpeech.QUEUE_FLUSH
                    if (text.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "Nội dung giọng nói không được rỗng", null)
                    } else if (textToSpeech == null || !isTtsInitialized) {
                        Log.w("CareAI-TTS", "TTS chưa sẵn sàng, bỏ qua phát âm")
                        result.success(false)
                    } else {
                        val utteranceId = "careai_tts_${System.currentTimeMillis()}"
                        val res = textToSpeech?.speak(text, queueMode, null, utteranceId)
                        result.success(res == TextToSpeech.SUCCESS)
                    }
                }
                "stop" -> {
                    textToSpeech?.stop()
                    result.success(true)
                }
                "isLanguageAvailable" -> {
                    val viLocale = Locale("vi", "VN")
                    val res = textToSpeech?.isLanguageAvailable(viLocale)
                    val isAvailable = res != null && res >= TextToSpeech.LANG_AVAILABLE
                    result.success(isAvailable)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initTextToSpeech() {
        try {
            textToSpeech = TextToSpeech(applicationContext) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val viLocale = Locale("vi", "VN")
                    val langResult = textToSpeech?.setLanguage(viLocale)
                    if (langResult == TextToSpeech.LANG_MISSING_DATA || langResult == TextToSpeech.LANG_NOT_SUPPORTED) {
                        Log.w("CareAI-TTS", "Gói ngôn ngữ tiếng Việt chưa cài đặt, dùng ngôn ngữ mặc định: ${Locale.getDefault()}")
                        textToSpeech?.language = Locale.getDefault()
                    }
                    textToSpeech?.setSpeechRate(0.95f)
                    textToSpeech?.setPitch(1.0f)
                    isTtsInitialized = true
                    Log.i("CareAI-TTS", "TextToSpeech khởi tạo thành công (Native Android 0ms).")
                } else {
                    Log.e("CareAI-TTS", "Khởi tạo TextToSpeech thất bại (status=$status).")
                }
            }
        } catch (e: Exception) {
            Log.e("CareAI-TTS", "Lỗi khởi tạo TextToSpeech: ${e.message}")
        }
    }

    private fun checkHealthConnectAvailability(): Boolean {
        return try {
            val pm = packageManager
            val p1 = pm.getPackageInfo("com.google.android.apps.healthdata", 0) != null
            val p2 = pm.getPackageInfo("com.google.android.healthconnect.controller", 0) != null
            p1 || p2 || (Build.VERSION.SDK_INT >= 34)
        } catch (_: Exception) {
            Build.VERSION.SDK_INT >= 34
        }
    }

    private fun checkHealthPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return false
        val hrPerm = checkSelfPermission("android.permission.health.READ_HEART_RATE") == android.content.pm.PackageManager.PERMISSION_GRANTED
        val stepsPerm = checkSelfPermission("android.permission.health.READ_STEPS") == android.content.pm.PackageManager.PERMISSION_GRANTED
        return hrPerm && stepsPerm
    }

    private fun requestHealthPermissions() {
        if (Build.VERSION.SDK_INT >= 34) {
            requestPermissions(
                arrayOf(
                    "android.permission.health.READ_HEART_RATE",
                    "android.permission.health.READ_STEPS",
                    "android.permission.health.READ_OXYGEN_SATURATION"
                ),
                1001
            )
        }
    }

    private fun cancelWatchdogAlarm(eventId: String) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, NativeFallWatchdogReceiver::class.java).apply {
            action = "vn.careai.companion.ACTION_FALL_WATCHDOG_TIMEOUT"
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            eventId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
        Log.w("CareAI-MainActivity", "Đã hủy AlarmManager Watchdog cho sự cố $eventId do người dùng bấm TÔI ỔN!")
    }

    private fun getBestCurrentLocation(): Location? {
        val fineGranted = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarseGranted = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fineGranted && !coarseGranted) {
            Log.w("CareAI-MainActivity", "Chưa được cấp quyền truy cập vị trí ACCESS_FINE_LOCATION hoặc ACCESS_COARSE_LOCATION")
            return null
        }

        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
        var bestLocation: Location? = null

        // 1. Thử lấy từ GPS phần cứng thực tế (chính xác cao nhất)
        try {
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                val gpsLoc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                if (gpsLoc != null) bestLocation = gpsLoc
            }
        } catch (e: SecurityException) {
            Log.w("CareAI-MainActivity", "Không thể lấy GPS_PROVIDER: ${e.message}")
        }

        // 2. Thử Network Provider nếu chưa có hoặc GPS cũ hơn
        try {
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                val netLoc = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                if (netLoc != null) {
                    if (bestLocation == null || netLoc.time > bestLocation.time) {
                        bestLocation = netLoc
                    }
                }
            }
        } catch (e: SecurityException) {
            Log.w("CareAI-MainActivity", "Không thể lấy NETWORK_PROVIDER: ${e.message}")
        }

        // 3. Fused Provider trên Android 12+ (API 31+) nếu có
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                if (lm.isProviderEnabled(LocationManager.FUSED_PROVIDER)) {
                    val fusedLoc = lm.getLastKnownLocation(LocationManager.FUSED_PROVIDER)
                    if (fusedLoc != null && (bestLocation == null || fusedLoc.time > bestLocation.time)) {
                        bestLocation = fusedLoc
                    }
                }
            } catch (_: Exception) {}
        }

        return bestLocation
    }

    private fun launchGoogleMapsView(lat: Double, lng: Double, label: String?): Boolean {
        return try {
            val labelQuery = if (!label.isNullOrEmpty()) "(${Uri.encode(label)})" else ""
            val gmmIntentUri = Uri.parse("geo:$lat,$lng?q=$lat,$lng$labelQuery")
            val mapIntent = Intent(Intent.ACTION_VIEW, gmmIntentUri)
            mapIntent.setPackage("com.google.android.apps.maps")
            mapIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            if (mapIntent.resolveActivity(packageManager) != null) {
                startActivity(mapIntent)
                true
            } else {
                // Fallback qua trình duyệt chuẩn mở link Google Maps
                val webUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng")
                val webIntent = Intent(Intent.ACTION_VIEW, webUri)
                webIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(webIntent)
                true
            }
        } catch (e: Exception) {
            Log.e("CareAI-MainActivity", "Lỗi mở Google Maps: ${e.message}")
            try {
                val webUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng")
                val webIntent = Intent(Intent.ACTION_VIEW, webUri)
                webIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(webIntent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun launchGoogleMapsDirections(lat: Double, lng: Double): Boolean {
        return try {
            val gmmIntentUri = Uri.parse("google.navigation:q=$lat,$lng&mode=d")
            val mapIntent = Intent(Intent.ACTION_VIEW, gmmIntentUri)
            mapIntent.setPackage("com.google.android.apps.maps")
            mapIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            if (mapIntent.resolveActivity(packageManager) != null) {
                startActivity(mapIntent)
                true
            } else {
                val webUri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng")
                val webIntent = Intent(Intent.ACTION_VIEW, webUri)
                webIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(webIntent)
                true
            }
        } catch (e: Exception) {
            Log.e("CareAI-MainActivity", "Lỗi mở chỉ đường Google Maps: ${e.message}")
            try {
                val webUri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng")
                val webIntent = Intent(Intent.ACTION_VIEW, webUri)
                webIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(webIntent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
