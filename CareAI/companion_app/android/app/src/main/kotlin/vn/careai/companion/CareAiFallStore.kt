package vn.careai.companion

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import org.json.JSONObject

data class FallRecord(
    val eventId: String,
    val timestamp: Long,
    val deadlineAt: Long,
    val status: String, // PENDING_CONFIRMATION | SOS_QUEUED | SOS_SENT | CANCELLED_BY_USER
    val impactG: Double?,
    val rawJson: String
)

object CareAiFallStore {
    private const val PREFS_NAME = "careai_fall_records"

    // [BẤT BIẾN P0-3 & P0-2]: DÙNG DEVICE PROTECTED STORAGE ĐỂ HỖ TRỢ DIRECT BOOT
    // Cho phép đọc/ghi dữ liệu khẩn cấp ngay cả khi điện thoại vừa khởi động lại mà người dùng chưa mở khóa màn hình (Before User Unlock)
    private fun getPrefs(context: Context): SharedPreferences {
        val storageContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        return storageContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    // [BẤT BIẾN P0-2]: ATOMIC REGISTRATION & DEDUP - GHI ĐĨA VÀ CHỐNG TRÙNG LẶP TRONG 1 THAO TÁC DUY NHẤT
    fun registerFallEvent(context: Context, eventId: String, timestamp: Long, deadlineAt: Long, impactG: Double?, rawJson: String): Boolean {
        val prefs = getPrefs(context)
        if (prefs.contains("fall_$eventId")) {
            return false // Đã tồn tại sự cố này -> Duplicate -> Bỏ qua an toàn
        }

        val json = JSONObject().apply {
            put("eventId", eventId)
            put("timestamp", timestamp)
            put("deadlineAt", deadlineAt)
            put("status", "PENDING_CONFIRMATION")
            put("impactG", impactG ?: JSONObject.NULL)
            put("rawJson", rawJson)
            put("createdAt", System.currentTimeMillis())
        }.toString()

        return prefs.edit().putString("fall_$eventId", json).commit()
    }

    fun getFallRecord(context: Context, eventId: String): FallRecord? {
        val raw = getPrefs(context).getString("fall_$eventId", null) ?: return null
        return try {
            val json = JSONObject(raw)
            FallRecord(
                eventId = json.getString("eventId"),
                timestamp = json.getLong("timestamp"),
                deadlineAt = json.getLong("deadlineAt"),
                status = json.getString("status"),
                impactG = if (json.isNull("impactG")) null else json.getDouble("impactG"),
                rawJson = json.optString("rawJson", "")
            )
        } catch (_: Exception) {
            null
        }
    }

    fun getAllPendingFalls(context: Context): List<FallRecord> {
        val list = mutableListOf<FallRecord>()
        val all = getPrefs(context).all
        for ((key, value) in all) {
            if (key.startsWith("fall_") && value is String) {
                try {
                    val json = JSONObject(value)
                    val status = json.optString("status")
                    if (status == "PENDING_CONFIRMATION" || status == "SOS_QUEUED") {
                        list.add(
                            FallRecord(
                                eventId = json.getString("eventId"),
                                timestamp = json.getLong("timestamp"),
                                deadlineAt = json.getLong("deadlineAt"),
                                status = status,
                                impactG = if (json.isNull("impactG")) null else json.getDouble("impactG"),
                                rawJson = json.optString("rawJson", "")
                            )
                        )
                    }
                } catch (_: Exception) {}
            }
        }
        return list
    }

    // [BẤT BIẾN P0-2]: CẬP NHẬT TRẠNG THÁI MÀ KHÔNG LÀM PHÁ HỎNG SCHEMA WRAPPER
    fun updateStatus(context: Context, eventId: String, newStatus: String): Boolean {
        val prefs = getPrefs(context)
        val raw = prefs.getString("fall_$eventId", null) ?: return false
        return try {
            val json = JSONObject(raw).apply {
                put("status", newStatus)
                put("updatedAt", System.currentTimeMillis())
            }
            prefs.edit().putString("fall_$eventId", json.toString()).commit()
        } catch (_: Exception) {
            false
        }
    }
}
