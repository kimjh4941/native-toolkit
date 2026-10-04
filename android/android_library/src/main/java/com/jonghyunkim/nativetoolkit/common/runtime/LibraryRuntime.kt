package com.jonghyunkim.nativetoolkit.common.runtime

import android.app.Activity
import android.app.Application
import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.presentation.ForegroundActivityTracker

/**
 * Initializes the parts of the library that need the Application (Kotlin API design 8.1).
 *
 * [LibraryInitializer] calls [ensureInitialized] at app start through androidx.startup. Apps that
 * disable Startup call it themselves, for example from `Application.onCreate` or the first
 * Activity's `onCreate`. APIs that need the foreground Activity (dialogs, the notification
 * permission request) complete with `NOT_INITIALIZED` until this has succeeded; the other APIs
 * work without it, as before.
 */
object LibraryRuntime {

    private const val TAG = "com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime"

    /** The result of [ensureInitialized]. */
    enum class InitState {
        /** The library is initialized. */
        DONE,

        /** Another thread is initializing. Call again later; this call does not wait. */
        IN_PROGRESS,

        /** This call failed and undid its work. Calling again retries. */
        ERROR
    }

    private val state = InitializationState { listener -> MainPoster.post(listener) }

    @Volatile
    private var application: Application? = null

    /**
     * Initializes the library once per process. Never waits; safe from any thread and more than once.
     *
     * When [context] is an Activity, it is also taken as the foreground Activity, because an
     * Activity already on screen is not reported to callbacks registered late.
     *
     * @param context Any Context. Its application context is kept.
     * @return [InitState.DONE] when initialized, [InitState.IN_PROGRESS] when another thread is
     *   initializing, or [InitState.ERROR] when this call failed.
     */
    fun ensureInitialized(context: Context): InitState {
        Log.d(TAG, "[ensureInitialized] context: $context")
        if (context is Activity) {
            // Every caller seeds, winner or not, so that the Activity passed in is never lost.
            MainPoster.post { ForegroundActivityTracker.seed(context) }
        }
        when (state.tryBegin()) {
            InitializationState.Begin.DONE -> return InitState.DONE
            InitializationState.Begin.IN_PROGRESS -> return InitState.IN_PROGRESS
            InitializationState.Begin.WON -> Unit
        }
        var registeredOn: Application? = null
        return try {
            val app = context.applicationContext as? Application
                ?: throw IllegalStateException("The application context is not an Application: ${context.applicationContext}")
            app.registerActivityLifecycleCallbacks(ForegroundActivityTracker)
            registeredOn = app
            application = app
            state.succeed()
            InitState.DONE
        } catch (e: Exception) {
            Log.e(TAG, "[ensureInitialized] context: $context", e)
            registeredOn?.unregisterActivityLifecycleCallbacks(ForegroundActivityTracker)
            application = null
            state.fail()
            InitState.ERROR
        }
    }

    /**
     * Returns whether [ensureInitialized] has succeeded in this process.
     */
    fun isInitialized(): Boolean {
        Log.d(TAG, "[isInitialized]")
        return state.isDone()
    }

    /**
     * Runs [listener] once on the main thread after the library is initialized: soon if it already
     * is, otherwise when initialization succeeds. The C ABI uses this to learn that the Kotlin side
     * is ready (C ABI design 5.3).
     *
     * @param listener The function to run.
     */
    fun addOnInitializedListener(listener: () -> Unit) {
        Log.d(TAG, "[addOnInitializedListener] listener: $listener")
        state.addListener(listener)
    }

    /**
     * Returns the Application kept by [ensureInitialized], or `null` before it has succeeded.
     */
    internal fun applicationOrNull(): Application? {
        Log.d(TAG, "[applicationOrNull]")
        return application
    }
}
