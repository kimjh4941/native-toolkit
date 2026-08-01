package android.library.clipboard.domain.model

/**
 * Clipboard metadata, obtained without touching the clip body.
 *
 * @property label Clip label, if present.
 * @property mimeTypes MIME types available on the clip.
 * @property isStyledText Whether the clip is styled text (API 31+).
 * @property classificationStatus Raw ClipDescription.CLASSIFICATION_* value (API 31+). Null if unavailable.
 */
data class ClipDescriptionInfo(
    val label: String?,
    val mimeTypes: List<String>,
    val isStyledText: Boolean,
    val classificationStatus: Int?
)
