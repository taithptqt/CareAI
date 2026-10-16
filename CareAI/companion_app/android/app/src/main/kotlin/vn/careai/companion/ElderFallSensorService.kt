package vn.careai.companion

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import kotlin.math.sqrt

/**
 * Foreground Service giám sát gia tốc điện thoại liên tục trong nền (ngay cả khi tắt màn hình)
 * dành cho Người cao tuổi (Elder Mode).
 */
class ElderFallSensorService : Service(), SensorEventListener {
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var freeFallDetected = false
    private var freeFallStartTime: Long = 0L
    private var lastFallDetectedTime: Long = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
        startForeground(NOTIFICATION_ID, buildForegroundNotification())

        // Giữ Partial WakeLock để CPU không bị deep sleep ngắt quãng lấy mẫu gia tốc
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "careai:elder_fall_sensor_wakelock"
            ).apply {
                acquire()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Không thể acquire Partial WakeLock: ${e.message}")
        }

        // Đăng ký cảm biến gia tốc
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (accelerometer != null) {
            sensorManager?.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME)
            Log.i(TAG, "Đã khởi động ElderFallSensorService và đăng ký cảm biến gia tốc thành công.")
        } else {
            Log.e(TAG, "Thiết bị không có cảm biến gia tốc!")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || event.sensor.type != Sensor.TYPE_ACCELEROMETER) return

        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val magnitude = sqrt((x * x + y * y + z * z).toDouble())
        val g = magnitude / 9.80665
        val now = System.currentTimeMillis()

        // Pha 1: Rơi tự do (Free Fall) - Trọng lực giảm đột ngột (< 0.40 G)
        if (g < 0.40) {
            freeFallDetected = true
            freeFallStartTime = now
            return
        }

        // Pha 2: Va đập mạnh (Impact: > 2.85 G) trong vòng 800ms sau pha rơi
        if (freeFallDetected) {
            if (now - freeFallStartTime <= 800) {
                if (g > 2.85) {
                    freeFallDetected = false
                    freeFallStartTime = 0L

                    // Debounce chống lặp lại trong 10 giây
                    if (now - lastFallDetectedTime > 10000L) {
                        lastFallDetectedTime = now
                        handleFallDetected(now, g)
                    }
                }
            } else {
                // Quá 800ms -> Hủy cờ rơi tự do
                freeFallDetected = false
                freeFallStartTime = 0L
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun handleFallDetected(timestamp: Long, impactG: Double) {
        val eventId = "FALL_PHONE_$timestamp"
        Log.w(TAG, "💥 [PHÁT HIỆN TÉ NGÃ TRÊN ĐIỆN THOẠI!] EventId=$eventId, Impact=${String.format("%.2f", impactG)}G")

        val rawJson = JSONObject().apply {
            put("eventId", eventId)
            put("timestamp", timestamp)
            put("impactG", impactG)
            put("source", "ANDROID_PHONE_ACCELEROMETER")
        }.toString()

        // 1. Ghi nhận sự cố vào đĩa với deadline 35 giây
        val deadlineAt = timestamp + 35000L
        CareAiFallStore.registerFallEvent(this, eventId, timestamp, deadlineAt, impactG, rawJson)

        // 2. Kích hoạt chuông còi hú y tế ngay lập tức (STREAM_ALARM)
        EmergencySoundPlayer.start(this, eventId)

        // 3. Vũ trang Watchdog Kernel RTC_WAKEUP 35s
        WearOsMessageReceiverService.armAlarmManagerWatchdog(this, eventId, deadlineAt)

        // 4. Bật sáng màn hình và hiển thị Full Screen Intent khẩn cấp
        WearOsMessageReceiverService.showFullScreenEmergencyNotification(this, eventId, timestamp, impactG)

        // 5. Gửi Local Broadcast cho Flutter nếu đang thức
        val intent = Intent("vn.careai.companion.ACTION_HARDWARE_FALL_DETECTED").apply {
            putExtra("timestamp", timestamp)
            putExtra("impactG", impactG)
            putExtra("eventId", eventId)
            putExtra("secondsRemaining", 30)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    override fun onDestroy() {
        try {
            sensorManager?.unregisterListener(this)
        } catch (_: Exception) {}
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (_: Exception) {}
        Log.i(TAG, "ElderFallSensorService đã dừng hoàn toàn.")
        super.onDestroy()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Giám sát an toàn CareAI",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Duy trì giám sát té ngã trong nền liên tục bảo vệ người cao tuổi"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): android.app.Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("CareAI đang bảo vệ bạn trong nền")
            .setContentText("Cảm biến phát hiện té ngã đang hoạt động liên tục")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    companion object {
        private const val TAG = "CareAI-ElderSensor"
        const val ACTION_START = "vn.careai.companion.ELDER_SENSOR_START"
        const val ACTION_STOP = "vn.careai.companion.ELDER_SENSOR_STOP"
        private const val CHANNEL_ID = "careai_elder_sensor_channel"
        private const val NOTIFICATION_ID = 43001
    }
}
