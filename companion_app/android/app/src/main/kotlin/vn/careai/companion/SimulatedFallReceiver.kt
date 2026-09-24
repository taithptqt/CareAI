package vn.careai.companion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONObject

class SimulatedFallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val eventId = intent.getStringExtra("eventId") ?: "FALL_SIM_${System.currentTimeMillis()}"
        val timestamp = intent.getLongExtra("timestamp", System.currentTimeMillis())
        val impactG = if (intent.hasExtra("impactG")) intent.getDoubleExtra("impactG", 3.2) else 3.2
        Log.w("CareAI-SimulatedFall", "Tiếp nhận Broadcast giả lập ngã ADB: eventId=$eventId, impactG=$impactG")

        val rawJson = JSONObject().apply {
            put("eventId", eventId)
            put("timestamp", timestamp)
            put("impactG", impactG)
        }.toString()

        WearOsMessageReceiverService.handleFallPayload(context, rawJson, "ADB_SIMULATED_BROADCAST")
    }
}
