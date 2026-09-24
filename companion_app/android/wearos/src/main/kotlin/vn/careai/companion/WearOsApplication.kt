// wearos/src/main/kotlin/vn/careai/companion/WearOsApplication.kt
package vn.careai.companion

import android.app.Application
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class WearOsApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Log.i("CareAI-Wear", "WearOsApplication khởi tạo. Đang đăng ký Fall Detection Listener với Health Services...")
        // [KHẮC PHỤC TRIỆT ĐỂ P0]: Đăng ký Listener ngay khi Application khởi động
        CoroutineScope(Dispatchers.IO).launch {
            WearOsFallRegistrationHelper.registerFallDetectionListener(applicationContext)
        }
    }
}
