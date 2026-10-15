// wearos/src/main/kotlin/vn/careai/companion/WearOsMainActivity.kt
package vn.careai.companion

import android.app.Activity
import android.app.Dialog
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.Window
import android.widget.Button
import android.widget.TextView
import android.widget.ViewFlipper
import android.os.Vibrator
import android.os.VibratorManager
import android.os.VibrationEffect
import androidx.core.content.ContextCompat
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject

class WearOsMainActivity : Activity(), SensorEventListener {

    private lateinit var wearViewFlipper: ViewFlipper
    private lateinit var tvWearTitle: TextView
    private lateinit var tvStatus: TextView
    private lateinit var tvVitals: TextView
    private lateinit var tvLogResult: TextView
    private lateinit var btnManualSos: Button
    private lateinit var btnOpenTestLab: Button
    private lateinit var tvPageIndicator1: TextView

    // Trang 2: Sức khỏe hằng ngày & Thiết bị
    private lateinit var tvTodaySteps: TextView
    private lateinit var tvSleepSummary: TextView
    private lateinit var tvBloodPressure: TextView
    private lateinit var tvDeviceModel: TextView
    private lateinit var tvSensorStatus: TextView
    private lateinit var btnBackToEmergency: Button
    private lateinit var tvPageIndicator2: TextView

    private var testLabDialog: Dialog? = null

    private var sensorManager: SensorManager? = null
    private var heartRateSensor: Sensor? = null
    private var stepSensor: Sensor? = null
    private var offBodySensor: Sensor? = null

    private var isWorn: Boolean = true
    private var isCharging: Boolean = false
    private var batteryLevel: Int = 100
    private var isPhoneConnected: Boolean = true
    private var secretTapCount: Int = 0
    private var lastSecretTapTime: Long = 0L

    // Bất biến Fact 35: Khởi tạo null, không bịa đặt số liệu giả (76, 98%, 3450)
    private var currentHeartRate: Int? = null
    private var currentSpo2: Double? = null
    private var currentSteps: Int? = null
    private var currentBpSystolic: Double? = null
    private var currentBpDiastolic: Double? = null
    private var hasHardwareSpo2: Boolean = false

    private lateinit var gestureDetector: GestureDetector

    private val sensorInjectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            val action = intent.action
            Log.i("CareAI-Wear", "Nhận broadcast kiểm thử cảm biến: $action")

