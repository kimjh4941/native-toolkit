package com.jonghyunkim.nativetoolkit.clipboard.application.usecase

import com.jonghyunkim.nativetoolkit.clipboard.application.port.ClipboardRepository
import com.jonghyunkim.nativetoolkit.clipboard.domain.error.ClipboardDomainError
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent
import android.util.Log

/**
 * Use case for copying multiple plain-text items (same form) to the clipboard.
 *
 * @param repository Clipboard repository.
 */
class CopyMultipleTextUseCase(private val repository: ClipboardRepository) {
    /**
     * Validates and copies [content] to the clipboard.
     *
     * @param content Multiple text items to copy. Must not be empty.
     */
    operator fun invoke(content: ClipContent.MultipleText) {
        Log.d(TAG, "[invoke] itemCount: ${content.texts.size}, label: ${content.label}, isSensitive: ${content.isSensitive}")
        if (content.texts.isEmpty()) throw ClipboardDomainError.EmptyItemList
        repository.copy(content)
    }

    companion object { private const val TAG = "com.jonghyunkim.nativetoolkit.clipboard.application.usecase.CopyMultipleTextUseCase" }
}
