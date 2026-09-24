// wearos/src/main/kotlin/vn/careai/companion/WearOsBootReceiver.kt
package vn.careai.companion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class WearOsBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i("CareAI-Wear", "Nhận ACTION_BOOT_COMPLETED. Tự động tái đăng ký Fall Detection...")
            val appContext = context.applicationContext
            CoroutineScope(Dispatchers.IO).launch {
                WearOsFallRegistrationHelper.registerFallDetectionListener(appContext)
            }
        }
    }
}
