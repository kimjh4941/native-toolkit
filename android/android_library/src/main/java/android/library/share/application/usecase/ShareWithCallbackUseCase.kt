package android.library.share.application.usecase

import android.library.share.application.port.ShareRepository
import android.library.share.domain.error.ShareDomainError
import android.library.share.domain.model.ShareContent
import android.util.Log

/**
 * Use case for sharing text content and receiving the selected app package name via callback.
 *
 * @param repository Share repository.
 */
class ShareWithCallbackUseCase(private val repository: ShareRepository) {
    /**
     * Validates and executes the share with callback operation.
     *
     * @param content Text content to share. text must not be blank.
     * @param onResult Called once after the Sharesheet is dismissed. Receives the selected
     *   package name, or null if the user cancelled.
     */
    operator fun invoke(content: ShareContent, onResult: (String?) -> Unit) {
        Log.d(TAG, "[invoke] content: $content, onResult: $onResult")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        repository.shareWithCallback(content, onResult)
    }
    companion object { private const val TAG = "ShareWithCallbackUseCase" }
}
