package com.jonghyunkim.nativetoolkit.share

import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.share.application.usecase.CancelShareSelectionUseCase
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareForSelectionUseCase
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareTextWithActionsUseCase
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareUseCases
import com.jonghyunkim.nativetoolkit.share.data.repository.ShareRepositoryImpl
import com.jonghyunkim.nativetoolkit.share.domain.model.DirectShareTarget
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareChooserAction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareSelection
import com.jonghyunkim.nativetoolkit.share.domain.model.logSafeDescription
import com.jonghyunkim.nativetoolkit.share.presentation.ShareEvents

/**
 * The entry point for sharing (Kotlin API design 6.3, 8.9).
 *
 * The existing operations take the same arguments and give the same results and exceptions as
 * [ShareUseCases], except [shareText], which takes typed chooser actions through
 * [shareTextWithActions] instead of JSON. This class only delegates; it keeps no Activity.
 *
 * @param useCases The existing share use cases.
 * @param shareForSelectionUseCase Opens the Sharesheet and reports the pick as an event.
 * @param cancelShareSelectionUseCase Stops waiting for a pick.
 * @param shareTextWithActionsUseCase Shares text with typed chooser actions.
 */
class AndroidShareManager internal constructor(
    private val useCases: ShareUseCases,
    private val shareForSelectionUseCase: ShareForSelectionUseCase,
    private val cancelShareSelectionUseCase: CancelShareSelectionUseCase,
    private val shareTextWithActionsUseCase: ShareTextWithActionsUseCase
) {

    /** Taps on the actions of [shareTextWithActions], as the action ID. Main thread. */
    val chooserActions: EventHub<String> get() = ShareEvents.chooserActions

    /** Apps picked in Sharesheets opened by [shareForSelection]. Main thread. */
    val selections: EventHub<ShareSelection> get() = ShareEvents.selections

    /**
     * Shares text or a URL.
     *
     * @param content The content.
     * @param preview Rich-preview options.
     */
    fun shareText(content: ShareContent, preview: SharePreviewOptions = SharePreviewOptions()) {
        Log.d(TAG, "[shareText] content: ${content.logSafeDescription()}, preview: $preview")
        // The deprecated JSON form with no actions is the existing share (Kotlin API design 8.13, IT-27).
        @Suppress("DEPRECATION")
        useCases.shareText(content, "[]", preview)
    }

    /**
     * Shares one image.
     *
     * @param filePath The image file.
     * @param mimeType Its MIME type.
     */
    fun shareImage(filePath: String, mimeType: String) {
        Log.d(TAG, "[shareImage] filePath: $filePath, mimeType: $mimeType")
        useCases.shareImage(filePath, mimeType)
    }

    /**
     * Shares several images.
     *
     * @param filePaths The image files.
     */
    fun shareImages(filePaths: List<String>) {
        Log.d(TAG, "[shareImages] filePaths: $filePaths")
        useCases.shareImages(filePaths)
    }

    /**
     * Shares one file.
     *
     * @param filePath The file.
     */
    fun shareFile(filePath: String) {
        Log.d(TAG, "[shareFile] filePath: $filePath")
        useCases.shareFile(filePath)
    }

    /**
     * Shares several files.
     *
     * @param filePaths The files.
     */
    fun shareFiles(filePaths: List<String>) {
        Log.d(TAG, "[shareFiles] filePaths: $filePaths")
        useCases.shareFiles(filePaths)
    }

    /**
     * Registers a Direct Share target.
     *
     * @param target The target.
     * @param iconBytes Its icon image.
     */
    fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray) {
        Log.d(TAG, "[registerDirectShareTarget] target: $target, iconBytes.size: ${iconBytes.size}")
        useCases.registerDirectShareTarget(target, iconBytes)
    }

    /**
     * Removes Direct Share targets.
     *
     * @param ids The target IDs.
     */
    fun removeDirectShareTargets(ids: List<String>) {
        Log.d(TAG, "[removeDirectShareTargets] ids: $ids")
        useCases.removeDirectShareTargets(ids)
    }

    /**
     * Shares text and reports the picked app to [onResult]; [onFinished] runs once after any
     * result, including Copy and Edit. Opening another Sharesheet replaces this wait.
     *
     * @param content The content.
     * @param preview Rich-preview options.
     * @param onResult Receives the picked package, or `null` when Android did not report it.
     * @param onFinished Runs after the result is handled.
     */
    fun shareWithCallback(
        content: ShareContent,
        preview: SharePreviewOptions = SharePreviewOptions(),
        onResult: (String?) -> Unit,
        onFinished: () -> Unit = {}
    ) {
        Log.d(TAG, "[shareWithCallback] content: ${content.logSafeDescription()}, preview: $preview, onResult: $onResult, onFinished: $onFinished")
        useCases.shareWithCallback(content, preview, onResult, onFinished)
    }

    /** Stops waiting for the result of [shareWithCallback]. */
    fun cancelPendingCallback() {
        Log.d(TAG, "[cancelPendingCallback]")
        useCases.cancelPendingCallback()
    }

    /**
     * Shares text with typed chooser actions (shown on API 34 and later). Taps arrive through
     * [chooserActions]; the actions of earlier shares stop working.
     *
     * @param content The content.
     * @param actions The actions; IDs must be non-empty and unique.
     * @param preview Rich-preview options.
     */
    fun shareTextWithActions(
        content: ShareContent,
        actions: List<ShareChooserAction>,
        preview: SharePreviewOptions = SharePreviewOptions()
    ) {
        Log.d(TAG, "[shareTextWithActions] content: ${content.logSafeDescription()}, actions: $actions, preview: $preview")
        shareTextWithActionsUseCase(content, actions, preview)
    }

    /**
     * Opens the Sharesheet and returns a token; the picked app arrives through [selections] with
     * that token. Closing the Sharesheet or a non-selection result sends nothing.
     *
     * @param content The content.
     * @param preview Rich-preview options.
     * @return The token.
     */
    fun shareForSelection(content: ShareContent, preview: SharePreviewOptions = SharePreviewOptions()): Long {
        Log.d(TAG, "[shareForSelection] content: ${content.logSafeDescription()}, preview: $preview")
        return shareForSelectionUseCase(content, preview)
    }

    /**
     * Stops waiting for the pick of [token]. Does nothing when another Sharesheet was opened since.
     *
     * @param token A value returned by [shareForSelection].
     */
    fun cancelShareSelection(token: Long) {
        Log.d(TAG, "[cancelShareSelection] token: $token")
        cancelShareSelectionUseCase(token)
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.share.AndroidShareManager"

        @Volatile
        private var instance: AndroidShareManager? = null

        /**
         * Returns the process-wide instance.
         *
         * @param context Any Context; only its Application Context is kept.
         */
        @JvmStatic
        fun getInstance(context: Context): AndroidShareManager {
            Log.d(TAG, "[getInstance] context: $context")
            return instance ?: synchronized(this) {
                instance ?: create(context.applicationContext).also { instance = it }
            }
        }

        private fun create(appContext: Context): AndroidShareManager {
            Log.d(TAG, "[create] appContext: $appContext")
            val repository = ShareRepositoryImpl(appContext)
            return AndroidShareManager(
                useCases = ShareUseCases(repository),
                shareForSelectionUseCase = ShareForSelectionUseCase(repository),
                cancelShareSelectionUseCase = CancelShareSelectionUseCase(repository),
                shareTextWithActionsUseCase = ShareTextWithActionsUseCase(repository)
            )
        }
    }
}
