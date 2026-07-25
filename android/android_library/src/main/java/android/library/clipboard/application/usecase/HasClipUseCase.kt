package android.library.clipboard.application.usecase

import android.library.clipboard.application.port.ClipboardRepository
import android.util.Log

/**
 * Use case for checking whether the clipboard currently holds data.
 *
 * @param repository Clipboard repository.
 */
class HasClipUseCase(private val repository: ClipboardRepository) {
    /**
     * Returns whether the clipboard currently holds data.
     */
    operator fun invoke(): Boolean {
        Log.d(TAG, "[invoke]")
        return repository.hasClip()
    }

    companion object { private const val TAG = "android.library.clipboard.application.usecase.HasClipUseCase" }
}
