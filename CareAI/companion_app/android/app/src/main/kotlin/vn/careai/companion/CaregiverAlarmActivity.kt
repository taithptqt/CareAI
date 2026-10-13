package vn.careai.companion

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Native alarm screen so a critical alert can be shown before Flutter is started. */
class CaregiverAlarmActivity : Activity() {
    private var incidentId: String? = null
    private var cycle = 1
    private lateinit var status: TextView

    private val closeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_CLOSED) return
            if (intent.getStringExtra("incidentId") == incidentId &&
                intent.getIntExtra("alertCycleNumber", 1) >= cycle) finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = Color.rgb(124, 16, 22)
        window.navigationBarColor = Color.rgb(77, 13, 17)
        val filter = IntentFilter(ACTION_CLOSED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(closeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(closeReceiver, filter)
        }
        render(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render(intent)
    }

    private fun render(alertIntent: Intent) {
        incidentId = alertIntent.getStringExtra("incidentId")?.takeIf { it.isNotBlank() }
        cycle = alertIntent.getIntExtra("alertCycleNumber", 1)
        if (incidentId == null) { finish(); return }
        val kind = alertIntent.getStringExtra("emergencyType")?.uppercase() ?: ""
        val title = alertIntent.getStringExtra("title")?.uppercase() ?: ""
        val heading = when {
            kind.contains("FALL") || title.contains("FALL") || title.contains("NGÃ") -> "PHÁT HIỆN TÉ NGÃ"
            kind.contains("LOW_OXYGEN") || kind.contains("LOWOXYGEN") || title.contains("OXYGEN") || title.contains("SPO2") -> "OXY MÁU (SpO₂) THẤP"
            kind.contains("TACHYCARDIA") || title.contains("NHANH") -> "NHỊP TIM QUÁ NHANH"
            kind.contains("BRADYCARDIA") || title.contains("CHẬM") -> "NHỊP TIM QUÁ CHẬM"
            kind.contains("SURGE") || title.contains("ĐỘT BIẾN") -> "NHỊP TIM TĂNG ĐỘT BIẾN"
            kind.contains("HYPERTENSION") || title.contains("HUYẾT ÁP") -> "CƠN TĂNG HUYẾT ÁP"
            kind.contains("STALE") || kind.contains("OFFLINE") || title.contains("MẤT TÍN HIỆU") || title.contains("MẤT KẾT NỐI") -> "THIẾT BỊ MẤT TÍN HIỆU"
            kind.contains("SOS") || title.contains("SOS") -> "BẤM NÚT KHẨN CẤP SOS"
            else -> "CẢNH BÁO KHẨN CẤP"
        }
        val isStale = kind.contains("STALE") || kind.contains("OFFLINE") || title.contains("MẤT TÍN HIỆU") || title.contains("MẤT KẾT NỐI")
        val isVital = kind.contains("LOW_OXYGEN") || kind.contains("LOWOXYGEN") || kind.contains("TACHYCARDIA") ||
            kind.contains("BRADYCARDIA") || kind.contains("SURGE") || kind.contains("HYPERTENSION")

        val bgColor = when {
            isStale -> Color.rgb(180, 83, 9) // Amber 700
            isVital -> Color.rgb(194, 65, 12) // Orange 700
            else -> Color.rgb(145, 20, 27) // Red 800
        }
        val statusBarCol = when {
            isStale -> Color.rgb(146, 64, 14)
            isVital -> Color.rgb(154, 52, 18)
            else -> Color.rgb(124, 16, 22)
        }
        val navBarCol = when {
            isStale -> Color.rgb(120, 53, 15)
            isVital -> Color.rgb(124, 45, 18)
            else -> Color.rgb(77, 13, 17)
        }
        window.statusBarColor = statusBarCol
        window.navigationBarColor = navBarCol

        val iconEmoji = when {
            isStale -> "📡"
            kind.contains("FALL") || title.contains("FALL") || title.contains("NGÃ") -> "⚠️"
            kind.contains("LOW_OXYGEN") || kind.contains("LOWOXYGEN") || title.contains("OXYGEN") || title.contains("SPO2") -> "🫁"
            kind.contains("TACHYCARDIA") || kind.contains("BRADYCARDIA") || kind.contains("SURGE") -> "💓"
            kind.contains("HYPERTENSION") -> "🩺"
            else -> "🚨"
        }
        val subHeading = when {
            isStale -> "CẦN KIỂM TRA THIẾT BỊ"
            isVital -> "CẦN THEO DÕI SINH HIỆU"
            else -> "CẦN TRỢ GIÚP NGAY"
        }

        val detail = alertIntent.getStringExtra("body")?.takeIf { it.isNotBlank() }
            ?: (if (isStale) "Tất cả thiết bị của người thân đã mất kết nối." else "Người thân của bạn cần được trợ giúp ngay.")

        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()
        fun label(text: String, size: Float, bold: Boolean = false): TextView = TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            if (bold) typeface = Typeface.DEFAULT_BOLD
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(28), dp(24), dp(28))
            setBackgroundColor(bgColor)
        }
        val scroll = ScrollView(this).apply { isFillViewport = true; addView(root) }
        setContentView(scroll)

        root.addView(label(iconEmoji, 72f), LinearLayout.LayoutParams(-1, dp(110)))
        root.addView(label(subHeading, 19f, true))
        root.addView(label(heading, 33f, true).apply {
            setPadding(0, dp(20), 0, dp(20))
        })
        root.addView(label(detail, 22f).apply {
            setPadding(dp(8), dp(8), dp(8), dp(30))
        })
        status = label(if (isStale) "Cảnh báo mất tín hiệu. Hãy kiểm tra kết nối thiết bị." else "Còi báo động đang phát. Hãy kiểm tra và tiếp nhận sự cố.", 15f)
        root.addView(status)

        val openTextColor = when {
            isStale -> Color.rgb(146, 64, 14)
            isVital -> Color.rgb(154, 52, 18)
            else -> Color.rgb(105, 12, 18)
        }
        val silenceBgColor = when {
            isStale -> Color.rgb(146, 64, 14)
            isVital -> Color.rgb(154, 52, 18)
            else -> Color.rgb(98, 15, 21)
        }

        val open = Button(this).apply {
            text = if (isStale) "XEM KẾT NỐI / TIẾP NHẬN" else "XEM SỰ CỐ / TIẾP NHẬN"
            textSize = 17f
            isAllCaps = false
            setTextColor(openTextColor)
            setBackgroundColor(Color.WHITE)
            setOnClickListener {
                startActivity(Intent(this@CaregiverAlarmActivity, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("caregiver_incident_id", incidentId)
                })
                finish()
            }
        }
        root.addView(open, LinearLayout.LayoutParams(-1, dp(68)).apply { topMargin = dp(38) })

        val silence = Button(this).apply {
            text = "Tắt âm (sự cố vẫn đang mở)"
            textSize = 15f
            isAllCaps = false
            setTextColor(Color.WHITE)
            setBackgroundColor(silenceBgColor)
            setOnClickListener {
                startService(Intent(this@CaregiverAlarmActivity, CaregiverAlertService::class.java).apply {
                    action = CaregiverAlertService.ACTION_SILENCE
                })
                status.text = "Đã tắt âm. Sự cố vẫn cần được tiếp nhận."
            }
        }
        root.addView(silence, LinearLayout.LayoutParams(-1, dp(56)).apply { topMargin = dp(14) })
        root.addView(label(if (isStale) "Kiểm tra pin, Bluetooth hoặc vị trí người thân." else "Mở sự cố để xác nhận hoặc liên hệ cấp cứu nếu cần.", 14f).apply {
            setPadding(0, dp(24), 0, 0)
        })
    }

    override fun onDestroy() {
        unregisterReceiver(closeReceiver)
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onDestroy()
    }

    companion object {
        const val ACTION_CLOSED = "vn.careai.companion.CAREGIVER_ALARM_CLOSED"
    }
}
