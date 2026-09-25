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
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                setDataSource(context, uri)
                setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK)
                isLooping = true
                prepare()
                start()
            }
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
