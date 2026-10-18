package com.jonghyunkim.nativetoolkit.share.data.repository

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import com.jonghyunkim.nativetoolkit.share.application.port.RichPreviewShareRepository
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.DirectShareTarget
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareChooserAction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.logSafeDescription
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import com.jonghyunkim.nativetoolkit.share.presentation.ShareChooserActionReceiver
import android.net.Uri
import android.os.Build
import android.service.chooser.ChooserAction
import android.util.Log
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutManagerCompat
import java.io.File

internal const val SHARE_FILE_PROVIDER_AUTHORITY_SUFFIX = ".native_toolkit.share.fileprovider"

class ShareRepositoryImpl(private val context: Context) : RichPreviewShareRepository {

    internal var shortcutPublisher: DirectShareShortcutPublisher = AndroidDirectShareShortcutPublisher

    private val coordinator by lazy { ShareCallbackCoordinator.get(context) }

    override fun shareText(content: ShareContent) {
        Log.d(TAG, "[shareText] content: ${content.logSafeDescription()}")
        shareText(content, SharePreviewOptions())
    }

    override fun shareText(content: ShareContent, preview: SharePreviewOptions) {
        Log.d(TAG, "[shareText] content: ${content.logSafeDescription()}, preview: $preview")
        startActivity(Intent.createChooser(textShareIntent(content, preview), content.title))
    }

    override fun shareTextWithActions(
        content: ShareContent,
        actions: List<ShareChooserAction>,
        preview: SharePreviewOptions
    ) {
        Log.d(TAG, "[shareTextWithActions] content: ${content.logSafeDescription()}, actions: $actions, preview: $preview")
        // Check every action before the generation changes, so a rejected share leaves the
        // actions of the previous share working.
        val seen = HashSet<String>()
        val icons = actions.map { action ->
            if (action.id.isEmpty() || !seen.add(action.id)) throw ShareDomainError.InvalidChooserAction(action.id)
            BitmapFactory.decodeByteArray(action.iconBytes, 0, action.iconBytes.size)
                ?: throw ShareDomainError.InvalidChooserAction(action.id)
        }
        val generation = ShareChooserActionReceiver.nextGeneration(context)
        val chooserIntent = Intent.createChooser(textShareIntent(content, preview), content.title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && actions.isNotEmpty()) {
            val chooserActions = actions.zip(icons).map { (action, icon) ->
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    0,
                    ShareChooserActionReceiver.intent(context, generation, action.id),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                ChooserAction.Builder(android.graphics.drawable.Icon.createWithBitmap(icon), action.label, pendingIntent).build()
            }
            chooserIntent.putExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS, chooserActions.toTypedArray())
        }
        startActivity(chooserIntent)
    }

    override fun shareForSelection(content: ShareContent, preview: SharePreviewOptions): Long {
        Log.d(TAG, "[shareForSelection] content: ${content.logSafeDescription()}, preview: $preview")
        return openWithResult(content, preview, ShareWaitMode.Event)
    }

    override fun cancelShareSelection(token: Long) {
        Log.d(TAG, "[cancelShareSelection] token: $token")
        coordinator.cancel(token)
    }

    override fun shareImage(filePath: String, mimeType: String) {
        Log.d(TAG, "[shareImage] filePath: $filePath, mimeType: $mimeType")
        val uri = fileToContentUri(filePath)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newUri(context.contentResolver, null, uri)
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
        val clip = ClipData.newUri(context.contentResolver, null, uris.first())
            .also { clip -> uris.drop(1).forEach { uri -> clip.addItem(ClipData.Item(uri)) } }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = mimeType
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            clipData = clip
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
            clipData = ClipData.newUri(context.contentResolver, null, uri)
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
        val clip = ClipData.newUri(context.contentResolver, null, uris.first())
            .also { clip -> uris.drop(1).forEach { uri -> clip.addItem(ClipData.Item(uri)) } }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = mimeType
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            clipData = clip
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
        Log.d(TAG, "[shareWithCallback] content: ${content.logSafeDescription()}, onResult: $onResult")
        shareWithCallback(content, SharePreviewOptions(), onResult) {}
    }

    override fun shareWithCallback(
        content: ShareContent,
        preview: SharePreviewOptions,
        onResult: (String?) -> Unit,
        onFinished: () -> Unit
    ) {
        Log.d(TAG, "[shareWithCallback] content: ${content.logSafeDescription()}, preview: $preview, onResult: $onResult, onFinished: $onFinished")
        openWithResult(content, preview, ShareWaitMode.Callback(onResult, onFinished))
    }

    // Each request has its own result PendingIntent: the data URI carries the process nonce and
    // the request's token (Kotlin API design 8.9).
    private fun openWithResult(content: ShareContent, preview: SharePreviewOptions, mode: ShareWaitMode): Long {
        Log.d(TAG, "[openWithResult] content: ${content.logSafeDescription()}, preview: $preview, mode: $mode")
        val token = coordinator.register(mode)
        try {
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                SHARE_CALLBACK_REQUEST_CODE,
                ShareResultIntents.intent(context, coordinator.nonce, token),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            val chooserIntent = Intent.createChooser(textShareIntent(content, preview), content.title, pendingIntent.intentSender)
            startActivity(chooserIntent)
        } catch (e: Throwable) {
            coordinator.cancel(token)
            throw e
        }
        return token
    }

    private fun textShareIntent(content: ShareContent, preview: SharePreviewOptions): Intent {
        Log.d(TAG, "[textShareIntent] content: ${content.logSafeDescription()}, preview: $preview")
        val previewUri = resolveOptionalPreviewUri(preview.thumbnailPath)
        return Intent(Intent.ACTION_SEND).apply {
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

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.share.data.repository.ShareRepositoryImpl"
        private const val SHARE_CALLBACK_REQUEST_CODE = 0
    }
}
