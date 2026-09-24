package vn.careai.companion

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class NativeFallWatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val eventId = intent.getStringExtra("eventId") ?: return
        Log.w("CareAI-WatchdogReceiver", "AlarmManager RTC_WAKEUP kích hoạt! Kiểm tra trạng thái sự cố $eventId...")

        val record = CareAiFallStore.getFallRecord(context, eventId)
        if (record == null) {
            Log.e("CareAI-WatchdogReceiver", "Không tìm thấy hồ sơ sự cố $eventId trên đĩa.")
            return
        }

        // Nếu trạng thái vẫn là PENDING_CONFIRMATION sau 35s -> Kích hoạt Outbox-First SOS ngay lập tức!
        if (record.status == "PENDING_CONFIRMATION") {
            Log.e("CareAI-WatchdogReceiver", "[WATCHDOG TIMEOUT] Sự cố $eventId chưa được hủy sau 35s! Dừng còi hú và thực thi OUTBOX-FIRST SOS...")
            
            // Dừng âm thanh còi báo động khẩn cấp vì đã kết thúc đếm ngược chuyển sang bắn SOS
            EmergencySoundPlayer.stop()
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(eventId.hashCode())
            } catch (_: Exception) {}

            NativeSosDispatcher.dispatchOutboxFirstSos(context, record)
        } else {
            Log.i("CareAI-WatchdogReceiver", "Sự cố $eventId đã xử lý với trạng thái: ${record.status}. Bỏ qua SOS.")
        }
    }
}
