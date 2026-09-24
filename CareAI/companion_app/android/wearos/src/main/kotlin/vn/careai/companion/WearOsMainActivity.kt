// wearos/src/main/kotlin/vn/careai/companion/WearOsMainActivity.kt
package vn.careai.companion

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.TextView

class WearOsMainActivity : Activity() {

    private lateinit var tvStatus: TextView
    private lateinit var tvVitals: TextView
    private lateinit var tvLogResult: TextView
    private lateinit var btnSimulateFall: Button
    private lateinit var btnManualSos: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_wear_main)

        tvStatus = findViewById(R.id.tvStatus)
        tvVitals = findViewById(R.id.tvVitals)
        tvLogResult = findViewById(R.id.tvLogResult)
        btnSimulateFall = findViewById(R.id.btnSimulateFall)
        btnManualSos = findViewById(R.id.btnManualSos)

        tvStatus.text = "🟢 Đang Giám Sát Cổ Tay"
        tvVitals.text = "❤️ 76 BPM · 98% SpO2"
        tvLogResult.text = "Cảm biến BioActive sẵn sàng"

        // Nút kích hoạt mô phỏng té ngã phần cứng
        btnSimulateFall.setOnClickListener {
            val eventId = "FALL_WEAR_${System.currentTimeMillis()}"
            val timestamp = System.currentTimeMillis()
            Log.w("CareAI-WearActivity", "Người dùng nhấn nút [THỬ NGHIỆM TÉ NGÃ] trên mặt đồng hồ! EventId=$eventId")
            tvLogResult.text = "Đang phát sóng Bluetooth Data Layer..."

            WearOsFallListenerService.dispatchFallAlert(
                context = this,
                eventId = eventId,
                eventTime = timestamp,
                sensorType = "SAMSUNG_BIOACTIVE_SIMULATED_TEST"
            ) { success ->
                runOnUiThread {
                    if (success) {
                        tvLogResult.text = "✅ Đã bắn tín hiệu ngã sang điện thoại!"
                    } else {
                        tvLogResult.text = "⚠️ Đã lưu vào DataClient (Store-and-Forward)"
                    }
                }
            }
        }

        // Nút phát SOS khẩn cấp bằng tay từ đồng hồ
        btnManualSos.setOnClickListener {
            val eventId = "SOS_WATCH_${System.currentTimeMillis()}"
            val timestamp = System.currentTimeMillis()
            Log.w("CareAI-WearActivity", "Người dùng nhấn nút [BẮN TÍN HIỆU SOS] trên mặt đồng hồ! EventId=$eventId")
            tvLogResult.text = "Đang gửi SOS khẩn cấp..."

            WearOsFallListenerService.dispatchFallAlert(
                context = this,
                eventId = eventId,
                eventTime = timestamp,
                sensorType = "WATCH_TOUCH_SOS"
            ) { success ->
                runOnUiThread {
                    if (success) {
                        tvLogResult.text = "✅ Đã gửi SOS sang điện thoại!"
                    } else {
                        tvLogResult.text = "⚠️ Đã lưu SOS vào DataClient"
                    }
                }
            }
        }
    }
}
