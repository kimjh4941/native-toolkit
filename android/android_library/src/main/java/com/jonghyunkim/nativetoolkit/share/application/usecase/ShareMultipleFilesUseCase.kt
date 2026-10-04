package com.jonghyunkim.nativetoolkit.share.application.usecase

import com.jonghyunkim.nativetoolkit.share.application.port.ShareRepository
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import android.util.Log

/**
 * Use case for sharing multiple files via the Sharesheet.
 *
 * @param repository Share repository.
 */
class ShareMultipleFilesUseCase(private val repository: ShareRepository) {
    /**
     * Validates and executes the share multiple files operation.
     *
     * @param filePaths List of absolute paths to files. Must not be empty.
     */
    operator fun invoke(filePaths: List<String>) {
        Log.d(TAG, "[invoke] filePaths: $filePaths")
        if (filePaths.isEmpty()) throw ShareDomainError.EmptyFileList
        repository.shareFiles(filePaths)
    }
    companion object { private const val TAG = "ShareMultipleFilesUseCase" }
}
