package ro.holban.lectura

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val channelName = "ro.holban.lectura/import"
    private var channel: MethodChannel? = null
    private var pendingImport: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "takePendingImport") {
                captureIntent(intent)
                result.success(pendingImport)
                pendingImport = null
            } else {
                result.notImplemented()
            }
        }
        captureIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIntent(intent)
        pendingImport?.let {
            channel?.invokeMethod("importDocument", it)
            pendingImport = null
        }
    }

    private fun captureIntent(source: Intent?) {
        if (source == null) return
        val uri = when (source.action) {
            Intent.ACTION_VIEW -> source.data
            Intent.ACTION_SEND -> source.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            else -> null
        } ?: return
        pendingImport = copyToCache(uri)
        source.action = null
        source.data = null
        source.removeExtra(Intent.EXTRA_STREAM)
    }

    private fun copyToCache(uri: Uri): Map<String, String>? {
        return try {
            val displayName = queryDisplayName(uri) ?: fallbackName(uri)
            val safeName = displayName.replace(Regex("[^A-Za-z0-9._ăâîșțĂÂÎȘȚ -]"), "_")
            val output = File(cacheDir, "shared_${System.currentTimeMillis()}_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                output.outputStream().use { target -> input.copyTo(target) }
            } ?: return null
            mapOf("path" to output.absolutePath, "name" to displayName)
        } catch (_: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme != "content") return null
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) return cursor.getString(0)
            }
        return null
    }

    private fun fallbackName(uri: Uri): String {
        val last = uri.lastPathSegment?.substringAfterLast('/')
        if (!last.isNullOrBlank() && last.contains('.')) return last
        val extension = contentResolver.getType(uri)
            ?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
            ?: "pdf"
        return "document.$extension"
    }
}
