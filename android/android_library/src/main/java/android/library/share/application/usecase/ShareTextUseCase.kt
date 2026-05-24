package android.library.share.application.usecase

import android.library.share.application.port.ShareRepository
import android.library.share.domain.error.ShareDomainError
import android.library.share.domain.model.ShareContent
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
        Log.d(TAG, "[invoke] content: $content, chooserActionsJson: $chooserActionsJson")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        if (content.mimeType.isBlank()) throw ShareDomainError.InvalidMimeType(content.mimeType)
        repository.shareText(content, chooserActionsJson)
    }
    companion object { private const val TAG = "ShareTextUseCase" }
}
