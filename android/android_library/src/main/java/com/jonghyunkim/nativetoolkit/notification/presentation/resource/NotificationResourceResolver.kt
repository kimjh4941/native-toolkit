package com.jonghyunkim.nativetoolkit.notification.presentation.resource

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * Finds the app's resources by name, for callers that only know names (the C ABI, Unity)
 * (Kotlin API design 8.5; moved from the Unity bridge).
 *
 * Resources referenced only by name may be removed by the app's resource shrinking. Keep them with
 * `tools:keep` (see the manual).
 *
 * @param context Any Context. Its application context is kept.
 */
class NotificationResourceResolver(context: Context) {

    private val appContext = context.applicationContext
    private val cache = ConcurrentHashMap<String, Int>()

    /**
     * Returns the resource ID of [name], or `null` when there is none.
     *
     * @param name The resource name, for example `ic_notification`.
     * @param type `drawable`, `mipmap`, `layout` or `id`. `null` or blank tries `drawable`, then `mipmap`.
     */
    fun resolve(name: String, type: String? = null): Int? {
        Log.d(TAG, "[resolve] name: $name, type: $type")
        val explicitType = type?.trim()?.takeIf { it.isNotEmpty() }
        if (explicitType != null) return lookUp(name, explicitType)
        return DEFAULT_TYPES.firstNotNullOfOrNull { lookUp(name, it) }
    }

    /**
     * Returns the app icon, or `android.R.drawable.ic_dialog_info` when the app has none.
     */
    fun defaultSmallIcon(): Int {
        Log.d(TAG, "[defaultSmallIcon]")
        return appContext.applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_dialog_info
    }

    // getIdentifier searches the compiled resource table, so it works with transitive and
    // non-transitive R classes alike (resources of a Unity library module included).
    @SuppressLint("DiscouragedApi")
    private fun lookUp(name: String, type: String): Int? {
        if (type !in SUPPORTED_TYPES) return null
        val id = cache.getOrPut("$type:$name") {
            appContext.resources.getIdentifier(name, type, appContext.packageName)
        }
        return id.takeIf { it != 0 }
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.presentation.resource.NotificationResourceResolver"
        private val SUPPORTED_TYPES = setOf("drawable", "mipmap", "layout", "id")
        private val DEFAULT_TYPES = listOf("drawable", "mipmap")
    }
}
