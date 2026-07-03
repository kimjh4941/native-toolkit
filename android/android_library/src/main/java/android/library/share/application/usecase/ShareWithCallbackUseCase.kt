package android.library.share.application.usecase

import android.library.share.application.port.ShareRepository
import android.library.share.application.port.RichPreviewShareRepository
import android.library.share.domain.error.ShareDomainError
import android.library.share.domain.model.ShareContent
import android.library.share.domain.model.SharePreviewOptions
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
     * [onResult] is called when the user selects an app. Cancel, Copy, and Edit do not trigger it.
     *
     * @param content Text content to share. text must not be blank.
     * @param onResult Called with the selected package name, or null if unavailable.
     */
    operator fun invoke(content: ShareContent, onResult: (String?) -> Unit) {
        Log.d(TAG, "[invoke] content: $content, onResult: $onResult")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        repository.shareWithCallback(content, onResult)
    }

    /**
     * Validates and executes callback sharing with rich-preview options.
     *
     * @param content Text content to share. text must not be blank.
     * @param preview Rich-preview options.
     * @param onResult Called with the selected package name, or null if unavailable.
     * @param onFinished Called after any chooser callback is handled.
     */
    operator fun invoke(
        content: ShareContent,
        preview: SharePreviewOptions,
        onResult: (String?) -> Unit,
        onFinished: () -> Unit = {}
    ) {
        Log.d(TAG, "[invoke] content: $content, preview: $preview, onResult: $onResult, onFinished: $onFinished")
        if (content.text.isBlank()) throw ShareDomainError.EmptyContent
        val richPreviewRepository = repository as? RichPreviewShareRepository
        if (richPreviewRepository != null) {
            richPreviewRepository.shareWithCallback(content, preview, onResult, onFinished)
        } else {
            repository.shareWithCallback(content) {
                try {
                    onResult(it)
                } finally {
                    onFinished()
                }
            }
        }
    }
    companion object { private const val TAG = "ShareWithCallbackUseCase" }
}
