package com.example.stamsofer

import android.content.Intent
import android.net.Uri
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "com.example.stamsofer/update"
        private const val METRONOME_CHANNEL = "sofer_vmone/metronome"
        private const val LIVE_BACKUP_CHANNEL = "com.example.stamsofer/live_backup"
        private const val INSTALL_PERMISSION_REQUEST = 7310
        private const val BACKUP_FOLDER_REQUEST = 7311
        private const val APK_MIME = "application/vnd.android.package-archive"
    }

    private var pendingApkPath: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBackupFolderResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("missing_path", "קובץ העדכון לא נמצא", null)
                    } else {
                        requestInstall(path, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LIVE_BACKUP_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickBackupFolder" -> pickBackupFolder(result)
                "readLiveBackup" -> {
                    val folder = call.argument<String>("folderUri")
                    val fileName = call.argument<String>("fileName")
                    if (folder.isNullOrBlank() || fileName.isNullOrBlank()) {
                        result.error("backup_arguments", "פרטי הגיבוי חסרים", null)
                    } else {
                        readLiveBackup(folder, fileName, result)
                    }
                }
                "writeLiveBackup" -> {
                    val folder = call.argument<String>("folderUri")
                    val fileName = call.argument<String>("fileName")
                    val content = call.argument<String>("content")
                    val checksum = call.argument<String>("checksum")
                    if (folder.isNullOrBlank() || fileName.isNullOrBlank() ||
                        content == null || checksum.isNullOrBlank()) {
                        result.error("backup_arguments", "פרטי הגיבוי חסרים", null)
                    } else {
                        writeLiveBackup(folder, fileName, content, checksum, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METRONOME_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "beat" -> {
                    val volume = (call.argument<Number>("volume")?.toInt() ?: 70)
                        .coerceIn(0, 100)
                    if (volume == 0) {
                        result.success(null)
                    } else {
                        playTone(
                            stream = AudioManager.STREAM_MUSIC,
                            toneType = ToneGenerator.TONE_PROP_BEEP,
                            volume = volume,
                            durationMs = 55,
                            releaseAfterMs = 90,
                            errorCode = "metronome_failed",
                            result = result,
                        )
                    }
                }
                "alert" -> playTone(
                    stream = AudioManager.STREAM_ALARM,
                    toneType = ToneGenerator.TONE_PROP_BEEP2,
                    volume = 100,
                    durationMs = 360,
                    releaseAfterMs = 430,
                    errorCode = "alert_failed",
                    result = result,
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun playTone(
        stream: Int,
        toneType: Int,
        volume: Int,
        durationMs: Int,
        releaseAfterMs: Long,
        errorCode: String,
        result: MethodChannel.Result,
    ) {
        try {
            val tone = ToneGenerator(stream, volume)
            if (!tone.startTone(toneType, durationMs)) {
                tone.release()
                result.error(errorCode, "The device refused to start the sound", null)
                return
            }
            mainHandler.postDelayed({ tone.release() }, releaseAfterMs)
            result.success(null)
        } catch (error: Exception) {
            result.error(errorCode, error.message, null)
        }
    }

    private fun requestInstall(path: String, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("install_busy", "מתקין עדכון אחר כבר פתוח", null)
            return
        }

        val apk = File(path)
        if (!apk.isFile || apk.length() <= 0L) {
            result.error("missing_apk", "קובץ העדכון אינו קיים או ריק", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            pendingApkPath = path
            pendingResult = result
            try {
                startActivityForResult(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ),
                    INSTALL_PERMISSION_REQUEST,
                )
            } catch (error: Exception) {
                pendingApkPath = null
                pendingResult = null
                result.error(
                    "permission_screen_failed",
                    "לא ניתן לפתוח את הרשאת התקנת העדכון",
                    error.message,
                )
            }
            return
        }

        openPackageInstaller(apk, result)
    }

    @Deprecated("Android activity result API; retained for the system settings round-trip")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == BACKUP_FOLDER_REQUEST) {
            val result = pendingBackupFolderResult
            pendingBackupFolderResult = null
            if (result == null) return
            if (resultCode != RESULT_OK || data?.data == null) {
                result.success(null)
                return
            }
            val uri = data.data!!
            try {
                val flags = data.flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                contentResolver.takePersistableUriPermission(uri, flags)
                result.success(uri.toString())
            } catch (error: Exception) {
                result.error("backup_permission", "לא ניתן לשמור הרשאה לתיקייה", error.message)
            }
            return
        }
        if (requestCode != INSTALL_PERMISSION_REQUEST) return

        val path = pendingApkPath
        val result = pendingResult
        pendingApkPath = null
        pendingResult = null
        if (path == null || result == null) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            result.error(
                "install_permission_denied",
                "כדי להתקין את העדכון יש לאפשר התקנה ממקור זה",
                null,
            )
            return
        }
        openPackageInstaller(File(path), result)
    }

    private fun pickBackupFolder(result: MethodChannel.Result) {
        if (pendingBackupFolderResult != null) {
            result.error("backup_busy", "בחירת תיקייה אחרת כבר פתוחה", null)
            return
        }
        pendingBackupFolderResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            startActivityForResult(intent, BACKUP_FOLDER_REQUEST)
        } catch (error: Exception) {
            pendingBackupFolderResult = null
            result.error("backup_picker", "לא ניתן לפתוח בחירת תיקייה", error.message)
        }
    }

    private fun readLiveBackup(folder: String, fileName: String, result: MethodChannel.Result) {
        Thread {
            try {
                val treeUri = Uri.parse(folder)
                val treeId = DocumentsContract.getTreeDocumentId(treeUri)
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, treeId)
                // A previous copy may be waiting for recovery after an
                // interrupted rename. It must also be checked before writing.
                val document = findChild(children, fileName)
                    ?: findChild(children, ".${fileName}.previous")
                val content = document?.let {
                    contentResolver.openInputStream(it)?.use { stream ->
                        stream.readBytes().toString(Charsets.UTF_8)
                    } ?: throw IllegalStateException("לא ניתן לקרוא את הגיבוי הקיים")
                }
                runOnUiThread { result.success(content) }
            } catch (error: Exception) {
                runOnUiThread { result.error("backup_read", "לא ניתן לבדוק את הגיבוי הקיים", error.message) }
            }
        }.start()
    }

    private fun writeLiveBackup(
        folder: String,
        fileName: String,
        content: String,
        checksum: String,
        result: MethodChannel.Result,
    ) {
        Thread {
            var temporaryUri: Uri? = null
            try {
                val treeUri = Uri.parse(folder)
                val treeId = DocumentsContract.getTreeDocumentId(treeUri)
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, treeId)
                val temporaryName = ".${fileName}.tmp"
                val previousName = ".${fileName}.previous"
                if (findChild(children, fileName) == null) {
                    findChild(children, previousName)?.let {
                        DocumentsContract.renameDocument(contentResolver, it, fileName)
                    }
                }
                findChild(children, temporaryName)?.let {
                    DocumentsContract.deleteDocument(contentResolver, it)
                }
                temporaryUri = DocumentsContract.createDocument(
                    contentResolver,
                    children,
                    "application/json",
                    temporaryName,
                ) ?: throw IllegalStateException("לא ניתן ליצור קובץ זמני")
                val output = contentResolver.openOutputStream(temporaryUri!!, "wt")
                    ?: throw IllegalStateException("לא ניתן לכתוב לתיקייה")
                output.use { stream ->
                    stream.write(content.toByteArray(Charsets.UTF_8))
                    stream.flush()
                }

                // Storage Access Framework providers are allowed to report a
                // successful close after a partial write. Read the temporary
                // document back before moving the last good snapshot aside;
                // the Dart side already validated the checksum, and the value
                // below proves the provider preserved that validated payload.
                val readBack = contentResolver.openInputStream(temporaryUri!!)
                    ?.use { it.readBytes().toString(Charsets.UTF_8) }
                    ?: throw IllegalStateException("לא ניתן לקרוא את הגיבוי הזמני")
                if (readBack != content) {
                    throw IllegalStateException("הגיבוי הזמני נכתב באופן חלקי")
                }
                val readBackChecksum = JSONObject(readBack).optString("checksum", "")
                if (readBackChecksum != checksum) {
                    throw IllegalStateException("אימות checksum של הגיבוי נכשל")
                }

                // Keep the previous valid document until the new one has a
                // name. Providers differ in whether rename can replace an
                // existing child, so move the old file aside and restore it on
                // any failure instead of deleting it first.
                val previousUri = findChild(children, previousName)
                previousUri?.let {
                    DocumentsContract.deleteDocument(contentResolver, it)
                }
                val oldUri = findChild(children, fileName)
                if (oldUri != null) {
                    DocumentsContract.renameDocument(
                        contentResolver,
                        oldUri,
                        previousName,
                    ) ?: throw IllegalStateException("לא ניתן לשמור את הגיבוי הקודם")
                }
                try {
                    DocumentsContract.renameDocument(
                        contentResolver,
                        temporaryUri!!,
                        fileName,
                    ) ?: throw IllegalStateException("לא ניתן להשלים את הגיבוי")
                    // The URI now names the final snapshot, not the temporary
                    // document. Do not let the outer error cleanup delete a
                    // successfully installed snapshot if cleanup of the old
                    // `.previous` file fails afterwards.
                    temporaryUri = null
                } catch (error: Exception) {
                    if (oldUri != null && findChild(children, fileName) == null) {
                        findChild(children, previousName)?.let {
                            DocumentsContract.renameDocument(
                                contentResolver,
                                it,
                                fileName,
                            )
                        }
                    }
                    throw error
                }
                findChild(children, previousName)?.let {
                    DocumentsContract.deleteDocument(contentResolver, it)
                }
                removeLegacyDailyFiles(children)
                temporaryUri = null
                post { result.success(true) }
            } catch (error: Exception) {
                temporaryUri?.let {
                    try { DocumentsContract.deleteDocument(contentResolver, it) } catch (_: Exception) { }
                }
                post { result.error("backup_write", "לא ניתן לכתוב את הגיבוי", error.message) }
            }
        }.start()
    }

    private fun findChild(children: Uri, name: String): Uri? {
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        contentResolver.query(children, projection, null, null, null)?.use { cursor ->
            val id = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val display = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (cursor.getString(display) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(children, cursor.getString(id))
                }
            }
        }
        return null
    }

    private fun removeLegacyDailyFiles(children: Uri) {
        val legacy = Regex("^sofer-vmone-\\d{4}-\\d{2}-\\d{2}\\.json$")
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        contentResolver.query(children, projection, null, null, null)?.use { cursor ->
            val id = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val display = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                val name = cursor.getString(display)
                if (legacy.matches(name)) {
                    val uri = DocumentsContract.buildDocumentUriUsingTree(children, cursor.getString(id))
                    try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) { }
                }
            }
        }
    }

    private fun post(action: () -> Unit) {
        mainHandler.post(action)
    }

    private fun openPackageInstaller(apk: File, result: MethodChannel.Result) {
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.update_provider",
                apk,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "installer_failed",
                "Android לא הצליח לפתוח את מתקין העדכון",
                error.message,
            )
        }
    }
}