            when (action) {
                "vn.careai.watch.INJECT_VITALS" -> {
                    val hr = intent.getIntExtra("heart_rate", intent.getFloatExtra("heart_rate", 0f).toInt())
                    val spo2 = intent.getDoubleExtra("spo2", intent.getFloatExtra("spo2", 0f).toDouble())
                    val steps = intent.getIntExtra("steps", 0)
                    val bpSys = intent.getDoubleExtra("bp_systolic", 0.0)
                    val bpDia = intent.getDoubleExtra("bp_diastolic", 0.0)
                    val alertType = intent.getStringExtra("alert_type") ?: ""

                    if (hr > 0) currentHeartRate = hr
                    if (spo2 > 0) currentSpo2 = spo2
                    if (steps > 0) currentSteps = steps
                    if (bpSys > 0) currentBpSystolic = bpSys
                    if (bpDia > 0) currentBpDiastolic = bpDia

                    updateVitalsUI(source = "Google/ADB", customAlert = alertType)
                }
                "whs.synthetic.user.SET_HEART_RATE" -> {
                    val hr = intent.getFloatExtra("heart_rate", 0f).toInt()
                    if (hr > 0) {
                        currentHeartRate = hr
                        updateVitalsUI(source = "Google Health Synthetic")
                    }
                }
                "whs.synthetic.user.SET_OXYGEN_SATURATION" -> {
                    val spo2 = intent.getFloatExtra("oxygen_saturation", 0f).toDouble()
                    if (spo2 > 0) {
                        currentSpo2 = spo2
                        updateVitalsUI(source = "Google Health Synthetic")
                    }
                }
                "vn.careai.watch.SIMULATE_FALL" -> {
                    val eventId = intent.getStringExtra("eventId") ?: "FALL_WEAR_${System.currentTimeMillis()}"
                    triggerSimulateFall(eventId)
                }
                "vn.careai.watch.SIMULATE_SOS" -> {
                    val eventId = intent.getStringExtra("eventId") ?: "SOS_WATCH_${System.currentTimeMillis()}"
                    triggerManualSos(eventId)
                }
                "vn.careai.watch.PAIR_PIN" -> {
                    val pin = intent.getStringExtra("pin") ?: ""
                    if (pin.length == 6) {
                        tvLogResult.text = "Đang ghép nối PIN $pin qua Wi-Fi..."
                        Thread {
                            val (ok, msg) = WearOsDirectCloudClient.pairWatchWithPin(this@WearOsMainActivity, pin)
                            runOnUiThread {
                                tvLogResult.text = msg
                                if (ok) updateVitalsUI(source = "Ghép nối Wi-Fi thành công")
                            }
                        }.start()
                    }
                }
                "vn.careai.watch.SET_BACKEND" -> {
                    val url = intent.getStringExtra("url") ?: ""
                    if (url.isNotBlank()) {
                        WearOsConfigStore.saveBackendUrl(this@WearOsMainActivity, url)
                        tvLogResult.text = "Đã lưu URL: $url"
                    }
                }
                Intent.ACTION_POWER_CONNECTED -> {
                    isCharging = true
                    dispatchCurrentWatchTelemetry()
                    updateVitalsUI(source = "Cắm sạc pin")
                }
                Intent.ACTION_POWER_DISCONNECTED -> {
                    isCharging = false
                    dispatchCurrentWatchTelemetry()
                    updateVitalsUI(source = "Rút sạc pin")
                }
                "vn.careai.watch.SET_WEAR_STATE" -> {
                    isWorn = intent.getBooleanExtra("isWorn", true)
                    dispatchCurrentWatchTelemetry()
                    updateVitalsUI(source = if (isWorn) "Lệnh: Đeo đồng hồ" else "Lệnh: Tháo đồng hồ")
                }
                "vn.careai.watch.SET_BATTERY" -> {
                    batteryLevel = intent.getIntExtra("level", 100)
                    if (intent.hasExtra("charging")) {
                        isCharging = intent.getBooleanExtra("charging", false)
                    }
                    dispatchWatchTelemetry(this@WearOsMainActivity, isWorn, isCharging, batteryLevel)
                    updateVitalsUI(source = "Lệnh: Pin $batteryLevel%, Sạc=$isCharging")
                }
                "vn.careai.watch.CREDENTIALS_UPDATED" -> {
                    updateVitalsUI(source = "Đã đồng bộ từ điện thoại")
                }
                "vn.careai.watch.REQUEST_TELEMETRY" -> {
                    dispatchCurrentWatchTelemetry()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_wear_main)

        wearViewFlipper = findViewById(R.id.wearViewFlipper)
        tvWearTitle = findViewById(R.id.tvWearTitle)
        tvStatus = findViewById(R.id.tvStatus)
        tvVitals = findViewById(R.id.tvVitals)
        tvLogResult = findViewById(R.id.tvLogResult)
        btnManualSos = findViewById(R.id.btnManualSos)
        btnOpenTestLab = findViewById(R.id.btnOpenTestLab)
        tvPageIndicator1 = findViewById(R.id.tvPageIndicator1)

        tvTodaySteps = findViewById(R.id.tvTodaySteps)
        tvSleepSummary = findViewById(R.id.tvSleepSummary)
        tvBloodPressure = findViewById(R.id.tvBloodPressure)
        tvDeviceModel = findViewById(R.id.tvDeviceModel)
        tvSensorStatus = findViewById(R.id.tvSensorStatus)
        btnBackToEmergency = findViewById(R.id.btnBackToEmergency)
        tvPageIndicator2 = findViewById(R.id.tvPageIndicator2)

        // Phát hiện phần cứng cảm biến tự động
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        heartRateSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_HEART_RATE)
        offBodySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_LOW_LATENCY_OFFBODY_DETECT)
        stepSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)

        // Kiểm tra xem thiết bị có cảm biến SpO2 quang học không
        val allSensors = sensorManager?.getSensorList(Sensor.TYPE_ALL) ?: emptyList()
        hasHardwareSpo2 = allSensors.any { s ->
            val n = s.name.lowercase()
            val t = s.stringType.lowercase()
            n.contains("oxygen") || n.contains("spo2") || t.contains("oxygen") || t.contains("spo2") || s.type == 65545
        }

        // Cử chỉ vuốt chuyển 2 trang
        gestureDetector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onFling(e1: MotionEvent?, e2: MotionEvent, velocityX: Float, velocityY: Float): Boolean {
                if (e1 == null) return false
                val diffX = e2.x - e1.x
                val diffY = e2.y - e1.y
                if (Math.abs(diffX) > Math.abs(diffY) && Math.abs(diffX) > 100 && Math.abs(velocityX) > 100) {
                    if (diffX < 0) {
                        // Vuốt sang trái -> Xem Trang 2 (Sức khỏe hằng ngày)
                        wearViewFlipper.displayedChild = 1
                    } else {
                        // Vuốt sang phải -> Về Trang 1 (Cấp cứu)
                        wearViewFlipper.displayedChild = 0
                    }
                    return true
                }
                return false
            }
        })

        // Chuyển trang khi nhấn vào chỉ báo
        tvPageIndicator1.setOnClickListener { wearViewFlipper.displayedChild = 1 }
        tvPageIndicator2.setOnClickListener { wearViewFlipper.displayedChild = 0 }
        btnBackToEmergency.setOnClickListener { wearViewFlipper.displayedChild = 0 }

        // Cơ chế 5-tap bí mật mở phòng thử nghiệm tín hiệu dành riêng cho kỹ thuật/giám khảo
        tvWearTitle.setOnClickListener {
            val now = System.currentTimeMillis()
            if (now - lastSecretTapTime < 2500) {
                secretTapCount++
                if (secretTapCount >= 5) {
                    secretTapCount = 0
                    showTestLabDialog()
                }
            } else {
                secretTapCount = 1
            }
            lastSecretTapTime = now
        }

        readBatteryStatus()
        dispatchCurrentWatchTelemetry()
        updateVitalsUI(source = "Cảm biến sẵn sàng")

        // Kích hoạt SOS bằng tay
        btnManualSos.setOnClickListener {
            val eventId = "SOS_WATCH_${System.currentTimeMillis()}"
            triggerManualSos(eventId)
        }

        // Mở phòng thử nghiệm tín hiệu & mô phỏng
        btnOpenTestLab.setOnClickListener {
            showTestLabDialog()
        }
    }

    override fun dispatchTouchEvent(ev: MotionEvent?): Boolean {
        if (ev != null && gestureDetector.onTouchEvent(ev)) {
            return true
        }
        return super.dispatchTouchEvent(ev)
    }

    private fun showTestLabDialog() {
        val dialog = Dialog(this)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        dialog.setContentView(R.layout.dialog_wear_test_lab)
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)

        val btnSimulateFall: Button = dialog.findViewById(R.id.btnSimulateFall)
        val btnTestTachycardia: Button = dialog.findViewById(R.id.btnTestTachycardia)
        val btnTestBradycardia: Button = dialog.findViewById(R.id.btnTestBradycardia)
        val btnTestHypoxia: Button = dialog.findViewById(R.id.btnTestHypoxia)
        val btnTestNormal: Button = dialog.findViewById(R.id.btnTestNormal)
        val tvDialogLogResult: TextView = dialog.findViewById(R.id.tvDialogLogResult)
        val btnDialogClose: Button = dialog.findViewById(R.id.btnDialogClose)

        tvDialogLogResult.text = tvLogResult.text

        btnSimulateFall.setOnClickListener {
            val eventId = "FALL_WEAR_${System.currentTimeMillis()}"
            triggerSimulateFall(eventId)
            tvDialogLogResult.text = "💥 Đã kích hoạt mô phỏng té ngã!"
        }

        btnTestTachycardia.setOnClickListener {
            currentHeartRate = 155
            updateVitalsUI(source = "Phòng thử nghiệm", customAlert = "TACHYCARDIA")
            tvDialogLogResult.text = "🚨 Đã kích hoạt Nhịp nhanh 155 BPM"
        }

        btnTestBradycardia.setOnClickListener {
            currentHeartRate = 38
            updateVitalsUI(source = "Phòng thử nghiệm", customAlert = "BRADYCARDIA")
            tvDialogLogResult.text = "⚠️ Đã kích hoạt Nhịp chậm 38 BPM"
        }

        btnTestHypoxia.setOnClickListener {
            currentSpo2 = 88.0
            updateVitalsUI(source = "Phòng thử nghiệm", customAlert = "HYPOXIA")
            tvDialogLogResult.text = "🫁 Đã kích hoạt Thiếu oxy 88%"
        }

        btnTestNormal.setOnClickListener {
            currentHeartRate = 75
            currentSpo2 = 98.5
            updateVitalsUI(source = "Phòng thử nghiệm", customAlert = "NORMAL")
            tvDialogLogResult.text = "🟢 Đã khôi phục Chuẩn 75 BPM"
        }

        btnDialogClose.setOnClickListener {
            dialog.dismiss()
        }

        testLabDialog = dialog
        dialog.show()
    }

    override fun onResume() {
        super.onResume()
        // Đăng ký nhận tín hiệu cảm biến phần cứng / Google Emulator
        heartRateSensor?.let { sensor ->
            sensorManager?.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
            Log.i("CareAI-Wear", "Đã kích hoạt lắng nghe Sensor.TYPE_HEART_RATE")
        }
        offBodySensor?.let { sensor ->
            sensorManager?.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
            Log.i("CareAI-Wear", "Đã kích hoạt lắng nghe Sensor.TYPE_LOW_LATENCY_OFFBODY_DETECT")
        }
        stepSensor?.let { sensor ->
            sensorManager?.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
            Log.i("CareAI-Wear", "Đã kích hoạt lắng nghe Sensor đếm bước")
        }

        // Đăng ký BroadcastReceiver nhận lệnh kiểm thử từ Google / ADB
        val filter = IntentFilter().apply {
            addAction("vn.careai.watch.INJECT_VITALS")
            addAction("whs.synthetic.user.SET_HEART_RATE")
            addAction("whs.synthetic.user.SET_OXYGEN_SATURATION")
            addAction("vn.careai.watch.SIMULATE_FALL")
            addAction("vn.careai.watch.SIMULATE_SOS")
            addAction("vn.careai.watch.PAIR_PIN")
            addAction("vn.careai.watch.SET_BACKEND")
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction("vn.careai.watch.SET_WEAR_STATE")
            addAction("vn.careai.watch.SET_BATTERY")
            addAction("vn.careai.watch.CREDENTIALS_UPDATED")
            addAction("vn.careai.watch.REQUEST_TELEMETRY")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(sensorInjectionReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(sensorInjectionReceiver, filter)
        }

        dispatchCurrentWatchTelemetry()
    }

    override fun onPause() {
        super.onPause()
        sensorManager?.unregisterListener(this)
        try {
            unregisterReceiver(sensorInjectionReceiver)
        } catch (_: Exception) {}
        if (testLabDialog?.isShowing == true) {
            testLabDialog?.dismiss()
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        when (event?.sensor?.type) {
            Sensor.TYPE_HEART_RATE -> {
                val hr = event.values.firstOrNull()?.toInt() ?: 0
                if (hr > 0) {
                    currentHeartRate = hr
                    updateVitalsUI(source = "Cảm biến PPG phần cứng")
                }
            }
            Sensor.TYPE_STEP_COUNTER -> {
                val steps = event.values.firstOrNull()?.toInt() ?: 0
                if (steps > 0) {
                    currentSteps = steps
                    updateVitalsUI(source = "Cảm biến đếm bước phần cứng")
                }
            }
            Sensor.TYPE_LOW_LATENCY_OFFBODY_DETECT -> {
                val v = event.values.firstOrNull() ?: 1.0f
                val nowWorn = v != 0.0f
                if (isWorn != nowWorn) {
                    isWorn = nowWorn
                    dispatchCurrentWatchTelemetry()
                    updateVitalsUI(source = if (isWorn) "Đeo vào cổ tay" else "Tháo khỏi cổ tay")
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun readBatteryStatus() {
        try {
            val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus: Intent? = registerReceiver(null, ifilter)
            val status: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
            val level: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            batteryLevel = if (level >= 0 && scale > 0) (level * 100 / scale) else 100
        } catch (e: Exception) {
            Log.w("CareAI-Wear", "Không thể đọc BatteryManager: ${e.message}")
        }
    }

    private fun triggerEmergencyVibration() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }

            if (vibrator != null && vibrator.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val timings = longArrayOf(0, 450, 180, 450, 180, 700)
                    val amplitudes = intArrayOf(0, 255, 0, 255, 0, 255)
                    val effect = VibrationEffect.createWaveform(timings, amplitudes, -1)
                    vibrator.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(longArrayOf(0, 450, 180, 450, 180, 700), -1)
                }
            }
        } catch (e: Exception) {
            Log.w("CareAI-Wear", "Không thể kích hoạt rung khẩn cấp: ${e.message}")
        }
    }

    private fun dispatchCurrentWatchTelemetry() {
        readBatteryStatus()
        dispatchWatchTelemetry(this, isWorn, isCharging, batteryLevel) { connected ->
            runOnUiThread {
                isPhoneConnected = connected
                updateVitalsUI()
            }
        }
    }

    private fun updateVitalsUI(source: String = "Cảm biến", customAlert: String = "") {
        runOnUiThread {
            // Sắp xếp thông minh: Kiểm tra xem thiết bị đo được những gì
            val isHypoxiaAlert = customAlert == "HYPOXIA" || (currentSpo2 != null && currentSpo2!! <= 90.0)
            val showSpo2 = hasHardwareSpo2 || (currentSpo2 != null && currentSpo2!! > 0) || isHypoxiaAlert

            val hrStr = currentHeartRate?.toString() ?: "--"
            if (showSpo2) {
                val spo2Str = currentSpo2?.let { String.format(java.util.Locale.US, "%.0f%%", it) } ?: "--"
                tvVitals.text = "❤️ $hrStr BPM · 🫁 $spo2Str SpO2"
            } else {
                val stepsStr = currentSteps?.toString() ?: "--"
                tvVitals.text = "❤️ $hrStr BPM · 👟 $stepsStr bước"
            }

            // Cập nhật Trang 2: Sức khỏe hằng ngày & Thông tin phần cứng
            tvTodaySteps.text = "👟 Vận động: ${currentSteps?.toString() ?: "--"} bước"
            tvSleepSummary.text = "🌙 Giấc ngủ: Chưa ghi nhận"
            if (currentBpSystolic != null && currentBpDiastolic != null) {
                val sys = currentBpSystolic!!.toInt()
                val dia = currentBpDiastolic!!.toInt()
                val category = when {
                    sys >= 180 || dia >= 120 -> "🚨 Cơn tăng HA"
                    sys >= 140 || dia >= 90 -> "🟠 Tăng HA Độ 2"
                    sys >= 130 || dia >= 80 -> "🟡 Tiền tăng HA"
                    sys < 90 -> "⚠️ Tụt HA"
                    else -> "🟢 Chuẩn"
                }
                tvBloodPressure.text = "🩸 Huyết áp: $sys/$dia mmHg ($category)"
            } else {
                tvBloodPressure.text = "🩸 Huyết áp: Chưa ghi nhận"
            }
            val watchName = Build.MODEL ?: "Wear OS Watch"
            tvDeviceModel.text = "⌚ Model: $watchName"
            tvSensorStatus.text = "Cảm biến SpO2: ${if (hasHardwareSpo2) "Có quang học" else "Không hỗ trợ"}"

            val hr = currentHeartRate ?: 0
            val spo2 = currentSpo2 ?: 100.0

            when {
                customAlert == "TACHYCARDIA" || hr >= 140 -> {
                    wearViewFlipper.displayedChild = 0 // Tự động chuyển về Trang 1 khi có cảnh báo
                    tvStatus.text = "🚨 Nhanh $hr BPM"
                    tvStatus.setTextColor(ContextCompat.getColor(this, R.color.wear_red_danger))
                    tvLogResult.text = "⚡ $source: Phát hiện nhịp nhanh!"
                }
                customAlert == "BRADYCARDIA" || (hr <= 45 && hr > 0) -> {
                    wearViewFlipper.displayedChild = 0
                    tvStatus.text = "⚠️ Chậm $hr BPM"
                    tvStatus.setTextColor(0xFFF59E0B.toInt()) // Amber
                    tvLogResult.text = "⚡ $source: Phát hiện nhịp chậm!"
                }
                customAlert == "HYPOXIA" || spo2 <= 90.0 -> {
                    wearViewFlipper.displayedChild = 0
                    tvStatus.text = "🫁 Oxy ${spo2.toInt()}%"
                    tvStatus.setTextColor(0xFFA855F7.toInt()) // Purple
                    tvLogResult.text = "⚡ $source: Nồng độ SpO2 giảm sâu!"
                }
                (currentBpSystolic != null && (currentBpSystolic!! >= 180 || (currentBpDiastolic ?: 0.0) >= 120)) -> {
                    wearViewFlipper.displayedChild = 0 // Tự động chuyển về Trang 1 khi có cảnh báo
                    val sys = currentBpSystolic!!.toInt()
                    val dia = currentBpDiastolic?.toInt() ?: 0
                    tvStatus.text = "🚨 HA Cao $sys/$dia"
                    tvStatus.setTextColor(ContextCompat.getColor(this, R.color.wear_red_danger))
                    tvLogResult.text = "⚡ $source: Phát hiện cơn tăng huyết áp khẩn cấp!"
                }
                (currentBpSystolic != null && currentBpSystolic!! < 90 && currentBpSystolic!! > 0) -> {
                    wearViewFlipper.displayedChild = 0
                    val sys = currentBpSystolic!!.toInt()
                    val dia = currentBpDiastolic?.toInt() ?: 0
                    tvStatus.text = "⚠️ HA Thấp $sys/$dia"
                    tvStatus.setTextColor(0xFFF59E0B.toInt())
                    tvLogResult.text = "⚡ $source: Phát hiện tụt huyết áp nguy kịch!"
                }
                isCharging -> {
                    tvStatus.text = if (batteryLevel >= 100) "🔋 Đầy 100%" else "⚡ Sạc: $batteryLevel%"
                    tvStatus.setTextColor(0xFF38BDF8.toInt())
                    tvLogResult.text = "⚡ $source [Cắm sạc, Pin $batteryLevel%]"
                }
                !isWorn -> {
                    tvStatus.text = "🟡 Đã Tháo Cổ Tay"
                    tvStatus.setTextColor(0xFFF59E0B.toInt())
                    tvLogResult.text = "⚡ $source [Tháo rời cổ tay, Pin $batteryLevel%]"
                }
                !isPhoneConnected -> {
                    tvStatus.text = "🟡 Lưu Đệm Cục Bộ"
                    tvStatus.setTextColor(ContextCompat.getColor(this, R.color.wear_amber_warning))
                    tvLogResult.text = "⚡ $source [Lưu đệm, chờ kết nối điện thoại]"
                }
                else -> {
                    tvStatus.text = "🟢 Giám Sát Cổ Tay"
                    tvStatus.setTextColor(ContextCompat.getColor(this, R.color.wear_green_online))
                    tvLogResult.text = "⚡ $source [HR=$hrStr, Steps=${currentSteps?.toString() ?: "--"}]"
                }
            }
        }
    }

    private fun triggerSimulateFall(eventId: String) {
        val timestamp = System.currentTimeMillis()
        Log.w("CareAI-WearActivity", "Kích hoạt mô phỏng té ngã! EventId=$eventId")
        triggerEmergencyVibration()
        wearViewFlipper.displayedChild = 0 // Tự động về Trang 1
        tvStatus.text = "💥 BÁO ĐỘNG NGÃ!"
        tvStatus.setTextColor(ContextCompat.getColor(this, R.color.wear_red_danger))
        tvLogResult.text = "Đang gửi cảnh báo té ngã (Bluetooth / Wi-Fi)..."

        WearOsFallListenerService.dispatchFallAlert(
            context = this,
            eventId = eventId,
            eventTime = timestamp,
            sensorType = "SAMSUNG_BIOACTIVE_SIMULATED_TEST",
            heartRate = currentHeartRate ?: 0,
            spo2 = currentSpo2 ?: 0.0,
            emergencyType = "FALL_DETECTED"
        ) { _, channelInfo ->
            runOnUiThread {
                tvLogResult.text = channelInfo
            }
        }
    }

    private fun triggerManualSos(eventId: String) {
        val timestamp = System.currentTimeMillis()
        Log.w("CareAI-WearActivity", "Kích hoạt SOS khẩn cấp! EventId=$eventId")
        triggerEmergencyVibration()
        wearViewFlipper.displayedChild = 0 // Tự động về Trang 1
        tvStatus.text = "🆘 ĐÃ GỬI SOS!"
        tvStatus.setTextColor(ContextCompat.getColor(this, R.color.wear_red_danger))
        tvLogResult.text = "Đang gửi SOS khẩn cấp (Bluetooth / Wi-Fi)..."

        WearOsFallListenerService.dispatchFallAlert(
            context = this,
            eventId = eventId,
            eventTime = timestamp,
            sensorType = "WATCH_TOUCH_SOS",
            heartRate = currentHeartRate ?: 0,
            spo2 = currentSpo2 ?: 0.0,
            emergencyType = "MANUAL_SOS"
        ) { _, channelInfo ->
            runOnUiThread {
                tvLogResult.text = channelInfo
            }
        }
    }

    companion object {
        fun dispatchWatchTelemetry(
            context: Context,
            isWorn: Boolean,
            isCharging: Boolean,
            batteryLevel: Int,
            onConnectionResult: ((Boolean) -> Unit)? = null
        ) {
            val payloadJson = JSONObject().apply {
                put("isWorn", isWorn)
                put("isCharging", isCharging)
                put("batteryLevel", batteryLevel)
                put("watchName", Build.MODEL ?: "Galaxy Watch")
                put("timestamp", System.currentTimeMillis())
            }.toString()
            val payloadBytes = payloadJson.toByteArray(Charsets.UTF_8)

            Thread {
                var isConnected = false
                try {
                    val nodeClient = Wearable.getNodeClient(context)
                    val nodes = Tasks.await(nodeClient.connectedNodes, 1500, java.util.concurrent.TimeUnit.MILLISECONDS)
                    isConnected = nodes.isNotEmpty()
                    for (node in nodes) {
                        Tasks.await(
                            Wearable.getMessageClient(context).sendMessage(node.id, "/careai/watch_telemetry", payloadBytes),
                            1500,
                            java.util.concurrent.TimeUnit.MILLISECONDS
                        )
                        Log.i("CareAI-Wear", "Đã gửi /careai/watch_telemetry tới node: ${node.displayName}")
                    }
                } catch (e: Exception) {
                    Log.e("CareAI-Wear", "Lỗi gửi /careai/watch_telemetry: ${e.message}")
                } finally {
                    onConnectionResult?.invoke(isConnected)
                }
            }.start()
        }
    }
}
