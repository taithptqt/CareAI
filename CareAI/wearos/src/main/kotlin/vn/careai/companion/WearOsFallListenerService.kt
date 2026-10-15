// wearos/src/main/kotlin/vn/careai/companion/WearOsFallListenerService.kt
package vn.careai.companion

import android.content.Context
import android.util.Log
import androidx.health.services.client.PassiveListenerService
import androidx.health.services.client.data.HealthEvent
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject

class WearOsFallListenerService : PassiveListenerService() {

    override fun onHealthEventReceived(event: HealthEvent) {
        if (event.type == HealthEvent.Type.FALL_DETECTED) {
            val eventTime = event.eventTime.toEpochMilli()
            val eventId = java.util.UUID.randomUUID().toString()
            Log.w("CareAI-Watch", "Cảm biến phần cứng Samsung Galaxy Watch phát hiện FALL_DETECTED! EventId=$eventId")

            dispatchFallAlert(
                context = applicationContext,
                eventId = eventId,
                eventTime = eventTime,
                sensorType = "SAMSUNG_BIOACTIVE_PPG_ACCEL"
            )
        }
    }

    companion object {
        fun dispatchFallAlert(
            context: Context,
            eventId: String,
            eventTime: Long,
            sensorType: String = "SAMSUNG_BIOACTIVE_PPG_ACCEL",
            heartRate: Int? = null,
            spo2: Double? = null,
            emergencyType: String = "FALL_DETECTED",
            onComplete: ((success: Boolean, channel: String) -> Unit)? = null
        ) {
            // [KHẮC PHỤC TRIỆT ĐỂ P1-11]: TRUNG THỰC DỮ LIỆU CẢM BIẾN (SENSOR DATA TRUTH)
            try {
                val vibrator = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? android.os.VibratorManager
                    vm?.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    context.getSystemService(Context.VIBRATOR_SERVICE) as? android.os.Vibrator
                }
                if (vibrator != null && vibrator.hasVibrator()) {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        val timings = longArrayOf(0, 450, 180, 450, 180, 700)
                        val amplitudes = intArrayOf(0, 255, 0, 255, 0, 255)
                        val effect = android.os.VibrationEffect.createWaveform(timings, amplitudes, -1)
                        vibrator.vibrate(effect)
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(longArrayOf(0, 450, 180, 450, 180, 700), -1)
                    }
                }
            } catch (e: Exception) {
                Log.w("CareAI-Watch", "Không thể kích hoạt rung khẩn cấp: ${e.message}")
            }

            val payloadJson = JSONObject().apply {
                put("eventId", eventId)
                put("eventType", if (emergencyType == "FALL_DETECTED") "HARDWARE_FALL_DETECTED" else "MANUAL_SOS_ALERT")
                put("timestamp", eventTime)
                put("source", "SAMSUNG_GALAXY_WATCH_HARDWARE_SENSOR")
                put("isHardwareVerified", true)
                put("sensorType", sensorType)
                put("impactG", JSONObject.NULL)
                if (heartRate != null) put("heartRate", heartRate)
                if (spo2 != null) put("spo2", spo2)
            }.toString()
            val payloadBytes = payloadJson.toByteArray(Charsets.UTF_8)

            Thread {
                var messageSuccess = false
                var directCloudSuccess = false
                var channelInfo = "Đang truyền tín hiệu..."

                // KÊNH 1: Fast-Lane MessageClient qua Bluetooth sang điện thoại (Ưu tiên tiết kiệm pin 0ms)
                try {
                    val nodeClient = Wearable.getNodeClient(context)
                    val nodes = Tasks.await(nodeClient.connectedNodes, 1500, java.util.concurrent.TimeUnit.MILLISECONDS)
                    if (nodes.isEmpty()) {
                        Log.w("CareAI-Watch", "Chưa kết nối điện thoại qua Bluetooth. Sẽ chuyển mạch tự động (Failover) sang Wi-Fi / Cloud...")
                    } else {
                        for (node in nodes) {
                            Tasks.await(
                                Wearable.getMessageClient(context).sendMessage(node.id, "/careai/fall_detected", payloadBytes),
                                1500,
                                java.util.concurrent.TimeUnit.MILLISECONDS
                            )
                            Log.i("CareAI-Watch", "MessageClient fast-lane đã gửi thành công tới node: ${node.displayName} (${node.id})")
                            messageSuccess = true
                        }
                    }
                } catch (e: Exception) {
                    Log.e("CareAI-Watch", "Lỗi MessageClient fast-lane Bluetooth: ${e.message}")
                }

                // KÊNH 2: Store-and-Forward DataClient chạy song song bảo toàn gói tin khi khôi phục sóng Bluetooth
                try {
                    val putDataReq = com.google.android.gms.wearable.PutDataMapRequest.create("/careai/fall_event/$eventId").apply {
                        dataMap.putString("payloadJson", payloadJson)
                        dataMap.putLong("timestamp", eventTime)
                        dataMap.putString("eventId", eventId)
                    }.asPutDataRequest().setUrgent()

                    Tasks.await(Wearable.getDataClient(context).putDataItem(putDataReq), 2500, java.util.concurrent.TimeUnit.MILLISECONDS)
                    Log.i("CareAI-Watch", "DataClient persistent store-and-forward thành công: $eventId")
                } catch (e: Exception) {
                    Log.e("CareAI-Watch", "Lỗi DataClient: ${e.message}")
                }

                // KÊNH 3 (MỚI): Direct Wi-Fi / LTE Cloud Fallover (Truyền trực tiếp lên Central Backend)
                // Kích hoạt khi:
                // 1) Bluetooth không gửi được (điện thoại ở xa / tắt nguồn / ngoài tầm sóng)
                // 2) Hoặc đồng hồ có kết nối Wi-Fi / LTE và đã có cấu hình xác thực (True Hybrid Parity với Apple Watch)
                val isDirectWifiEnabled = WearOsConfigStore.isDirectWifiEnabled(context)
                if (isDirectWifiEnabled && (!messageSuccess || WearOsDirectCloudClient.isNetworkAvailable(context))) {
                    try {
                        val (cloudOk, cloudMsg) = WearOsDirectCloudClient.sendDirectSosPacket(
                            context = context,
                            packetId = "SOS_WEAR_${eventId}",
                            eventId = eventId,
                            emergencyType = emergencyType,
                            eventTime = eventTime,
                            heartRate = heartRate,
                            spo2 = spo2
                        )
                        directCloudSuccess = cloudOk
                        Log.i("CareAI-Watch", "Kênh 3 Direct Wi-Fi Cloud kết quả: $cloudOk ($cloudMsg)")
                    } catch (e: Exception) {
                        Log.e("CareAI-Watch", "Lỗi Kênh 3 Direct Wi-Fi: ${e.message}")
                    }
                }

                // Tổng hợp kênh truyền thành công
                channelInfo = when {
                    messageSuccess && directCloudSuccess -> "✅ Đã gửi qua Bluetooth & Wi-Fi Cloud"
                    directCloudSuccess -> "🌐 Đã gửi trực tiếp lên Cloud qua Wi-Fi"
                    messageSuccess -> "✅ Đã gửi sang điện thoại qua Bluetooth"
                    else -> "⚠️ Đã lưu bộ đệm (Sẽ gửi khi có mạng/Bluetooth)"
                }

                val overallSuccess = messageSuccess || directCloudSuccess
                onComplete?.invoke(overallSuccess, channelInfo)
            }.start()
        }
    }
}
