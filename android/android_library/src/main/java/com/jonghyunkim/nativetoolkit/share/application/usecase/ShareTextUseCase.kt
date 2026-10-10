package com.jonghyunkim.nativetoolkit.share.application.usecase

import com.jonghyunkim.nativetoolkit.share.application.port.ShareRepository
import com.jonghyunkim.nativetoolkit.share.application.port.RichPreviewShareRepository
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.logSafeDescription
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import android.util.Log

/**
 * Use case for sharing text or URL content via the Sharesheet.
 *
 * @param repository Share repository.
 */
class ShareTextUseCase(private val repository: ShareRepository) {
    /**
     * Validates and executes the share text operation.
     *
     * @param content Text content to share.
     */
    operator fun invoke(content: ShareContent) {
        Log.d(TAG, "[invoke] content: ${content.logSafeDescription()}")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        if (content.mimeType.isBlank()) throw ShareDomainError.InvalidMimeType(content.mimeType)
        repository.shareText(content)
    }

    /**
     * Validates and executes text sharing with rich-preview options.
     *
     * Repositories that do not implement [RichPreviewShareRepository] still share the body without
     * a rich preview, preserving compatibility with existing repository implementations. Custom
     * chooser actions are shared with [ShareTextWithActionsUseCase].
     *
     * @param content Text content to share.
     * @param preview Rich-preview options.
     */
    operator fun invoke(content: ShareContent, preview: SharePreviewOptions) {
        Log.d(TAG, "[invoke] content: ${content.logSafeDescription()}, preview: $preview")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        if (content.mimeType.isBlank()) throw ShareDomainError.InvalidMimeType(content.mimeType)
        val richPreviewRepository = repository as? RichPreviewShareRepository
        if (richPreviewRepository != null) {
            richPreviewRepository.shareText(content, preview)
        } else {
            repository.shareText(content)
        }
    }
    companion object { private const val TAG = "ShareTextUseCase" }
}
