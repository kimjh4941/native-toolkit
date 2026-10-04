package com.jonghyunkim.nativetoolkit.clipboard.application.usecase

import com.jonghyunkim.nativetoolkit.clipboard.application.port.ClipboardRepository
import com.jonghyunkim.nativetoolkit.clipboard.domain.error.ClipboardDomainError
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent
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

    companion object { private const val TAG = "com.jonghyunkim.nativetoolkit.clipboard.application.usecase.CopyHtmlTextUseCase" }
}
