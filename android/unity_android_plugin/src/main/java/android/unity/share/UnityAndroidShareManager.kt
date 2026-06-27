package android.unity.share

import android.content.ActivityNotFoundException
import android.content.Context
import android.library.share.data.repository.ShareUseCases
import android.library.share.domain.error.ShareDomainError
import android.library.share.domain.model.DirectShareTarget
import android.library.share.domain.model.ShareContent
import android.library.share.domain.model.SharePreviewOptions
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.annotation.VisibleForTesting

/**
 * Unity-facing share bridge for native-toolkit.
 *
 * Exposes share operations to Unity via JNI / AndroidJavaObject.
 * All operations report results through [ShareOperationListener].
 */
object UnityAndroidShareManager {

    private const val TAG = "android.unity.share.UnityAndroidShareManager"

    const val OPERATION_SHARE_TEXT = "shareText"
    const val OPERATION_SHARE_IMAGE = "shareImage"
    const val OPERATION_SHARE_IMAGES = "shareImages"
    const val OPERATION_SHARE_FILE = "shareFile"
    const val OPERATION_SHARE_FILES = "shareFiles"
    const val OPERATION_REGISTER_DIRECT_SHARE_TARGET = "registerDirectShareTarget"
    const val OPERATION_REMOVE_DIRECT_SHARE_TARGETS = "removeDirectShareTargets"
    const val OPERATION_SHARE_WITH_CALLBACK = "shareWithCallback"
    const val OPERATION_CANCEL_PENDING_SHARE_CALLBACK = "cancelPendingShareCallback"

    private var shareOperationListener: ShareOperationListener? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Holds applicationContext while a shareWithCallback is pending, enabling clearShareOperationListener to cancel it.
    private var pendingCallbackContext: Context? = null

    private var shareChooserActionListener: ShareChooserActionListener? = null
    private var chooserActionRegistry: ShareChooserActionReceiverRegistry? = null
    private var chooserActionToken: Long = 0L

    // Test seam: swap in a fake registry without a device.
    @VisibleForTesting
    internal var chooserActionRegistryFactory: (Context) -> ShareChooserActionReceiverRegistry =
        { ctx -> AndroidShareChooserActionReceiverRegistry(ctx.applicationContext) }

    /**
     * Listener for custom chooser action taps reported back to Unity.
     *
     * Callbacks are delivered on the main thread.
     * Exceptions thrown by the implementation are caught and logged; they do not propagate.
     */
    interface ShareChooserActionListener {
        /**
         * Called when the user taps a custom chooser action in the Sharesheet.
         *
         * @param actionId The intentAction string of the tapped action.
         */
        fun onChooserAction(actionId: String)
    }

    /**
     * Listener for share operation results.
     */
    interface ShareOperationListener {
        /** Called for all operations except shareWithCallback on success or failure. */
        fun onShareOperation(operation: String, isSuccessful: Boolean, errorMessage: String?)

        /**
         * Called after shareWithCallback when the user selects an app.
         *
         * @param operation Always [OPERATION_SHARE_WITH_CALLBACK].
         * @param selectedPackageName Package name of the selected app, or null if unavailable.
         */
        fun onShareResult(operation: String, selectedPackageName: String?)
    }

    /**
     * Returns the singleton instance for Unity JNI bridge calls.
     */
    @JvmStatic
    fun getInstance(): UnityAndroidShareManager {
        Log.d(TAG, "[getInstance] called")
        return this
    }

    /**
     * Registers a share operation result listener.
     *
     * @param listener Listener to register.
     */
    fun setShareOperationListener(listener: ShareOperationListener) {
        Log.d(TAG, "[setShareOperationListener] listener: $listener")
        shareOperationListener = listener
    }

    /**
     * Clears the share operation result listener and cancels any pending share-callback receiver.
     */
    fun clearShareOperationListener() {
        Log.d(TAG, "[clearShareOperationListener]")
        runOnMain {
            pendingCallbackContext?.let { ShareUseCases(it).cancelPendingCallback() }
            pendingCallbackContext = null
            shareOperationListener = null
        }
    }

