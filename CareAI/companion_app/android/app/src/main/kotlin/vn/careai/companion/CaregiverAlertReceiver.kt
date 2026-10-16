package vn.careai.companion

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Receives the data-only FCM alert relayed by Flutter in foreground or background. */
class CaregiverAlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_ALERT) return
        val incidentId = intent.getStringExtra("incidentId")?.takeIf { it.isNotBlank() } ?: return
        val cycle = intent.getIntExtra("alertCycleNumber", 1)
        val eventType = intent.getStringExtra("eventType")
        val siren = intent.getBooleanExtra("siren", false)
        val priority = intent.getStringExtra("priority")?.uppercase() ?: ""
        val isHighPriority = priority == "HIGH" || priority == "CRITICAL"
        if (!siren && !isHighPriority &&
            eventType != "ACKNOWLEDGED" && eventType != "RESOLVED") return

        if (eventType == "ACKNOWLEDGED" || eventType == "RESOLVED") {
            val serviceIntent = Intent(context, CaregiverAlertService::class.java).apply {
                action = CaregiverAlertService.ACTION_STOP
                putExtra("incidentId", incidentId)
                putExtra("alertCycleNumber", cycle)
            }
            context.sendBroadcast(Intent(CaregiverAlarmActivity.ACTION_CLOSED).apply {
                setPackage(context.packageName)
                putExtra("incidentId", incidentId)
                putExtra("alertCycleNumber", cycle)
            })
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(incidentId.hashCode())
            context.startService(serviceIntent)
            return
        }

        // Cảnh báo khẩn cấp cần còi báo động (siren = true): Chạy foreground service & AlarmActivity
        if (siren) {
            val serviceIntent = Intent(context, CaregiverAlertService::class.java).apply {
                action = CaregiverAlertService.ACTION_START
                putExtra("incidentId", incidentId)
                putExtra("alertCycleNumber", cycle)
                putExtra("title", intent.getStringExtra("title"))
                putExtra("body", intent.getStringExtra("body"))
                putExtra("emergencyType", intent.getStringExtra("emergencyType"))
            }
            try {
                ContextCompat.startForegroundService(context, serviceIntent)
            } catch (ex: Exception) {
                Log.e("CareAI-CaregiverAlert", "Could not start alarm service", ex)
                CaregiverAlertService.showFallbackNotification(
                    context, incidentId,
                    intent.getStringExtra("title") ?: "CẢNH BÁO CẤP CỨU",
                    intent.getStringExtra("body") ?: "Người cao tuổi cần trợ giúp ngay."
                )
            }
            return
        }

        // Thông báo nhắc nhở nhẹ nhàng (siren = false, isHighPriority = true):
        // Đánh thức màn hình (WakeLock) và hiển thị Heads-up notification trên màn hình khóa KHÔNG hú còi inh ỏi
        showReminderNotification(
            context,
            incidentId,
            intent.getStringExtra("title") ?: "🟢 Sinh hiệu người thân đã ổn định",
            intent.getStringExtra("body") ?: "Vui lòng kiểm tra và đóng sự cố khi người thân đã an toàn.",
            eventType
        )
    }

    private fun showReminderNotification(
        context: Context,
        incidentId: String,
        title: String,
        body: String,
        eventType: String?
    ) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Đánh thức màn hình sáng lên khi nhận thông báo
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager != null && !powerManager.isInteractive) {
                @Suppress("DEPRECATION")
                val wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "CareAI:ReminderWakeLock"
                )
                wakeLock.acquire(3000)
            }
        } catch (e: Exception) {
            Log.w("CareAI-CaregiverAlert", "WakeLock acquire failed: ${e.message}")
        }

        val channelId = "careai_reminder_v1"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Nhắc nhở chăm sóc",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Thông báo nhắc nhở theo dõi và đóng sự cố khi người thân đã ổn định"
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                setSound(soundUri, AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
            }
            manager.createNotificationChannel(channel)
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("caregiver_incident_id", incidentId)
            putExtra("incidentId", incidentId)
            putExtra("fromNotification", true)
            putExtra("eventType", eventType)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            incidentId.hashCode() + 1000,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify(incidentId.hashCode() + 1000, notification)
        Log.i("CareAI-CaregiverAlert", "Showed reminder notification for incident $incidentId")
    }

    companion object {
        const val ACTION_ALERT = "vn.careai.companion.ACTION_CAREGIVER_ALERT"
    }
}
