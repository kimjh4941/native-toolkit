package android.unity.dialog

import android.content.Context
import android.library.dialog.NativeDialogFragment
import android.util.Log
import androidx.fragment.app.FragmentActivity

object NativeDialog {
    private const val TAG = "NativeDialog"

    @JvmStatic
    fun showDialog(context: Context, title: String, message: String) {
        Log.d(TAG, "showDialog called")
        val activity = context as? FragmentActivity
        if (activity != null) {
            val dialog = NativeDialogFragment.Companion.newInstance(title, message)
            dialog.setNativeDialogListener(object : NativeDialogFragment.NativeDialogListener {
                override fun onClickDialogNeutralButton(dialog: NativeDialogFragment) {
                    Log.d(TAG, "onClickDialogNeutralButton called")
                }

                override fun onClickDialogNegativeButton(dialog: NativeDialogFragment) {
                    Log.d(TAG, "onClickDialogNegativeButton called")
                }

                override fun onClickDialogPositiveButton(dialog: NativeDialogFragment) {
                    Log.d(TAG, "onClickDialogPositiveButton called")
                }
            })
            dialog.show(activity.supportFragmentManager, "NativeDialogFragment")
        } else {
            Log.e(TAG, "Failed to cast context to FragmentActivity")
        }
    }
}