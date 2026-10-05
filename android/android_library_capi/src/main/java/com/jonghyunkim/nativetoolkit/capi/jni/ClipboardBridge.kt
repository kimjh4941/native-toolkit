package com.jonghyunkim.nativetoolkit.capi.jni

import android.util.Log
import com.jonghyunkim.nativetoolkit.clipboard.AndroidClipboardManager
import com.jonghyunkim.nativetoolkit.clipboard.domain.error.ClipboardErrorCode
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster

/**
 * The C ABI's entry to the clipboard (C ABI design part 2, 5.1, 6.1). Writes, reads and queries
 * run on the calling thread (AP-2, AP-3); observing and the change events go through the main
 * thread. Strings arrive and leave as UTF-8 byte arrays (Utf8). Nothing here throws to C: a
 * failure becomes the value of `ntk_clipboard_error` (part 2, 11.3).
 */
internal object ClipboardBridge {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.ClipboardBridge"

    /** The ledger kind of change listeners. */
    const val KIND_CHANGE = 100

    // ntk_clipboard_error 6 to 11, in the declaration order of ClipboardErrorCode (part 2, 11.3).
    private const val EMPTY_CONTENT = 6
    private const val EMPTY_ITEMS = 7
    private const val INVALID_URI = 8
    private const val UNAVAILABLE = 9
    private const val READ_NOT_ALLOWED = 10
    private const val SECURITY = 11

    /** Whether the one EventHub listener of design AP-21 is added. Main thread only. */
    private var hubListener: EventHub.Registration? = null

    private fun manager(): AndroidClipboardManager {
        Log.d(TAG, "[manager]")
        return AndroidClipboardManager.getInstance(NtkRuntime.context())
    }

    /** The value of ntk_clipboard_error for a failure (part 2, 11.3). */
    fun errorOf(error: Throwable): Int {
        Log.d(TAG, "[errorOf] error: ${error.javaClass.name}")
        if (error is OutOfMemoryError) return Errors.OUT_OF_MEMORY
        return when (ClipboardErrorCode.of(error)) {
            ClipboardErrorCode.EMPTY_CONTENT -> EMPTY_CONTENT
            ClipboardErrorCode.EMPTY_ITEMS -> EMPTY_ITEMS
            ClipboardErrorCode.INVALID_URI -> INVALID_URI
            ClipboardErrorCode.UNAVAILABLE -> UNAVAILABLE
            ClipboardErrorCode.READ_NOT_ALLOWED -> READ_NOT_ALLOWED
            ClipboardErrorCode.SECURITY -> SECURITY
            ClipboardErrorCode.UNKNOWN -> Errors.common(error)
        }
    }

    private inline fun guarded(name: String, block: () -> Unit): Int {
        return try {
            block()
            Errors.NONE
        } catch (e: Throwable) {
            Log.e(TAG, "[$name] failed: ${e.javaClass.name}")
            errorOf(e)
        }
    }

    // --- writes (OP-01 to OP-05). The text is a secret: only lengths are logged. ---

    @JvmStatic
    fun copyText(text: ByteArray, label: ByteArray?, sensitive: Boolean): Int {
        Log.d(TAG, "[copyText] textSize: ${text.size}, labelSize: ${label?.size}, sensitive: $sensitive")
        return guarded("copyText") {
            manager().copyPlainText(ClipContent.PlainText(Utf8.decode(text), Utf8.decodeOrNull(label) ?: "", sensitive))
        }
    }

    @JvmStatic
    fun copyHtml(html: ByteArray, plainText: ByteArray?, label: ByteArray?, sensitive: Boolean): Int {
        Log.d(TAG, "[copyHtml] htmlSize: ${html.size}, plainTextSize: ${plainText?.size}, labelSize: ${label?.size}, sensitive: $sensitive")
        return guarded("copyHtml") {
            manager().copyHtmlText(
                ClipContent.HtmlText(Utf8.decodeOrNull(plainText) ?: "", Utf8.decode(html), Utf8.decodeOrNull(label) ?: "", sensitive)
            )
        }
    }

    @JvmStatic
    fun copyUri(uri: ByteArray, label: ByteArray?, sensitive: Boolean): Int {
        Log.d(TAG, "[copyUri] uriSize: ${uri.size}, labelSize: ${label?.size}, sensitive: $sensitive")
        return guarded("copyUri") {
            manager().copyUri(ClipContent.UriContent(Utf8.decode(uri), Utf8.decodeOrNull(label) ?: "", sensitive))
        }
    }

