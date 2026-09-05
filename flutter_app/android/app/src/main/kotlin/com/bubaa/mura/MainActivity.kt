package com.bubaa.mura

import android.app.DownloadManager
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import org.json.JSONArray
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val motionChannelName = "com.bubaa.mura/motion_quote"
    private val updaterChannelName = "com.bubaa.mura/updater"
    private val prefs by lazy { getSharedPreferences("updater", MODE_PRIVATE) }
    private var updaterChannel: MethodChannel? = null

    // APK awaiting the "install unknown apps" permission grant.
    private var pendingInstall: File? = null

    // Tells Flutter the moment the system download completes (no polling).
    private val downloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == DownloadManager.ACTION_DOWNLOAD_COMPLETE) {
                val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
                val pending = prefs.getLong("mura.update.downloadId", -1L)
                if (id > 0 && id == pending) {
                    updaterChannel?.invokeMethod("onDownloadComplete", id, null)
                }
            }
        }
    }
    private val receiverRegistered = arrayOf(false)

    override fun onResume() {
        super.onResume()
        // User returned from the install-permission screen -> continue.
        pendingInstall?.let { file ->
            if (canInstall()) {
                pendingInstall = null
                launchInstaller(file)
            }
        }
        // Listen for the pending system download completing.
        val pending = prefs.getLong("mura.update.downloadId", -1L)
        if (pending > 0 && !receiverRegistered[0]) {
            val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
            ContextCompat.registerReceiver(
                this, downloadReceiver, filter, ContextCompat.RECEIVER_EXPORTED
            )
            receiverRegistered[0] = true
        }
    }

    override fun onPause() {
        super.onPause()
        if (receiverRegistered[0]) {
            try {
                unregisterReceiver(downloadReceiver)
            } catch (_: Exception) {
            }
            receiverRegistered[0] = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, motionChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "update") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val texts = call.argument<List<String>>("texts").orEmpty()
                val sources = call.argument<List<String>>("sources").orEmpty()
                getSharedPreferences("motion_quote", MODE_PRIVATE).edit()
                    .putString("texts", JSONArray(texts).toString())
                    .putString("sources", JSONArray(sources).toString())
                    .apply()
                val manager = AppWidgetManager.getInstance(this)
                val component = ComponentName(this, MotionQuoteWidgetProvider::class.java)
                manager.notifyAppWidgetViewDataChanged(manager.getAppWidgetIds(component), R.id.motion_quote_text)
                MotionQuoteWidgetProvider.updateAll(this)
                result.success(null)
            }

        updaterChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannelName)
        updaterChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startDownload" -> {
                        val url = call.argument<String>("url")
                        val filename = call.argument<String>("filename") ?: "mura-update.apk"
                        if (url == null) {
                            result.error("bad_args", "Missing download url", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val id = enqueueDownload(url, filename)
                            result.success(id)
                        } catch (e: Exception) {
                            result.error("enqueue_failed", e.message ?: "Could not start download", null)
                        }
                    }
                    "downloadStatus" -> {
                        val id = call.argument<Long>("id") ?: -1L
                        result.success(downloadStatus(id))
                    }
                    "finishDownload" -> {
                        val id = call.argument<Long>("id") ?: -1L
                        finishDownloadedApk(id, result)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "Missing apk path", null)
                            return@setMethodCallHandler
                        }
                        installFile(File(path), result)
                    }
                    "openInstallSettings" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("settings_failed", e.message ?: "Could not open settings", null)
                        }
                    }
                    "clearDownload" -> {
                        prefs.edit()
                            .remove("mura.update.downloadId")
                            .remove("mura.update.fileName")
                            .apply()
                        result.success(null)
                    }
                    "pendingDownload" -> {
                        val id = prefs.getLong("mura.update.downloadId", -1L)
                        val fileName = prefs.getString("mura.update.fileName", "")
                        if (id <= 0) {
                            result.success(null)
                        } else {
                            result.success(mapOf("id" to id, "fileName" to (fileName ?: "")))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ------------------------------------------------------------------
    // Background download via the system DownloadManager. Keeps running
    // when the app is backgrounded or killed, with a system notification.
    // ------------------------------------------------------------------

    private fun enqueueDownload(url: String, filename: String): Long {
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val versionName = callVersionHint(filename)
        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle("MURA $versionName update")
            setDescription("Downloading the new build in the background…")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setDestinationInExternalFilesDir(this@MainActivity, null, "updates/$filename")
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
        }
        val id = dm.enqueue(request)
        prefs.edit()
            .putLong("mura.update.downloadId", id)
            .putString("mura.update.fileName", filename)
            .apply()
        return id
    }

    private fun callVersionHint(filename: String): String {
        val m = Regex("mura-([0-9.]+)").find(filename)
        return m?.groupValues?.get(1) ?: ""
    }

    private fun downloadStatus(id: Long): Map<String, Any> {
        if (id <= 0) return mapOf("status" to "none", "progress" to 0.0, "bytes" to 0, "total" to 0)
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val query = DownloadManager.Query().setFilterById(id)
        var status = "pending"
        var progress = 0.0
        var bytes = 0L
        var total = 0L
        var error = ""
        try {
            dm.query(query).use { cursor ->
                if (cursor.moveToFirst()) {
                    status = when (cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                        DownloadManager.STATUS_SUCCESSFUL -> "success"
                        DownloadManager.STATUS_FAILED -> "failed"
                        DownloadManager.STATUS_PAUSED -> "paused"
                        else -> "running"
                    }
                    total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                    bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    if (total > 0) progress = bytes.toDouble() / total.toDouble()
                    if (status == "failed") {
                        error = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)).toString()
                    }
                } else {
                    status = "gone"
                }
            }
        } catch (e: Exception) {
            status = "error"
            error = e.message ?: "query failed"
        }
        return mapOf(
            "status" to status,
            "progress" to progress,
            "bytes" to bytes,
            "total" to total,
            "error" to error,
        )
    }

    private fun finishDownloadedApk(id: Long, result: MethodChannel.Result) {
        if (id <= 0) {
            result.success("not_ready")
            return
        }
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val query = DownloadManager.Query().setFilterById(id)
        var localUri: String? = null
        dm.query(query).use { cursor ->
            if (cursor.moveToFirst()) {
                val s = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                if (s != DownloadManager.STATUS_SUCCESSFUL) {
                    result.success("not_ready")
                    return
                }
                localUri = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
            }
        }
        if (localUri == null) {
            result.success("not_ready")
            return
        }
        // Copy the completed download into our files dir (FileProvider-visible)
        // and hand it to the installer (permission-aware).
        val fileName = (prefs.getString("mura.update.fileName", "mura-update.apk"))
        try {
            val apkDir = File(filesDir, "apks").apply { mkdirs() }
            val target = File(apkDir, fileName)
            contentResolver.openInputStream(Uri.parse(localUri)).use { input ->
                if (input == null) { result.success("not_ready"); return }
                target.outputStream().use { output -> input.copyTo(output) }
            }
            installFile(target, result)
            // The installer now owns the file; forget the download record.
            prefs.edit()
                .remove("mura.update.downloadId")
                .remove("mura.update.fileName")
                .apply()
        } catch (e: Exception) {
            result.error("finish_failed", e.message ?: "Could not finish download", null)
        }
    }

    private fun installFile(file: File, result: MethodChannel.Result) {
        if (!canInstall()) {
            pendingInstall = file
            result.success("need_permission")
            return
        }
        try {
            launchInstaller(file)
            result.success("launched")
        } catch (e: Exception) {
            result.error("install_failed", e.message ?: "Could not open installer", null)
        }
    }

    private fun canInstall(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    private fun launchInstaller(file: File) {
        val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
