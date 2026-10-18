package com.jonghyunkim.nativetoolkit.dialog.domain.model

import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.dialog.domain.error.DialogError

/**
 * The value a dialog returns with a button press.
 */
sealed interface DialogValue {
    /** No value (the negative button, or an Alert or Confirm dialog). */
    data object None : DialogValue

    /**
     * The selected item of a single-choice dialog.
     *
     * @property index The selected index, or `null` when nothing is selected.
     */
    data class SingleChoice(val index: Int?) : DialogValue

    /**
     * The selection of a multi-choice dialog.
     *
     * @property checked One value per item.
     */
    data class MultiChoice(val checked: List<Boolean>) : DialogValue

    /**
     * The text of a text-input dialog. [toString] hides the text.
     *
     * @property text The text.
     */
    class Text(val text: String) : DialogValue {
        override fun equals(other: Any?): Boolean = other is Text && other.text == text
        override fun hashCode(): Int = text.hashCode()
        override fun toString(): String = "Text(length=${text.length})"
    }

    /**
     * The fields of a login dialog. [toString] hides both.
     *
     * @property username The username.
     * @property password The password.
     */
    class Login(val username: String, val password: String) : DialogValue {
        override fun equals(other: Any?): Boolean =
            other is Login && other.username == username && other.password == password
        override fun hashCode(): Int = 31 * username.hashCode() + password.hashCode()
        override fun toString(): String = "Login(usernameLength=${username.length}, passwordLength=${password.length})"
    }
}

/**
 * The result of a dialog. Exactly one result is delivered per request.
 */
sealed interface DialogResult {

    /** An answer from the user: [Button] or [Dismissed]. */
    sealed interface Answer : DialogResult

    /**
     * The user pressed a button.
     *
     * @property which Which button.
     * @property text The button label.
     * @property value The value, [DialogValue.None] for the negative button.
     */
    data class Button(val which: DialogButton, val text: String, val value: DialogValue) : Answer

    /** The user closed the dialog with the back key or a tap outside. */
    data object Dismissed : Answer

    /**
     * The request ended without an answer.
     *
     * @property reason Why.
     */
    data class Canceled(val reason: CancelReason) : DialogResult

    /**
     * The dialog could not be shown.
     *
     * @property error Why.
     */
    data class Failed(val error: DialogError) : DialogResult
}
