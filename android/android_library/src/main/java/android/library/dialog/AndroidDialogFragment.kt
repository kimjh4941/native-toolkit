package android.library.dialog

import android.app.AlertDialog
import android.app.Dialog
import android.content.DialogInterface
import android.os.Bundle
import android.util.Log
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.Fragment
import kotlin.toString

/**
 * ダイアログタイプを表すenum
 */
private enum class DialogType(val value: Int) {
    SIMPLE(0),
    CONFIRM(1),
    SINGLE_CHOICE(2),
    MULTI_CHOICE(3),
    TEXT_INPUT(4),
    LOGIN(5);

    companion object {
        fun fromInt(value: Int): DialogType = DialogType.entries.find { it.value == value } ?: SIMPLE
    }
}

/**
 * A simple [Fragment] subclass.
 * Use the [AndroidDialogFragment.newInstance] factory method to
 * create an instance of this fragment.
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
        fun onDialog(dialog: AndroidDialogFragment, buttonText: String, isSuccessful: Boolean, errorMessage: String)
    }

    interface ConfirmDialogListener {
        fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String, isSuccessful: Boolean, errorMessage: String)
    }

    interface SingleChoiceItemDialogListener {
        fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String, checkedItem: Int, isSuccessful: Boolean, errorMessage: String)
    }

    interface MultiChoiceItemDialogListener {
        fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String, checkedItems: BooleanArray, isSuccessful: Boolean, errorMessage: String)
    }

    interface TextInputDialogListener {
        fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String, inputText: String, isSuccessful: Boolean, errorMessage: String)
    }

    interface LoginDialogListener {
        fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String, username: String, password: String, isSuccessful: Boolean, errorMessage: String)
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
                            dialogListener?.onDialog(this@AndroidDialogFragment, buttonText ?: "OK", true, "")
                        }
                    }

                    DialogType.CONFIRM -> {
                        setNegativeButton(negativeButtonText) { dialog, id ->
                            Log.d(TAG, "NegativeButton Click")
                            confirmListener?.onConfirmDialog(this@AndroidDialogFragment, negativeButtonText!!, true, "")
                        }
                        setPositiveButton(positiveButtonText) { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            confirmListener?.onConfirmDialog(this@AndroidDialogFragment, positiveButtonText!!, true, "")
                        }
                    }

                    DialogType.SINGLE_CHOICE -> {
                        setSingleChoiceItems(singleChoiceItems, checkedItem) { dialog, which ->
                            Log.d(TAG, "SingleChoiceItem Click: $which")
                            checkedItem = which
                        }
                        setNegativeButton(negativeButtonText ?: "Cancel") { dialog, id ->
                            Log.d(TAG, "NegativeButton Click")
                            singleChoiceItemListener?.onSingleChoiceItemDialog(this@AndroidDialogFragment, negativeButtonText ?: "Cancel", checkedItem, true, "")
                        }
                        setPositiveButton(positiveButtonText ?: "OK") { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            singleChoiceItemListener?.onSingleChoiceItemDialog(this@AndroidDialogFragment, positiveButtonText ?: "OK", checkedItem, true, "")
                        }
                    }

                    DialogType.MULTI_CHOICE -> {
                        setMultiChoiceItems(multiChoiceItems, checkedItems) { dialog, which, isChecked ->
                            Log.d(TAG, "MultiChoiceItem Click: $which, isChecked: $isChecked")
                            checkedItems!![which] = isChecked
                        }
                        setNegativeButton(negativeButtonText ?: "Cancel") { dialog, id ->
                            Log.d(TAG, "NegativeButton Click")
                            multiChoiceItemListener?.onMultiChoiceItemDialog(this@AndroidDialogFragment, negativeButtonText ?: "Cancel", checkedItems!!, true, "")
                        }
                        setPositiveButton(positiveButtonText ?: "OK") { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            multiChoiceItemListener?.onMultiChoiceItemDialog(this@AndroidDialogFragment, positiveButtonText ?: "OK", checkedItems!!, true, "")
                        }
                    }

                    DialogType.TEXT_INPUT -> {
                        val editText = android.widget.EditText(context)
                        textInputEditTextId = android.view.View.generateViewId() // IDを生成して保存
                        editText.id = textInputEditTextId
                        editText.isSingleLine = true
                        editText.hint = hint
                        setView(editText)
                        setNegativeButton(negativeButtonText ?: "Cancel") { dialog, id ->
                            textInputListener?.onTextInputDialog(this@AndroidDialogFragment, negativeButtonText ?: "Cancel", "", true, "")
                        }
                        setPositiveButton(positiveButtonText ?: "OK") { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            val inputText = editText.text.toString()
                            textInputListener?.onTextInputDialog(this@AndroidDialogFragment, positiveButtonText ?: "OK", inputText, true, "")
                        }
                    }

                    DialogType.LOGIN -> {
                        val layout = android.widget.LinearLayout(context)
                        layout.orientation = android.widget.LinearLayout.VERTICAL

                        val usernameEditText = android.widget.EditText(context)
                        usernameEditTextId = android.view.View.generateViewId() // IDを生成して保存
                        usernameEditText.id = usernameEditTextId
                        usernameEditText.imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_NEXT
                        usernameEditText.inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                        usernameEditText.isSingleLine = true
                        usernameEditText.hint = usernameHint
                        layout.addView(usernameEditText)

                        val passwordEditText = android.widget.EditText(context)
                        passwordEditTextId = android.view.View.generateViewId() // IDを生成して保存
                        passwordEditText.id = passwordEditTextId
                        passwordEditText.imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_DONE
                        passwordEditText.isSingleLine = true
                        passwordEditText.hint = passwordHint
                        passwordEditText.inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
                        layout.addView(passwordEditText)
                        setView(layout)

                        setNegativeButton(negativeButtonText ?: "Cancel") { dialog, id ->
                            Log.d(TAG, "NegativeButton Click")
                            loginListener?.onLoginDialog(this@AndroidDialogFragment, negativeButtonText ?: "Cancel", "", "", true, "")
                        }
                        setPositiveButton(positiveButtonText ?: "OK") { dialog, id ->
                            Log.d(TAG, "PositiveButton Click")
                            val username = usernameEditText.text.toString()
                            val password = passwordEditText.text.toString()
                            loginListener?.onLoginDialog(this@AndroidDialogFragment, positiveButtonText ?: "OK", username, password, true, "")
                        }
                    }
                }
            }

            val dialog = builder.create()
            // enablePositiveButtonWhenEmptyの制御
            if (dialogType == DialogType.TEXT_INPUT || dialogType == DialogType.LOGIN) {
                dialog.setOnShowListener {
                    val positiveButton = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                    positiveButton.isEnabled = enablePositiveButtonWhenEmpty

                    when (dialogType) {
                        DialogType.TEXT_INPUT -> {
                            // 保存したIDでEditTextを取得
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
                            // 保存したIDでEditTextを取得
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

    fun setDialogListener(listener: DialogListener) {
        Log.d(TAG, "setDialogListener")
        this.dialogListener = listener
    }

    fun setConfirmDialogListener(listener: ConfirmDialogListener) {
        Log.d(TAG, "setConfirmDialogListener")
        this.confirmListener = listener
    }

    fun setSingleChoiceItemDialogListener(listener: SingleChoiceItemDialogListener) {
        Log.d(TAG, "setSingleChoiceItemDialogListener")
        this.singleChoiceItemListener = listener
    }

    fun setMultiChoiceItemDialogListener(listener: MultiChoiceItemDialogListener) {
        Log.d(TAG, "setMultiChoiceItemDialogListener")
        this.multiChoiceItemListener = listener
    }

    fun setTextInputDialogListener(listener: TextInputDialogListener) {
        Log.d(TAG, "setTextInputDialogListener")
        this.textInputListener = listener
    }

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

        // シンプルダイアログ
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

        // 確認ダイアログ
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

        // 単一選択ダイアログ
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

        // 複数選択ダイアログ
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

        // テキスト入力ダイアログ
        fun newInstance(title: String,
                        message: String,
                        hint: String,
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

        // ログインダイアログ
        fun newInstance(title: String,
                        message: String,
                        usernameHint: String,
                        passwordHint: String,
                        negativeButtonText: String = "Cancel",
                        positiveButtonText: String = "OK",
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
