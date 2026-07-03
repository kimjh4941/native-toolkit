package android.unity.share

import android.util.Log

/** Normalizes chooser action inputs into the set of action strings to register. */
internal object ShareChooserActionInputs {

    private const val TAG = "android.unity.share.ShareChooserActionInputs"
    private const val DEFAULT_SEND_ACTION = "android.intent.action.SEND"

    /**
     * Returns distinct, non-blank action strings extracted from [actions].
     * Emits a warning when the default SEND action is present,
     * as it is not a reliable callback identifier.
     */
    fun normalizeActionIds(actions: List<UnityChooserActionSpec>): List<String> {
        Log.d(TAG, "[normalizeActionIds] actions.size: ${actions.size}")
        val ids = actions.map { it.intentAction }.filter { it.isNotBlank() && it != DEFAULT_SEND_ACTION }
        val sendCount = actions.count { it.intentAction == DEFAULT_SEND_ACTION }
        if (sendCount > 0) {
            Log.w(TAG, "[normalizeActionIds] $sendCount action(s) with SEND intentAction excluded: not a reliable callback identifier")
        }
        return ids.distinct()
    }
}
