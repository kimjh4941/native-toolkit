package android.unity.dialog

import android.content.Context
import android.library.dialog.AndroidDialogFragment
import android.util.Log
import androidx.fragment.app.FragmentActivity
import kotlin.Boolean

/**
 * Unified dialog bridge for Unity.
 *
 * Provides six dialog variants (Simple / Confirm / SingleChoice / MultiChoice / TextInput / Login)
 * backed by AndroidDialogFragment. Each variant has its own listener interface (setXxxListener).
 *
 * Features:
 * - Outside tap / back press cancellation control (cancelableOnTouchOutside / cancelable)
 * - TextInput / Login positive button gating (disabled while empty unless enablePositiveButtonWhenEmpty=true)
 * - Internal failures (non FragmentActivity / exception) reported with isSuccessful=false and errorMessage
 *
 * Unity C# wrapper (AndroidDialogManager.cs):
 * - Receives these Java callbacks and re-maps them to C# events
 * - SingleChoice: checkedItem=-1 normalized to null
 * - MultiChoice: cancel may deliver null checkedItems (distinguishable)
 * - TextInput / Login: inputs null on cancel
 *
 * Mapping (Java -> C#):
 * | Variant      | show* Method                   | Listener Method                | C# Event                     |
 * |--------------|--------------------------------|--------------------------------|------------------------------|
 * | Simple       | showDialog                     | onDialog                       | DialogResult                 |
 * | Confirm      | showConfirmDialog              | onConfirmDialog                | ConfirmDialogResult          |
 * | SingleChoice | showSingleChoiceItemDialog     | onSingleChoiceItemDialog       | SingleChoiceItemDialogResult |
 * | MultiChoice  | showMultiChoiceItemDialog      | onMultiChoiceItemDialog        | MultiChoiceItemDialogResult  |
 * | TextInput    | showTextInputDialog            | onTextInputDialog              | TextInputDialogResult        |
 * | Login        | showLoginDialog                | onLoginDialog                  | LoginDialogResult            |
 *
 * isSuccessful:
 * - true: user-driven completion (OK / Cancel) successfully routed through the fragment
 * - false: internal error before / during dialog creation
 *
 * Notes:
 * - Cancel (back / outside) still treated as success (user action) with a Cancel-style buttonText
 * - If a listener is not registered its result is discarded silently
 */
object UnityAndroidDialogManager {

    private const val TAG = "UnityAndroidDialogManager"

    private var dialogListener: DialogListener? = null
    private var confirmDialogListener: ConfirmDialogListener? = null
    private var singleChoiceItemDialogListener: SingleChoiceItemDialogListener? = null
    private var multiChoiceItemDialogListener: MultiChoiceItemDialogListener? = null
    private var textInputDialogListener: TextInputDialogListener? = null
    private var loginDialogListener: LoginDialogListener? = null

    /**
     * Listener for simple dialog variant.
     *
     * @param buttonText Pressed button label ("OK" / "Cancel") or null on internal error
     * @param isSuccessful False only for internal errors (cancel still true)
     * @param errorMessage Non-null only when isSuccessful=false
     */
    interface DialogListener {
        fun onDialog(buttonText: String?, isSuccessful: Boolean, errorMessage: String?)
    }

    /**
     * Listener for confirm dialog (two buttons).
     *
     * @param buttonText "Yes" / "No" / "Cancel" (depending on user path) or null on internal error
     * @param isSuccessful False only for internal errors
     * @param errorMessage Present only when failed
     */
    interface ConfirmDialogListener {
        fun onConfirmDialog(buttonText: String?, isSuccessful: Boolean, errorMessage: String?)
    }

