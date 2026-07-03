package android.library.share.domain.model

/**
 * Optional rich-preview values for text sharing.
 *
 * @property title Title shown in the Sharesheet rich preview.
 * @property thumbnailPath Absolute file path for the preview thumbnail.
 */
data class SharePreviewOptions(
    val title: String? = null,
    val thumbnailPath: String? = null
)
