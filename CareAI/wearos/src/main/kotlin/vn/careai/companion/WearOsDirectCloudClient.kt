// wearos/src/main/kotlin/vn/careai/companion/WearOsDirectCloudClient.kt
package vn.careai.companion

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

object WearOsDirectCloudClient {
    private const val TAG = "CareAI-WearCloud"

    /**
     * Kiểm tra xem đồng hồ có kết nối Internet thật sự (Wi-Fi, LTE, hoặc Ethernet) hay không
     */
    fun isNetworkAvailable(context: Context): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val network = cm.activeNetwork ?: return false
                val capabilities = cm.getNetworkCapabilities(network) ?: return false
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                        (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                         capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                         capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))
            } else {
                @Suppress("DEPRECATION")
                val activeNetworkInfo = cm.activeNetworkInfo
                activeNetworkInfo != null && activeNetworkInfo.isConnected
            }
        } catch (e: Exception) {
            Log.w(TAG, "Lỗi kiểm tra trạng thái mạng: ${e.message}")
            false
        }
    }

    /**
     * Gửi trực tiếp gói tin SOS Fast-Lane lên Central Backend qua Wi-Fi / LTE
     * Tuân thủ 100% Bất biến Fact 35: Bắt buộc đính kèm toàn bộ mẫu đo sinh hiệu (Heart Rate, SpO2)
     */
    fun sendDirectSosPacket(
        context: Context,
        packetId: String,
        eventId: String,
        emergencyType: String,
        eventTime: Long,
        heartRate: Int? = null,
        spo2: Double? = null
    ): Pair<Boolean, String> {
        val backendUrl = WearOsConfigStore.getBackendUrl(context)
        val deviceId = WearOsConfigStore.getDeviceId(context)
        val deviceToken = WearOsConfigStore.getDeviceToken(context)

        if (deviceToken.isNullOrBlank()) {
            val msg = "Đồng hồ chưa có DeviceToken ghép nối. Không thể gửi trực tiếp lên Cloud."
            Log.w(TAG, msg)
            return Pair(false, msg)
        }

        return try {
            val endpoint = "${backendUrl.trimEnd('/')}/api/v1/incidents/sos"
            Log.i(TAG, "Đang gửi SOS trực tiếp qua Wi-Fi tới: $endpoint (DeviceId=$deviceId)")
            val url = URL(endpoint)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 6000
                readTimeout = 9000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("X-DeviceId", deviceId)
                setRequestProperty("X-Device-Token", deviceToken)
            }

            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            val triggeredAtStr = isoFormat.format(Date(eventTime))

            // BẤT BIẾN FACT 35: Đính kèm mẫu đo sinh hiệu thực tế đi kèm (nếu có, không bịa đặt số liệu giả)
            val samplesArray = JSONArray()
            if (heartRate != null && heartRate > 0) {
                samplesArray.put(JSONObject().apply {
                    put("metricType", "HEART_RATE")
                    put("value", heartRate.toDouble())
                    put("unit", "bpm")
                    put("timestamp", triggeredAtStr)
                })
            }

            if (spo2 != null && spo2 > 0) {
                samplesArray.put(JSONObject().apply {
                    put("metricType", "SPO2")
                    put("value", spo2)
                    put("unit", "%")
                    put("timestamp", triggeredAtStr)
                })
            }

            val canonicalPacketId = if (packetId.startsWith("SOS_") || packetId.startsWith("FALL_")) {
                packetId
            } else {
                "${emergencyType}_$packetId"
            }

            val payload = JSONObject().apply {
                put("packetId", canonicalPacketId)
                put("eventId", eventId)
                put("emergencyType", emergencyType)
                put("severity", "CRITICAL")
                put("triggeredAt", triggeredAtStr)
                put("gpsLocation", JSONObject.NULL)
                put("gpsIsSimulated", false)
                put("samples", samplesArray)
            }

            OutputStreamWriter(conn.outputStream, "UTF-8").use { writer ->
                writer.write(payload.toString())
                writer.flush()
            }

            val responseCode = conn.responseCode
            if (responseCode in 200..299) {
                val msg = "✅ Direct Wi-Fi thành công (HTTP $responseCode)"
                Log.i(TAG, msg)
                conn.disconnect()
                Pair(true, msg)
            } else {
                val errStream = conn.errorStream ?: conn.inputStream
                val errBody = errStream?.bufferedReader()?.use { it.readText() } ?: ""
                val msg = "⚠️ Máy chủ từ chối (HTTP $responseCode): $errBody"
                Log.w(TAG, msg)
                conn.disconnect()
                Pair(false, msg)
            }
        } catch (e: Exception) {
            val msg = "❌ Lỗi mạng Wi-Fi đồng hồ: ${e.message}"
            Log.e(TAG, msg)
            Pair(false, msg)
        }
    }

    /**
     * Kích hoạt ghép nối độc lập đồng hồ trực tiếp qua mã PIN 6 số với Central Backend
     */
    fun pairWatchWithPin(context: Context, pin: String): Pair<Boolean, String> {
        val backendUrl = WearOsConfigStore.getBackendUrl(context)
        val deviceId = WearOsConfigStore.getDeviceId(context)

        return try {
            val endpoint = "${backendUrl.trimEnd('/')}/api/v1/devices/pair"
            val url = URL(endpoint)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 7000
                readTimeout = 10000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
            }

            val reqObj = JSONObject().apply {
                put("deviceId", deviceId)
                put("pairingPin", pin.trim())
                put("deviceType", "Smartwatch")
                put("deviceModel", "Samsung Galaxy Watch (Wear OS)")
            }

            OutputStreamWriter(conn.outputStream, "UTF-8").use { writer ->
                writer.write(reqObj.toString())
                writer.flush()
            }

            val responseCode = conn.responseCode
            if (responseCode in 200..299) {
                val respStr = conn.inputStream.bufferedReader().use { it.readText() }
                val respJson = JSONObject(respStr)
                val token = respJson.optString("deviceToken", "")
                val elderName = respJson.optString("fullName", "")
                if (token.isNotBlank()) {
                    WearOsConfigStore.saveCredentials(context, deviceId, token, elderName)
                    val msg = "Ghép nối thành công cho $elderName"
                    Log.i(TAG, msg)
                    conn.disconnect()
                    Pair(true, msg)
                } else {
                    conn.disconnect()
                    Pair(false, "Không tìm thấy deviceToken trong phản hồi")
                }
            } else {
                val errBody = conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                val msg = "Ghép nối thất bại (HTTP $responseCode): $errBody"
                Log.w(TAG, msg)
                conn.disconnect()
                Pair(false, msg)
            }
        } catch (e: Exception) {
            val msg = "Lỗi kết nối Wi-Fi khi ghép đôi: ${e.message}"
            Log.e(TAG, msg)
            Pair(false, msg)
        }
    }
}
