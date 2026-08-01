package android.library.clipboard.application.usecase

import android.library.clipboard.application.port.ClipboardRepository
import android.library.clipboard.domain.error.ClipboardDomainError
import android.library.clipboard.domain.model.ClipReadResult
import android.util.Log

/**
 * Use case for reading the current clipboard content.
 *
 * @param repository Clipboard repository.
 */
class ReadClipboardUseCase(private val repository: ClipboardRepository) {
    /**
     * Reads the clipboard content.
     *
     * An empty clipboard is a normal case and yields null; it is not an error.
     * [ClipboardDomainError.ReadNotAllowed] is thrown only when the system explicitly denies the
     * read (SecurityException).
     *
     * @return The clip content, or null if the clipboard is empty.
     */
    operator fun invoke(): ClipReadResult? {
        Log.d(TAG, "[invoke]")
        return repository.read()
    }

    companion object { private const val TAG = "android.library.clipboard.application.usecase.ReadClipboardUseCase" }
}
