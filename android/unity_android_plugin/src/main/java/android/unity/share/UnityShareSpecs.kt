package android.unity.share

/**
 * DTO for custom chooser action button passed from Unity (API 34+ only).
 *
 * @property label Button label shown in the Sharesheet.
 * @property iconBase64 Base64-encoded PNG/JPEG icon.
 * @property intentAction Intent action string. Defaults to "android.intent.action.SEND".
 */
internal data class UnityChooserActionSpec(
    val label: String,
    val iconBase64: String,
    val intentAction: String = "android.intent.action.SEND"
)

/**
 * DTO for text/URL share content passed from Unity.
 *
 * @property text Text or URL to share. Must not be blank.
 * @property title Optional chooser dialog title.
 * @property subject Optional email subject.
 * @property mimeType MIME type. Defaults to "text/plain".
 * @property chooserActions Custom action buttons for API 34+ Sharesheet.
 */
internal data class UnityShareTextSpec(
    val text: String,
    val title: String? = null,
    val subject: String? = null,
    val mimeType: String = "text/plain",
    val chooserActions: List<UnityChooserActionSpec> = emptyList()
)

/**
 * DTO for single image share passed from Unity.
 *
 * @property filePath Absolute path to the image file.
 * @property mimeType MIME type of the image. Defaults to image/&#42;.
 */
internal data class UnityShareImageSpec(
    val filePath: String,
    val mimeType: String = "image/*"
)

/**
 * DTO for file share passed from Unity. Supports single and multiple files.
 *
 * @property filePath Absolute path for single-file share.
 * @property filePaths List of absolute paths for multi-file share.
 * @property mimeType Optional MIME type override. Auto-detected when null.
 */
internal data class UnityShareFileSpec(
    val filePath: String? = null,
    val filePaths: List<String> = emptyList(),
    val mimeType: String? = null
)

/**
 * DTO for Direct Share target registration passed from Unity.
 *
 * @property id Unique shortcut ID.
 * @property label Display label in the Sharesheet.
 * @property iconBase64 Base64-encoded PNG/JPEG icon.
 * @property category Shortcut category. Defaults to "android.shortcut.conversation".
 */
internal data class UnityDirectShareTargetSpec(
    val id: String,
    val label: String,
    val iconBase64: String,
    val category: String = "android.shortcut.conversation"
)

/**
 * DTO for Direct Share target removal passed from Unity.
 *
 * @property ids List of shortcut IDs to remove.
 */
internal data class UnityRemoveDirectShareTargetsSpec(
    val ids: List<String>
)
