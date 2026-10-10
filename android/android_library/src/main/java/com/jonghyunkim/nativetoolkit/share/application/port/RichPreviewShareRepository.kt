package com.jonghyunkim.nativetoolkit.share.application.port

import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions

/**
 * Optional repository capability for rich-preview sharing and callback cancellation.
 *
 * Kept separate from [ShareRepository] so existing repository implementations remain binary
 * compatible when the capability is added.
 */
interface RichPreviewShareRepository : ShareRepository {
    /**
     * Shares text or URL content with rich-preview options.
     *
     * @param content Text content to share.
     * @param preview Rich-preview options.
     */
    fun shareText(
        content: ShareContent,
        preview: SharePreviewOptions
    )

    /**
     * Shares text and reports the selected app package name.
     *
     * @param content Text content to share.
     * @param preview Rich-preview options.
     * @param onResult Called with the selected package name, or null if unavailable.
     * @param onFinished Called after any chooser callback, including Copy, Edit, or Unknown.
     */
    fun shareWithCallback(
        content: ShareContent,
        preview: SharePreviewOptions,
        onResult: (String?) -> Unit,
        onFinished: () -> Unit
    )

    /** Cancels the pending share-callback BroadcastReceiver, if any. */
    fun cancelPendingCallback()
}
