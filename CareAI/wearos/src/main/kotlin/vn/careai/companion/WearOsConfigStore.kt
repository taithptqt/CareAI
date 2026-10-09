// wearos/src/main/kotlin/vn/careai/companion/WearOsConfigStore.kt
package vn.careai.companion

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import java.util.UUID

object WearOsConfigStore {
    private const val PREF_NAME = "careai_wear_config"
    private const val KEY_BACKEND_URL = "backend_url"
    private const val KEY_DEVICE_ID = "device_id"
    private const val KEY_DEVICE_TOKEN = "device_token"
    private const val KEY_ELDER_NAME = "elder_name"
    private const val KEY_DIRECT_WIFI_ENABLED = "direct_wifi_enabled"

    // URL máy chủ Cloud mặc định của CareAI (Đám mây Azure Production)
    const val DEFAULT_BACKEND_URL = "https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net"

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    }

    fun getBackendUrl(context: Context): String {
        val url = getPrefs(context).getString(KEY_BACKEND_URL, null)
        return if (!url.isNullOrBlank()) url else DEFAULT_BACKEND_URL
    }

    fun saveBackendUrl(context: Context, url: String) {
        getPrefs(context).edit().putString(KEY_BACKEND_URL, url.trim().trimEnd('/')).apply()
    }

    fun getDeviceId(context: Context): String {
        var id = getPrefs(context).getString(KEY_DEVICE_ID, null)
        if (id.isNullOrBlank()) {
            val serialPart = try {
                Build.SERIAL.takeIf { it.isNotBlank() && it != "unknown" } ?: UUID.randomUUID().toString().take(8)
            } catch (_: Exception) {
                UUID.randomUUID().toString().take(8)
            }
            id = "GALAXY_WATCH_${serialPart}".uppercase()
            getPrefs(context).edit().putString(KEY_DEVICE_ID, id).apply()
        }
        return id
    }

    fun getDeviceToken(context: Context): String? {
        return getPrefs(context).getString(KEY_DEVICE_TOKEN, null)
    }

    fun getElderName(context: Context): String? {
        return getPrefs(context).getString(KEY_ELDER_NAME, null)
    }

    fun isPaired(context: Context): Boolean {
        return !getDeviceToken(context).isNullOrBlank()
    }

    fun isDirectWifiEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_DIRECT_WIFI_ENABLED, true)
    }

    fun setDirectWifiEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_DIRECT_WIFI_ENABLED, enabled).apply()
    }

    fun saveCredentials(context: Context, deviceId: String, token: String, elderName: String? = null) {
        getPrefs(context).edit().apply {
            putString(KEY_DEVICE_ID, deviceId)
            putString(KEY_DEVICE_TOKEN, token)
            if (!elderName.isNullOrBlank()) {
                putString(KEY_ELDER_NAME, elderName)
            }
            apply()
        }
    }

    fun clearCredentials(context: Context) {
        getPrefs(context).edit().apply {
            remove(KEY_DEVICE_TOKEN)
            remove(KEY_ELDER_NAME)
            apply()
        }
    }
}
