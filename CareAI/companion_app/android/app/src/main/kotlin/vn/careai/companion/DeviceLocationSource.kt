package vn.careai.companion

import android.os.Build

object DeviceLocationSource {
    fun isEmulator(): Boolean {
        val hardware = Build.HARDWARE.lowercase()
        val product = Build.PRODUCT.lowercase()
        val fingerprint = Build.FINGERPRINT.lowercase()
        return hardware.contains("ranchu") || hardware.contains("goldfish") ||
            product.contains("sdk_gphone") || product.contains("emulator") ||
            fingerprint.contains("generic") || fingerprint.contains("emulator")
    }
}
