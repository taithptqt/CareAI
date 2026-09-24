package vn.careai.companion

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class PhoneBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val receivedAction = intent.action
        // [BẤT BIẾN P0-3]: TIẾP NHẬN CẢ LOCKED_BOOT_COMPLETED (DIRECT BOOT) VÀ BOOT_COMPLETED
        if (receivedAction == Intent.ACTION_LOCKED_BOOT_COMPLETED || receivedAction == Intent.ACTION_BOOT_COMPLETED) {
            Log.i("CareAI-Boot", "Nhận tín hiệu khởi động [$receivedAction]. Quét sự cố tồn đọng trong Device Protected Storage...")
            val now = System.currentTimeMillis()
            val pendingFalls = CareAiFallStore.getAllPendingFalls(context)

            for (record in pendingFalls) {
                if (record.status == "SOS_QUEUED") {
                    Log.w("CareAI-Boot", "Sự cố ${record.eventId} đang nằm trong Outbox. Kích hoạt WorkManager retry!")
                    NativeSosDispatcher.enqueueWorkManagerRetry(context, record.eventId)
                } else if (record.deadlineAt <= now) {
                    Log.e("CareAI-Boot", "Sự cố ${record.eventId} đã quá hạn trong thời gian tắt nguồn! Thực thi OUTBOX-FIRST SOS ngay!")
                    NativeSosDispatcher.dispatchOutboxFirstSos(context, record)
                } else {
                    // Tái thiết lập AlarmManager cho thời gian còn lại
                    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val alarmIntent = Intent(context, NativeFallWatchdogReceiver::class.java).apply {
                        this.action = "vn.careai.companion.ACTION_FALL_WATCHDOG_TIMEOUT"
                        putExtra("eventId", record.eventId)
                    }
                    val pendingIntent = PendingIntent.getBroadcast(
                        context,
                        record.eventId.hashCode(),
                        alarmIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )

                    val canExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        alarmManager.canScheduleExactAlarms()
                    } else true

                    if (canExact) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, record.deadlineAt, pendingIntent)
                            } else {
                                alarmManager.setExact(AlarmManager.RTC_WAKEUP, record.deadlineAt, pendingIntent)
                            }
                            Log.i("CareAI-Boot", "Đã tái lập EXACT AlarmManager cho sự cố ${record.eventId} với deadline: ${record.deadlineAt}")
                        } catch (e: SecurityException) {
                            Log.e("CareAI-Boot", "Mất quyền Exact Alarm sau boot: ${e.message}. Fallback Inexact.")
                            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, record.deadlineAt, pendingIntent)
                        }
                    } else {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, record.deadlineAt, pendingIntent)
                    }
                }
            }
        }
    }
}
