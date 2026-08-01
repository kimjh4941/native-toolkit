package android.library.clipboard.application.usecase

import android.library.clipboard.application.port.ClipboardRepository
import android.library.clipboard.domain.model.ClipDescriptionInfo
import android.util.Log

/**
 * Use case for reading clipboard metadata without touching the clip body.
 *
 * @param repository Clipboard repository.
 */
class GetClipDescriptionUseCase(private val repository: ClipboardRepository) {
    /**
     * Reads clipboard metadata.
     *
     * @return Metadata, or null if the clipboard is empty.
     */
    operator fun invoke(): ClipDescriptionInfo? {
        Log.d(TAG, "[invoke]")
        return repository.getDescription()
    }

    companion object { private const val TAG = "android.library.clipboard.application.usecase.GetClipDescriptionUseCase" }
}
