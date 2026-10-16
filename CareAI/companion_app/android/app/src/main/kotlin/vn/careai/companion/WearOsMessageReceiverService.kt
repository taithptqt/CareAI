package vn.careai.companion

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

class WearOsMessageReceiverService : WearableListenerService() {

    override fun onPeerConnected(peer: Node) {
        super.onPeerConnected(peer)
        Log.i("CareAI-WearReceiver", "[EVENT-DRIVEN] Đồng hồ vừa kết nối tức thì: ${peer.displayName} (${peer.id})")
        sendBroadcast(Intent("vn.careai.companion.WATCH_CONNECTION_CHANGED").apply {
            setPackage(packageName)
            putExtra("isConnected", true)
            putExtra("watchName", peer.displayName)
            putExtra("nodeId", peer.id)
            putExtra("isNearby", peer.isNearby)
        })
    }

    override fun onPeerDisconnected(peer: Node) {
        super.onPeerDisconnected(peer)
        Log.w("CareAI-WearReceiver", "[EVENT-DRIVEN] Đồng hồ vừa ngắt kết nối tức thì: ${peer.displayName} (${peer.id})")
        sendBroadcast(Intent("vn.careai.companion.WATCH_CONNECTION_CHANGED").apply {
            setPackage(packageName)
            putExtra("isConnected", false)
            putExtra("watchName", peer.displayName)
            putExtra("nodeId", peer.id)
            putExtra("isNearby", peer.isNearby)
        })
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path == "/careai/fall_detected") {
            val rawJson = String(messageEvent.data, Charsets.UTF_8)
            handleFallPayload(this, rawJson, "MESSAGE_CLIENT_FAST_LANE")
        } else if (messageEvent.path == "/careai/watch_telemetry") {
            val rawJson = String(messageEvent.data, Charsets.UTF_8)
            try {
                val json = JSONObject(rawJson)
                val isWorn = if (json.has("isWorn")) json.getBoolean("isWorn") else null
                val isCharging = if (json.has("isCharging")) json.getBoolean("isCharging") else null
                val batteryLevel = if (json.has("batteryLevel")) json.getInt("batteryLevel") else null
                val todaySteps = if (json.has("todaySteps")) json.getInt("todaySteps") else null
                val watchName = json.optString("watchName", "Galaxy Watch")

                Log.i("CareAI-WearReceiver", "[WATCH_TELEMETRY] Nhận viễn trắc đồng hồ: worn=$isWorn, charging=$isCharging, battery=$batteryLevel%, steps=$todaySteps")
                val prefs = getSharedPreferences("careai_watch_telemetry", Context.MODE_PRIVATE)
                prefs.edit().apply {
                    if (isWorn != null) putBoolean("isWorn", isWorn)
                    if (isCharging != null) putBoolean("isCharging", isCharging)
                    if (batteryLevel != null) putInt("batteryLevel", batteryLevel)
                    if (todaySteps != null && todaySteps > 0) putInt("todaySteps", todaySteps)
                    putString("watchName", watchName)
                    apply()
                }

                sendBroadcast(Intent("vn.careai.companion.WATCH_CONNECTION_CHANGED").apply {
                    setPackage(packageName)
                    putExtra("isConnected", true)
                    putExtra("watchName", watchName)
                    putExtra("reason", "CONNECTED")
                    if (isWorn != null) putExtra("isWorn", isWorn)
                    if (isCharging != null) putExtra("isCharging", isCharging)
                    if (batteryLevel != null) putExtra("batteryLevel", batteryLevel)
                    if (todaySteps != null && todaySteps > 0) putExtra("todaySteps", todaySteps)
                })
            } catch (e: Exception) {
                Log.e("CareAI-WearReceiver", "Lỗi phân tích /careai/watch_telemetry: ${e.message}")
            }
        }
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path?.startsWith("/careai/fall_event/") == true) {
                val dataMapItem = DataMapItem.fromDataItem(event.dataItem)
                val rawJson = dataMapItem.dataMap.getString("payloadJson") ?: ""
                handleFallPayload(this, rawJson, "DATA_CLIENT_STORE_AND_FORWARD")
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null) {
            val eventId = intent.getStringExtra("eventId") ?: "FALL_SIM_${System.currentTimeMillis()}"
            val timestamp = intent.getLongExtra("timestamp", System.currentTimeMillis())
            val impactG = if (intent.hasExtra("impactG")) intent.getDoubleExtra("impactG", 3.2) else 3.2
            val rawJson = JSONObject().apply {
                put("eventId", eventId)
                put("timestamp", timestamp)
                put("impactG", impactG)
            }.toString()
            handleFallPayload(this, rawJson, "ADB_COMMAND_SERVICE")
        }
        return START_NOT_STICKY
    }

    companion object {
        fun handleFallPayload(context: Context, rawJson: String, channelSource: String) {
            if (rawJson.isEmpty()) return
            try {
                val json = JSONObject(rawJson)
                val eventId = json.optString("eventId", java.util.UUID.randomUUID().toString())
                val timestamp = json.optLong("timestamp", System.currentTimeMillis())
                val impactG = if (json.isNull("impactG")) null else json.optDouble("impactG")

                // 1. Ghi đĩa nguyên tử và khử trùng lặp đồng bộ trong Device Protected Storage
                val deadlineAt = System.currentTimeMillis() + 35000L // 35s deadline
                val isNewlyRegistered = CareAiFallStore.registerFallEvent(context, eventId, timestamp, deadlineAt, impactG, rawJson)
                if (!isNewlyRegistered) {
                    Log.i("CareAI-PhoneReceiver", "Bỏ qua sự kiện ngã trùng lặp hoặc đã tồn tại [$channelSource]: $eventId")
                    return
                }

                Log.w("CareAI-PhoneReceiver", "[$channelSource] Tiếp nhận và ghi đĩa thành công sự cố ngã Galaxy Watch! EventId=$eventId")

                // 2. Khởi chạy ngay âm thanh còi hú y tế khẩn cấp chuyên dụng (STREAM_ALARM)
                EmergencySoundPlayer.start(context, eventId)

                // 3. Vũ trang Kernel AlarmManager RTC_WAKEUP
                armAlarmManagerWatchdog(context, eventId, deadlineAt)

                // 4. Full-Screen Intent đánh thức màn hình cứu trợ khẩn cấp
                showFullScreenEmergencyNotification(context, eventId, timestamp, impactG)

                // 5. Phát Local Broadcast
                val intent = Intent("vn.careai.companion.ACTION_HARDWARE_FALL_DETECTED").apply {
                    putExtra("timestamp", timestamp)
                    if (impactG != null) putExtra("impactG", impactG)
                    putExtra("eventId", eventId)
                    putExtra("secondsRemaining", 30)
                    setPackage(context.packageName)
                }
                context.sendBroadcast(intent)

            } catch (e: Exception) {
                Log.e("CareAI-PhoneReceiver", "Lỗi phân tích payload ngã: ${e.message}", e)
            }
        }

        fun armAlarmManagerWatchdog(context: Context, eventId: String, deadlineAt: Long) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, NativeFallWatchdogReceiver::class.java).apply {
                action = "vn.careai.companion.ACTION_FALL_WATCHDOG_TIMEOUT"
                putExtra("eventId", eventId)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                eventId.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val canExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                alarmManager.canScheduleExactAlarms()
            } else true

            if (canExact) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineAt, pendingIntent)
                    } else {
                        alarmManager.setExact(AlarmManager.RTC_WAKEUP, deadlineAt, pendingIntent)
                    }
                    Log.w("CareAI-Watchdog", "Đã vũ trang EXACT AlarmManager RTC_WAKEUP Watchdog cho sự cố $eventId tại deadline: $deadlineAt")
                } catch (e: SecurityException) {
                    Log.e("CareAI-Watchdog", "Bị từ chối Exact Alarm: ${e.message}. Kích hoạt Inexact Fallback!")
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineAt, pendingIntent)
                }
            } else {
                Log.w("CareAI-Watchdog", "Chưa cấp quyền SCHEDULE_EXACT_ALARM. Kích hoạt Inexact Fallback!")
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineAt, pendingIntent)
            }
        }

        fun showFullScreenEmergencyNotification(context: Context, eventId: String, timestamp: Long, impactG: Double?) {
            val channelId = "careai_emergency_fall_channel_v3"
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Cảnh báo Khẩn cấp Té ngã",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Kênh cảnh báo khẩn cấp và đánh thức toàn màn hình khi phát hiện té ngã"
                    enableLights(true)
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 200, 500)
                    setSound(null, null)
                }
                notificationManager.createNotificationChannel(channel)
            }

            val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("hardware_fall_event", true)
                putExtra("eventId", eventId)
                putExtra("timestamp", timestamp)
                if (impactG != null) putExtra("impactG", impactG)
                putExtra("secondsRemaining", 30)
            }

            val fullScreenPendingIntent = PendingIntent.getActivity(
                context,
                eventId.hashCode(),
                fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val canUseFsi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                notificationManager.canUseFullScreenIntent()
            } else true

            val notificationBuilder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("CẢNH BÁO TÉ NGÃ KHẨN CẤP")
                .setContentText("Đồng hồ Galaxy Watch phát hiện cú ngã! Đang đếm ngược 30 giây...")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setContentIntent(fullScreenPendingIntent)

            // 0. Bật sáng màn hình bằng WakeLock nếu đang tắt màn hình / Dozing
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                @Suppress("DEPRECATION")
                val wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                    "careai:emergency_wakelock"
                )
                wakeLock.acquire(10000)
                Log.w("CareAI-WakeLock", "Đã kích hoạt Screen WakeLock đánh thức màn hình khẩn cấp 10s!")
            } catch (e: Exception) {
                Log.w("CareAI-WakeLock", "Không thể lấy WakeLock: ${e.message}")
            }

            if (canUseFsi) {
                notificationBuilder.setFullScreenIntent(fullScreenPendingIntent, true)
                try {
                    context.startActivity(fullScreenIntent)
                } catch (e: Exception) {
                    Log.w("CareAI-FSI", "Direct startActivity fallback: ${e.message}")
                }
            } else {
                notificationBuilder.addAction(
                    android.R.drawable.ic_menu_call,
                    "MỞ MÀN HÌNH CỨU HỘ",
                    fullScreenPendingIntent
                )
            }

            notificationManager.notify(eventId.hashCode(), notificationBuilder.build())
        }
    }
}
