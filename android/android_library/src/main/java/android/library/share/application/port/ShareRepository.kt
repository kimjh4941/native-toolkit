package android.library.share.application.port

import android.library.share.domain.model.DirectShareTarget
import android.library.share.domain.model.ShareContent

/**
 * Port for share operations.
 *
 * Note: [shareText] accepts [chooserActionsJson] as a plain String to pass API 34+ ChooserAction
 * data through the UseCase chain without introducing a UI presentation type into the Domain layer.
 */
interface ShareRepository {
    /**
     * Shares text or URL content via the Android Sharesheet.
     *
     * @param content Text content to share.
     * @param chooserActionsJson JSON array of custom chooser action objects. Ignored on API < 34.
     *   Each element: { "label": "...", "iconBase64": "...", "intentAction": "..." }
     */
    fun shareText(content: ShareContent, chooserActionsJson: String = "[]")

    /**
     * Shares a single image via the Sharesheet using FileProvider.
     *
     * @param filePath Absolute path to the image file.
     * @param mimeType MIME type of the image.
     */
    fun shareImage(filePath: String, mimeType: String)

    /**
     * Shares multiple images via the Sharesheet using FileProvider.
     *
     * @param filePaths List of absolute paths to image files.
     */
    fun shareImages(filePaths: List<String>)

    /**
     * Shares a single file via the Sharesheet using FileProvider.
     *
     * @param filePath Absolute path to the file.
     */
    fun shareFile(filePath: String)

    /**
     * Shares multiple files via the Sharesheet using FileProvider.
     *
     * @param filePaths List of absolute paths to files.
     */
    fun shareFiles(filePaths: List<String>)

    /**
     * Registers a Direct Share shortcut target.
     *
     * @param target Target metadata.
     * @param iconBytes Raw bytes of the PNG/JPEG icon image.
     */
    fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray)

    /**
     * Removes Direct Share shortcut targets by ID.
     *
     * @param ids List of shortcut IDs to remove.
     */
    fun removeDirectShareTargets(ids: List<String>)

    /**
     * Shares text content and reports the selected app package name via callback.
     *
     * onResult is called exactly once after the Sharesheet is dismissed:
     * with the selected package name on success, or null if the user cancelled.
     *
     * @param content Text content to share.
     * @param onResult Called once with the selected package name, or null on cancel.
     */
    fun shareWithCallback(content: ShareContent, onResult: (String?) -> Unit)
}