    /**
     * Registers the listener for custom chooser action taps.
     * The callback is delivered on the main thread.
     *
     * @param listener Listener to register.
     */
    fun setShareChooserActionListener(listener: ShareChooserActionListener) {
        Log.d(TAG, "[setShareChooserActionListener] listener: $listener")
        runOnMain { shareChooserActionListener = listener }
    }

    /**
     * Clears the chooser action listener and unregisters the current dynamic receiver.
     */
    fun clearShareChooserActionListener() {
        Log.d(TAG, "[clearShareChooserActionListener]")
        runOnMain {
            chooserActionRegistry?.unregister(chooserActionToken)
            chooserActionToken = 0L
            shareChooserActionListener = null
        }
    }

    /**
     * Shares text or URL content via the Android Sharesheet.
     *
     * @param context Android context.
     * @param shareJson JSON: { "text": "...", "title": "...", "subject": "...", "mimeType": "text/plain",
     *   "chooserActions": [...], "previewTitle": "...", "previewThumbnailPath": "..." }
     */
    fun shareText(context: Context, shareJson: String) {
        Log.d(TAG, "[shareText] context: $context, shareJson: $shareJson")
        executeOperationOnMain(OPERATION_SHARE_TEXT) {
            val spec = UnityShareJsonParser.parseShareText(shareJson)
            val content = ShareContent(
                text = spec.text,
                title = spec.title,
                subject = spec.subject,
                mimeType = spec.mimeType
            )
            val chooserActionsJson = buildChooserActionsJson(spec.chooserActions)
            val preview = SharePreviewOptions(spec.previewTitle, spec.previewThumbnailPath)
            val actionIds = ShareChooserActionInputs.normalizeActionIds(spec.chooserActions)
            val registry = chooserActionRegistry
                ?: chooserActionRegistryFactory(context).also { chooserActionRegistry = it }
            val token = registry.register(actionIds) { actionId -> dispatchChooserAction(actionId) }
            chooserActionToken = token
            try {
                ShareUseCases(context).shareText(content, chooserActionsJson, preview)
            } catch (error: Throwable) {
                // Share launch failed: drop this registration only (generation-guarded).
                registry.unregister(token)
                if (chooserActionToken == token) chooserActionToken = 0L
                throw error
            }
        }
    }

    /**
     * Shares a single image via the Android Sharesheet.
     *
     * @param context Android context.
     * @param shareJson JSON: { "filePath": "...", "mimeType": "image/jpeg" }
     */
    fun shareImage(context: Context, shareJson: String) {
        Log.d(TAG, "[shareImage] context: $context, shareJson: $shareJson")
        executeOperationOnMain(OPERATION_SHARE_IMAGE) {
            val spec = UnityShareJsonParser.parseShareImage(shareJson)
            ShareUseCases(context).shareImage(spec.filePath, spec.mimeType)
        }
    }

    /**
     * Shares multiple images via the Android Sharesheet.
     *
     * @param context Android context.
     * @param shareJson JSON: { "filePaths": ["...", "..."], "mimeType": "image/&#42;" }
     */
    fun shareImages(context: Context, shareJson: String) {
        Log.d(TAG, "[shareImages] context: $context, shareJson: $shareJson")
        executeOperationOnMain(OPERATION_SHARE_IMAGES) {
            val spec = UnityShareJsonParser.parseShareImages(shareJson)
            ShareUseCases(context).shareImages(spec.filePaths)
        }
    }

    /**
     * Shares a single file via the Android Sharesheet.
     *
     * @param context Android context.
     * @param shareJson JSON: { "filePath": "..." }
     */
    fun shareFile(context: Context, shareJson: String) {
        Log.d(TAG, "[shareFile] context: $context, shareJson: $shareJson")
        executeOperationOnMain(OPERATION_SHARE_FILE) {
            val spec = UnityShareJsonParser.parseShareFile(shareJson)
            ShareUseCases(context).shareFile(spec.filePath!!)
        }
    }