    @JvmStatic
    fun copyTexts(texts: Array<ByteArray>, label: ByteArray?, sensitive: Boolean): Int {
        Log.d(TAG, "[copyTexts] count: ${texts.size}, labelSize: ${label?.size}, sensitive: $sensitive")
        return guarded("copyTexts") {
            manager().copyMultipleText(
                ClipContent.MultipleText(texts.map(Utf8::decode), Utf8.decodeOrNull(label) ?: "", sensitive)
            )
        }
    }

    @JvmStatic
    fun clear(): Int {
        Log.d(TAG, "[clear]")
        return guarded("clear") { manager().clear() }
    }

    // --- reads and queries (OP-06 to OP-08) ---

    /**
     * Reads the clip. Returns null when the clipboard is empty or the app has no input focus,
     * otherwise [label, mime types, items flattened as text, html, uri, coerced text per item].
     * [error] receives the result.
     */
    @JvmStatic
    fun read(error: IntArray): Array<Any?>? {
        Log.d(TAG, "[read] error: $error")
        var result: Array<Any?>? = null
        error[0] = guarded("read") {
            val clip = manager().read() ?: return@guarded
            val items = arrayOfNulls<ByteArray>(clip.items.size * 4)
            clip.items.forEachIndexed { i, item ->
                items[i * 4] = Utf8.encodeOrNull(item.text)
                items[i * 4 + 1] = Utf8.encodeOrNull(item.htmlText)
                items[i * 4 + 2] = Utf8.encodeOrNull(item.uri)
                items[i * 4 + 3] = Utf8.encodeOrNull(item.coercedText)
            }
            result = arrayOf(Utf8.encodeOrNull(clip.label), clip.mimeTypes.map(Utf8::encode).toTypedArray(), items)
        }
        return result
    }

    @JvmStatic
    fun hasClip(out: BooleanArray): Int {
        Log.d(TAG, "[hasClip] out: $out")
        return guarded("hasClip") { out[0] = manager().hasClip() }
    }

    /**
     * Returns null when the clipboard is empty, otherwise [label, mime types, [styled, status]]
     * where status is -1 when the OS reported none.
     */
    @JvmStatic
    fun getDescription(error: IntArray): Array<Any?>? {
        Log.d(TAG, "[getDescription] error: $error")
        var result: Array<Any?>? = null
        error[0] = guarded("getDescription") {
            val info = manager().getDescription() ?: return@guarded
            result = arrayOf(
                Utf8.encodeOrNull(info.label),
                info.mimeTypes.map(Utf8::encode).toTypedArray(),
                intArrayOf(if (info.isStyledText) 1 else 0, info.classificationStatus ?: -1)
            )
        }
        return result
    }

    // --- observing and events (OP-09 to OP-11) ---

    /** Posts starting to observe. Returns whether it was posted; a failure on main is only logged (part 2, 6.1). */
    @JvmStatic
    fun startObserving(): Boolean {
        Log.d(TAG, "[startObserving]")
        return MainPoster.post {
            try {
                manager().startObserving()
            } catch (e: Exception) {
                Log.e(TAG, "[startObserving] observing did not start: ${e.javaClass.name}", e)
            }
        }
    }

    @JvmStatic
    fun stopObserving(): Boolean {
        Log.d(TAG, "[stopObserving]")
        return MainPoster.post {
            try {
                manager().stopObserving()
            } catch (e: Exception) {
                Log.e(TAG, "[stopObserving] failed: ${e.javaClass.name}", e)
            }
        }
    }

    /** Accepts a change listener: inserts it on the main thread (design part 1, 5.7). */
    @JvmStatic
    fun addListener(id: Long): Boolean {
        Log.d(TAG, "[addListener] id: $id")
        return MainPoster.post {
            if (Ledger.insertIfActive(id, KIND_CHANGE)) ensureHubListener()
        }
    }

    // One EventHub listener for every C registration, added with the first and never removed
    // (part 2, AP-21). Clipboard changes are not retained, so a change with no registration is lost.
    private fun ensureHubListener() {
        Log.d(TAG, "[ensureHubListener]")
        if (hubListener != null) return
        hubListener = manager().changes.addListener { _, _ ->
            for (id in Ledger.idsOf(KIND_CHANGE)) nativeChanged(id)
        }
    }

    /** Delivers a change to one C registration. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeChanged(id: Long)
}
