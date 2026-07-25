package android.library.clipboard.domain.model

/**
 * Content to write to the clipboard.
 */
sealed class ClipContent {
    /** Display label for the clip. */
    abstract val label: String
    /** Sensitive-content display hint (Android 13+ preview suppression). */
    abstract val isSensitive: Boolean

    /**
     * Plain text content.
     *
     * @property text Text to copy. Blank text is allowed.
     */
    data class PlainText(
        val text: String,
        override val label: String = "",
        override val isSensitive: Boolean = false
    ) : ClipContent()

    /**
     * HTML text content with a plain-text fallback.
     *
     * @property plainText Plain-text representation.
     * @property htmlText HTML representation. Must not be blank.
     */
    data class HtmlText(
        val plainText: String,
        val htmlText: String,
        override val label: String = "",
        override val isSensitive: Boolean = false
    ) : ClipContent()

    /**
     * URI content (content:// scheme), including image and file references.
     *
     * @property uri URI string. Must not be blank and must be parseable.
     */
    data class UriContent(
        val uri: String,
        override val label: String = "",
        override val isSensitive: Boolean = false
    ) : ClipContent()

    /**
     * Multiple plain-text items of the same form.
     *
     * @property texts Text items. Must not be empty.
     */
    data class MultipleText(
        val texts: List<String>,
        override val label: String = "",
        override val isSensitive: Boolean = false
    ) : ClipContent()
}
