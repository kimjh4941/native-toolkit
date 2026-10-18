package com.jonghyunkim.nativetoolkit.common.presentation

import android.app.Activity
import android.app.ActivityOptions
import android.content.Intent
import android.util.Log
import androidx.fragment.app.FragmentActivity
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster

/**
 * The process-wide UI host (Kotlin API design 8.3). Main thread only.
 */
internal object UiHost {

    private const val TAG = "com.jonghyunkim.nativetoolkit.common.presentation.UiHost"

    /** Fragment tags of library fragments start with this, so that the host can tell when it is idle. */
    const val FRAGMENT_TAG_PREFIX: String = "ntk."

    private val core = UiHostCore(AndroidEnvironment)

    /**
     * See [UiHostCore.acquire].
     *
     * @param client The request.
     */
    fun acquire(client: UiHostClient<FragmentActivity>) {
        Log.d(TAG, "[acquire] client: $client")
        MainPoster.checkMainThread("UiHost.acquire")
        core.acquire(client)
    }

    /**
     * See [UiHostCore.onHostCreated].
     *
     * @param host The host.
     * @param token The token the host was started with.
     */
    fun onHostCreated(host: FragmentActivity, token: Long): Boolean {
        Log.d(TAG, "[onHostCreated] host: $host, token: $token")
        MainPoster.checkMainThread("UiHost.onHostCreated")
        return core.onHostCreated(host, token)
    }

    /**
     * Called by a library fragment that is going away for good. When it lived in the transparent
     * host, the host finishes once no library fragment is left.
     *
     * @param activity The fragment's Activity, if any.
     */
    fun onLibraryFragmentGone(activity: Activity?) {
        Log.d(TAG, "[onLibraryFragmentGone] activity: $activity")
        val host = activity as? NtkHostActivity ?: return
        MainPoster.post { host.finishIfIdle() }
    }

    private object AndroidEnvironment : UiHostEnvironment<FragmentActivity, Activity> {
        override fun isInitialized(): Boolean = LibraryRuntime.isInitialized()

        override fun currentActivity(): Activity? {
            Log.d(TAG, "[currentActivity]")
            return ForegroundActivityTracker.current()
        }

        override fun currentHost(): FragmentActivity? {
            Log.d(TAG, "[currentHost]")
            return ForegroundActivityTracker.currentFragmentActivity()
        }

        override fun isSavedFragmentActivity(activity: Activity): Boolean {
            Log.d(TAG, "[isSavedFragmentActivity] activity: $activity")
            return (activity as? FragmentActivity)?.supportFragmentManager?.isStateSaved == true
        }

        override fun launchHost(from: Activity, token: Long) {
            Log.d(TAG, "[launchHost] from: $from, token: $token")
            val intent = Intent(from, NtkHostActivity::class.java)
                .putExtra(NtkHostActivity.EXTRA_TOKEN, token)
            // Start without NEW_TASK so that the host joins the foreground Activity's task.
            from.startActivity(intent, ActivityOptions.makeCustomAnimation(from, 0, 0).toBundle())
        }

        override fun postDelayed(delayMillis: Long, runnable: Runnable) {
            Log.d(TAG, "[postDelayed] delayMillis: $delayMillis, runnable: $runnable")
            MainPoster.postDelayed(delayMillis, runnable)
        }

        override fun cancel(runnable: Runnable) {
            Log.d(TAG, "[cancel] runnable: $runnable")
            MainPoster.cancel(runnable)
        }
    }
}
