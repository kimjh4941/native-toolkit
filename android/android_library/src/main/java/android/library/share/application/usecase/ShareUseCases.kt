package android.library.share.application.usecase

import android.library.share.application.port.ShareRepository

/**
 * Use-case suite for share operations.
 *
 * Exposes all share use cases as properties for convenient access.
 *
 * @param repository [ShareRepository] used to execute share operations.
 */
class ShareUseCases(repository: ShareRepository) {
    val shareText = ShareTextUseCase(repository)
    val shareImage = ShareImageUseCase(repository)
    val shareImages = ShareMultipleImagesUseCase(repository)
    val shareFile = ShareFileUseCase(repository)
    val shareFiles = ShareMultipleFilesUseCase(repository)
    val registerDirectShareTarget = RegisterDirectShareTargetUseCase(repository)
    val removeDirectShareTargets = RemoveDirectShareTargetsUseCase(repository)
    val shareWithCallback = ShareWithCallbackUseCase(repository)
    val cancelPendingCallback = CancelPendingShareCallbackUseCase(repository)
}
