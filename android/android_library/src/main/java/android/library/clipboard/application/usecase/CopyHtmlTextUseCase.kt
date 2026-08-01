package android.library.clipboard.application.usecase

import android.library.clipboard.application.port.ClipboardRepository
import android.library.clipboard.domain.error.ClipboardDomainError
import android.library.clipboard.domain.model.ClipContent
import android.util.Log

/**
 * Use case for copying HTML text to the clipboard.
 *
 * @param repository Clipboard repository.
 */
class CopyHtmlTextUseCase(private val repository: ClipboardRepository) {
    /**
     * Validates and copies [content] to the clipboard.
     *
     * @param content HTML text content to copy.
     */
    operator fun invoke(content: ClipContent.HtmlText) {
        Log.d(
            TAG,
            "[invoke] plainTextLength: ${content.plainText.length}, htmlTextLength: ${content.htmlText.length}, " +
                "label: ${content.label}, isSensitive: ${content.isSensitive}"
        )
        if (content.htmlText.isBlank()) throw ClipboardDomainError.EmptyContent
        repository.copy(content)
    }

    companion object { private const val TAG = "android.library.clipboard.application.usecase.CopyHtmlTextUseCase" }
}
