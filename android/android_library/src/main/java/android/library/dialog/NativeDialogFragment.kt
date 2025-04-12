package android.library.dialog

import android.app.AlertDialog
import android.app.Dialog
import android.os.Bundle
import android.util.Log
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.Fragment

/**
 * A simple [Fragment] subclass.
 * Use the [NativeDialogFragment.newInstance] factory method to
 * create an instance of this fragment.
 */
class NativeDialogFragment : DialogFragment() {
    private var title: String? = null
    private var message: String? = null
    private var listener: NativeDialogListener? = null

    interface NativeDialogListener {
        fun onClickDialogNeutralButton(dialog: NativeDialogFragment)
        fun onClickDialogNegativeButton(dialog: NativeDialogFragment)
        fun onClickDialogPositiveButton(dialog: NativeDialogFragment)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate")
        arguments?.let {
            title = it.getString(ARG_TITLE)
            message = it.getString(ARG_MESSAGE)
        }
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        Log.d(TAG, "onCreateDialog")
        return activity?.let {
            val builder = AlertDialog.Builder(it)
            builder
                .setTitle(title)
                .setMessage(message)
                .setNeutralButton("キャンセル") { dialog, id ->
                    Log.d(TAG, "NeutralButton Click")
                    listener?.onClickDialogNeutralButton(this)
                }
                .setNegativeButton("いいえ") { dialog, id ->
                    Log.d(TAG, "NegativeButton Click")
                    listener?.onClickDialogNegativeButton(this)
                }
                .setPositiveButton("はい") { dialog, id ->
                    Log.d(TAG, "PositiveButton Click")
                    listener?.onClickDialogPositiveButton(this)
                }
            return builder.create()
        } ?: throw IllegalStateException("Activity cannot be null")
    }

    fun setNativeDialogListener(listener: NativeDialogListener) {
        Log.d(TAG, "setNativeDialogListener")
        this.listener = listener
    }

//    override fun onCreateView(
//        inflater: LayoutInflater, container: ViewGroup?,
//        savedInstanceState: Bundle?
//    ): View? {
//        // Inflate the layout for this fragment
//        return inflater.inflate(R.layout.fragment_native_dialog, container, false)
//    }

    companion object {
        private const val TAG = "NativeDialogFragment"
        private const val ARG_TITLE = "title"
        private const val ARG_MESSAGE = "message"

        /**
         * Use this factory method to create a new instance of
         * this fragment using the provided parameters.
         *
         * @param title Parameter 1.
         * @param message Parameter 2.
         * @return A new instance of fragment NativeDialogFragment.
         */
        @JvmStatic
        fun newInstance(title: String, message: String) =
            NativeDialogFragment().apply {
                Log.d(TAG, "newInstance")
                arguments = Bundle().apply {
                    putString(ARG_TITLE, title)
                    putString(ARG_MESSAGE, message)
                }
            }
    }
}
