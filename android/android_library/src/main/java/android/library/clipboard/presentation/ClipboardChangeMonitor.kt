package android.library.clipboard.presentation

import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Owns the system [ClipboardManager.OnPrimaryClipChangedListener] registration for clipboard
 * change observation.
 *
 * This class is the single owner of the system listener (common.md: a system Delegate/Listener is
 * owned by exactly one class, never by RepositoryImpl and never by a Unity-Bridge-only class).
 * It lives in the native library so that native consumers — the native sample app, other native
 * callers — can observe clipboard changes without depending on the Unity plugin. The Unity bridge
 * (`UnityAndroidClipboardManager`) delegates to this class rather than owning its own listener.
 *
 * The Data layer (`ClipboardRepositoryImpl`) intentionally holds no listener; it covers only the
 * synchronous copy/read/metadata/clear operations.
 *
 * Note: Android 10+ (API 29+) restricts clipboard reads to the foreground app or the default IME,
 * so observation is only reliable while the app is in the foreground.
 */
class ClipboardChangeMonitor {

    private var clipboardManager: ClipboardManager? = null
    private var systemListener: ClipboardManager.OnPrimaryClipChangedListener? = null

    /**
     * Starts observing clipboard changes. A second call while already observing is a no-op
     * (no duplicate system listener registration).
     *
     * @param context Android context.
     * @param onChange Called on the system listener's callback thread when the clipboard changes.
     *   Callers that update UI state must marshal to the main thread themselves.
     */
    fun start(context: Context, onChange: () -> Unit) {
        Log.d(TAG, "[start] context: $context")
        if (systemListener != null) {
            Log.d(TAG, "[start] already observing, ignoring duplicate start")
            return
        }
        val manager = ContextCompat.getSystemService(context.applicationContext, ClipboardManager::class.java)
        if (manager == null) {
            Log.w(TAG, "[start] ClipboardManager is unavailable")
            return
        }
        val listener = ClipboardManager.OnPrimaryClipChangedListener { onChange() }
        manager.addPrimaryClipChangedListener(listener)
        clipboardManager = manager
        systemListener = listener
    }

    /**
     * Stops observing clipboard changes. A no-op if not currently observing.
     */
    fun stop() {
        Log.d(TAG, "[stop]")
        val manager = clipboardManager
        val listener = systemListener
        if (manager != null && listener != null) {
            manager.removePrimaryClipChangedListener(listener)
        }
        clipboardManager = null
        systemListener = null
    }

    /**
     * Returns whether observation is currently active.
     */
    fun isObserving(): Boolean = systemListener != null

    private companion object {
        private const val TAG = "android.library.clipboard.presentation.ClipboardChangeMonitor"
    }
}
