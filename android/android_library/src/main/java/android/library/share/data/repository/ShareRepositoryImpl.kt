package android.library.share.data.repository

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.library.share.application.port.RichPreviewShareRepository
import android.library.share.domain.error.ShareDomainError
import android.library.share.domain.model.DirectShareTarget
import android.library.share.domain.model.ShareContent
import android.library.share.domain.model.SharePreviewOptions
import android.net.Uri
import android.os.Build
import android.service.chooser.ChooserAction
import android.util.Base64
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutManagerCompat
import org.json.JSONArray
import java.io.File

internal const val SHARE_FILE_PROVIDER_AUTHORITY_SUFFIX = ".native_toolkit.share.fileprovider"

class ShareRepositoryImpl(private val context: Context) : RichPreviewShareRepository {

    internal var shortcutPublisher: DirectShareShortcutPublisher = AndroidDirectShareShortcutPublisher

    private val coordinator = ShareCallbackCoordinator.get(context)

    override fun shareText(content: ShareContent, chooserActionsJson: String) {
        Log.d(TAG, "[shareText] content: $content, chooserActionsJson: $chooserActionsJson")
        shareText(content, chooserActionsJson, SharePreviewOptions())
    }

    override fun shareText(
        content: ShareContent,
        chooserActionsJson: String,
        preview: SharePreviewOptions
    ) {
        Log.d(TAG, "[shareText] content: $content, chooserActionsJson: $chooserActionsJson, preview: $preview")
        val previewUri = resolveOptionalPreviewUri(preview.thumbnailPath)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = content.mimeType
            putExtra(Intent.EXTRA_TEXT, content.text)
            content.subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
            preview.title?.let { putExtra(Intent.EXTRA_TITLE, it) }
            previewUri?.let {
                // Sharesheet reads the thumbnail from clipData, not from data.
                clipData = ClipData.newUri(context.contentResolver, null, it)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        val chooserIntent = Intent.createChooser(shareIntent, content.title)
        addChooserActionsIfSupported(chooserIntent, chooserActionsJson)
        startActivity(chooserIntent)
    }

    override fun shareImage(filePath: String, mimeType: String) {
        Log.d(TAG, "[shareImage] filePath: $filePath, mimeType: $mimeType")
        val uri = fileToContentUri(filePath)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, null))
    }

    override fun shareImages(filePaths: List<String>) {
        Log.d(TAG, "[shareImages] filePaths: $filePaths")
        val uris = ArrayList(filePaths.map { fileToContentUri(it) })
        val mimeType = filePaths
            .map { ShareMimeTypeHelper.getMimeType(File(it)) }
            .distinct()
            .let { if (it.size == 1) it.first() else "image/*" }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = mimeType
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, null))
    }

    override fun shareFile(filePath: String) {
        Log.d(TAG, "[shareFile] filePath: $filePath")
        val uri = fileToContentUri(filePath)
        val mimeType = ShareMimeTypeHelper.getMimeType(File(filePath))
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, null))
    }

    override fun shareFiles(filePaths: List<String>) {
        Log.d(TAG, "[shareFiles] filePaths: $filePaths")
        val uris = ArrayList(filePaths.map { fileToContentUri(it) })
        val mimeType = filePaths
            .map { ShareMimeTypeHelper.getMimeType(File(it)) }
            .distinct()
            .let { if (it.size == 1) it.first() else "*/*" }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = mimeType
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, null))
    }

    override fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray) {
        Log.d(TAG, "[registerDirectShareTarget] target: $target, iconBytes.size: ${iconBytes.size}")
        val result = try {
            shortcutPublisher.push(context, target, iconBytes)
        } catch (error: ShareDomainError.InvalidBase64Icon) {
            throw error
        } catch (error: RuntimeException) {
            val reason = error.message?.takeIf { it.isNotBlank() } ?: error.javaClass.simpleName
            throw ShareDomainError.DirectShareRegistrationFailed(reason)
        }
        if (!result) {
            throw ShareDomainError.DirectShareRegistrationFailed("push_failed")
        }
    }

    override fun removeDirectShareTargets(ids: List<String>) {
        Log.d(TAG, "[removeDirectShareTargets] ids: $ids")
        ShortcutManagerCompat.removeLongLivedShortcuts(context, ids)
    }

    override fun shareWithCallback(
        content: ShareContent,
        onResult: (String?) -> Unit
    ) {
        Log.d(TAG, "[shareWithCallback] content: $content, onResult: $onResult")
        shareWithCallback(content, SharePreviewOptions(), onResult) {}
    }

    override fun shareWithCallback(
        content: ShareContent,
        preview: SharePreviewOptions,
        onResult: (String?) -> Unit,
        onFinished: () -> Unit
    ) {
        Log.d(TAG, "[shareWithCallback] content: $content, preview: $preview, onResult: $onResult, onFinished: $onFinished")
        val callbackAction = "${context.packageName}.SHARE_CALLBACK"
        val token = coordinator.register(callbackAction, onResult, onFinished)
        try {
            val previewUri = resolveOptionalPreviewUri(preview.thumbnailPath)
            val callbackIntent = Intent(callbackAction).setPackage(context.packageName)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                SHARE_CALLBACK_REQUEST_CODE,
                callbackIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = content.mimeType
                putExtra(Intent.EXTRA_TEXT, content.text)
                content.subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                preview.title?.let { putExtra(Intent.EXTRA_TITLE, it) }
                previewUri?.let {
                    // Sharesheet reads the thumbnail from clipData, not from data.
                    clipData = ClipData.newUri(context.contentResolver, null, it)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            val chooserIntent = Intent.createChooser(shareIntent, content.title, pendingIntent.intentSender)
            startActivity(chooserIntent)
        } catch (e: Throwable) {
            coordinator.cancel(token)
            throw e
        }
    }

    override fun cancelPendingCallback() {
        Log.d(TAG, "[cancelPendingCallback]")
        coordinator.cancel()
    }

    /** Converts an optional preview thumbnail path to a content URI; returns null (with a warning) if not convertible. */
    private fun resolveOptionalPreviewUri(path: String?): Uri? {
        if (path.isNullOrBlank()) return null
        return try {
            fileToContentUri(path)
        } catch (e: ShareDomainError.FileNotFound) {
            Log.w(TAG, "[resolveOptionalPreviewUri] thumbnail not found: $path"); null
        } catch (e: ShareDomainError.IllegalFileAccess) {
            Log.w(TAG, "[resolveOptionalPreviewUri] thumbnail not shareable: $path"); null
        }
    }

    private fun fileToContentUri(filePath: String): Uri {
        val file = File(filePath)
        if (!file.exists()) throw ShareDomainError.FileNotFound(filePath)
        return try {
            FileProvider.getUriForFile(context, "${context.packageName}$SHARE_FILE_PROVIDER_AUTHORITY_SUFFIX", file)
        } catch (e: IllegalArgumentException) {
            throw ShareDomainError.IllegalFileAccess(filePath)
        }
    }

    private fun startActivity(intent: Intent) {
        if (context !is android.app.Activity) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            throw ShareDomainError.NoShareTarget
        }
    }

    @SuppressLint("NewApi")
    private fun addChooserActionsIfSupported(chooserIntent: Intent, chooserActionsJson: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        if (chooserActionsJson.isBlank() || chooserActionsJson == "[]") return
        try {
            buildChooserActions(chooserActionsJson).let { actions ->
                if (actions.isNotEmpty()) {
                    chooserIntent.putExtra(
                        Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS,
                        actions.toTypedArray<ChooserAction>()
                    )
                }
            }
        } catch (_: Exception) {
            Log.w(TAG, "[addChooserActionsIfSupported] failed to parse chooserActionsJson")
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun buildChooserActions(chooserActionsJson: String): List<ChooserAction> {
        val array = JSONArray(chooserActionsJson)
        val actions = mutableListOf<ChooserAction>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            val label = obj.optString("label").takeIf { it.isNotBlank() } ?: continue
            val iconBase64 = obj.optString("iconBase64").takeIf { it.isNotBlank() } ?: continue
            val intentAction = obj.optString("intentAction").ifBlank { Intent.ACTION_SEND }

            val iconBytes = runCatching { Base64.decode(iconBase64, Base64.DEFAULT) }.getOrNull() ?: continue
            val bitmap = BitmapFactory.decodeByteArray(iconBytes, 0, iconBytes.size) ?: continue
            val icon = android.graphics.drawable.Icon.createWithBitmap(bitmap)

            val actionIntent = PendingIntent.getBroadcast(
                context,
                label.hashCode(),
                Intent(intentAction).setPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            actions.add(ChooserAction.Builder(icon, label, actionIntent).build())
        }
        return actions
    }

    private companion object {
        private const val TAG = "android.library.share.data.repository.ShareRepositoryImpl"
        private const val SHARE_CALLBACK_REQUEST_CODE = 0
    }
}
