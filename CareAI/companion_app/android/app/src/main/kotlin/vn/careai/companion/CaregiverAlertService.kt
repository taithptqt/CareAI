package vn.careai.companion

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/** Keeps a caregiver's fall alarm audible while its incident is still open. */
class CaregiverAlertService : Service() {
    private data class Alert(val cycle: Int, val title: String, val body: String, val emergencyType: String)
    private val active = linkedMapOf<String, Alert>()
    private var silenced = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getStringExtra("incidentId")?.takeIf { it.isNotBlank() }
        val cycle = intent?.getIntExtra("alertCycleNumber", 1) ?: 1
        when (intent?.action) {
            ACTION_START -> {
                if (id == null) return START_NOT_STICKY
                val previous = active[id]
                if (previous == null || cycle > previous.cycle) {
                    active[id] = Alert(cycle,
                        intent.getStringExtra("title") ?: "CẢNH BÁO CẤP CỨU",
                        intent.getStringExtra("body") ?: "Người cao tuổi cần trợ giúp ngay.",
                        intent.getStringExtra("emergencyType") ?: "")
                    silenced = false
                }
                showCurrentAlert()
            }
            ACTION_STOP -> {
                if (id != null && (active[id]?.cycle ?: Int.MAX_VALUE) <= cycle) {
                    active.remove(id)
                    sendBroadcast(Intent(CaregiverAlarmActivity.ACTION_CLOSED).apply {
                        setPackage(packageName)
                        putExtra("incidentId", id)
                        putExtra("alertCycleNumber", cycle)
                    })
                }
                if (active.isEmpty()) {
                    CaregiverAlarmPlayer.stop()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                } else showCurrentAlert()
            }
            ACTION_SILENCE -> {
                silenced = true
                CaregiverAlarmPlayer.stop()
                showCurrentAlert()
            }
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun showCurrentAlert() {
        val (id, alert) = active.entries.lastOrNull() ?: return
        ensureChannel(this)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val open = Intent(this, CaregiverAlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("incidentId", id)
            putExtra("alertCycleNumber", alert.cycle)
            putExtra("title", alert.title)
            putExtra("body", alert.body)
            putExtra("emergencyType", alert.emergencyType)
        }
        val openIntent = PendingIntent.getActivity(this, id.hashCode(), open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val silence = Intent(this, CaregiverAlertService::class.java).apply { action = ACTION_SILENCE }
        val silenceIntent = PendingIntent.getService(this, 12, silence,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(alert.title)
            .setContentText(alert.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(alert.body))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(android.R.drawable.ic_lock_silent_mode, "Tắt âm", silenceIntent)
            .apply {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
                    manager.canUseFullScreenIntent()) {
                    setFullScreenIntent(openIntent, true)
                }
            }
            .build()
        startForeground(NOTIFICATION_ID, notification)
        if (!silenced) CaregiverAlarmPlayer.start(this)
        Log.i("CareAI-CaregiverAlert", "Active alarm incident=$id cycle=${alert.cycle}")
    }

    override fun onDestroy() {
        CaregiverAlarmPlayer.stop()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "vn.careai.companion.CAREGIVER_START"
        const val ACTION_STOP = "vn.careai.companion.CAREGIVER_STOP"
        const val ACTION_SILENCE = "vn.careai.companion.CAREGIVER_SILENCE"
        private const val CHANNEL_ID = "careai_caregiver_alarm_v2"
        private const val FALLBACK_CHANNEL_ID = "careai_caregiver_fallback_v1"
        private const val NOTIFICATION_ID = 42001

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "Cấp cứu người thân", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Cảnh báo ngã và sự cố nguy kịch cần được tiếp nhận"
                enableVibration(true)
                setSound(null, null) // The foreground service plays the looping alarm.
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            })
        }

        fun showFallbackNotification(context: Context, id: String, title: String, body: String) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(NotificationChannel(
                    FALLBACK_CHANNEL_ID, "Cấp cứu dự phòng", NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    setSound(sound, AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM).build())
                    enableVibration(true)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                })
            }
            val open = Intent(context, CaregiverAlarmActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("incidentId", id)
                putExtra("title", title)
                putExtra("body", body)
            }
            val pending = PendingIntent.getActivity(context, id.hashCode(), open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            manager.notify(id.hashCode(), NotificationCompat.Builder(context, FALLBACK_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title).setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(pending).setAutoCancel(true)
                .apply {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
                        manager.canUseFullScreenIntent()) setFullScreenIntent(pending, true)
                }.build())
        }
    }
}
