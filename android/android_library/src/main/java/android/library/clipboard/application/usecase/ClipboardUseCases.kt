package android.library.clipboard.application.usecase

import android.library.clipboard.application.port.ClipboardRepository

/**
 * Use-case suite for clipboard operations.
 *
 * Exposes all clipboard use cases as properties for convenient access.
 *
 * Note: Clipboard change observation is not part of this suite. It is owned by the Manager layer
 * (ClipboardChangeMonitor) and does not go through a UseCase / Port.
 *
 * @param repository [ClipboardRepository] used to execute clipboard operations.
 */
class ClipboardUseCases(repository: ClipboardRepository) {
    val copyPlainText = CopyPlainTextUseCase(repository)
    val copyHtmlText = CopyHtmlTextUseCase(repository)
    val copyUri = CopyUriUseCase(repository)
    val copyMultipleText = CopyMultipleTextUseCase(repository)
    val read = ReadClipboardUseCase(repository)
    val hasClip = HasClipUseCase(repository)
    val getDescription = GetClipDescriptionUseCase(repository)
    val clear = ClearClipboardUseCase(repository)
}
