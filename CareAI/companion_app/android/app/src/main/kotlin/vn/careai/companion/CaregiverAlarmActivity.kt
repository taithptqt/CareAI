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
        val heading = if (kind.contains("FALL") || title.contains("FALL") || title.contains("NGÃ"))
            "PHÁT HIỆN TÉ NGÃ" else "CẢNH BÁO KHẨN CẤP"
        val detail = alertIntent.getStringExtra("body")?.takeIf { it.isNotBlank() }
            ?: "Người thân của bạn cần được trợ giúp ngay."

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
            setBackgroundColor(Color.rgb(145, 20, 27))
        }
        val scroll = ScrollView(this).apply { isFillViewport = true; addView(root) }
        setContentView(scroll)

        root.addView(label("🚨", 72f), LinearLayout.LayoutParams(-1, dp(110)))
        root.addView(label("CẦN TRỢ GIÚP NGAY", 19f, true))
        root.addView(label(heading, 33f, true).apply {
            setPadding(0, dp(20), 0, dp(20))
        })
        root.addView(label(detail, 22f).apply {
            setPadding(dp(8), dp(8), dp(8), dp(30))
        })
        status = label("Còi báo động đang phát. Hãy kiểm tra và tiếp nhận sự cố.", 15f)
        root.addView(status)

        val open = Button(this).apply {
            text = "XEM SỰ CỐ / TIẾP NHẬN"
            textSize = 17f
            isAllCaps = false
            setTextColor(Color.rgb(105, 12, 18))
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
            setBackgroundColor(Color.rgb(98, 15, 21))
            setOnClickListener {
                startService(Intent(this@CaregiverAlarmActivity, CaregiverAlertService::class.java).apply {
                    action = CaregiverAlertService.ACTION_SILENCE
                })
                status.text = "Đã tắt âm. Sự cố vẫn cần được tiếp nhận."
            }
        }
        root.addView(silence, LinearLayout.LayoutParams(-1, dp(56)).apply { topMargin = dp(14) })
        root.addView(label("Mở sự cố để xác nhận hoặc liên hệ cấp cứu nếu cần.", 14f).apply {
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
