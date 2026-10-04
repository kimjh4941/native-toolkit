package com.jonghyunkim.nativetoolkit.notification.presentation.permission

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import com.jonghyunkim.nativetoolkit.common.presentation.UiHost
import com.jonghyunkim.nativetoolkit.common.presentation.UiHostClient
import com.jonghyunkim.nativetoolkit.common.presentation.UiRequestGate
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationPermissionPort
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult

/**
 * Requests the notification permission without an Activity from the caller (Kotlin API design 8.7).
 *
 * The request runs on the foreground FragmentActivity or the transparent host, through a fragment
 * with no UI that registers for the Activity Result before it is created (the registration-time
 * rule of the Activity Result API).
 *
 * @param appContext The Application Context, used only for the "already granted" check.
 */
internal class FragmentPermissionRequester private constructor(
    private val appContext: Context
) : NotificationPermissionPort {

    override fun request(requestId: Long, onResult: (PermissionRequestResult) -> Unit) {
        Log.d(TAG, "[request] requestId: $requestId, onResult: $onResult")
        MainPoster.post { sessions(appContext).request(requestId, onResult) }
    }

    override fun cancel(requestId: Long) {
        Log.d(TAG, "[cancel] requestId: $requestId")
        MainPoster.post { sessions(appContext).cancel(requestId) }
    }

    private class Environment(private val appContext: Context) : PermissionEnvironment<FragmentActivity> {
        override fun isGrantedOrNotNeeded(): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(appContext, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED

        override fun isInitialized(): Boolean = LibraryRuntime.isInitialized()

        override fun acquire(client: UiHostClient<FragmentActivity>) {
            UiHost.acquire(client)
        }

        override fun addFragment(host: FragmentActivity, sessionId: Long) {
            Log.d(TAG, "[addFragment] host: $host, sessionId: $sessionId")
            host.supportFragmentManager.beginTransaction()
                .add(PermissionRequestFragment.newInstance(sessionId), "${UiHost.FRAGMENT_TAG_PREFIX}permission.$sessionId")
                .commitNow()
        }

        override fun isStateSaved(error: Exception): Boolean = error is IllegalStateException
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.presentation.permission.FragmentPermissionRequester"

        @Volatile
        private var instance: FragmentPermissionRequester? = null
        private var sessions: PermissionSessions<FragmentActivity>? = null

        /**
         * Returns the process-wide requester.
         *
         * @param context Any Context. Its application context is kept.
         */
        fun get(context: Context): FragmentPermissionRequester {
            Log.d(TAG, "[get] context: $context")
            return instance ?: synchronized(this) {
                instance ?: FragmentPermissionRequester(context.applicationContext).also { instance = it }
            }
        }

        /** The sessions. Main thread only. */
        internal fun sessions(appContext: Context): PermissionSessions<FragmentActivity> {
            Log.d(TAG, "[sessions] appContext: $appContext")
            return sessions ?: PermissionSessions(Environment(appContext), UiRequestGate.shared).also { sessions = it }
        }
    }
}

/**
 * A fragment with no UI that shows the system permission dialog once (Kotlin API design 8.7).
 */
internal class PermissionRequestFragment : Fragment() {

    private var launched = false
    private var orphan = false
    private lateinit var launcher: ActivityResultLauncher<String>

    private val sessionId: Long get() = requireArguments().getLong(ARG_SESSION_ID)

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] savedInstanceState: $savedInstanceState")
        super.onCreate(savedInstanceState)
        launched = savedInstanceState?.getBoolean(STATE_LAUNCHED) ?: false
        // Registered here, before the fragment is created, as the Activity Result API requires.
        // After a rotation the registry hands a pending answer to this new instance.
        launcher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            Log.d(TAG, "[onActivityResult] sessionId: $sessionId, granted: $granted")
            sessions().onResult(sessionId, granted)
            removeSelf()
        }
        if (!sessions().isCurrent(sessionId)) {
            // Restored after the process died: no request waits for this fragment.
            orphan = true
            removeSelf()
        }
    }

    override fun onStart() {
        Log.d(TAG, "[onStart]")
        super.onStart()
        if (!orphan && !launched) {
            launched = true
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        Log.d(TAG, "[onSaveInstanceState] outState: $outState")
        super.onSaveInstanceState(outState)
        outState.putBoolean(STATE_LAUNCHED, launched)
    }

    override fun onDestroy() {
        Log.d(TAG, "[onDestroy]")
        val hostActivity = activity
        super.onDestroy()
        if (hostActivity?.isChangingConfigurations != true) {
            if (!orphan) sessions().onFragmentDestroyed(sessionId)
            UiHost.onLibraryFragmentGone(hostActivity)
        }
    }

    private fun sessions(): PermissionSessions<FragmentActivity> =
        FragmentPermissionRequester.sessions(requireContext().applicationContext)

    private fun removeSelf() {
        if (isAdded) parentFragmentManager.beginTransaction().remove(this).commitAllowingStateLoss()
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.presentation.permission.PermissionRequestFragment"
        private const val ARG_SESSION_ID = "session_id"
        private const val STATE_LAUNCHED = "launched"

        /**
         * Creates the fragment for [sessionId].
         *
         * @param sessionId The session ID.
         */
        fun newInstance(sessionId: Long): PermissionRequestFragment {
            Log.d(TAG, "[newInstance] sessionId: $sessionId")
            return PermissionRequestFragment().apply {
                arguments = Bundle().apply { putLong(ARG_SESSION_ID, sessionId) }
            }
        }
    }
}
