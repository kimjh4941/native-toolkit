package com.jonghyunkim.nativetoolkit.share.application.usecase

import com.jonghyunkim.nativetoolkit.share.application.port.ShareRepository
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import android.util.Log

/**
 * Use case for removing Direct Share shortcut targets by ID.
 *
 * @param repository Share repository.
 */
class RemoveDirectShareTargetsUseCase(private val repository: ShareRepository) {
    /**
     * Removes Direct Share targets for the given shortcut IDs.
     *
     * @param ids List of shortcut IDs to remove. Must not be empty.
     */
    operator fun invoke(ids: List<String>) {
        Log.d(TAG, "[invoke] ids: $ids")
        if (ids.isEmpty()) throw ShareDomainError.EmptyIdList
        repository.removeDirectShareTargets(ids)
    }
    companion object { private const val TAG = "RemoveDirectShareTargetsUseCase" }
}
