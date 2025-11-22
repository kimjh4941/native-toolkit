package android.library.dialog

import android.app.AlertDialog
import android.app.Dialog
import android.content.DialogInterface
import android.os.Bundle
import android.util.Log
import androidx.fragment.app.DialogFragment
import kotlin.toString

/**
 * Internal enumeration describing the dialog variant rendered by [AndroidDialogFragment].
 * Each value maps to a factory overload of `newInstance`.
 */
private enum class DialogType(val value: Int) {
    /** Simple dialog with a single OK button. */
    SIMPLE(0),

    /** Confirm dialog with Yes / No buttons. */
    CONFIRM(1),

    /** Single choice list dialog (radio list) with OK/Cancel. */
    SINGLE_CHOICE(2),

    /** Multi choice list dialog (checkbox list) with OK/Cancel. */
    MULTI_CHOICE(3),

    /** Text input dialog with a single line EditText. */
    TEXT_INPUT(4),

    /** Login dialog with username and password fields. */
    LOGIN(5);

    companion object {
        fun fromInt(value: Int): DialogType = DialogType.entries.find { it.value == value } ?: SIMPLE
    }
}

/**
 * Versatile dialog fragment supporting multiple patterns:
 * 1. Simple (single OK button)
 * 2. Confirm (Yes / No)
 * 3. Single choice list (radio list + OK/Cancel)
 * 4. Multi choice list (checkbox list + OK/Cancel)
 * 5. Text input (single line EditText)
 * 6. Login (username + password form)
 *
 * The specific mode is chosen through the static `newInstance` factory you call.
 * After creation you must set the corresponding listener (e.g. [setDialogListener], [setConfirmDialogListener], etc.) before showing.
 *
 * Basic simple example:
 * ```kotlin
 * AndroidDialogFragment.newInstance(
 *     title = "Notice",
 *     message = "Operation completed"
 * ).apply {
 *     setDialogListener(object : AndroidDialogFragment.DialogListener {
 *         override fun onDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
 *             // Handle OK tap
 *         }
 *     })
 * }.show(supportFragmentManager, "AndroidDialogFragment")
 * ```
 * Single choice example:
 * ```kotlin
 * AndroidDialogFragment.newInstance(
 *     title = "Choose Color",
 *     singleChoiceItems = arrayOf("Red","Green","Blue"),
 *     checkedItem = 0
 * ).apply {
 *     setSingleChoiceItemDialogListener(object : AndroidDialogFragment.SingleChoiceItemDialogListener {
 *         override fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItem: Int?, isSuccessful: Boolean, errorMessage: String?) {
 *             if (buttonText == "OK" && checkedItem != null) {
 *                 // use selected index
 *             }
 *         }
 *     })
 * }.show(supportFragmentManager, "AndroidDialogFragment")
 * ```
 * Login example:
 * ```kotlin
 * AndroidDialogFragment.newInstance(
 *     title = "Sign In",
 *     message = "Enter credentials",
 *     usernameHint = "Username",
 *     passwordHint = "Password"
 * ).apply {
 *     setLoginDialogListener(object : AndroidDialogFragment.LoginDialogListener {
 *         override fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?) {
 *             if (buttonText == "OK") {
 *                 // authenticate
 *             }
 *         }
 *     })
 * }.show(supportFragmentManager, "AndroidDialogFragment")
 * ```
 */
class AndroidDialogFragment : DialogFragment() {
    private var title: String? = null
    private var message: String? = null
    private var buttonText: String? = null
    private var negativeButtonText: String? = null
    private var positiveButtonText: String? = null
    private var singleChoiceItems: Array<String>? = null
    private var checkedItem: Int = 0
    private var multiChoiceItems: Array<String>? = null
    private var checkedItems: BooleanArray? = null
    private var hint: String? = null
    private var usernameHint: String? = null
    private var passwordHint: String? = null
    private var enablePositiveButtonWhenEmpty: Boolean = false
    private var cancelableOnTouchOutside: Boolean = true
    private var cancelable: Boolean = true

