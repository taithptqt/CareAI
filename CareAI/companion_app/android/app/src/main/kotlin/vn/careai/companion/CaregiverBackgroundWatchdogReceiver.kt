package vn.careai.companion

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL

/**
 * Watchdog đánh thức định kỳ kiểm tra sự cố cứu hộ khẩn cấp dành cho Người thân (Caregiver),
 * chạy hoàn toàn độc lập với Firebase FCM và hoạt động ngay cả khi app bị tắt hoặc màn hình tắt.
 */
class CaregiverBackgroundWatchdogReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wl = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "careai:caregiver_poll_wakelock")
        try {
            wl?.acquire(15000)
        } catch (_: Exception) {}

        val appPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val selectedRole = appPrefs.getString("flutter.selected_role", "") ?: ""
        val token = appPrefs.getString("flutter.jwt_token", "") ?: ""
        val serverUrl = appPrefs.getString(
            "flutter.server_base_url",
            "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"
        ) ?: "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"

        if (selectedRole != "caregiver" || token.isBlank()) {
            try { wl?.release() } catch (_: Exception) {}
            return
        }

        // Tái vũ trang chu kỳ tiếp theo (30 giây)
        armNextPoll(context)

        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                pollActiveIncidents(context, serverUrl, token)
            } catch (e: Exception) {
                Log.e("CareAI-CaregiverPoll", "Lỗi kiểm tra sự cố nền: ${e.message}")
            } finally {
                try {
                    if (wl?.isHeld == true) wl.release()
                } catch (_: Exception) {}
                pendingResult.finish()
            }
        }
    }

    private fun pollActiveIncidents(context: Context, baseUrl: String, token: String) {
        val cleanBase = baseUrl.trimEnd('/')
        val url = URL("$cleanBase/api/v1/incidents/active")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 8000
            readTimeout = 8000
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "application/json")
        }

        val code = conn.responseCode
        if (code == 200) {
            val responseText = conn.inputStream.bufferedReader().use { it.readText() }
            val array = JSONArray(responseText)
            for (i in 0 until array.length()) {
                val inc = array.getJSONObject(i)
                val isOpen = inc.optBoolean("isOpen", false)
                val status = inc.optString("status", "")
                val severity = inc.optString("severity", "")
                val incidentId = inc.optString("id", "")
                val emergencyType = inc.optString("emergencyType", "FALL")

                val isCritical = severity.equals("Critical", ignoreCase = true) || emergencyType.contains("FALL", ignoreCase = true)
                val isStillOpen = isOpen || status.equals("Open", ignoreCase = true)

                if (isCritical && isStillOpen && incidentId.isNotBlank()) {
                    Log.w("CareAI-CaregiverPoll", "🚨 Phát hiện sự cố khẩn cấp qua nền: $incidentId ($emergencyType). Kích hoạt còi hú!")
                    val alertIntent = Intent(context, CaregiverAlertReceiver::class.java).apply {
                        action = CaregiverAlertReceiver.ACTION_ALERT
                        putExtra("incidentId", incidentId)
                        putExtra("alertCycleNumber", 1)
                        putExtra("title", "CẢNH BÁO CẤP CỨU")
                        putExtra("body", "Người cao tuổi gặp sự cố khẩn cấp ($emergencyType). Cần trợ giúp ngay!")
                        putExtra("emergencyType", emergencyType)
                        putExtra("priority", "CRITICAL")
                        putExtra("siren", true)
                    }
                    context.sendBroadcast(alertIntent)
                    break
                }
            }
        }
        conn.disconnect()
    }

    companion object {
        const val ACTION_POLL = "vn.careai.companion.ACTION_CAREGIVER_BACKGROUND_POLL"

        fun armNextPoll(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, CaregiverBackgroundWatchdogReceiver::class.java).apply {
                action = ACTION_POLL
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                42099,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val triggerAt = System.currentTimeMillis() + 30000L // 30s
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                }
            } catch (_: Exception) {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        }
    }
}
