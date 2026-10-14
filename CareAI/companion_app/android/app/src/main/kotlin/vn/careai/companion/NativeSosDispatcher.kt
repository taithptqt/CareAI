package vn.careai.companion

import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager

import android.os.Build
import android.os.CancellationSignal
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.work.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

object NativeSosDispatcher {

    // [BẤT BIẾN P0-2]: STRICT OUTBOX-FIRST SOS VỚI DEVICE PROTECTED STORAGE
    fun dispatchOutboxFirstSos(context: Context, record: FallRecord) {
        val appPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val serverUrl = appPrefs.getString("flutter.server_base_url", "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net") ?: "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"
        val deviceId = appPrefs.getString("flutter.device_id", "") ?: ""
        val deviceToken = appPrefs.getString("flutter.device_token", "") ?: ""
        val gpsAt = appPrefs.getLong("flutter.careai_recent_gps_at", 0L)
        val recentGps = appPrefs.getString("flutter.careai_recent_gps", null)
        val recentGpsSimulated = appPrefs.getBoolean("flutter.careai_recent_gps_simulated", false)
        val hadFreshGps = recentGps != null && gpsAt > 0 &&
            kotlin.math.abs(System.currentTimeMillis() - gpsAt) <= 15_000L

        // [BẤT BIẾN P0-4]: ĐỒNG NHẤT CANONICAL PACKETID (CHỐNG DUPLICATE RACE CONDITION VỚI FLUTTER)
        val canonicalPacketId = "FALL_${record.eventId}"
        val nativeGps = getNativeLastKnownLocation(context)

        val payload = JSONObject().apply {
            put("deviceId", deviceId)
            put("packetId", canonicalPacketId)
            put("eventId", record.eventId)
            put("emergencyType", "FALL")
            if (hadFreshGps) {
                put("gpsLocation", recentGps)
                put("gpsIsSimulated", recentGpsSimulated || DeviceLocationSource.isEmulator())
            }
            put("notes", "CẢNH BÁO TÉ NGÃ NATIVE FAIL-SAFE: Cảm biến Galaxy Watch xác nhận ngã phần cứng. Watchdog OS kích hoạt Outbox-First SOS.")
            if (nativeGps != null) {
                put("gpsLocation", nativeGps)
            }
            val timeIso = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Instant.ofEpochMilli(record.timestamp).toString() else record.timestamp.toString()
            put("samples", JSONArray().apply {
                put(JSONObject().apply {
                    put("metricType", "FALL")
                    if (record.impactG != null) put("value", record.impactG) else put("value", 1.0)
                    put("unit", "G")
                    put("timestamp", timeIso)
                })
                // BẤT BIẾN FACT 35: Gói tin Fast-Lane SOS lưu toàn bộ mẫu đo sinh hiệu thực tế đi kèm (nếu có, không bịa đặt số liệu giả)
                if (appPrefs.contains("flutter.careai_last_heart_rate")) {
                    val lastHr = appPrefs.getFloat("flutter.careai_last_heart_rate", 0f).toDouble()
                    if (lastHr > 0) {
                        put(JSONObject().apply {
                            put("metricType", "HEART_RATE")
                            put("value", lastHr)
                            put("unit", "bpm")
                            put("timestamp", timeIso)
                        })
                    }
                }
                if (appPrefs.contains("flutter.careai_last_spo2")) {
                    val lastSpo2 = appPrefs.getFloat("flutter.careai_last_spo2", 0f).toDouble()
                    if (lastSpo2 > 0) {
                        put(JSONObject().apply {
                            put("metricType", "SPO2")
                            put("value", lastSpo2)
                            put("unit", "%")
                            put("timestamp", timeIso)
                        })
                    }
                }
            })
        }.toString()

        // BƯỚC 1: GHI ĐĨA OUTBOX TRONG DEVICE PROTECTED STORAGE BẰNG COMMIT()
        val storageContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) context.createDeviceProtectedStorageContext() else context
        val outboxPrefs = storageContext.getSharedPreferences("careai_native_sos_outbox", Context.MODE_PRIVATE)
        outboxPrefs.edit().putString("outbox_${record.eventId}", payload).commit()
        Log.w("CareAI-Dispatcher", "[OUTBOX-FIRST] BƯỚC 1: Đã commit payload sự cố ${record.eventId} vào Outbox đĩa!")

