package com.jonghyunkim.android.nativetoolkit.releaseprobe

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Records which activities were resumed, so that [ProbeActivity] can tell that the library's
 * transparent host was used.
 */
class ProbeApplication : Application() {

    override fun onCreate() {
        Log.d(TAG, "[onCreate]")
        super.onCreate()
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                Log.d(TAG, "[onActivityResumed] activity: ${activity.javaClass.name}")
                resumed += activity.javaClass.name
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
    }

    companion object {
        private const val TAG = "NtkProbeApp"

        /** The class names of the activities resumed in this process, in order. */
        val resumed = CopyOnWriteArrayList<String>()
    }
}
