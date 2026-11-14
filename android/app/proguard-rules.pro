# WorkManager persists worker names between app updates.
-keep class com.microplanner.microplanner.ReminderSyncWorker { public <init>(android.content.Context, androidx.work.WorkerParameters); }
# The signed device verification runner invokes the same headless coordinator.
-keep class com.microplanner.microplanner.BackgroundSync { *; }
