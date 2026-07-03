package android.library.share.domain.model

/**
 * Text or URL content for sharing. Used exclusively for text/URL share operations.
 *
 * @property text The text or URL to share. Must not be blank.
 * @property title Optional chooser dialog title shown to the user.
 * @property subject Optional email subject line.
 * @property mimeType MIME type of the content. Defaults to "text/plain".
 */
data class ShareContent(
    val text: String,
    val title: String? = null,
    val subject: String? = null,
    val mimeType: String = "text/plain"
)