    /**
     * Listener for single choice (radio list) dialog.
     *
     * @param buttonText "OK" / "Cancel" or null on internal error
     * @param checkedItem Selected index (>=0 on OK). On cancel last known index or -1. C# wrapper converts -1 to null.
     * @param isSuccessful False only for internal errors
     * @param errorMessage Present only when failed
     *
     * Cancel path: buttonText is Cancel label; checkedItem may be last index or -1.
     */
    interface SingleChoiceItemDialogListener {
        fun onSingleChoiceItemDialog(buttonText: String?, checkedItem: Int, isSuccessful: Boolean, errorMessage: String?)
    }

    /**
     * Listener for multi choice (checkbox list) dialog.
     *
     * @param buttonText Pressed button label
     * @param checkedItems Current states (non-null on OK). May be null on cancel or internal error.
     * @param isSuccessful False only for internal errors
     * @param errorMessage Present only when failed
     */
    interface MultiChoiceItemDialogListener {
        fun onMultiChoiceItemDialog(buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?)
    }

    /**
     * Listener for single-line text input dialog.
     *
     * @param buttonText Pressed button label
     * @param inputText Entered text on OK (may be empty if gating disabled). Null on cancel or error.
     * @param isSuccessful False only for internal errors
     * @param errorMessage Present only when failed
     *
     * Positive button enable rule:
     * - enablePositiveButtonWhenEmpty=false disables OK while text is empty
     */
    interface TextInputDialogListener {
        fun onTextInputDialog(buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?)
    }

    /**
     * Listener for login dialog (username + password).
     *
     * @param buttonText Pressed button label
     * @param username Username on OK, null on cancel/error
     * @param password Password on OK, null on cancel/error
     * @param isSuccessful False only for internal errors
     * @param errorMessage Present only when failed
     *
     * When enablePositiveButtonWhenEmpty=false, OK disabled while either field empty.
     */
    interface LoginDialogListener {
        fun onLoginDialog(buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?)
    }

    /** Obtain singleton for JNI convenience. */
    @JvmStatic
    fun getInstance(): UnityAndroidDialogManager {
        Log.d(TAG, "getInstance called")
        return this
    }

    /** Register listener for simple dialog variant. */
    fun setDialogListener(listener: DialogListener) {
        this.dialogListener = listener
    }

    /** Register listener for confirm dialog variant. */
    fun setConfirmDialogListener(listener: ConfirmDialogListener) {
        this.confirmDialogListener = listener
    }

    /** Register listener for single-choice dialog variant. */
    fun setSingleChoiceItemDialogListener(listener: SingleChoiceItemDialogListener) {
        this.singleChoiceItemDialogListener = listener
    }

    /** Register listener for multi-choice dialog variant. */
    fun setMultiChoiceItemDialogListener(listener: MultiChoiceItemDialogListener) {
        this.multiChoiceItemDialogListener = listener
    }

    /** Register listener for text input dialog variant. */
    fun setTextInputDialogListener(listener: TextInputDialogListener) {
        this.textInputDialogListener = listener
    }

    /** Register listener for login dialog variant. */
    fun setLoginDialogListener(listener: LoginDialogListener) {
        this.loginDialogListener = listener
    }

