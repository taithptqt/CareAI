package vn.careai.companion

import android.content.Intent
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
                    sendBroadcast(Intent("vn.careai.watch.CREDENTIALS_UPDATED").apply {
                        setPackage(packageName)
                    })
                    dispatchTelemetryFromService()
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
                    sendBroadcast(Intent("vn.careai.watch.CREDENTIALS_UPDATED").apply {
                        setPackage(packageName)
                    })
                    dispatchTelemetryFromService()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Lỗi phân tích credentials message: ${e.message}")
            }
        } else if (messageEvent.path == "/careai/request_telemetry") {
            Log.i(TAG, "Nhận yêu cầu cập nhật viễn trắc từ điện thoại Android (/careai/request_telemetry)")
            dispatchTelemetryFromService()
            sendBroadcast(Intent("vn.careai.watch.REQUEST_TELEMETRY").apply {
                setPackage(packageName)
            })
        }
    }

    private fun dispatchTelemetryFromService() {
        try {
            val ifilter = android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus: Intent? = registerReceiver(null, ifilter)
            val status: Int = batteryStatus?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ?: -1
            val isCharging = status == android.os.BatteryManager.BATTERY_STATUS_CHARGING || status == android.os.BatteryManager.BATTERY_STATUS_FULL
            val level: Int = batteryStatus?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale: Int = batteryStatus?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
            val batteryLevel = if (level >= 0 && scale > 0) (level * 100 / scale) else 100
            val isWorn = !isCharging
            WearOsMainActivity.dispatchWatchTelemetry(applicationContext, isWorn, isCharging, batteryLevel)
            Log.i(TAG, "Đã gửi telemetry trực tiếp từ background service: Pin=$batteryLevel%, Sạc=$isCharging, Đeo=$isWorn")
        } catch (e: Exception) {
            Log.w(TAG, "Lỗi đọc battery và gửi telemetry từ service: ${e.message}")
        }
    }
}
