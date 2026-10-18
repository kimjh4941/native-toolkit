package com.jonghyunkim.nativetoolkit.share.domain.model

/**
 * A custom action shown in the Sharesheet (API 34 and later; ignored on older versions).
 *
 * Taps arrive as the action's [id] through `AndroidShareManager.chooserActions`.
 *
 * @property id Identifies the action in the tap event. Must not be empty and must be unique
 *   within one share.
 * @property label The text shown under the icon.
 * @property iconBytes The icon in a format `BitmapFactory` can decode (PNG, JPEG, WebP).
 */
class ShareChooserAction(val id: String, val label: String, val iconBytes: ByteArray) {

    override fun equals(other: Any?): Boolean =
        other is ShareChooserAction && id == other.id && label == other.label && iconBytes.contentEquals(other.iconBytes)

    override fun hashCode(): Int = (id.hashCode() * 31 + label.hashCode()) * 31 + iconBytes.contentHashCode()

    override fun toString(): String = "ShareChooserAction(id=$id, label=$label, iconBytes=${iconBytes.size} bytes)"
}
