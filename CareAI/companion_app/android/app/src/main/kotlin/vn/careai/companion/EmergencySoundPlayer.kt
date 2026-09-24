package vn.careai.companion

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.util.Log

object EmergencySoundPlayer {
    private const val TAG = "CareAI-SoundPlayer"
    private var soundPool: SoundPool? = null
    private var soundId: Int = 0
    private var streamId: Int = 0
    private var isLoaded: Boolean = false
    private var isPlayingSound: Boolean = false
    private var currentPlayingEventId: String? = null

    private fun ensureSoundPool(context: Context) {
        if (soundPool != null) return

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        soundPool = SoundPool.Builder()
            .setMaxStreams(1)
            .setAudioAttributes(audioAttributes)
            .build().apply {
                setOnLoadCompleteListener { _, sampleId, status ->
                    if (status == 0 && sampleId == soundId) {
                        isLoaded = true
                        Log.i(TAG, "SoundPool đã nạp file âm thanh còi hú y tế vào RAM thành công (sampleId=$soundId).")
                        if (isPlayingSound && streamId == 0) {
                            streamId = play(soundId, 1.0f, 1.0f, 1, -1, 1.0f)
                            Log.w(TAG, "Đã phát lặp vô hạn SoundPool không độ trễ (STREAM_ALARM). streamId=$streamId")
                        }
                    } else {
                        Log.e(TAG, "Lỗi nạp SoundPool sampleId=$sampleId, status=$status")
                    }
                }
            }

        soundId = soundPool?.load(context.applicationContext, R.raw.careai_emergency_alarm, 1) ?: 0
    }

    @Synchronized
    fun preload(context: Context) {
        ensureSoundPool(context)
    }

    @Synchronized
    fun start(context: Context, eventId: String) {
        if (isPlayingSound && currentPlayingEventId == eventId) {
            Log.d(TAG, "Còi hú cấp cứu đang phát cho sự cố $eventId, tiếp tục duy trì.")
            return
        }

        stop()

        currentPlayingEventId = eventId
        isPlayingSound = true

        ensureSoundPool(context)

        if (isLoaded && soundId != 0) {
            streamId = soundPool?.play(soundId, 1.0f, 1.0f, 1, -1, 1.0f) ?: 0
            Log.w(TAG, "Đã khởi chạy còi hú y tế nhịp đôi 0ms latency (STREAM_ALARM) cho sự cố: $eventId (streamId=$streamId)")
        } else {
            Log.i(TAG, "SoundPool đang nạp âm thanh vào RAM, sẽ tự phát ngay khi hoàn tất...")
        }
    }

    @Synchronized
    fun stop() {
        try {
            if (streamId != 0) {
                soundPool?.stop(streamId)
                streamId = 0
            }
        } catch (e: Exception) {
            Log.w(TAG, "Lỗi khi dừng SoundPool: ${e.message}")
        } finally {
            isPlayingSound = false
            currentPlayingEventId = null
            Log.i(TAG, "Đã tắt hoàn toàn âm thanh còi hú cấp cứu.")
        }
    }

    @Synchronized
    fun isPlaying(): Boolean = isPlayingSound

    @Synchronized
    fun getCurrentEventId(): String? = currentPlayingEventId
}
