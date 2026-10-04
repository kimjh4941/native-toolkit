package com.jonghyunkim.nativetoolkit.common.presentation

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import androidx.annotation.MainThread
import androidx.annotation.RestrictTo
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster
import java.util.WeakHashMap

/**
 * Tracks the foreground Activity (Kotlin API design 8.2, C ABI design 5.8).
 *
 * The foreground Activity is one that is started, not yet stopped, has not saved its instance
 * state, and is not finishing. When there are several, the one started last wins.
 * [com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime] registers this object.
 * Everything here runs on the main thread.
 */
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)
object ForegroundActivityTracker : Application.ActivityLifecycleCallbacks {

    private const val TAG = "com.jonghyunkim.nativetoolkit.common.presentation.ForegroundActivityTracker"

    private class Record(
        var started: Boolean = false,
        var stopped: Boolean = false,
        var stateSaved: Boolean = false,
        var order: Long = 0L
    )

    private val records = WeakHashMap<Activity, Record>()
    private var nextOrder = 0L

    /**
     * Returns the foreground Activity, or `null` when no Activity of the app is in the foreground.
     */
    @MainThread
    fun current(): Activity? {
        Log.d(TAG, "[current]")
        MainPoster.checkMainThread("ForegroundActivityTracker.current")
        return records.entries
            .filter { (activity, record) ->
                record.started && !record.stopped && !record.stateSaved && !activity.isFinishing
            }
            .maxByOrNull { it.value.order }
            ?.key
    }

    /**
     * Returns the foreground Activity when it is a [FragmentActivity] whose FragmentManager can
     * still commit, otherwise `null`.
     */
    @MainThread
    fun currentFragmentActivity(): FragmentActivity? {
        Log.d(TAG, "[currentFragmentActivity]")
        val activity = current() as? FragmentActivity ?: return null
        return activity.takeUnless { it.supportFragmentManager.isStateSaved }
    }

    /**
     * Takes [activity] as the foreground Activity when no lifecycle callback has reported it yet.
     *
     * Manual initialization calls this with the Activity it was given, because callbacks
     * registered late miss the Activity that is already on screen (README D-4). State already
     * received through callbacks wins.
     *
     * @param activity The Activity passed to manual initialization.
     */
    @MainThread
    internal fun seed(activity: Activity) {
        Log.d(TAG, "[seed] activity: $activity")
        MainPoster.checkMainThread("ForegroundActivityTracker.seed")
        if (records.containsKey(activity) || activity.isFinishing || activity.isDestroyed) return
        if (activity is LifecycleOwner &&
            !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
        ) {
            return
        }
        records[activity] = Record(started = true, order = ++nextOrder)
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        Log.d(TAG, "[onActivityCreated] activity: $activity, savedInstanceState: $savedInstanceState")
    }

    override fun onActivityStarted(activity: Activity) {
        Log.d(TAG, "[onActivityStarted] activity: $activity")
        val record = records.getOrPut(activity) { Record() }
        record.started = true
        record.stopped = false
        record.stateSaved = false
        record.order = ++nextOrder
    }

    override fun onActivityResumed(activity: Activity) {
        Log.d(TAG, "[onActivityResumed] activity: $activity")
    }

    override fun onActivityPaused(activity: Activity) {
        Log.d(TAG, "[onActivityPaused] activity: $activity")
    }

    override fun onActivityStopped(activity: Activity) {
        Log.d(TAG, "[onActivityStopped] activity: $activity")
        records[activity]?.stopped = true
    }

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {
        Log.d(TAG, "[onActivitySaveInstanceState] activity: $activity, outState: $outState")
        records[activity]?.stateSaved = true
    }

    override fun onActivityDestroyed(activity: Activity) {
        Log.d(TAG, "[onActivityDestroyed] activity: $activity")
        records.remove(activity)
    }
}
