package com.jonghyunkim.nativetoolkit.share.application.usecase

import android.util.Log
import com.jonghyunkim.nativetoolkit.share.application.port.ShareRepository
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import com.jonghyunkim.nativetoolkit.share.domain.model.logSafeDescription

/**
 * Use case for opening the Sharesheet and receiving the picked app as a selection event.
 *
 * @param repository Share repository.
 */
class ShareForSelectionUseCase(private val repository: ShareRepository) {
    /**
     * Validates and opens the Sharesheet.
     *
     * @param content Text content to share. text must not be blank.
     * @param preview Rich-preview options.
     * @return The token that the selection event carries.
     * @throws ShareDomainError When the content is blank or no app can share it.
     */
    operator fun invoke(content: ShareContent, preview: SharePreviewOptions = SharePreviewOptions()): Long {
        Log.d(TAG, "[invoke] content: ${content.logSafeDescription()}, preview: $preview")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        return repository.shareForSelection(content, preview)
    }

    private companion object {
        private const val TAG = "ShareForSelectionUseCase"
    }
}