    /**
     * Shares multiple files via the Android Sharesheet.
     *
     * @param context Android context.
     * @param shareJson JSON: { "filePaths": ["...", "..."] }
     */
    fun shareFiles(context: Context, shareJson: String) {
        Log.d(TAG, "[shareFiles] context: $context, shareJson: $shareJson")
        executeOperationOnMain(OPERATION_SHARE_FILES) {
            val spec = UnityShareJsonParser.parseShareFiles(shareJson)
            ShareUseCases(context).shareFiles(spec.filePaths)
        }
    }

    /**
     * Registers a Direct Share shortcut target.
     *
     * @param context Android context.
     * @param shareJson JSON: { "id": "...", "label": "...", "iconBase64": "...", "category": "..." }
     */
    fun registerDirectShareTarget(context: Context, shareJson: String) {
        Log.d(TAG, "[registerDirectShareTarget] context: $context, shareJson: $shareJson")
        executeOperationOnMain(OPERATION_REGISTER_DIRECT_SHARE_TARGET) {
            val spec = UnityShareJsonParser.parseRegisterDirectShareTarget(shareJson)
            val iconBytes = try {
                Base64.decode(spec.iconBase64, Base64.DEFAULT)
            } catch (_: IllegalArgumentException) {
                throw ShareDomainError.InvalidBase64Icon(spec.id)
            }
            val target = DirectShareTarget(
                id = spec.id,
                label = spec.label,
                category = spec.category
            )
            ShareUseCases(context).registerDirectShareTarget(target, iconBytes)
        }
    }

    /**
     * Removes Direct Share shortcut targets.
     *
     * @param context Android context.
     * @param shareJson JSON: { "ids": ["...", "..."] }
     */
    fun removeDirectShareTargets(context: Context, shareJson: String) {
        Log.d(TAG, "[removeDirectShareTargets] context: $context, shareJson: $shareJson")
        executeOperationOnMain(OPERATION_REMOVE_DIRECT_SHARE_TARGETS) {
            val spec = UnityShareJsonParser.parseRemoveDirectShareTargets(shareJson)
            ShareUseCases(context).removeDirectShareTargets(spec.ids)
        }
    }

    /**
     * Shares text content and reports the selected app via [ShareOperationListener.onShareResult].
     *
     * @param context Android context.
     * @param shareJson JSON: { "text": "...", "title": "...", "previewTitle": "...", "previewThumbnailPath": "..." }
     */
    fun shareWithCallback(context: Context, shareJson: String) {
        Log.d(TAG, "[shareWithCallback] context: $context, shareJson: $shareJson")
        executeOperationOnMain(OPERATION_SHARE_WITH_CALLBACK) {
            val spec = UnityShareJsonParser.parseShareText(shareJson)
            val content = ShareContent(
                text = spec.text,
                title = spec.title,
                subject = spec.subject,
                mimeType = spec.mimeType
            )
            val preview = SharePreviewOptions(spec.previewTitle, spec.previewThumbnailPath)
            pendingCallbackContext = context.applicationContext
            try {
                ShareUseCases(context).shareWithCallback(
                    content = content,
                    preview = preview,
                    onResult = { selectedPackageName ->
                        val listener = shareOperationListener
                        if (listener != null) {
                            listener.onShareResult(OPERATION_SHARE_WITH_CALLBACK, selectedPackageName)
                        } else {
                            Log.w(TAG, "[shareWithCallback] onShareResult: listener is null, packageName=$selectedPackageName")
                        }
                    },
                    onFinished = { pendingCallbackContext = null }
                )
            } catch (error: Throwable) {
                pendingCallbackContext = null
                throw error
            }
        }
    }

