package android.library.share.application.usecase

import android.library.share.application.port.ShareRepository
import android.library.share.domain.model.DirectShareTarget
import android.util.Log

/**
 * Use case for registering a Direct Share shortcut target.
 *
 * @param repository Share repository.
 */
class RegisterDirectShareTargetUseCase(private val repository: ShareRepository) {
    /**
     * Registers a Direct Share target with the given icon bytes.
     *
     * @param target Target metadata including id, label, and category.
     * @param iconBytes Raw bytes of the icon image (PNG or JPEG).
     */
    operator fun invoke(target: DirectShareTarget, iconBytes: ByteArray) {
        Log.d(TAG, "[invoke] target: $target, iconBytes.size: ${iconBytes.size}")
        repository.registerDirectShareTarget(target, iconBytes)
    }
    companion object { private const val TAG = "RegisterDirectShareTargetUseCase" }
}
