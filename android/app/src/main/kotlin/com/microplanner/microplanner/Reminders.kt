package com.microplanner.microplanner

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** OS-owned alarms with a small encrypted store, independent of Flutter lifetime. */
object Reminders {
    private const val CHANNEL = "deadline_reminders"
    private const val KEY = "microplanner.reminders.v1"
    private fun preferences(context: Context) = context.getSharedPreferences("reminders", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        return Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }
    private fun decrypt(value: String): String {
        val bytes = Base64.decode(value, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        }
        return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
    }
    fun status(context: Context): Map<String, Boolean> {
        val notifications = context.getSystemService(NotificationManager::class.java)
        val permitted = if (Build.VERSION.SDK_INT >= 33) context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED else true
        val channel = if (Build.VERSION.SDK_INT >= 26) notifications.getNotificationChannel(CHANNEL) else null
        val enabled = permitted && (Build.VERSION.SDK_INT < 24 || notifications.areNotificationsEnabled()) && (channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE)
        val alarm = context.getSystemService(AlarmManager::class.java)
        return mapOf("enabled" to enabled, "precise" to (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()))
    }
    private fun alarmIntent(context: Context, id: Int): PendingIntent = PendingIntent.getBroadcast(context, id,
        Intent(context, ReminderReceiver::class.java).putExtra("id", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun schedule(context: Context, event: JSONObject) {
        val id = event.getInt("id")
        check(preferences(context).edit().putString(id.toString(), encrypt(event.toString())).commit()) { "Could not save reminder" }
        installAlarm(context, event)
    }
    private fun installAlarm(context: Context, event: JSONObject) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val intent = alarmIntent(context, event.getInt("id"))
        val at = event.getLong("at")
        if (at <= System.currentTimeMillis()) { deliver(context, event); return }
        try {
            if (Build.VERSION.SDK_INT >= 23 && (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()))
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            else if (Build.VERSION.SDK_INT >= 23) alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            else alarm.setExact(AlarmManager.RTC_WAKEUP, at, intent)
        } catch (_: SecurityException) {
            if (Build.VERSION.SDK_INT >= 23) alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            else alarm.set(AlarmManager.RTC_WAKEUP, at, intent)
        }
    }
    fun cancel(context: Context, id: Int) {
        context.getSystemService(AlarmManager::class.java).cancel(alarmIntent(context, id))
        context.getSystemService(NotificationManager::class.java).cancel(id)
        check(preferences(context).edit().remove(id.toString()).commit()) { "Could not remove reminder" }
    }
    private fun events(context: Context): List<JSONObject> = preferences(context).all.mapNotNull { (_, value) ->
        try { JSONObject(decrypt(value as String)) } catch (_: Exception) { null }
    }
    fun pending(context: Context): List<String> = events(context).filter { !it.optBoolean("delivered") }.map { it.getInt("id").toString() }
    fun rearmFuture(context: Context) {
        // Revoking exact-alarm access removes OS alarms. Resume must also recover
        // when access remains denied, using the visible inexact fallback.
        val now = System.currentTimeMillis()
        events(context).filter { !it.optBoolean("delivered") && it.getLong("at") > now && it.optLong("expires", Long.MAX_VALUE) > now }
            .forEach { installAlarm(context, it) }
    }
    fun receive(context: Context, id: Int) {
        val raw = preferences(context).getString(id.toString(), null) ?: return
        try { deliver(context, JSONObject(decrypt(raw))) } catch (_: Exception) { cancel(context, id) }
    }
    fun restore(context: Context) {
        val now = System.currentTimeMillis()
        val events = events(context).filter { !it.optBoolean("delivered") }
        val due = events.filter { it.getLong("at") <= now && it.optLong("expires", Long.MAX_VALUE) > now && it.optLong("deadline", Long.MAX_VALUE) > now }
        if (due.size > 1) {
            due.forEach { event -> event.put("delivered", true); preferences(context).edit().putString(event.getInt("id").toString(), encrypt(event.toString())).commit() }
            val summary = JSONObject(due.first().toString()).put("title", "microplanner").put("body", "${due.size} tasks have approaching deadlines").put("delivered", false)
            summary.remove("boardName")
            deliver(context, summary)
        }
        events.filter { due.size < 2 || !due.contains(it) }.forEach { installAlarm(context, it) }
    }
    private fun deliver(context: Context, event: JSONObject) {
        if (event.optBoolean("delivered")) return
        val now = System.currentTimeMillis()
        val deadline = event.optLong("deadline", Long.MAX_VALUE)
        val allowedLate = if (event.optBoolean("atDeadline")) 300000L else 0L
        if (now > event.optLong("expires", Long.MAX_VALUE) || now > deadline + allowedLate || !status(context).getValue("enabled")) {
            cancel(context, event.getInt("id")); return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "Task reminders", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "Upcoming task deadlines" })
        val open = Intent(context, MainActivity::class.java).putExtra("reminder", event.getString("payload"))
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val action = PendingIntent.getActivity(context, event.getInt("id"), open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        val body = if (event.has("boardName")) "${event.getString("boardName")} · Due ${deadlineLabel(deadline, now)}" else event.getString("body")
        builder.setSmallIcon(R.drawable.ic_notification).setContentTitle(event.getString("title"))
            .setContentText(body).setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(action).setAutoCancel(true).setGroup("microplanner.reminders")
            .setVisibility(Notification.VISIBILITY_PRIVATE)
        manager.notify(event.getInt("id"), builder.build())
        event.put("delivered", true)
        check(preferences(context).edit().putString(event.getInt("id").toString(), encrypt(event.toString())).commit())
    }
    private fun deadlineLabel(deadline: Long, delivery: Long): String {
        val day = Calendar.getInstance().apply { timeInMillis = deadline }
        val today = Calendar.getInstance().apply { timeInMillis = delivery }
        val tomorrow = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
        fun sameDate(other: Calendar) = day.get(Calendar.YEAR) == other.get(Calendar.YEAR) && day.get(Calendar.DAY_OF_YEAR) == other.get(Calendar.DAY_OF_YEAR)
        val label = when {
            sameDate(today) -> "today"
            sameDate(tomorrow) -> "tomorrow"
            else -> SimpleDateFormat("EEE d MMM", Locale.ENGLISH).format(day.time)
        }
        return "$label, ${SimpleDateFormat("HH:mm", Locale.ENGLISH).format(day.time)}"
    }
    fun settings(activity: Activity, exact: Boolean) {
        val intent = if (exact && Build.VERSION.SDK_INT >= 31) Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${activity.packageName}"))
            else if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
        activity.startActivity(intent)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == null) Reminders.receive(context, intent.getIntExtra("id", -1))
        else Reminders.restore(context)
    }
}
