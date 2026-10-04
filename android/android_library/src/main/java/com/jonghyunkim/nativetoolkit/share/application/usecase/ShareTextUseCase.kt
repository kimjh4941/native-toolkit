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
     * @param chooserActionsJson JSON array of custom chooser actions for API 34+. Defaults to empty.
     */
    operator fun invoke(content: ShareContent, chooserActionsJson: String = "[]") {
        Log.d(TAG, "[invoke] content: ${content.logSafeDescription()}, chooserActionsJson: $chooserActionsJson")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        if (content.mimeType.isBlank()) throw ShareDomainError.InvalidMimeType(content.mimeType)
        repository.shareText(content, chooserActionsJson)
    }

    /**
     * Validates and executes text sharing with rich-preview options.
     *
     * Repositories that do not implement [RichPreviewShareRepository] still share the body without
     * a rich preview, preserving compatibility with existing repository implementations.
     *
     * @param content Text content to share.
     * @param chooserActionsJson JSON array of custom chooser actions for API 34+.
     * @param preview Rich-preview options.
     */
    operator fun invoke(
        content: ShareContent,
        chooserActionsJson: String,
        preview: SharePreviewOptions
    ) {
        Log.d(TAG, "[invoke] content: ${content.logSafeDescription()}, chooserActionsJson: $chooserActionsJson, preview: $preview")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        if (content.mimeType.isBlank()) throw ShareDomainError.InvalidMimeType(content.mimeType)
        val richPreviewRepository = repository as? RichPreviewShareRepository
        if (richPreviewRepository != null) {
            richPreviewRepository.shareText(content, chooserActionsJson, preview)
        } else {
            repository.shareText(content, chooserActionsJson)
        }
    }
    companion object { private const val TAG = "ShareTextUseCase" }
}
