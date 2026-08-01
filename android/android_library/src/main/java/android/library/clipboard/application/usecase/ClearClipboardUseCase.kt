package android.library.clipboard.application.usecase

import android.library.clipboard.application.port.ClipboardRepository
import android.util.Log

/**
 * Use case for clearing the clipboard.
 *
 * @param repository Clipboard repository.
 */
class ClearClipboardUseCase(private val repository: ClipboardRepository) {
    /**
     * Clears the clipboard.
     */
    operator fun invoke() {
        Log.d(TAG, "[invoke]")
        repository.clear()
    }

    companion object { private const val TAG = "android.library.clipboard.application.usecase.ClearClipboardUseCase" }
}
