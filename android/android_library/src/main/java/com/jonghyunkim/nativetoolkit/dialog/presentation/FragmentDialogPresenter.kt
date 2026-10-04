package com.jonghyunkim.nativetoolkit.dialog.presentation

import android.util.Log
import androidx.fragment.app.FragmentActivity
import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason
import com.jonghyunkim.nativetoolkit.common.presentation.UiHost
import com.jonghyunkim.nativetoolkit.common.presentation.UiHostClient
import com.jonghyunkim.nativetoolkit.common.presentation.UiRequestGate
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogFragment
import com.jonghyunkim.nativetoolkit.dialog.application.port.DialogPresenter
import com.jonghyunkim.nativetoolkit.dialog.domain.error.DialogError
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import java.lang.ref.WeakReference

/**
 * Shows dialogs as [AndroidDialogFragment] on the foreground FragmentActivity or the transparent
 * host (Kotlin API design 8.3, 8.8).
 *
 * Every result goes through [UiRequestGate], so each request completes exactly once. The state
 * below is touched on the main thread only.
 */
internal object FragmentDialogPresenter : DialogPresenter {

    private const val TAG = "com.jonghyunkim.nativetoolkit.dialog.presentation.FragmentDialogPresenter"

    private class Pending(val request: DialogRequest, val onResult: (DialogResult) -> Unit) {
        var fragment: WeakReference<AndroidDialogFragment>? = null
    }

    private val pending = HashMap<Long, Pending>()
    private val gate: UiRequestGate get() = UiRequestGate.shared

    override fun show(requestId: Long, request: DialogRequest, onResult: (DialogResult) -> Unit) {
        Log.d(TAG, "[show] requestId: $requestId, request: $request, onResult: $onResult")
        MainPoster.post {
            gate.open(requestId)
            pending[requestId] = Pending(request, onResult)
            UiHost.acquire(Client(requestId))
        }
    }

    override fun cancel(requestId: Long) {
        Log.d(TAG, "[cancel] requestId: $requestId")
        MainPoster.post {
            val entry = pending[requestId] ?: return@post
            entry.fragment?.get()?.dismissAllowingStateLoss()
            complete(requestId, DialogResult.Canceled(CancelReason.REQUESTED))
        }
    }

    /**
     * Delivers [result] when [requestId] has not completed yet. Main thread only.
     *
     * @param requestId The request ID.
     * @param result The result.
     */
    fun complete(requestId: Long, result: DialogResult) {
        Log.d(TAG, "[complete] requestId: $requestId, result: $result")
        if (!gate.tryComplete(requestId)) return
        val entry = pending.remove(requestId) ?: return
        try {
            entry.onResult(result)
        } catch (e: Exception) {
            Log.e(TAG, "[complete] requestId: $requestId", e)
        }
    }

    /**
     * Called by the fragment of [requestId] when it is created, including after a configuration
     * change. Main thread only.
     *
     * @param requestId The request ID.
     * @param fragment The fragment.
     * @return `false` when the request is no longer active (the fragment then closes itself).
     */
    fun attach(requestId: Long, fragment: AndroidDialogFragment): Boolean {
        Log.d(TAG, "[attach] requestId: $requestId, fragment: $fragment")
        val entry = pending[requestId] ?: return false
        if (!gate.isActive(requestId)) return false
        entry.fragment = WeakReference(fragment)
        return true
    }

    /**
     * Called by the fragment of [requestId] when it is destroyed for good. Main thread only.
     *
     * @param requestId The request ID.
     * @param fragment The fragment.
     */
    fun detach(requestId: Long, fragment: AndroidDialogFragment) {
        Log.d(TAG, "[detach] requestId: $requestId, fragment: $fragment")
        val entry = pending[requestId] ?: return
        if (entry.fragment?.get() === fragment) entry.fragment = null
    }

    private class Client(private val requestId: Long) : UiHostClient<FragmentActivity> {

        override fun isActive(): Boolean = gate.isActive(requestId)

        override fun onReady(host: FragmentActivity) {
            Log.d(TAG, "[onReady] requestId: $requestId, host: $host")
            val entry = pending[requestId] ?: return
            val fragment = AndroidDialogFragment.newRequestInstance(requestId, entry.request)
            try {
                // showNow commits synchronously, so the host never sees a gap without the fragment.
                fragment.showNow(host.supportFragmentManager, "${UiHost.FRAGMENT_TAG_PREFIX}dialog.$requestId")
            } catch (e: IllegalStateException) {
                Log.e(TAG, "[onReady] requestId: $requestId", e)
                complete(requestId, DialogResult.Failed(DialogError.NOT_FOREGROUND))
                UiHost.onLibraryFragmentGone(host)
            } catch (e: Exception) {
                Log.e(TAG, "[onReady] requestId: $requestId", e)
                complete(requestId, DialogResult.Failed(DialogError.SHOW_FAILED))
                UiHost.onLibraryFragmentGone(host)
            }
        }

        override fun onUnavailable(reason: UiUnavailableReason) {
            Log.d(TAG, "[onUnavailable] requestId: $requestId, reason: $reason")
            complete(requestId, DialogResult.Failed(DialogError.from(reason)))
        }
    }
}
