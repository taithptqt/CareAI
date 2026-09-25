package vn.careai.companion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.util.Log
import androidx.core.content.ContextCompat

/** Receives the data-only FCM alert relayed by Flutter in foreground or background. */
class CaregiverAlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_ALERT) return
        val incidentId = intent.getStringExtra("incidentId")?.takeIf { it.isNotBlank() } ?: return
        val cycle = intent.getIntExtra("alertCycleNumber", 1)
        val eventType = intent.getStringExtra("eventType")
        if (!intent.getBooleanExtra("siren", false) &&
            eventType != "ACKNOWLEDGED" && eventType != "RESOLVED") return

        val serviceIntent = Intent(context, CaregiverAlertService::class.java).apply {
            action = if (intent.getBooleanExtra("siren", false))
                CaregiverAlertService.ACTION_START else CaregiverAlertService.ACTION_STOP
            putExtra("incidentId", incidentId)
            putExtra("alertCycleNumber", cycle)
            putExtra("title", intent.getStringExtra("title"))
            putExtra("body", intent.getStringExtra("body"))
            putExtra("emergencyType", intent.getStringExtra("emergencyType"))
        }
        if (serviceIntent.action == CaregiverAlertService.ACTION_STOP) {
            context.sendBroadcast(Intent(CaregiverAlarmActivity.ACTION_CLOSED).apply {
                setPackage(context.packageName)
                putExtra("incidentId", incidentId)
                putExtra("alertCycleNumber", cycle)
            })
        }
        try {
            if (serviceIntent.action == CaregiverAlertService.ACTION_START) {
                ContextCompat.startForegroundService(context, serviceIntent)
            } else {
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .cancel(incidentId.hashCode())
                context.startService(serviceIntent)
            }
        } catch (ex: Exception) {
            Log.e("CareAI-CaregiverAlert", "Could not start alarm service", ex)
            if (serviceIntent.action == CaregiverAlertService.ACTION_START) {
                CaregiverAlertService.showFallbackNotification(
                    context, incidentId,
                    intent.getStringExtra("title") ?: "CẢNH BÁO CẤP CỨU",
                    intent.getStringExtra("body") ?: "Người cao tuổi cần trợ giúp ngay."
                )
            }
        }
    }

    companion object {
        const val ACTION_ALERT = "vn.careai.companion.ACTION_CAREGIVER_ALERT"
    }
}
