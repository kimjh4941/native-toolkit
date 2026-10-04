package com.jonghyunkim.nativetoolkit.clipboard

import android.content.Context
import android.util.Log
import androidx.annotation.MainThread
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.ClipboardUseCases
import com.jonghyunkim.nativetoolkit.clipboard.domain.error.ClipboardErrorCode
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipDescriptionInfo
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipReadResult
import com.jonghyunkim.nativetoolkit.clipboard.presentation.ClipboardEvents
import com.jonghyunkim.nativetoolkit.clipboard.presentation.ClipboardObserver
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.common.logging.LogRedaction
import com.jonghyunkim.nativetoolkit.clipboard.data.repository.ClipboardUseCases as createClipboardUseCases

/**
 * The entry point for the clipboard (Kotlin API design 6.3, 8.10).
 *
 * The existing operations take the same arguments and give the same results and exceptions as
 * [ClipboardUseCases]. Observation is one per process and shared by every listener of [changes].
 * This class only delegates; it keeps the Application Context only.
 *
 * @param appContext The Application Context.
 * @param useCases The existing clipboard use cases.
 */
class AndroidClipboardManager internal constructor(
    private val appContext: Context,
    private val useCases: ClipboardUseCases
) {

    /** Clipboard changes while observing. Main thread. */
    val changes: EventHub<Unit> get() = ClipboardEvents.changes

    /**
     * Copies plain text.
     *
     * @param content The text.
     */
    fun copyPlainText(content: ClipContent.PlainText) {
        Log.d(TAG, "[copyPlainText] textLength: ${content.text.length}, label: ${content.label}")
        useCases.copyPlainText(content)
    }

    /**
     * Copies HTML text.
     *
     * @param content The HTML and its plain text.
     */
    fun copyHtmlText(content: ClipContent.HtmlText) {
        Log.d(TAG, "[copyHtmlText] htmlLength: ${content.htmlText.length}, plainTextLength: ${content.plainText.length}, label: ${content.label}")
        useCases.copyHtmlText(content)
    }

    /**
     * Copies a URI.
     *
     * @param content The URI.
     */
    fun copyUri(content: ClipContent.UriContent) {
        Log.d(TAG, "[copyUri] content: ${LogRedaction.redact(content.uri)}, label: ${content.label}")
        useCases.copyUri(content)
    }

    /**
     * Copies several texts as one clip.
     *
     * @param content The texts.
     */
    fun copyMultipleText(content: ClipContent.MultipleText) {
        Log.d(TAG, "[copyMultipleText] itemCount: ${content.texts.size}, label: ${content.label}")
        useCases.copyMultipleText(content)
    }

    /** Clears the clipboard. */
    fun clear() {
        Log.d(TAG, "[clear]")
        useCases.clear()
    }

    /** Reads the clipboard, or `null` when it is empty or not readable without an error. */
    fun read(): ClipReadResult? {
        Log.d(TAG, "[read]")
        return useCases.read()
    }

    /** Returns whether the clipboard has a clip. */
    fun hasClip(): Boolean {
        Log.d(TAG, "[hasClip]")
        return useCases.hasClip()
    }

    /** Returns the description of the clip, or `null`. */
    fun getDescription(): ClipDescriptionInfo? {
        Log.d(TAG, "[getDescription]")
        return useCases.getDescription()
    }

    /**
     * Starts observing clipboard changes. Does nothing when already observing.
     *
     * @throws IllegalStateException When not called on the main thread.
     */
    @MainThread
    fun startObserving() {
        Log.d(TAG, "[startObserving]")
        ClipboardObserver.start(appContext)
    }

    /**
     * Stops observing. Does nothing when not observing.
     *
     * @throws IllegalStateException When not called on the main thread.
     */
    @MainThread
    fun stopObserving() {
        Log.d(TAG, "[stopObserving]")
        ClipboardObserver.stop()
    }

    /**
     * Returns whether clipboard changes are observed.
     *
     * @throws IllegalStateException When not called on the main thread.
     */
    @MainThread
    fun isObserving(): Boolean {
        Log.d(TAG, "[isObserving]")
        return ClipboardObserver.isObserving()
    }

    /**
     * Classifies a failure of a clipboard operation.
     *
     * @param error The failure.
     */
    fun errorCodeOf(error: Throwable): ClipboardErrorCode {
        Log.d(TAG, "[errorCodeOf] error: ${error.javaClass.name}")
        return ClipboardErrorCode.of(error)
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.clipboard.AndroidClipboardManager"

        @Volatile
        private var instance: AndroidClipboardManager? = null

        /**
         * Returns the process-wide instance.
         *
         * @param context Any Context; only its Application Context is kept.
         */
        @JvmStatic
        fun getInstance(context: Context): AndroidClipboardManager {
            Log.d(TAG, "[getInstance] context: $context")
            return instance ?: synchronized(this) {
                instance ?: create(context.applicationContext).also { instance = it }
            }
        }

        private fun create(appContext: Context): AndroidClipboardManager {
            Log.d(TAG, "[create] appContext: $appContext")
            return AndroidClipboardManager(appContext, createClipboardUseCases(appContext))
        }
    }
}
