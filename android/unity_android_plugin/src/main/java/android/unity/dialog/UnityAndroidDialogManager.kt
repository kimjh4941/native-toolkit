package android.unity.dialog

import android.content.Context
import android.library.dialog.AndroidDialogFragment
import android.util.Log
import androidx.fragment.app.FragmentActivity
import kotlin.Boolean

object UnityAndroidDialogManager {

    private const val TAG = "UnityAndroidDialogManager"

    private var dialogListener: DialogListener? = null
    private var confirmDialogListener: ConfirmDialogListener? = null
    private var singleChoiceItemDialogListener: SingleChoiceItemDialogListener? = null
    private var multiChoiceItemDialogListener: MultiChoiceItemDialogListener? = null
    private var textInputDialogListener: TextInputDialogListener? = null
    private var loginDialogListener: LoginDialogListener? = null

    interface DialogListener {
        fun onDialog(buttonText: String, isSuccessful: Boolean, errorMessage: String)
    }

    interface ConfirmDialogListener {
        fun onConfirmDialog(buttonText: String, isSuccessful: Boolean, errorMessage: String)
    }

    interface SingleChoiceItemDialogListener {
        fun onSingleChoiceItemDialog(buttonText: String, checkedItem: Int, isSuccessful: Boolean, errorMessage: String)
    }

    interface MultiChoiceItemDialogListener {
        fun onMultiChoiceItemDialog(buttonText: String, checkedItems: BooleanArray, isSuccessful: Boolean, errorMessage: String)
    }

    interface TextInputDialogListener {
        fun onTextInputDialog(buttonText: String, inputText: String, isSuccessful: Boolean, errorMessage: String)
    }

    interface LoginDialogListener {
        fun onLoginDialog(buttonText: String, username: String, password: String, isSuccessful: Boolean, errorMessage: String)
    }

    @JvmStatic
    fun getInstance(): UnityAndroidDialogManager {
        Log.d(TAG, "getInstance called")
        return this
    }

    fun setDialogListener(listener: DialogListener) {
        this.dialogListener = listener
    }

    fun setConfirmDialogListener(listener: ConfirmDialogListener) {
        this.confirmDialogListener = listener
    }

    fun setSingleChoiceItemDialogListener(listener: SingleChoiceItemDialogListener) {
        this.singleChoiceItemDialogListener = listener
    }

    fun setMultiChoiceItemDialogListener(listener: MultiChoiceItemDialogListener) {
        this.multiChoiceItemDialogListener = listener
    }

    fun setTextInputDialogListener(listener: TextInputDialogListener) {
        this.textInputDialogListener = listener
    }

    fun setLoginDialogListener(listener: LoginDialogListener) {
        this.loginDialogListener = listener
    }

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
                        override fun onDialog(dialog: AndroidDialogFragment, buttonText: String, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onDialog called")
                            dialogListener?.onDialog(buttonText, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to show dialog: ${e.message}")
                dialogListener?.onDialog(buttonText, false, "Failed to show dialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            dialogListener?.onDialog(buttonText, false, "Failed to cast context to FragmentActivity")
        }
    }

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
                        override fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onConfirmDialog called")
                            confirmDialogListener?.onConfirmDialog(buttonText, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to show confirm dialog: ${e.message}")
                confirmDialogListener?.onConfirmDialog("", false, "Failed to show confirm dialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            confirmDialogListener?.onConfirmDialog("", false, "Failed to cast context to FragmentActivity")
        }
    }

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
                        override fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String, checkedItem: Int, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onSingleChoiceItemDialog called")
                            singleChoiceItemDialogListener?.onSingleChoiceItemDialog(buttonText, checkedItem, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to show single choice dialog: ${e.message}")
                singleChoiceItemDialogListener?.onSingleChoiceItemDialog("", checkedItem, false, "Failed to show single choice dialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            singleChoiceItemDialogListener?.onSingleChoiceItemDialog("", checkedItem, false, "Failed to cast context to FragmentActivity")
        }
    }

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
                        override fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String, checkedItems: BooleanArray, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onMultiChoiceItemDialog called")
                            multiChoiceItemDialogListener?.onMultiChoiceItemDialog(buttonText, checkedItems, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to show multi choice dialog: ${e.message}")
                multiChoiceItemDialogListener?.onMultiChoiceItemDialog("", checkedItems, false, "Failed to show multi choice dialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            multiChoiceItemDialogListener?.onMultiChoiceItemDialog("", checkedItems, false, "Failed to cast context to FragmentActivity")
        }
    }

    fun showTextInputDialog(context: Context,
                            title: String,
                            message: String,
                            hint: String,
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
                        override fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String, inputText: String, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onTextInputDialog called")
                            textInputDialogListener?.onTextInputDialog(buttonText, inputText, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to show text input dialog: ${e.message}")
                textInputDialogListener?.onTextInputDialog("", "", false, "Failed to show text input dialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            textInputDialogListener?.onTextInputDialog("", "", false, "Failed to cast context to FragmentActivity")
        }
    }

    fun showLoginDialog(context: Context,
                        title: String,
                        message: String,
                        usernameHint: String,
                        passwordHint: String,
                        negativeButtonText: String = "Cancel",
                        positiveButtonText: String = "OK",
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
                        override fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String, username: String, password: String, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onLoginDialog called")
                            loginDialogListener?.onLoginDialog(buttonText, username, password, isSuccessful, errorMessage)
                        }
                    })
                    show(activity.supportFragmentManager, "AndroidDialogFragment")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to show login dialog: ${e.message}")
                loginDialogListener?.onLoginDialog("", "", "", false, "Failed to show login dialog: ${e.message}")
            }
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
            loginDialogListener?.onLoginDialog("", "", "", false, "Failed to cast context to FragmentActivity")
        }
    }
}
