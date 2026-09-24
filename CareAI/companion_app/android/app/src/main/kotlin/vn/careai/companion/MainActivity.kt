package vn.careai.companion

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val FALL_BRIDGE_CHANNEL = "vn.careai.companion/fall_bridge"
    private var fallMethodChannel: MethodChannel? = null

    private var pendingFallPayload: HashMap<String, Any?>? = null
    private var lastHandledEventId: String? = null

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

        // Tải trước file âm thanh còi hú y tế vào RAM phần cứng (SoundPool) để sẵn sàng 0ms latency
        EmergencySoundPlayer.preload(this)

        checkFallFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        checkFallFromIntent(intent)
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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        fallMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FALL_BRIDGE_CHANNEL)
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
                else -> result.notImplemented()
            }
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
}