    private var textInputEditTextId: Int = android.view.View.NO_ID
    private var usernameEditTextId: Int = android.view.View.NO_ID
    private var passwordEditTextId: Int = android.view.View.NO_ID

    private var dialogListener: DialogListener? = null

    private var confirmListener: ConfirmDialogListener? = null

    private var singleChoiceItemListener: SingleChoiceItemDialogListener? = null

    private var multiChoiceItemListener: MultiChoiceItemDialogListener? = null

    private var textInputListener: TextInputDialogListener? = null

    private var loginListener: LoginDialogListener? = null

    private var dialogType: DialogType = DialogType.SIMPLE

    interface DialogListener {
        /** Callback for Simple dialog positive button tap (or cancel event). */
        fun onDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?)
    }

    interface ConfirmDialogListener {
        /** Callback for Confirm dialog button taps (positive or negative). */
        fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?)
    }

    interface SingleChoiceItemDialogListener {
        /** Callback for Single choice dialog. [checkedItem] is provided only when OK pressed. */
        fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItem: Int?, isSuccessful: Boolean, errorMessage: String?)
    }

    interface MultiChoiceItemDialogListener {
        /** Callback for Multi choice dialog. [checkedItems] is provided only when OK pressed. */
        fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?)
    }

    interface TextInputDialogListener {
        /** Callback for Text input dialog. [inputText] is supplied when OK pressed. */
        fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?)
    }

    interface LoginDialogListener {
        /** Callback for Login dialog. [username] & [password] supplied when OK pressed. */
        fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate")
        arguments?.let {
            dialogType = DialogType.fromInt(it.getInt(ARG_DIALOG_TYPE, DialogType.SIMPLE.value))
            title = it.getString(ARG_TITLE)
            message = it.getString(ARG_MESSAGE)
            buttonText = it.getString(ARG_BUTTON_TEXT)
            negativeButtonText = it.getString(ARG_NEGATIVE_BUTTON_TEXT)
            positiveButtonText = it.getString(ARG_POSITIVE_BUTTON_TEXT)
            singleChoiceItems = it.getStringArray(ARG_SINGLE_CHOICE_ITEMS)
            checkedItem = it.getInt(ARG_CHECKED_ITEM)
            multiChoiceItems = it.getStringArray(ARG_MULTI_CHOICE_ITEMS)
            checkedItems = it.getBooleanArray(ARG_CHECKED_ITEMS)
            hint = it.getString(ARG_HINT)
            usernameHint = it.getString(ARG_USERNAME_HINT)
            passwordHint = it.getString(ARG_PASSWORD_HINT)
            enablePositiveButtonWhenEmpty = it.getBoolean(ARG_ENABLE_POSITIVE_BUTTON_WHEN_EMPTY)
            cancelableOnTouchOutside = it.getBoolean(ARG_CANCELABLE_ON_TOUCH_OUTSIDE, true)
            cancelable = it.getBoolean(ARG_CANCELABLE, true)

            Log.d(TAG, "dialogType: $dialogType")
            Log.d(TAG, "title: $title")
            Log.d(TAG, "message: $message")
            Log.d(TAG, "buttonText: $buttonText")
            Log.d(TAG, "negativeButtonText: $negativeButtonText")
            Log.d(TAG, "positiveButtonText: $positiveButtonText")
            Log.d(TAG, "singleChoiceItems: ${singleChoiceItems?.contentToString()}")
            Log.d(TAG, "checkedItem: $checkedItem")
            Log.d(TAG, "multiChoiceItems: ${multiChoiceItems?.contentToString()}")
            Log.d(TAG, "checkedItems: ${checkedItems?.contentToString()}")
            Log.d(TAG, "hint: $hint")
            Log.d(TAG, "usernameHint: $usernameHint")
            Log.d(TAG, "passwordHint: $passwordHint")
            Log.d(TAG, "enablePositiveButtonWhenEmpty: $enablePositiveButtonWhenEmpty")
            Log.d(TAG, "cancelableOnTouchOutside: $cancelableOnTouchOutside")
            Log.d(TAG, "cancelable: $cancelable")
        }
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        Log.d(TAG, "onCreateDialog")
        return activity?.let {
            val builder = AlertDialog.Builder(it)
            builder.apply {
                if (title != null) {
                    setTitle(title)
                }
                if (message != null) {
                    setMessage(message)
                }

                when (dialogType) {
                    DialogType.SIMPLE -> {
                        setPositiveButton(buttonText ?: "OK") { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            dialogListener?.onDialog(this@AndroidDialogFragment, buttonText ?: "OK", true, null)
                        }
                    }

                    DialogType.CONFIRM -> {
                        setNegativeButton(negativeButtonText) { dialog, id ->
                            Log.d(TAG, "NegativeButton Click")
                            confirmListener?.onConfirmDialog(this@AndroidDialogFragment, negativeButtonText!!, true, null)
                        }
                        setPositiveButton(positiveButtonText) { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            confirmListener?.onConfirmDialog(this@AndroidDialogFragment, positiveButtonText!!, true, null)
                        }
                    }

                    DialogType.SINGLE_CHOICE -> {
                        setSingleChoiceItems(singleChoiceItems, checkedItem) { dialog, which ->
                            Log.d(TAG, "SingleChoiceItem Click: $which")
                            checkedItem = which
                        }
                        setNegativeButton(negativeButtonText ?: "Cancel") { dialog, id ->
                            Log.d(TAG, "NegativeButton Click")
                            singleChoiceItemListener?.onSingleChoiceItemDialog(this@AndroidDialogFragment, negativeButtonText ?: "Cancel", null, true, null)
                        }
                        setPositiveButton(positiveButtonText ?: "OK") { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            singleChoiceItemListener?.onSingleChoiceItemDialog(this@AndroidDialogFragment, positiveButtonText ?: "OK", checkedItem, true, null)
                        }
                    }

                    DialogType.MULTI_CHOICE -> {
                        setMultiChoiceItems(multiChoiceItems, checkedItems) { dialog, which, isChecked ->
                            Log.d(TAG, "MultiChoiceItem Click: $which, isChecked: $isChecked")
                            checkedItems!![which] = isChecked
                        }
                        setNegativeButton(negativeButtonText ?: "Cancel") { dialog, id ->
                            Log.d(TAG, "NegativeButton Click")
                            multiChoiceItemListener?.onMultiChoiceItemDialog(this@AndroidDialogFragment, negativeButtonText ?: "Cancel", null, true, null)
                        }
                        setPositiveButton(positiveButtonText ?: "OK") { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            multiChoiceItemListener?.onMultiChoiceItemDialog(this@AndroidDialogFragment, positiveButtonText ?: "OK", checkedItems!!, true, null)
                        }
                    }

                    DialogType.TEXT_INPUT -> {
                        val editText = android.widget.EditText(context)
                        textInputEditTextId = android.view.View.generateViewId() // Generate and save ID
                        editText.id = textInputEditTextId
                        editText.isSingleLine = true
                        editText.hint = hint
                        setView(editText)
                        setNegativeButton(negativeButtonText ?: "Cancel") { dialog, id ->
                            textInputListener?.onTextInputDialog(this@AndroidDialogFragment, negativeButtonText ?: "Cancel", null, true, null)
                        }
                        setPositiveButton(positiveButtonText ?: "OK") { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            val inputText = editText.text.toString()
                            textInputListener?.onTextInputDialog(this@AndroidDialogFragment, positiveButtonText ?: "OK", inputText, true, null)
                        }
                    }

                    DialogType.LOGIN -> {
                        val layout = android.widget.LinearLayout(context)
                        layout.orientation = android.widget.LinearLayout.VERTICAL

                        val usernameEditText = android.widget.EditText(context)
                        usernameEditTextId = android.view.View.generateViewId() // Generate and save ID
                        usernameEditText.id = usernameEditTextId
                        usernameEditText.imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_NEXT
                        usernameEditText.inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                        usernameEditText.isSingleLine = true
                        usernameEditText.hint = usernameHint
                        layout.addView(usernameEditText)

                        val passwordEditText = android.widget.EditText(context)
                        passwordEditTextId = android.view.View.generateViewId() // Generate and save ID
                        passwordEditText.id = passwordEditTextId
                        passwordEditText.imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_DONE
                        passwordEditText.isSingleLine = true
                        passwordEditText.hint = passwordHint
                        passwordEditText.inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
                        layout.addView(passwordEditText)
                        setView(layout)

                        setNegativeButton(negativeButtonText ?: "Cancel") { dialog, id ->
                            Log.d(TAG, "NegativeButton Click")
                            loginListener?.onLoginDialog(this@AndroidDialogFragment, negativeButtonText ?: "Cancel", null, null, true, null)
                        }
                        setPositiveButton(positiveButtonText ?: "OK") { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            val username = usernameEditText.text.toString()
                            val password = passwordEditText.text.toString()
                            loginListener?.onLoginDialog(this@AndroidDialogFragment, positiveButtonText ?: "OK", username, password, true, null)
                        }
                    }
                }
            }

            val dialog = builder.create()
            // Control positive button enabled state for input/login dialogs
            if (dialogType == DialogType.TEXT_INPUT || dialogType == DialogType.LOGIN) {
                dialog.setOnShowListener {
                    val positiveButton = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                    positiveButton.isEnabled = enablePositiveButtonWhenEmpty

                    when (dialogType) {
                        DialogType.TEXT_INPUT -> {
                            // Retrieve EditText via stored generated ID
                            val editText = dialog.findViewById<android.widget.EditText>(textInputEditTextId)
                            editText?.addTextChangedListener(object : android.text.TextWatcher {
                                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                                override fun afterTextChanged(s: android.text.Editable?) {
                                    Log.d(TAG, "afterTextChanged: ${s.toString()}")
                                    positiveButton.isEnabled = enablePositiveButtonWhenEmpty || !s.isNullOrEmpty()
                                    Log.d(TAG, "positiveButton.isEnabled: ${positiveButton.isEnabled}")
                                }
                            })
                        }

                        DialogType.LOGIN -> {
                            // Retrieve both EditTexts via stored generated IDs
                            val usernameEditText = dialog.findViewById<android.widget.EditText>(usernameEditTextId)
                            val passwordEditText = dialog.findViewById<android.widget.EditText>(passwordEditTextId)

                            val textWatcher = object : android.text.TextWatcher {
                                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                                override fun afterTextChanged(s: android.text.Editable?) {
                                    Log.d(TAG, "afterTextChanged: ${s.toString()}")
                                    val username = usernameEditText?.text?.toString() ?: ""
                                    val password = passwordEditText?.text?.toString() ?: ""
                                    positiveButton.isEnabled = enablePositiveButtonWhenEmpty || (username.isNotEmpty() && password.isNotEmpty())
                                    Log.d(TAG, "positiveButton.isEnabled: ${positiveButton.isEnabled}")
                                }
                            }

                            usernameEditText?.addTextChangedListener(textWatcher)
                            passwordEditText?.addTextChangedListener(textWatcher)
                        }

                        else -> {}
                    }
                }
            }

            dialog.setCanceledOnTouchOutside(cancelableOnTouchOutside)
            isCancelable = cancelable
            return dialog
        } ?: throw IllegalStateException("Activity cannot be null")
    }

    override fun onCancel(dialog: DialogInterface) {
        super.onCancel(dialog)
        Log.d(TAG, "onCancel")
        when (dialogType) {
            DialogType.SIMPLE -> {
                dialogListener?.onDialog(this, "Cancel", true, "")
            }
            DialogType.CONFIRM -> {
                confirmListener?.onConfirmDialog(this, "Cancel", true, "")
            }
            DialogType.SINGLE_CHOICE -> {
                singleChoiceItemListener?.onSingleChoiceItemDialog(this, "Cancel", checkedItem, true, "")
            }
            DialogType.MULTI_CHOICE -> {
                multiChoiceItemListener?.onMultiChoiceItemDialog(this, "Cancel", checkedItems ?: BooleanArray(0), true, "")
            }
            DialogType.TEXT_INPUT -> {
                textInputListener?.onTextInputDialog(this, "Cancel", "", true, "")
            }
            DialogType.LOGIN -> {
                loginListener?.onLoginDialog(this, "Cancel", "", "", true, "")
            }
        }
    }

    /** Assign listener for Simple dialog variant. */
    fun setDialogListener(listener: DialogListener) {
        Log.d(TAG, "setDialogListener")
        this.dialogListener = listener
    }

    /** Assign listener for Confirm dialog variant. */
    fun setConfirmDialogListener(listener: ConfirmDialogListener) {
        Log.d(TAG, "setConfirmDialogListener")
        this.confirmListener = listener
    }

    /** Assign listener for Single choice dialog variant. */
    fun setSingleChoiceItemDialogListener(listener: SingleChoiceItemDialogListener) {
        Log.d(TAG, "setSingleChoiceItemDialogListener")
        this.singleChoiceItemListener = listener
    }

    /** Assign listener for Multi choice dialog variant. */
    fun setMultiChoiceItemDialogListener(listener: MultiChoiceItemDialogListener) {
        Log.d(TAG, "setMultiChoiceItemDialogListener")
        this.multiChoiceItemListener = listener
    }

    /** Assign listener for Text input dialog variant. */
    fun setTextInputDialogListener(listener: TextInputDialogListener) {
        Log.d(TAG, "setTextInputDialogListener")
        this.textInputListener = listener
    }

    /** Assign listener for Login dialog variant. */
    fun setLoginDialogListener(listener: LoginDialogListener) {
        Log.d(TAG, "setLoginDialogListener")
        this.loginListener = listener
    }

    companion object {
        private const val TAG = "AndroidDialogFragment"

        private const val ARG_TITLE = "title"
        private const val ARG_MESSAGE = "message"
        private const val ARG_BUTTON_TEXT = "button_text"
        private const val ARG_NEGATIVE_BUTTON_TEXT = "negative_button_text"
        private const val ARG_POSITIVE_BUTTON_TEXT = "positive_button_text"
        private const val ARG_SINGLE_CHOICE_ITEMS = "single_choice_items"
        private const val ARG_MULTI_CHOICE_ITEMS = "multi_choice_items"
        private const val ARG_CHECKED_ITEMS = "checked_items"
        private const val ARG_CHECKED_ITEM = "checked_item"
        private const val ARG_ENABLE_POSITIVE_BUTTON_WHEN_EMPTY = "enable_positive_button_when_empty"
        private const val ARG_HINT = "hint"
        private const val ARG_USERNAME_HINT = "username_hint"
        private const val ARG_PASSWORD_HINT = "password_hint"
        private const val ARG_DIALOG_TYPE = "dialog_type"
        private const val ARG_CANCELABLE_ON_TOUCH_OUTSIDE = "cancelable_on_touch_outside"
        private const val ARG_CANCELABLE = "cancelable"

        /**
         * Create a Simple dialog with a single positive button.
         * @param title Dialog title.
         * @param message Body message.
         * @param buttonText Text for the positive button (default: OK).
         * @param cancelableOnTouchOutside If true tapping outside dismisses.
         * @param cancelable If true back press / outside allowed.
         */
        /** Create a Simple dialog (single positive button). */
        fun newInstance(title: String,
                        message: String,
                        buttonText: String = "OK",
                        cancelableOnTouchOutside: Boolean = true,
                        cancelable: Boolean = true) =
            AndroidDialogFragment().apply {
                Log.d(TAG, "newInstance")
                arguments = Bundle().apply {
                    putInt(ARG_DIALOG_TYPE, DialogType.SIMPLE.value)
                    putString(ARG_TITLE, title)
                    putString(ARG_MESSAGE, message)
                    putString(ARG_BUTTON_TEXT, buttonText)
                    putBoolean(ARG_CANCELABLE_ON_TOUCH_OUTSIDE, cancelableOnTouchOutside)
                    putBoolean(ARG_CANCELABLE, cancelable)
                }
            }

        /**
         * Create a Confirm dialog with negative / positive buttons.
         * Typical usage:
         * ```kotlin
         * AndroidDialogFragment.newInstance("Delete File", "Are you sure?",
         *     negativeButtonText = "No", positiveButtonText = "Yes")
         * ```
         */
        /** Create a Confirm dialog (negative & positive buttons). */
        fun newInstance(title: String,
                        message: String,
                        negativeButtonText: String = "No",
                        positiveButtonText: String = "Yes",
                        cancelableOnTouchOutside: Boolean = true,
                        cancelable: Boolean = true) =
            AndroidDialogFragment().apply {
                Log.d(TAG, "newInstance")
                arguments = Bundle().apply {
                    putInt(ARG_DIALOG_TYPE, DialogType.CONFIRM.value)
                    putString(ARG_TITLE, title)
                    putString(ARG_MESSAGE, message)
                    putString(ARG_NEGATIVE_BUTTON_TEXT, negativeButtonText)
                    putString(ARG_POSITIVE_BUTTON_TEXT, positiveButtonText)
                    putBoolean(ARG_CANCELABLE_ON_TOUCH_OUTSIDE, cancelableOnTouchOutside)
                    putBoolean(ARG_CANCELABLE, cancelable)
                }
            }

        /**
         * Create a Single choice list dialog (radio).
         * @param singleChoiceItems Items to display.
         * @param checkedItem Initially selected index.
         */
        /** Create a Single choice (radio list) dialog. */
        fun newInstance(title: String,
                        singleChoiceItems: Array<String>,
                        checkedItem: Int = 0,
                        negativeButtonText: String = "Cancel",
                        positiveButtonText: String = "OK",
                        cancelableOnTouchOutside: Boolean = true,
                        cancelable: Boolean = true) =
            AndroidDialogFragment().apply {
                Log.d(TAG, "newInstance")
                arguments = Bundle().apply {
                    putInt(ARG_DIALOG_TYPE, DialogType.SINGLE_CHOICE.value)
                    putString(ARG_TITLE, title)
                    putStringArray(ARG_SINGLE_CHOICE_ITEMS, singleChoiceItems)
                    putInt(ARG_CHECKED_ITEM, checkedItem)
                    putString(ARG_NEGATIVE_BUTTON_TEXT, negativeButtonText)
                    putString(ARG_POSITIVE_BUTTON_TEXT, positiveButtonText)
                    putBoolean(ARG_CANCELABLE_ON_TOUCH_OUTSIDE, cancelableOnTouchOutside)
                    putBoolean(ARG_CANCELABLE, cancelable)
                }
            }

        /**
         * Create a Multi choice list dialog (checkboxes).
         * @param multiChoiceItems Items to display.
         * @param checkedItems Boolean array initial states (length must match items).
         */
        /** Create a Multi choice (checkbox list) dialog. */
        fun newInstance(title: String,
                        multiChoiceItems: Array<String>,
                        checkedItems: BooleanArray,
                        negativeButtonText: String = "Cancel",
                        positiveButtonText: String = "OK",
                        cancelableOnTouchOutside: Boolean = true,
                        cancelable: Boolean = true) =
            AndroidDialogFragment().apply {
                Log.d(TAG, "newInstance")
                arguments = Bundle().apply {
                    putInt(ARG_DIALOG_TYPE, DialogType.MULTI_CHOICE.value)
                    putString(ARG_TITLE, title)
                    putStringArray(ARG_MULTI_CHOICE_ITEMS, multiChoiceItems)
                    putBooleanArray(ARG_CHECKED_ITEMS, checkedItems)
                    putString(ARG_NEGATIVE_BUTTON_TEXT, negativeButtonText)
                    putString(ARG_POSITIVE_BUTTON_TEXT, positiveButtonText)
                    putBoolean(ARG_CANCELABLE_ON_TOUCH_OUTSIDE, cancelableOnTouchOutside)
                    putBoolean(ARG_CANCELABLE, cancelable)
                }
            }

        /**
         * Create a Text input dialog.
         * @param hint Hint text for the EditText.
         * @param enablePositiveButtonWhenEmpty If false OK disabled until non-empty.
         */
        /** Create a Text input dialog. */
        fun newInstance(title: String,
                        message: String,
                        hint: String = "",
                        negativeButtonText: String = "Cancel",
                        positiveButtonText: String = "OK",
                        enablePositiveButtonWhenEmpty: Boolean = false,
                        cancelableOnTouchOutside: Boolean = true,
                        cancelable: Boolean = true) =
            AndroidDialogFragment().apply {
                Log.d(TAG, "newInstance")
                arguments = Bundle().apply {
                    putInt(ARG_DIALOG_TYPE, DialogType.TEXT_INPUT.value)
                    putString(ARG_TITLE, title)
                    putString(ARG_MESSAGE, message)
                    putString(ARG_HINT, hint)
                    putString(ARG_NEGATIVE_BUTTON_TEXT, negativeButtonText)
                    putString(ARG_POSITIVE_BUTTON_TEXT, positiveButtonText)
                    putBoolean(ARG_ENABLE_POSITIVE_BUTTON_WHEN_EMPTY, enablePositiveButtonWhenEmpty)
                    putBoolean(ARG_CANCELABLE_ON_TOUCH_OUTSIDE, cancelableOnTouchOutside)
                    putBoolean(ARG_CANCELABLE, cancelable)
                }
            }

        /**
         * Create a Login dialog containing username & password fields.
         * @param usernameHint Hint for username field.
         * @param passwordHint Hint for password field.
         * @param enablePositiveButtonWhenEmpty If false OK disabled until both fields non-empty.
         */
        /** Create a Login dialog (username & password). */
        fun newInstance(title: String,
                        message: String,
                        usernameHint: String = "Username",
                        passwordHint: String = "Password",
                        negativeButtonText: String = "Cancel",
                        positiveButtonText: String = "Login",
                        enablePositiveButtonWhenEmpty: Boolean = false,
                        cancelableOnTouchOutside: Boolean = true,
                        cancelable: Boolean = true) =
            AndroidDialogFragment().apply {
                Log.d(TAG, "newInstance")
                arguments = Bundle().apply {
                    putInt(ARG_DIALOG_TYPE, DialogType.LOGIN.value)
                    putString(ARG_TITLE, title)
                    putString(ARG_MESSAGE, message)
                    putString(ARG_USERNAME_HINT, usernameHint)
                    putString(ARG_PASSWORD_HINT, passwordHint)
                    putString(ARG_NEGATIVE_BUTTON_TEXT, negativeButtonText)
                    putString(ARG_POSITIVE_BUTTON_TEXT, positiveButtonText)
                    putBoolean(ARG_ENABLE_POSITIVE_BUTTON_WHEN_EMPTY, enablePositiveButtonWhenEmpty)
                    putBoolean(ARG_CANCELABLE_ON_TOUCH_OUTSIDE, cancelableOnTouchOutside)
                    putBoolean(ARG_CANCELABLE, cancelable)
                }
            }
    }
}
