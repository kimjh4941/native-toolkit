package android.library.clipboard.domain.model

/**
 * Result of reading the clipboard.
 *
 * @property label Clip label, if present.
 * @property mimeTypes MIME types available on the clip.
 * @property items Clip items, in clipboard order.
 */
data class ClipReadResult(
    val label: String?,
    val mimeTypes: List<String>,
    val items: List<ClipItemData>
)
