package com.jonghyunkim.nativetoolkit.clipboard.application.usecase

import com.jonghyunkim.nativetoolkit.clipboard.application.port.ClipboardRepository
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent
import android.util.Log

/**
 * Use case for copying plain text to the clipboard.
 *
 * @param repository Clipboard repository.
 */
class CopyPlainTextUseCase(private val repository: ClipboardRepository) {
    /**
     * Copies [content] to the clipboard. Blank text is allowed.
     *
     * @param content Plain text content to copy.
     */
    operator fun invoke(content: ClipContent.PlainText) {
        Log.d(TAG, "[invoke] textLength: ${content.text.length}, label: ${content.label}, isSensitive: ${content.isSensitive}")
        repository.copy(content)
    }

    companion object { private const val TAG = "com.jonghyunkim.nativetoolkit.clipboard.application.usecase.CopyPlainTextUseCase" }
}
