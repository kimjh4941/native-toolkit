package android.library.share.application.usecase

import android.library.share.application.port.ShareRepository
import android.library.share.domain.error.ShareDomainError
import android.util.Log

/**
 * Use case for sharing a single image via the Sharesheet.
 *
 * @param repository Share repository.
 */
class ShareImageUseCase(private val repository: ShareRepository) {
    /**
     * Validates and executes the share image operation.
     *
     * @param filePath Absolute path to the image file.
     * @param mimeType MIME type of the image. Must not be blank.
     */
    operator fun invoke(filePath: String, mimeType: String) {
        Log.d(TAG, "[invoke] filePath: $filePath, mimeType: $mimeType")
        if (mimeType.isBlank()) throw ShareDomainError.InvalidMimeType(mimeType)
        repository.shareImage(filePath, mimeType)
    }
    companion object { private const val TAG = "ShareImageUseCase" }
}
