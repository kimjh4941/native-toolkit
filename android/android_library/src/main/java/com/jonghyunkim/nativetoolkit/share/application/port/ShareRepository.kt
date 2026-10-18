package com.jonghyunkim.nativetoolkit.share.application.port

import com.jonghyunkim.nativetoolkit.share.domain.model.DirectShareTarget
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareChooserAction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions

/**
 * Port for share operations.
 */
interface ShareRepository {
    /**
     * Shares text or URL content via the Android Sharesheet.
     *
     * @param content Text content to share.
     */
    fun shareText(content: ShareContent)

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
     * [onResult] is called when the user selects an app from the Sharesheet, with the selected
     * package name, or null if the package name could not be retrieved. Cancel, Copy, and Edit
     * actions do not trigger [onResult].
     *
     * @param content Text content to share.
     * @param onResult Called with the selected package name, or null if unavailable.
     */
    fun shareWithCallback(content: ShareContent, onResult: (String?) -> Unit)

    /**
     * Opens the Sharesheet for text and returns a token. The picked app arrives later as a
     * selection event with this token; closing the Sharesheet or a non-selection result (Copy,
     * Edit) sends nothing. Opening another one replaces the wait, so a pick in an older
     * Sharesheet is not reported.
     *
     * The default implementation throws, so that implementations written before this function
     * keep compiling.
     *
     * @param content Text content to share.
     * @param preview Rich-preview options.
     * @return The token of this Sharesheet.
     */
    fun shareForSelection(content: ShareContent, preview: SharePreviewOptions): Long =
        throw UnsupportedOperationException()

    /**
     * Stops waiting for the Sharesheet of [token]. Does nothing when another Sharesheet was
     * opened since.
     *
     * @param token A value returned by [shareForSelection].
     */
    fun cancelShareSelection(token: Long): Unit = throw UnsupportedOperationException()

    /**
     * Shares text with custom Sharesheet actions (API 34 and later). The actions of an earlier
     * share stop working.
     *
     * @param content Text content to share.
     * @param actions The actions. Empty is allowed.
     * @param preview Rich-preview options.
     */
    fun shareTextWithActions(content: ShareContent, actions: List<ShareChooserAction>, preview: SharePreviewOptions): Unit =
        throw UnsupportedOperationException()
}
