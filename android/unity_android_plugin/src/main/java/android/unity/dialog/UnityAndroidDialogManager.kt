package android.unity.dialog

import android.content.Context
import android.library.dialog.AndroidDialogFragment
import android.util.Log
import androidx.fragment.app.FragmentActivity

object UnityAndroidDialogManager {
    private const val TAG = "NativeDialogManager"

    private var callback: NativeDialogManagerCallback? = null

    interface NativeDialogManagerCallback {
        fun onClickDialogNeutralButton(message: String)
        fun onClickDialogNegativeButton(message: String)
        fun onClickDialogPositiveButton(message: String)
    }

    @JvmStatic
    fun getInstance(): UnityAndroidDialogManager {
        Log.d(TAG, "getInstance called")
        return this
    }

    fun registerCallback(callback: NativeDialogManagerCallback) {
        Log.d(TAG, "registerCallback called")
        this.callback = callback
    }

    fun showDialog(context: Context, title: String, message: String) {
        Log.d(TAG, "showDialog called")
        val activity = context as? FragmentActivity
        if (activity != null) {
            val dialog = AndroidDialogFragment.newInstance(title, message)
            dialog.setNativeDialogListener(object : AndroidDialogFragment.NativeDialogListener {
                override fun onClickDialogNeutralButton(dialog: AndroidDialogFragment) {
                    Log.d(TAG, "onClickDialogNeutralButton called")
                    callback?.onClickDialogNeutralButton("callback 1")
                }

                override fun onClickDialogNegativeButton(dialog: AndroidDialogFragment) {
                    Log.d(TAG, "onClickDialogNegativeButton called")
                    callback?.onClickDialogNegativeButton("callback 2")
                }

                override fun onClickDialogPositiveButton(dialog: AndroidDialogFragment) {
                    Log.d(TAG, "onClickDialogPositiveButton called")
                    callback?.onClickDialogPositiveButton("callback 3")
                }
            })
            dialog.show(activity.supportFragmentManager, "NativeDialogFragment")
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
        }
    }
}