        // BƯỚC 2: CẬP NHẬT TRẠNG THÁI SANG SOS_QUEUED TRÊN ĐĨA
        CareAiFallStore.updateStatus(context, record.eventId, "SOS_QUEUED")
        Log.w("CareAI-Dispatcher", "[OUTBOX-FIRST] BƯỚC 2: Đã cập nhật trạng thái sự cố ${record.eventId} -> SOS_QUEUED!")

        // BƯỚC 3: BÀN GIAO WORKMANAGER ĐẢM BẢO RETRY XUYÊN SUỐT NẾU TIẾN TRÌNH BỊ KILL
        enqueueWorkManagerRetry(context, record.eventId)

        // BƯỚC 4: THỬ FAST-PATH DIRECT HTTP POST TRONG BACKGROUND COROUTINE
        CoroutineScope(Dispatchers.IO).launch {
            if (deviceId.isEmpty() || deviceToken.isEmpty()) {
                Log.e("CareAI-Dispatcher", "Thiếu deviceId/token. Giữ nguyên sự cố ${record.eventId} trong Outbox chờ cấu hình!")
                return@launch
            }

            try {
                Log.i("CareAI-Dispatcher", "[OUTBOX-FIRST] BƯỚC 4: Thử Fast-Path HTTP POST tới máy chủ: $serverUrl/api/v1/incidents/sos")
                val url = URL("$serverUrl/api/v1/incidents/sos")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                // [BẤT BIẾN P0-2]: SỬA LỖI TYPO HEADER TỪ X-Device-Id SANG X-DeviceId CHÍNH XÁC
                conn.setRequestProperty("X-DeviceId", deviceId)
                conn.setRequestProperty("X-Device-Token", deviceToken)
                conn.doOutput = true
                conn.connectTimeout = 8000
                conn.readTimeout = 8000

                conn.outputStream.use { os ->
                    os.write(payload.toByteArray(Charsets.UTF_8))
                }

                val responseCode = conn.responseCode
                if (responseCode in 200..299) {
                    val responseBody = conn.inputStream.bufferedReader().use { it.readText() }
                    Log.w("CareAI-Dispatcher", "[OUTBOX-FIRST SUCCESS] Máy chủ xác nhận HTTP $responseCode! Cập nhật SOS_SENT và xóa Outbox.")
                    CareAiFallStore.updateStatus(context, record.eventId, "SOS_SENT")
                    outboxPrefs.edit().remove("outbox_${record.eventId}").commit()
                    WorkManager.getInstance(context).cancelUniqueWork("native_sos_retry_${record.eventId}")
                    val incidentId = JSONObject(responseBody).optString("incidentId")
                    if (incidentId.isNotBlank() && !hadFreshGps) {
                        attachCurrentLocation(context, serverUrl, deviceId, deviceToken, incidentId)
                    }
                } else {
                    Log.e("CareAI-Dispatcher", "[FAST-PATH FAILED] HTTP $responseCode. Sự cố vẫn nằm an toàn trong Outbox cho WorkManager!")
                }
            } catch (e: Exception) {
                Log.e("CareAI-Dispatcher", "[FAST-PATH EXCEPTION] Lỗi kết nối mạng: ${e.message}. Sự cố vẫn nằm an toàn trong Outbox cho WorkManager!")
            }
        }
    }

    fun getNativeLastKnownLocation(context: Context): String? {
        return try {
            val fine = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val coarse = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
            if (!fine && !coarse) return null

            val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
            var bestLoc: android.location.Location? = null

            try {
                if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    val loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                    if (loc != null) bestLoc = loc
                }
            } catch (_: SecurityException) {}

            try {
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    val loc = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                    if (loc != null && (bestLoc == null || loc.time > bestLoc.time)) {
                        bestLoc = loc
                    }
                }
            } catch (_: SecurityException) {}

            if (bestLoc != null) {
                "${String.format(java.util.Locale.US, "%.6f", bestLoc.latitude)}, ${String.format(java.util.Locale.US, "%.6f", bestLoc.longitude)}"
            } else null
        } catch (e: Exception) {
            Log.w("CareAI-Dispatcher", "Không thể lấy vị trí native: ${e.message}")
            null
        }
    }

    suspend fun attachCurrentLocation(context: Context, serverUrl: String,
                                      deviceId: String, deviceToken: String, incidentId: String) {
        if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val provider = when {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> return
        }
        try {
            val location = withTimeoutOrNull(15_000L) {
                suspendCancellableCoroutine<Location?> { continuation ->
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val cancellation = CancellationSignal()
                        continuation.invokeOnCancellation { cancellation.cancel() }
                        manager.getCurrentLocation(provider, cancellation, context.mainExecutor) {
                            if (continuation.isActive) continuation.resume(it)
                        }
                    } else {
                        continuation.resume(manager.getLastKnownLocation(provider))
                    }
                }
            } ?: return
            if (kotlin.math.abs(System.currentTimeMillis() - location.time) > 30_000L) return
            val coordinates = String.format(java.util.Locale.US, "%.6f, %.6f", location.latitude, location.longitude)
            val body = JSONObject().apply {
                put("coordinates", coordinates)
                put("capturedAt", Instant.ofEpochMilli(location.time).toString())
                put("isSimulated", DeviceLocationSource.isEmulator() ||
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) location.isMock
                    else location.isFromMockProvider)
                if (location.hasAccuracy()) put("accuracyMeters", location.accuracy.toDouble())
            }.toString()
            val conn = URL("$serverUrl/api/v1/incidents/$incidentId/location").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("X-DeviceId", deviceId)
            conn.setRequestProperty("X-Device-Token", deviceToken)
            conn.doOutput = true
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            Log.i("CareAI-Dispatcher", "Đã gửi GPS hiện tại của sự cố $incidentId: HTTP ${conn.responseCode}")
            conn.disconnect()
        } catch (e: Exception) {
            Log.w("CareAI-Dispatcher", "Không lấy/gửi được GPS hiện tại: ${e.javaClass.simpleName}")
        }
    }

    fun enqueueWorkManagerRetry(context: Context, eventId: String) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val workRequest = OneTimeWorkRequestBuilder<NativeSosRetryWorker>()
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .setInputData(workDataOf("eventId" to eventId))
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            "native_sos_retry_$eventId",
            ExistingWorkPolicy.KEEP,
            workRequest
        )
    }
}

