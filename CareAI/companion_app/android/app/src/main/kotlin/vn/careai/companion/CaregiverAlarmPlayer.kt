package vn.careai.companion

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.PowerManager

object CaregiverAlarmPlayer {
    private var player: MediaPlayer? = null

    fun start(context: Context) {
        if (player?.isPlaying == true) return
        stop()
        try {
            var afd: android.content.res.AssetFileDescriptor? = null
            try {
                afd = context.resources.openRawResourceFd(R.raw.careai_emergency_alarm)
            } catch (e: Exception) {
                android.util.Log.w("CareAI-CaregiverAlarm", "Không mở được careai_emergency_alarm từ raw resources", e)
            }

            player = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK)
                isLooping = true

                if (afd != null) {
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                } else {
                    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        ?: return
                    setDataSource(context, uri)
                }

                prepare()
                start()
            }
            android.util.Log.i("CareAI-CaregiverAlarm", "Đã phát còi hú cấp cứu y tế cho người thân.")
        } catch (_: Exception) {
            stop()
        }
    }

    fun stop() {
        player?.run {
            try { stop() } catch (_: Exception) {}
            release()
        }
        player = null
    }
}