    /**
     * Cancels the pending share-callback BroadcastReceiver.
     *
     * @param context Android context.
     */
    fun cancelPendingShareCallback(context: Context) {
        Log.d(TAG, "[cancelPendingShareCallback] context: $context")
        executeOperationOnMain(OPERATION_CANCEL_PENDING_SHARE_CALLBACK) {
            ShareUseCases(context).cancelPendingCallback()
            pendingCallbackContext = null
        }
    }

    private fun executeOperationOnMain(name: String, block: () -> Unit) {
        Log.d(TAG, "[executeOperationOnMain] name: $name")
        val task = Runnable { executeOperation(name, block) }
        if (Looper.myLooper() == Looper.getMainLooper()) task.run() else mainHandler.post(task)
    }

    private fun executeOperation(name: String, block: () -> Unit) {
        try {
            block()
            notifyOperationResult(name, true, null)
        } catch (exception: ShareDomainError.EmptyContent) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "Share content is empty. Please provide text or a file path."
            )
        } catch (exception: ShareDomainError.NoShareTarget) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "No app available to handle this share request."
            )
        } catch (exception: ShareDomainError.FileNotFound) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "File not found: ${exception.path}"
            )
        } catch (exception: ShareDomainError.IllegalFileAccess) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "File cannot be shared: ${exception.path}. Ensure the file is in a supported directory."
            )
        } catch (exception: ShareDomainError.InvalidMimeType) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "Invalid MIME type: ${exception.mimeType}"
            )
        } catch (exception: ShareDomainError.DirectShareRegistrationFailed) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "Failed to register Direct Share target: ${exception.reason}"
            )
        } catch (exception: ShareDomainError.EmptyIdList) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "No shortcut IDs provided for removal."
            )
        } catch (exception: ShareDomainError.EmptyFileList) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "No file paths provided for share."
            )
        } catch (exception: ShareDomainError.InvalidBase64Icon) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "Invalid icon data for Direct Share target: ${exception.id}"
            )
        } catch (exception: ActivityNotFoundException) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "No app available to handle this share request."
            )
        } catch (exception: SecurityException) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "Security restriction while executing $name: ${exception.message}"
            )
        } catch (exception: Exception) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "Failed to $name: ${exception.message ?: exception.javaClass.simpleName}"
            )
        }
    }

    private fun notifyOperationFailure(name: String, throwable: Exception, errorMessage: String) {
        Log.e(TAG, "[$name] failed: $errorMessage", throwable)
        notifyOperationResult(name, false, errorMessage)
    }

    private fun notifyOperationResult(operation: String, isSuccessful: Boolean, errorMessage: String?) {
        val listener = shareOperationListener
        if (listener == null) {
            Log.w(
                TAG,
                "[notifyOperationResult] ShareOperationListener is not set. operation=$operation, isSuccessful=$isSuccessful"
            )
            return
        }
        listener.onShareOperation(operation, isSuccessful, errorMessage)
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    private fun dispatchChooserAction(actionId: String) {
        Log.d(TAG, "[dispatchChooserAction] actionId: $actionId")
        val listener = shareChooserActionListener
        if (listener == null) {
            Log.w(TAG, "[dispatchChooserAction] listener is null, actionId=$actionId")
            return
        }
        try {
            listener.onChooserAction(actionId)
        } catch (e: Exception) {
            // Never let a Unity-side exception escape the BroadcastReceiver thread.
            Log.e(TAG, "[dispatchChooserAction] listener threw for actionId=$actionId", e)
        }
    }

    private fun buildChooserActionsJson(actions: List<UnityChooserActionSpec>): String {
        if (actions.isEmpty()) return "[]"
        val array = org.json.JSONArray()
        actions.forEach { action ->
            array.put(
                org.json.JSONObject().apply {
                    put("label", action.label)
                    put("iconBase64", action.iconBase64)
                    put("intentAction", action.intentAction)
                }
            )
        }
        return array.toString()
    }
}