class NativeSosRetryWorker(appContext: Context, workerParams: WorkerParameters) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        val eventId = inputData.getString("eventId") ?: return Result.failure()
        val storageContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) applicationContext.createDeviceProtectedStorageContext() else applicationContext
        val outboxPrefs = storageContext.getSharedPreferences("careai_native_sos_outbox", Context.MODE_PRIVATE)
        val payload = outboxPrefs.getString("outbox_$eventId", null) ?: return Result.success()

        val appPrefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val serverUrl = appPrefs.getString("flutter.server_base_url", "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net") ?: "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"
        val deviceId = appPrefs.getString("flutter.device_id", "") ?: ""
        val deviceToken = appPrefs.getString("flutter.device_token", "") ?: ""

        if (deviceId.isEmpty() || deviceToken.isEmpty()) {
            return Result.retry()
        }

        return try {
            val url = URL("$serverUrl/api/v1/incidents/sos")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            // [BẤT BIẾN P0-2]: SỬA LỖI TYPO HEADER TỪ X-Device-Id SANG X-DeviceId CHÍNH XÁC
            conn.setRequestProperty("X-DeviceId", deviceId)
            conn.setRequestProperty("X-Device-Token", deviceToken)
            conn.doOutput = true
            conn.connectTimeout = 10000
            conn.readTimeout = 10000

            conn.outputStream.use { os ->
                os.write(payload.toByteArray(Charsets.UTF_8))
            }

            val responseCode = conn.responseCode
            if (responseCode in 200..299) {
                val responseBody = conn.inputStream.bufferedReader().use { it.readText() }
                Log.w("CareAI-RetryWorker", "[RETRY SUCCESS] WorkManager đã gửi thành công SOS sự cố $eventId! HTTP $responseCode")
                CareAiFallStore.updateStatus(applicationContext, eventId, "SOS_SENT")
                outboxPrefs.edit().remove("outbox_$eventId").commit()
                val incidentId = JSONObject(responseBody).optString("incidentId")
                if (incidentId.isNotBlank()) {
                    NativeSosDispatcher.attachCurrentLocation(applicationContext, serverUrl,
                        deviceId, deviceToken, incidentId)
                }
                Result.success()
            } else {
                Log.e("CareAI-RetryWorker", "[RETRY FAILED] HTTP $responseCode. WorkManager sẽ thử lại với Exponential Backoff...")
                Result.retry()
            }
        } catch (e: Exception) {
            Log.e("CareAI-RetryWorker", "[RETRY EXCEPTION] Lỗi mạng: ${e.message}. Sẽ thử lại...", e)
            Result.retry()
        }
    }
}
