package android.library.clipboard.domain.model

/**
 * A single clip item read from the clipboard, in a flat, serializable form.
 *
 * @property text Plain text, if the item holds text.
 * @property htmlText HTML text, if the item holds HTML.
 * @property uri URI string, if the item holds a URI.
 * @property coercedText A best-effort plain-text fallback for this item (falls back to [text],
 *   then the string form of [uri]). Not a call to `ClipData.Item.coerceToText(Context)` — no
 *   `Context` is threaded through the mapper, so content-provider/URI resolution is not performed.
 */
data class ClipItemData(
    val text: String? = null,
    val htmlText: String? = null,
    val uri: String? = null,
    val coercedText: String? = null
)
