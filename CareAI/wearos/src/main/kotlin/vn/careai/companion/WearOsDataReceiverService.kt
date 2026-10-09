// wearos/src/main/kotlin/vn/careai/companion/WearOsDataReceiverService.kt
package vn.careai.companion

import android.util.Log
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

class WearOsDataReceiverService : WearableListenerService() {
    private val TAG = "CareAI-WearReceiver"

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path?.startsWith("/careai/credentials") == true) {
                val dataMapItem = DataMapItem.fromDataItem(event.dataItem)
                val deviceId = dataMapItem.dataMap.getString("deviceId") ?: dataMapItem.dataMap.getString("device_id") ?: ""
                val deviceToken = dataMapItem.dataMap.getString("deviceToken") ?: dataMapItem.dataMap.getString("device_token") ?: ""
                val backendUrl = dataMapItem.dataMap.getString("backendUrl") ?: dataMapItem.dataMap.getString("backend_url") ?: ""
                val elderName = dataMapItem.dataMap.getString("elderName") ?: dataMapItem.dataMap.getString("elder_name") ?: ""

                if (deviceToken.isNotBlank()) {
                    WearOsConfigStore.saveCredentials(applicationContext, deviceId, deviceToken, elderName)
                    if (backendUrl.isNotBlank()) {
                        WearOsConfigStore.saveBackendUrl(applicationContext, backendUrl)
                    }
                    Log.i(TAG, "Đã nhận và đồng bộ thông tin xác thực từ điện thoại Android! DeviceId=$deviceId, Elder=$elderName")
                }
            }
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path == "/careai/sync_credentials") {
            try {
                val rawJson = String(messageEvent.data, Charsets.UTF_8)
                val json = JSONObject(rawJson)
                val deviceId = json.optString("deviceId", json.optString("device_id", ""))
                val deviceToken = json.optString("deviceToken", json.optString("device_token", ""))
                val backendUrl = json.optString("backendUrl", json.optString("backend_url", ""))
                val elderName = json.optString("elderName", json.optString("elder_name", ""))

                if (deviceToken.isNotBlank()) {
                    WearOsConfigStore.saveCredentials(applicationContext, deviceId, deviceToken, elderName)
                    if (backendUrl.isNotBlank()) {
                        WearOsConfigStore.saveBackendUrl(applicationContext, backendUrl)
                    }
                    Log.i(TAG, "MessageClient: Đã đồng bộ thông tin xác thực thành công từ điện thoại! DeviceId=$deviceId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Lỗi phân tích credentials message: ${e.message}")
            }
        }
    }
}
