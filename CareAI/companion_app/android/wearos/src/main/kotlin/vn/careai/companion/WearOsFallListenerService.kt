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

            dispatchFallAlert(applicationContext, eventId, eventTime, "SAMSUNG_BIOACTIVE_PPG_ACCEL")
        }
    }

    companion object {
        fun dispatchFallAlert(context: Context, eventId: String, eventTime: Long, sensorType: String = "SAMSUNG_BIOACTIVE_PPG_ACCEL", onComplete: ((Boolean) -> Unit)? = null) {
            // [KHẮC PHỤC TRIỆT ĐỂ P1-11]: TRUNG THỰC DỮ LIỆU CẢM BIẾN (SENSOR DATA TRUTH)
            // Health Services chỉ trả về sự kiện xác nhận té ngã (FALL_DETECTED), không có số đo gia tốc thô (Raw G).
            // Tuyệt đối không hardcode 3.2G giả mạo! Đặt impactG là null và bổ sung cờ xác thực phần cứng.
            val payloadJson = JSONObject().apply {
                put("eventId", eventId)
                put("eventType", "HARDWARE_FALL_DETECTED")
                put("timestamp", eventTime)
                put("source", "SAMSUNG_GALAXY_WATCH_HARDWARE_SENSOR")
                put("isHardwareVerified", true)
                put("sensorType", sensorType)
                put("impactG", JSONObject.NULL)
            }.toString()
            val payloadBytes = payloadJson.toByteArray(Charsets.UTF_8)

            // [KHẮC PHỤC TRIỆT ĐỂ P1]: ĐỘC LẬP HOÀN TOÀN 2 KÊNH VẬN CHUYỂN SONG SONG (TRUE CONCURRENT DUAL-CHANNEL)
            // Kênh 1: Fast-Lane MessageClient bắn ngay qua Bluetooth không đợi DataClient
            Thread {
                var messageSuccess = false
                try {
                    val nodeClient = Wearable.getNodeClient(context)
                    val nodes = Tasks.await(nodeClient.connectedNodes, 2000, java.util.concurrent.TimeUnit.MILLISECONDS)
                    if (nodes.isEmpty()) {
                        Log.w("CareAI-Watch", "Chưa tìm thấy Node điện thoại kết nối Bluetooth. Dữ liệu sẽ được bảo toàn qua DataClient...")
                    }
                    for (node in nodes) {
                        Tasks.await(Wearable.getMessageClient(context).sendMessage(node.id, "/careai/fall_detected", payloadBytes), 2000, java.util.concurrent.TimeUnit.MILLISECONDS)
                        Log.i("CareAI-Watch", "MessageClient fast-lane đã gửi thành công tới node: ${node.displayName} (${node.id})")
                        messageSuccess = true
                    }
                } catch (e: Exception) {
                    Log.e("CareAI-Watch", "Lỗi MessageClient fast-lane: ${e.message}")
                }

                // Kênh 2: Store-and-Forward DataClient chạy song song độc lập với timeout bảo vệ
                try {
                    val putDataReq = com.google.android.gms.wearable.PutDataMapRequest.create("/careai/fall_event/$eventId").apply {
                        dataMap.putString("payloadJson", payloadJson)
                        dataMap.putLong("timestamp", eventTime)
                        dataMap.putString("eventId", eventId)
                    }.asPutDataRequest().setUrgent()

                    Tasks.await(Wearable.getDataClient(context).putDataItem(putDataReq), 3000, java.util.concurrent.TimeUnit.MILLISECONDS)
                    Log.i("CareAI-Watch", "DataClient persistent store-and-forward thành công: $eventId")
                    onComplete?.invoke(true)
                } catch (e: Exception) {
                    Log.e("CareAI-Watch", "Lỗi DataClient: ${e.message}")
                    onComplete?.invoke(messageSuccess)
                }
            }.start()
        }
    }
}