    /**
     * Show a simple dialog.
     *
     * @param title Dialog title
     * @param message Body text
     * @param buttonText Positive button label (default "OK")
     * @param cancelableOnTouchOutside Dismiss on outside touch
     * @param cancelable Dismiss on back press
     * Internal error path: listener invoked with isSuccessful=false and errorMessage.
     */
    fun showDialog(context: Context,
                   title: String,
                   message: String,
                   buttonText: String = "OK",
                   cancelableOnTouchOutside: Boolean = true,
                   cancelable: Boolean = true) {
        Log.d(TAG, "showDialog called")

        if (dialogListener == null) {
            Log.w(TAG, "DialogListener is not set")
        }

        val activity = context as? FragmentActivity
        if (activity != null) {
            try {
                AndroidDialogFragment.newInstance(title, message, buttonText, cancelableOnTouchOutside, cancelable).apply {
                    setDialogListener(object : AndroidDialogFragment.DialogListener {
                        override fun onDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onDialog called")
                            dialogListener?.onDialog(buttonText, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to showDialog: ${e.message}")
                dialogListener?.onDialog(null, false, "Failed to showDialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            dialogListener?.onDialog(null, false, "Failed to cast context to FragmentActivity")
        }
    }

    /**
     * Show a confirm (two-button) dialog.
     * Notes:
     * - negativeButtonText / positiveButtonText specify labels
     * - Cancel via outside/back may return a Cancel label (implementation dependent)
     */
    fun showConfirmDialog(context: Context,
                          title: String,
                          message: String,
                          negativeButtonText: String = "No",
                          positiveButtonText: String = "Yes",
                          cancelableOnTouchOutside: Boolean = true,
                          cancelable: Boolean = true) {
        Log.d(TAG, "showConfirmDialog called")

        if (confirmDialogListener == null) {
            Log.w(TAG, "ConfirmDialogListener is not set")
        }

        val activity = context as? FragmentActivity
        if (activity != null) {
            try {
                AndroidDialogFragment.newInstance(title, message, negativeButtonText, positiveButtonText, cancelableOnTouchOutside, cancelable).apply {
                    setConfirmDialogListener(object : AndroidDialogFragment.ConfirmDialogListener {
                        override fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onConfirmDialog called")
                            confirmDialogListener?.onConfirmDialog(buttonText, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to showConfirmDialog: ${e.message}")
                confirmDialogListener?.onConfirmDialog(null, false, "Failed to showConfirmDialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            confirmDialogListener?.onConfirmDialog(null, false, "Failed to cast context to FragmentActivity")
        }
    }

    /**
     * Show a single choice list dialog.
     * - checkedItem: initial selection index
     * - Cancel: last index or -1
     */
    fun showSingleChoiceItemDialog(context: Context,
                                   title: String,
                                   singleChoiceItems: Array<String>,
                                   checkedItem: Int = 0,
                                   negativeButtonText: String = "Cancel",
                                   positiveButtonText: String = "OK",
                                   cancelableOnTouchOutside: Boolean = true,
                                   cancelable: Boolean = true) {
        Log.d(TAG, "showSingleChoiceItemDialog called")

        if (singleChoiceItemDialogListener == null) {
            Log.w(TAG, "SingleChoiceItemDialogListener is not set")
        }

        val activity = context as? FragmentActivity
        if (activity != null) {
            try {
                AndroidDialogFragment.newInstance(title, singleChoiceItems, checkedItem, negativeButtonText, positiveButtonText, cancelableOnTouchOutside, cancelable).apply {
                    setSingleChoiceItemDialogListener(object : AndroidDialogFragment.SingleChoiceItemDialogListener {
                        override fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItem: Int?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onSingleChoiceItemDialog called")
                            singleChoiceItemDialogListener?.onSingleChoiceItemDialog(buttonText, checkedItem ?: -1, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to showSingleChoiceItemDialog: ${e.message}")
                singleChoiceItemDialogListener?.onSingleChoiceItemDialog(null, -1, false, "Failed to showSingleChoiceItemDialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            singleChoiceItemDialogListener?.onSingleChoiceItemDialog(null, -1, false, "Failed to cast context to FragmentActivity")
        }
    }

    /**
     * Show a multi choice list dialog.
     * - checkedItems: initial states (caller should pass a copy if mutability matters)
     * - Cancel: may yield null checkedItems
     */
    fun showMultiChoiceItemDialog(context: Context,
                                  title: String,
                                  multiChoiceItems: Array<String>,
                                  checkedItems: BooleanArray,
                                  negativeButtonText: String = "Cancel",
                                  positiveButtonText: String = "OK",
                                  cancelableOnTouchOutside: Boolean = true,
                                  cancelable: Boolean = true) {
        Log.d(TAG, "showMultiChoiceItemDialog called")

        if (multiChoiceItemDialogListener == null) {
            Log.w(TAG, "MultiChoiceItemDialogListener is not set")
        }

        val activity = context as? FragmentActivity
        if (activity != null) {
            try {
                AndroidDialogFragment.newInstance(title, multiChoiceItems, checkedItems, negativeButtonText, positiveButtonText, cancelableOnTouchOutside, cancelable).apply {
                    setMultiChoiceItemDialogListener(object : AndroidDialogFragment.MultiChoiceItemDialogListener {
                        override fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onMultiChoiceItemDialog called")
                            multiChoiceItemDialogListener?.onMultiChoiceItemDialog(buttonText, checkedItems, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to showMultiChoiceItemDialog: ${e.message}")
                multiChoiceItemDialogListener?.onMultiChoiceItemDialog(null, null, false, "Failed to showMultiChoiceItemDialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            multiChoiceItemDialogListener?.onMultiChoiceItemDialog(null, null, false, "Failed to cast context to FragmentActivity")
        }
    }

    /**
     * Show a text input dialog.
     * - enablePositiveButtonWhenEmpty=false disables OK while empty
     * - Cancel: inputText=null
     */
    fun showTextInputDialog(context: Context,
                            title: String,
                            message: String,
                            hint: String = "",
                            negativeButtonText: String = "Cancel",
                            positiveButtonText: String = "OK",
                            enablePositiveButtonWhenEmpty: Boolean = false,
                            cancelableOnTouchOutside: Boolean = true,
                            cancelable: Boolean = true) {
        Log.d(TAG, "showTextInputDialog called")

        if (textInputDialogListener == null) {
            Log.w(TAG, "TextInputDialogListener is not set")
        }

        val activity = context as? FragmentActivity
        if (activity != null) {
            try {
                AndroidDialogFragment.newInstance(title, message, hint, negativeButtonText, positiveButtonText, enablePositiveButtonWhenEmpty, cancelableOnTouchOutside, cancelable).apply {
                    setTextInputDialogListener(object : AndroidDialogFragment.TextInputDialogListener {
                        override fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onTextInputDialog called")
                            textInputDialogListener?.onTextInputDialog(buttonText, inputText, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to showTextInputDialog: ${e.message}")
                textInputDialogListener?.onTextInputDialog(null, null, false, "Failed to showTextInputDialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            textInputDialogListener?.onTextInputDialog(null, null, false, "Failed to cast context to FragmentActivity")
        }
    }

    /**
     * Show a login dialog (username + password).
     * - enablePositiveButtonWhenEmpty=false disables OK while either field empty
     * - Cancel: username/password null
     */
    fun showLoginDialog(context: Context,
                        title: String,
                        message: String,
                        usernameHint: String = "Username",
                        passwordHint: String = "Password",
                        negativeButtonText: String = "Cancel",
                        positiveButtonText: String = "Login",
                        enablePositiveButtonWhenEmpty: Boolean = false,
                        cancelableOnTouchOutside: Boolean = true,
                        cancelable: Boolean = true) {
        Log.d(TAG, "showLoginDialog called")

        if (loginDialogListener == null) {
            Log.w(TAG, "LoginDialogListener is not set")
        }

        val activity = context as? FragmentActivity
        if (activity != null) {
            try {
                AndroidDialogFragment.newInstance(title, message, usernameHint, passwordHint, negativeButtonText, positiveButtonText, enablePositiveButtonWhenEmpty, cancelableOnTouchOutside, cancelable).apply {
                    setLoginDialogListener(object : AndroidDialogFragment.LoginDialogListener {
                        override fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onLoginDialog called")
                            loginDialogListener?.onLoginDialog(buttonText, username, password, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to showLoginDialog: ${e.message}")
                loginDialogListener?.onLoginDialog(null, null, null, false, "Failed to showLoginDialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            loginDialogListener?.onLoginDialog(null, null, null, false, "Failed to cast context to FragmentActivity")
        }
    }
}
