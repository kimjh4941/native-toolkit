package android.library.share.application.usecase

import android.library.share.application.port.ShareRepository
import android.library.share.domain.error.ShareDomainError
import android.util.Log
import java.io.File

/**
 * Use case for sharing a single file via the Sharesheet.
 *
 * @param repository Share repository.
 */
class ShareFileUseCase(private val repository: ShareRepository) {
    /**
     * Validates and executes the share file operation.
     *
     * @param filePath Absolute path to the file. The file must exist.
     */
    operator fun invoke(filePath: String) {
        Log.d(TAG, "[invoke] filePath: $filePath")
        if (!File(filePath).exists()) throw ShareDomainError.FileNotFound(filePath)
        repository.shareFile(filePath)
    }
    companion object { private const val TAG = "ShareFileUseCase" }
}
