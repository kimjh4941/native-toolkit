package android.library.share.domain.model

/**
 * A Direct Share shortcut target for the Android Sharesheet.
 *
 * @property id Unique shortcut ID used for registration and removal.
 * @property label Display label shown in the Sharesheet.
 * @property category Shortcut category. Defaults to "android.shortcut.conversation".
 */
data class DirectShareTarget(
    val id: String,
    val label: String,
    val category: String = "android.shortcut.conversation"
)
