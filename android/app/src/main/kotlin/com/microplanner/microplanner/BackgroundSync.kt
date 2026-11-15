package com.microplanner.microplanner

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** One engine owns reminder storage at a time; idle jobs never keep an engine alive. */
object BackgroundSync {
    private const val NAME = "microplanner.reminder-sync"
    private val main = Handler(Looper.getMainLooper())
    private var foreground: MethodChannel? = null
    private var applying = false
    private var running = false
    @JvmStatic fun verify(context: Context): Boolean = run(context) { false }
    fun bindForeground(engine: FlutterEngine, context: Context) {
        foreground = MethodChannel(engine.dartExecutor.binaryMessenger, "microplanner/backgroundSync").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "foregroundStart" -> {
                        fun ready() {
                            if (applying) main.postDelayed({ ready() }, 25)
                            else result.success(null)
                        }
                        ready()
                    }
                    "configure" -> {
                        try { configure(context, call.arguments == true, result) }
                        catch (_: Exception) { result.error("background", "Background sync could not be scheduled.", null) }
                    }
                    "status" -> {
                        val status = WorkManager.getInstance(context).getWorkInfosForUniqueWork(NAME)
                        status.addListener({
                            try { result.success(mapOf("registered" to status.get().any { !it.state.isFinished })) }
                            catch (_: Exception) { result.error("background", "Background sync status is unavailable.", null) }
                        }, java.util.concurrent.Executor { main.post(it) })
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
    fun unbindForeground() { foreground = null }
    private fun configure(context: Context, enabled: Boolean, result: MethodChannel.Result? = null) {
        val work = WorkManager.getInstance(context)
        val operation = if (enabled) {
            val request = PeriodicWorkRequestBuilder<ReminderSyncWorker>(30, TimeUnit.MINUTES, 10, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).setRequiresBatteryNotLow(true).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES).build()
            work.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        } else work.cancelUniqueWork(NAME)
        operation.result.addListener({
            try { operation.result.get(); result?.success(null) }
            catch (_: Exception) { result?.error("background", "Background sync could not be scheduled.", null) }
        }, java.util.concurrent.Executor { main.post(it) })
    }
    fun run(context: Context, stopped: () -> Boolean): Boolean {
        val done = CountDownLatch(1)
        var success = false
        var engine: FlutterEngine? = null
        var ownsRun = false
        main.post {
            val live = foreground
            if (live != null) {
                live.invokeMethod("sync", null, object : MethodChannel.Result {
                    override fun success(result: Any?) { success = true; done.countDown() }
                    override fun error(code: String, message: String?, details: Any?) { done.countDown() }
                    override fun notImplemented() { done.countDown() }
                })
                return@post
            }
            if (running) { done.countDown(); return@post }
            running = true
            ownsRun = true
            try {
                val loader = io.flutter.FlutterInjector.instance().flutterLoader()
                loader.startInitialization(context)
                loader.ensureInitializationComplete(context, null)
                engine = FlutterEngine(context)
                val workerEngine = engine!!
                MethodChannel(workerEngine.dartExecutor.binaryMessenger, "microplanner/notifications").setMethodCallHandler { call, result ->
                    try {
                        when(call.method) {
                            "status" -> result.success(Reminders.status(context))
                            "schedule" -> { Reminders.schedule(context, org.json.JSONObject(call.arguments as Map<*,*>)); result.success(null) }
                            "cancel" -> { Reminders.cancel(context, (call.arguments as Number).toInt()); result.success(null) }
                            else -> result.notImplemented()
                        }
                    } catch (_: Exception) { result.error("background", "Reminder update failed", null) }
                }
                MethodChannel(workerEngine.dartExecutor.binaryMessenger, "microplanner/backgroundSync").setMethodCallHandler { call, result ->
                    when(call.method) {
                        "acquire" -> {
                            val allowed = !applying && foreground == null && !stopped()
                            if (allowed) applying = true
                            result.success(allowed)
                        }
                        "release" -> { applying = false; result.success(null) }
                        "complete" -> {
                            android.util.Log.i("microplannerSync", "Finished reminder check: ${call.arguments}")
                            if (call.arguments == "disabled" || call.arguments == "expired") configure(context, false)
                            success = call.arguments != "error"; result.success(null); done.countDown()
                        }
                        else -> result.notImplemented()
                    }
                }
                workerEngine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "backgroundReminderSync"))
            } catch (_: Exception) { done.countDown() }
        }
        // Network has a 20s deadline; leave ample time for native reconciliation.
        val finished = done.await(60, TimeUnit.SECONDS)
        val destroyed = CountDownLatch(1)
        main.post {
            if (ownsRun) { applying = false; engine?.destroy(); running = false }
            destroyed.countDown()
        }
        destroyed.await(5, TimeUnit.SECONDS)
        return finished && success
    }
}

class ReminderSyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result = try {
        if (BackgroundSync.run(applicationContext) { isStopped }) Result.success() else Result.retry()
    } catch (_: Exception) { Result.retry() }
}
