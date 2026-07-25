package android.unity.clipboard

import android.content.Context
import android.library.clipboard.data.repository.ClipboardUseCases
import android.library.clipboard.domain.error.ClipboardDomainError
import android.library.clipboard.domain.model.ClipContent
import android.library.clipboard.domain.model.ClipReadResult
import android.library.clipboard.presentation.ClipboardChangeMonitor
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Unity-facing clipboard bridge for native-toolkit.
 *
 * Exposes clipboard operations to Unity via JNI / AndroidJavaObject.
 *
 * copy/clear operations report results through [ClipboardOperationListener]. read/hasClip/
 * getDescription are synchronous and return their result as a JSON string directly (no listener
 * round trip), since clipboard reads are inherently synchronous and foreground-bound.
 *
 * Clipboard change observation is delegated to [ClipboardChangeMonitor], which lives in the native
 * library and owns the system listener. This bridge holds no system listener of its own, so native
 * callers can observe clipboard changes without depending on the Unity plugin.
 */
object UnityAndroidClipboardManager {

    private const val TAG = "android.unity.clipboard.UnityAndroidClipboardManager"

    const val OPERATION_COPY_PLAIN_TEXT = "copyPlainText"
    const val OPERATION_COPY_HTML_TEXT = "copyHtmlText"
    const val OPERATION_COPY_URI = "copyUri"
    const val OPERATION_COPY_MULTIPLE_TEXT = "copyMultipleText"
    const val OPERATION_CLEAR = "clear"
    const val OPERATION_STOP_OBSERVING = "stopObserving"

    private var clipboardOperationListener: ClipboardOperationListener? = null
    private var clipboardChangeListener: ClipboardChangeListener? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val monitor = ClipboardChangeMonitor()

    /**
     * Listener for clipboard operation results (copy/clear/stopObserving).
     */
    interface ClipboardOperationListener {
        /** Called for copy/clear/stopObserving operations on success or failure. */
        fun onClipboardOperation(operation: String, isSuccessful: Boolean, errorMessage: String?)
    }

    /**
     * Listener for clipboard change notifications.
     *
     * Callbacks are delivered on the main thread.
     */
    interface ClipboardChangeListener {
        /** Called when the clipboard content changes while observing. */
        fun onClipboardChanged()
    }

    /**
     * Returns the singleton instance for Unity JNI bridge calls.
     */
    @JvmStatic
    fun getInstance(): UnityAndroidClipboardManager {
        Log.d(TAG, "[getInstance] called")
        return this
    }

    /**
     * Registers a clipboard operation result listener.
     *
     * @param listener Listener to register.
     */
    fun setClipboardOperationListener(listener: ClipboardOperationListener) {
        Log.d(TAG, "[setClipboardOperationListener] listener: $listener")
        clipboardOperationListener = listener
    }

    /**
     * Clears the clipboard operation result listener.
     */
    fun clearClipboardOperationListener() {
        Log.d(TAG, "[clearClipboardOperationListener]")
        clipboardOperationListener = null
    }

    /**
     * Registers the listener for clipboard change notifications.
     *
     * Registering the listener alone does not start observation; call [startObserving] to begin
     * receiving [ClipboardChangeListener.onClipboardChanged] callbacks.
     *
     * @param listener Listener to register.
     */
    fun setClipboardChangeListener(listener: ClipboardChangeListener) {
        Log.d(TAG, "[setClipboardChangeListener] listener: $listener")
        runOnMain { clipboardChangeListener = listener }
    }

    /**
     * Clears the clipboard change listener and stops observing.
     */
    fun clearClipboardChangeListener() {
        Log.d(TAG, "[clearClipboardChangeListener]")
        runOnMain {
            monitor.stop()
            clipboardChangeListener = null
        }
    }

    /**
     * Copies plain text to the clipboard.
     *
     * @param context Android context.
     * @param clipboardJson JSON: { "text": "...", "label": "...", "isSensitive": false }
     */
    fun copyPlainText(context: Context, clipboardJson: String) {
        Log.d(TAG, "[copyPlainText] context: $context, clipboardJson: ${maskJson(clipboardJson)}")
        executeOperationOnMain(OPERATION_COPY_PLAIN_TEXT) {
            val spec = UnityClipboardJsonParser.parseCopyPlainText(clipboardJson)
            val content = ClipContent.PlainText(text = spec.text, label = spec.label, isSensitive = spec.isSensitive)
            ClipboardUseCases(context).copyPlainText(content)
        }
    }

