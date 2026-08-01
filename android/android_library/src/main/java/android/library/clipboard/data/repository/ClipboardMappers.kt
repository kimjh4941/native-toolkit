package android.library.clipboard.data.repository

import android.content.ClipData
import android.content.ClipDescription
import android.content.ContentResolver
import android.library.clipboard.domain.model.ClipContent
import android.library.clipboard.domain.model.ClipDescriptionInfo
import android.library.clipboard.domain.model.ClipItemData
import android.library.clipboard.domain.model.ClipReadResult
import android.net.Uri
import android.os.PersistableBundle

/**
 * Converts [content] into a platform [ClipData], applying the sensitive-content flag when set.
 *
 * @param resolver Used to resolve MIME types for URI content.
 */
internal fun ClipContent.toClipData(resolver: ContentResolver): ClipData {
    val clipData = when (this) {
        is ClipContent.PlainText -> ClipData.newPlainText(label, text)
        is ClipContent.HtmlText -> ClipData.newHtmlText(label, plainText, htmlText)
        is ClipContent.UriContent -> ClipData.newUri(resolver, label, Uri.parse(uri))
        is ClipContent.MultipleText -> {
            val data = ClipData.newPlainText(label, texts.first())
            texts.drop(1).forEach { data.addItem(ClipData.Item(it)) }
            data
        }
    }
    if (isSensitive) clipData.applySensitiveFlag()
    return clipData
}

private fun ClipData.applySensitiveFlag() {
    val extras = description.extras ?: PersistableBundle()
    extras.putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
    description.extras = extras
}

/**
 * Converts a platform [ClipData] into a domain [ClipReadResult].
 */
internal fun ClipData.toReadResult(): ClipReadResult {
    val items = (0 until itemCount).map { index ->
        val item = getItemAt(index)
        ClipItemData(
            text = item.text?.toString(),
            htmlText = item.htmlText,
            uri = item.uri?.toString(),
            coercedText = item.text?.toString() ?: item.uri?.toString()
        )
    }
    val mimeTypes = (0 until description.mimeTypeCount).map { description.getMimeType(it) }
    return ClipReadResult(
        label = description.label?.toString(),
        mimeTypes = mimeTypes,
        items = items
    )
}

/**
 * Converts a platform [ClipDescription] into a domain [ClipDescriptionInfo].
 */
internal fun ClipDescription.toDescriptionInfo(): ClipDescriptionInfo {
    val mimeTypes = (0 until mimeTypeCount).map { getMimeType(it) }
    return ClipDescriptionInfo(
        label = label?.toString(),
        mimeTypes = mimeTypes,
        isStyledText = isStyledText,
        classificationStatus = runCatching { classificationStatus }.getOrNull()
    )
}
