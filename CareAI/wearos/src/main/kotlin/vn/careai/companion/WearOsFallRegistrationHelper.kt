// wearos/src/main/kotlin/vn/careai/companion/WearOsFallRegistrationHelper.kt
package vn.careai.companion

import android.content.Context
import android.util.Log
import androidx.concurrent.futures.await
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.HealthEvent
import androidx.health.services.client.data.PassiveListenerConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object WearOsFallRegistrationHelper {
    private const val TAG = "CareAI-WatchRegister"

    suspend fun registerFallDetectionListener(context: Context): Boolean = withContext(Dispatchers.IO) {
        try {
            val healthClient = HealthServices.getClient(context)
            val passiveMonitoringClient = healthClient.passiveMonitoringClient

            val config = PassiveListenerConfig.builder()
                .setHealthEventTypes(setOf(HealthEvent.Type.FALL_DETECTED))
                .build()

            passiveMonitoringClient.setPassiveListenerServiceAsync(
                WearOsFallListenerService::class.java,
                config
            ).await()

            Log.i(TAG, "Đã đăng ký thành công WearOsFallListenerService với Google Health Services (FALL_DETECTED).")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Lỗi đăng ký Fall Detection với Health Services: ${e.message}", e)
            false
        }
    }
}