    /**
     * Copies HTML text to the clipboard.
     *
     * @param context Android context.
     * @param clipboardJson JSON: { "plainText": "...", "htmlText": "...", "label": "...", "isSensitive": false }
     */
    fun copyHtmlText(context: Context, clipboardJson: String) {
        Log.d(TAG, "[copyHtmlText] context: $context, clipboardJson: ${maskJson(clipboardJson)}")
        executeOperationOnMain(OPERATION_COPY_HTML_TEXT) {
            val spec = UnityClipboardJsonParser.parseCopyHtmlText(clipboardJson)
            val content = ClipContent.HtmlText(
                plainText = spec.plainText,
                htmlText = spec.htmlText,
                label = spec.label,
                isSensitive = spec.isSensitive
            )
            ClipboardUseCases(context).copyHtmlText(content)
        }
    }

    /**
     * Copies a URI (content://, including image/file references) to the clipboard.
     *
     * @param context Android context.
     * @param clipboardJson JSON: { "uri": "...", "label": "...", "isSensitive": false }
     */
    fun copyUri(context: Context, clipboardJson: String) {
        Log.d(TAG, "[copyUri] context: $context, clipboardJson: ${maskJson(clipboardJson)}")
        executeOperationOnMain(OPERATION_COPY_URI) {
            val spec = UnityClipboardJsonParser.parseCopyUri(clipboardJson)
            val content = ClipContent.UriContent(uri = spec.uri, label = spec.label, isSensitive = spec.isSensitive)
            ClipboardUseCases(context).copyUri(content)
        }
    }

    /**
     * Copies multiple plain-text items (same form) to the clipboard.
     *
     * @param context Android context.
     * @param clipboardJson JSON: { "texts": ["...", "..."], "label": "...", "isSensitive": false }
     */
    fun copyMultipleText(context: Context, clipboardJson: String) {
        Log.d(TAG, "[copyMultipleText] context: $context, clipboardJson: ${maskJson(clipboardJson)}")
        executeOperationOnMain(OPERATION_COPY_MULTIPLE_TEXT) {
            val spec = UnityClipboardJsonParser.parseCopyMultipleText(clipboardJson)
            val content = ClipContent.MultipleText(texts = spec.texts, label = spec.label, isSensitive = spec.isSensitive)
            ClipboardUseCases(context).copyMultipleText(content)
        }
    }

    /**
     * Reads the current clipboard content.
     *
     * @param context Android context.
     * @return On success with content: JSON `{ "label": "...", "mimeTypes": [...], "items": [{ "text":..., "htmlText":..., "uri":..., "coercedText":... }] }`.
     *   On an empty clipboard (normal case): the string `"null"`.
     *   On failure (e.g. read denied by the system): JSON `{ "error": "CLIPBOARD_READ_NOT_ALLOWED", "message": "..." }`
     *   using the same error codes as [ClipboardOperationListener.onClipboardOperation].
     */
    fun read(context: Context): String {
        Log.d(TAG, "[read] context: $context")
        return try {
            val result = ClipboardUseCases(context).read()
            result?.let { readResultToJson(it).toString() } ?: "null"
        } catch (exception: Exception) {
            val (code, message) = errorInfoOf(exception)
            Log.e(TAG, "[read] failed: $message", exception)
            errorJson(code, message)
        }
    }

    /**
     * Returns whether the clipboard currently holds data.
     *
     * @param context Android context.
     * @return "true" or "false". Returns "false" if the clipboard service could not be queried.
     */
    fun hasClip(context: Context): String {
        Log.d(TAG, "[hasClip] context: $context")
        return try {
            ClipboardUseCases(context).hasClip().toString()
        } catch (exception: Exception) {
            Log.e(TAG, "[hasClip] failed", exception)
            "false"
        }
    }

    /**
     * Reads clipboard metadata without touching the clip body.
     *
     * @param context Android context.
     * @return On success with content: JSON `{ "label": "...", "mimeTypes": [...], "isStyledText": false, "classificationStatus": null }`.
     *   On an empty clipboard (normal case): the string `"null"`.
     *   On failure: JSON `{ "error": "CLIPBOARD_UNAVAILABLE", "message": "..." }` using the same
     *   error codes as [ClipboardOperationListener.onClipboardOperation].
     */
    fun getDescription(context: Context): String {
        Log.d(TAG, "[getDescription] context: $context")
        return try {
            val description = ClipboardUseCases(context).getDescription() ?: return "null"
            JSONObject().apply {
                put("label", description.label)
                put("mimeTypes", JSONArray(description.mimeTypes))
                put("isStyledText", description.isStyledText)
                put("classificationStatus", description.classificationStatus)
            }.toString()
        } catch (exception: Exception) {
            val (code, message) = errorInfoOf(exception)
            Log.e(TAG, "[getDescription] failed: $message", exception)
            errorJson(code, message)
        }
    }

