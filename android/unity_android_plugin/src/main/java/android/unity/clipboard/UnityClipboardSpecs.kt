package android.unity.clipboard

/**
 * DTO for plain-text copy passed from Unity.
 *
 * @property text Text to copy. Blank text is allowed.
 * @property label Optional clip label.
 * @property isSensitive Sensitive-content display hint (Android 13+).
 */
internal data class UnityCopyPlainTextSpec(
    val text: String,
    val label: String = "",
    val isSensitive: Boolean = false
)

/**
 * DTO for HTML-text copy passed from Unity.
 *
 * @property plainText Plain-text fallback.
 * @property htmlText HTML representation. Must not be blank.
 * @property label Optional clip label.
 * @property isSensitive Sensitive-content display hint (Android 13+).
 */
internal data class UnityCopyHtmlTextSpec(
    val plainText: String,
    val htmlText: String,
    val label: String = "",
    val isSensitive: Boolean = false
)

/**
 * DTO for URI copy passed from Unity.
 *
 * @property uri URI string (content:// scheme, including image/file references).
 * @property label Optional clip label.
 * @property isSensitive Sensitive-content display hint (Android 13+).
 */
internal data class UnityCopyUriSpec(
    val uri: String,
    val label: String = "",
    val isSensitive: Boolean = false
)

/**
 * DTO for multiple plain-text copy passed from Unity.
 *
 * @property texts Text items of the same form. Must not be empty.
 * @property label Optional clip label.
 * @property isSensitive Sensitive-content display hint (Android 13+).
 */
internal data class UnityCopyMultipleTextSpec(
    val texts: List<String>,
    val label: String = "",
    val isSensitive: Boolean = false
)
