package com.jonghyunkim.nativetoolkit.share.application.usecase

import android.util.Log
import com.jonghyunkim.nativetoolkit.share.application.port.ShareRepository
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareChooserAction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import com.jonghyunkim.nativetoolkit.share.domain.model.logSafeDescription

/**
 * Use case for sharing text with custom Sharesheet actions.
 *
 * @param repository Share repository.
 */
class ShareTextWithActionsUseCase(private val repository: ShareRepository) {
    /**
     * Validates and opens the Sharesheet with [actions].
     *
     * @param content Text content to share. text and mimeType must not be blank.
     * @param actions The actions; IDs must be non-empty and unique.
     * @param preview Rich-preview options.
     * @throws ShareDomainError When the content or an action is invalid, or no app can share it.
     */
    operator fun invoke(
        content: ShareContent,
        actions: List<ShareChooserAction>,
        preview: SharePreviewOptions = SharePreviewOptions()
    ) {
        Log.d(TAG, "[invoke] content: ${content.logSafeDescription()}, actions: $actions, preview: $preview")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        if (content.mimeType.isBlank()) throw ShareDomainError.InvalidMimeType(content.mimeType)
        val seen = HashSet<String>()
        actions.forEach { action ->
            if (action.id.isEmpty() || !seen.add(action.id)) throw ShareDomainError.InvalidChooserAction(action.id)
        }
        repository.shareTextWithActions(content, actions, preview)
    }

    private companion object {
        private const val TAG = "ShareTextWithActionsUseCase"
    }
}