    /**
     * Clears the clipboard.
     *
     * @param context Android context.
     */
    fun clear(context: Context) {
        Log.d(TAG, "[clear] context: $context")
        executeOperationOnMain(OPERATION_CLEAR) {
            ClipboardUseCases(context).clear()
        }
    }

    /**
     * Starts observing clipboard changes. [setClipboardChangeListener] should be called first so
     * that changes are delivered; starting observation without a registered listener is a no-op
     * for delivery (changes are silently dropped with a warning log).
     *
     * A second call while already observing is a no-op (no duplicate system listener registration).
     *
     * @param context Android context.
     */
    fun startObserving(context: Context) {
        Log.d(TAG, "[startObserving] context: $context")
        runOnMain { monitor.start(context) { notifyClipboardChanged() } }
    }

    /**
     * Stops observing clipboard changes.
     */
    fun stopObserving() {
        Log.d(TAG, "[stopObserving]")
        runOnMain {
            monitor.stop()
            notifyOperationResult(OPERATION_STOP_OBSERVING, true, null)
        }
    }

    private fun readResultToJson(result: ClipReadResult): JSONObject {
        val items = JSONArray()
        result.items.forEach { item ->
            items.put(
                JSONObject().apply {
                    put("text", item.text)
                    put("htmlText", item.htmlText)
                    put("uri", item.uri)
                    put("coercedText", item.coercedText)
                }
            )
        }
        return JSONObject().apply {
            put("label", result.label)
            put("mimeTypes", JSONArray(result.mimeTypes))
            put("items", items)
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
        } catch (exception: Exception) {
            val (_, message) = errorInfoOf(exception)
            Log.e(TAG, "[$name] failed: $message", exception)
            notifyOperationResult(name, false, message)
        }
    }

    /**
     * Maps a thrown exception to a stable error code and a Bridge-facing error message, per the
     * clipboard error code table (CLIPBOARD_EMPTY_CONTENT / CLIPBOARD_EMPTY_ITEMS /
     * CLIPBOARD_INVALID_URI / CLIPBOARD_UNAVAILABLE / CLIPBOARD_READ_NOT_ALLOWED /
     * CLIPBOARD_SECURITY / CLIPBOARD_UNKNOWN). Shared by the Listener-based copy/clear path and
     * the synchronous read/getDescription JSON path so both surfaces stay consistent.
     */
    private fun errorInfoOf(exception: Exception): Pair<String, String> = when (exception) {
        is ClipboardDomainError.EmptyContent ->
            "CLIPBOARD_EMPTY_CONTENT" to "Clipboard content is empty. Please provide text or HTML."
        is ClipboardDomainError.EmptyItemList ->
            "CLIPBOARD_EMPTY_ITEMS" to "No items provided for clipboard copy."
        is ClipboardDomainError.InvalidUri ->
            "CLIPBOARD_INVALID_URI" to "Invalid URI: ${exception.uri}"
        is ClipboardDomainError.ClipboardUnavailable ->
            "CLIPBOARD_UNAVAILABLE" to "Clipboard service is unavailable."
        is ClipboardDomainError.ReadNotAllowed ->
            "CLIPBOARD_READ_NOT_ALLOWED" to "Clipboard read is not allowed. The app must be in the foreground."
        is SecurityException ->
            "CLIPBOARD_SECURITY" to "Security restriction while accessing clipboard: ${exception.message}"
        else ->
            "CLIPBOARD_UNKNOWN" to "Failed: ${exception.message ?: exception.javaClass.simpleName}"
    }

    private fun errorJson(code: String, message: String): String =
        JSONObject().apply {
            put("error", code)
            put("message", message)
        }.toString()

    /**
     * Masks a clipboard-bearing JSON payload for logging: replaces the raw value with its length
     * so method-entry parameter tracking (android.md) does not leak clipboard content (which may
     * hold passwords, tokens, or other sensitive data) into Logcat.
     */
    private fun maskJson(json: String): String = "<redacted, length=${json.length}>"

    private fun notifyOperationResult(operation: String, isSuccessful: Boolean, errorMessage: String?) {
        val listener = clipboardOperationListener
        if (listener == null) {
            Log.w(
                TAG,
                "[notifyOperationResult] ClipboardOperationListener is not set. operation=$operation, isSuccessful=$isSuccessful"
            )
            return
        }
        listener.onClipboardOperation(operation, isSuccessful, errorMessage)
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    private fun notifyClipboardChanged() {
        val listener = clipboardChangeListener
        if (listener == null) {
            Log.w(TAG, "[notifyClipboardChanged] ClipboardChangeListener is not set")
            return
        }
        try {
            listener.onClipboardChanged()
        } catch (exception: Exception) {
            // Never let a Unity-side exception escape the clipboard listener callback.
            Log.e(TAG, "[notifyClipboardChanged] listener threw", exception)
        }
    }
}
