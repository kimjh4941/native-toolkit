package android.library.clipboard.application.port

import android.library.clipboard.domain.model.ClipContent
import android.library.clipboard.domain.model.ClipDescriptionInfo
import android.library.clipboard.domain.model.ClipReadResult

/**
 * Port for clipboard operations.
 *
 * Note: Clipboard change observation (OnPrimaryClipChangedListener) is intentionally not part of
 * this Port. The system listener is owned by the Manager layer (ClipboardChangeMonitor); this Port
 * only covers synchronous read/write/metadata/clear operations.
 */
interface ClipboardRepository {
    /**
     * Writes [content] to the clipboard.
     *
     * @param content Content to copy (PlainText/HtmlText/UriContent/MultipleText).
     */
    fun copy(content: ClipContent)

    /**
     * Reads the current clipboard content.
     *
     * @return The clip content, or null if the clipboard is empty.
     */
    fun read(): ClipReadResult?

    /**
     * Returns whether the clipboard currently holds data.
     */
    fun hasClip(): Boolean

    /**
     * Reads clipboard metadata without touching the clip body.
     *
     * @return Metadata, or null if the clipboard is empty.
     */
    fun getDescription(): ClipDescriptionInfo?

    /**
     * Clears the clipboard.
     */
    fun clear()
}
