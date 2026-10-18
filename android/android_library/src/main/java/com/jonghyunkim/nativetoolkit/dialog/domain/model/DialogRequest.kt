package com.jonghyunkim.nativetoolkit.dialog.domain.model

/**
 * Options shared by every dialog.
 *
 * @property cancelable Whether the back key closes the dialog.
 * @property cancelableOnTouchOutside Whether a tap outside closes the dialog.
 */
data class DialogOptions(
    val cancelable: Boolean = true,
    val cancelableOnTouchOutside: Boolean = true
)

/**
 * The button the user pressed.
 */
enum class DialogButton { POSITIVE, NEGATIVE }

/**
 * A dialog to show. The defaults match the Unity bridge's defaults.
 */
sealed interface DialogRequest {
    /** The dialog title. */
    val title: String

    /** Options shared by every dialog. */
    val options: DialogOptions

    /**
     * A message with one button.
     *
     * @property message The message.
     * @property buttonText The button label.
     */
    data class Alert(
        override val title: String,
        val message: String,
        val buttonText: String = "OK",
        override val options: DialogOptions = DialogOptions()
    ) : DialogRequest

    /**
     * A message with negative and positive buttons.
     *
     * @property message The message.
     * @property negativeText The negative button label.
     * @property positiveText The positive button label.
     */
    data class Confirm(
        override val title: String,
        val message: String,
        val negativeText: String = "No",
        val positiveText: String = "Yes",
        override val options: DialogOptions = DialogOptions()
    ) : DialogRequest

    /**
     * A list with one selectable item.
     *
     * @property items The items. Must not be empty.
     * @property checkedIndex The initially selected item, or `null` for none.
     * @property negativeText The negative button label.
     * @property positiveText The positive button label.
     */
    data class SingleChoice(
        override val title: String,
        val items: List<String>,
        val checkedIndex: Int? = 0,
        val negativeText: String = "Cancel",
        val positiveText: String = "OK",
        override val options: DialogOptions = DialogOptions()
    ) : DialogRequest

    /**
     * A list with any number of selectable items.
     *
     * @property items The items. Must not be empty.
     * @property checked The initial selection, one value per item.
     * @property negativeText The negative button label.
     * @property positiveText The positive button label.
     */
    data class MultiChoice(
        override val title: String,
        val items: List<String>,
        val checked: List<Boolean>,
        val negativeText: String = "Cancel",
        val positiveText: String = "OK",
        override val options: DialogOptions = DialogOptions()
    ) : DialogRequest

    /**
     * A message with one text field.
     *
     * @property message The message.
     * @property hint The field hint.
     * @property negativeText The negative button label.
     * @property positiveText The positive button label.
     * @property enablePositiveWhenEmpty Whether the positive button works while the field is empty.
     */
    data class TextInput(
        override val title: String,
        val message: String,
        val hint: String = "",
        val negativeText: String = "Cancel",
        val positiveText: String = "OK",
        val enablePositiveWhenEmpty: Boolean = false,
        override val options: DialogOptions = DialogOptions()
    ) : DialogRequest

    /**
     * A message with username and password fields.
     *
     * @property message The message.
     * @property usernameHint The username field hint.
     * @property passwordHint The password field hint.
     * @property negativeText The negative button label.
     * @property positiveText The positive button label.
     * @property enablePositiveWhenEmpty Whether the positive button works while a field is empty.
     */
    data class Login(
        override val title: String,
        val message: String,
        val usernameHint: String = "Username",
        val passwordHint: String = "Password",
        val negativeText: String = "Cancel",
        val positiveText: String = "Login",
        val enablePositiveWhenEmpty: Boolean = false,
        override val options: DialogOptions = DialogOptions()
    ) : DialogRequest
}
