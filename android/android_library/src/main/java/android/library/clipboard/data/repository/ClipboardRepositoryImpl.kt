package android.library.clipboard.data.repository

import android.content.ClipboardManager
import android.content.Context
import android.library.clipboard.application.port.ClipboardRepository
import android.library.clipboard.domain.error.ClipboardDomainError
import android.library.clipboard.domain.model.ClipContent
import android.library.clipboard.domain.model.ClipDescriptionInfo
import android.library.clipboard.domain.model.ClipReadResult
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * [ClipboardRepository] implementation backed by the system [ClipboardManager].
 *
 * @param context Context used to access the system clipboard service.
 */
class ClipboardRepositoryImpl(private val context: Context) : ClipboardRepository {

    private val clipboardManager: ClipboardManager
        get() = ContextCompat.getSystemService(context, ClipboardManager::class.java)
            ?: throw ClipboardDomainError.ClipboardUnavailable

    override fun copy(content: ClipContent) {
        Log.d(TAG, "[copy] ${content.logSafeDescription()}")
        val clipData = content.toClipData(context.contentResolver)
        clipboardManager.setPrimaryClip(clipData)
    }

    override fun read(): ClipReadResult? {
        Log.d(TAG, "[read]")
        val clipData = try {
            clipboardManager.primaryClip
        } catch (exception: SecurityException) {
            Log.e(TAG, "[read] read denied by the system", exception)
            throw ClipboardDomainError.ReadNotAllowed
        }
        return clipData?.toReadResult()
    }

    override fun hasClip(): Boolean {
        Log.d(TAG, "[hasClip]")
        return clipboardManager.hasPrimaryClip()
    }

    override fun getDescription(): ClipDescriptionInfo? {
        Log.d(TAG, "[getDescription]")
        return clipboardManager.primaryClipDescription?.toDescriptionInfo()
    }

    override fun clear() {
        Log.d(TAG, "[clear]")
        clipboardManager.clearPrimaryClip()
    }

    companion object { private const val TAG = "android.library.clipboard.data.repository.ClipboardRepositoryImpl" }
}

/**
 * Builds a log-safe summary of [this] (type, sizes/scheme, label, isSensitive) without exposing
 * the clip body — clipboard content may hold passwords, tokens, or other sensitive data.
 */
private fun ClipContent.logSafeDescription(): String = when (this) {
    is ClipContent.PlainText ->
        "contentType: PlainText, textLength: ${text.length}, label: $label, isSensitive: $isSensitive"
    is ClipContent.HtmlText ->
        "contentType: HtmlText, plainTextLength: ${plainText.length}, htmlTextLength: ${htmlText.length}, " +
            "label: $label, isSensitive: $isSensitive"
    is ClipContent.UriContent ->
        "contentType: UriContent, uriScheme: ${uri.substringBefore("://", missingDelimiterValue = "")}, " +
            "label: $label, isSensitive: $isSensitive"
    is ClipContent.MultipleText ->
        "contentType: MultipleText, itemCount: ${texts.size}, label: $label, isSensitive: $isSensitive"
}
