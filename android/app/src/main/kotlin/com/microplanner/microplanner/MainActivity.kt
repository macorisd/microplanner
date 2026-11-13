package com.microplanner.microplanner

import io.flutter.embedding.android.FlutterActivity
import android.os.Build
import android.os.Bundle
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var notificationChannel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "microplanner/notifications").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(Reminders.status(this))
                        "requestPermission" -> {
                            if (Build.VERSION.SDK_INT >= 33 && !Reminders.status(this).getValue("enabled")) {
                                if (permissionResult != null) result.error("busy", "Permission request already open", null)
                                else { permissionResult = result; requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 381) }
                            } else result.success(Reminders.status(this))
                        }
                        "exactPermission" -> { Reminders.settings(this, true); result.success(null) }
                        "settings" -> { Reminders.settings(this, false); result.success(null) }
                        "schedule" -> { Reminders.schedule(this, JSONObject(call.arguments as Map<*, *>)); result.success(null) }
                        "cancel" -> { Reminders.cancel(this, (call.arguments as Number).toInt()); result.success(null) }
                        "pending" -> result.success(Reminders.pending(this))
                        "launch" -> { result.success(intent.getStringExtra("reminder") ?: ""); intent.removeExtra("reminder") }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) { result.error("notifications", "Could not update device reminders. Please try again.", null) }
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        notificationChannel?.invokeMethod("activated", null)
    }
    override fun onResume() {
        super.onResume()
        try { Reminders.rearmFuture(this) } catch (_: Exception) {
            // Flutter reconciliation reports setup failures and can retry.
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 381) { permissionResult?.success(Reminders.status(this)); permissionResult = null }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Avoid overlapping native and Flutter artwork during the handoff.
            splashScreen.setOnExitAnimationListener { view -> view.remove() }
        }
    }
}
