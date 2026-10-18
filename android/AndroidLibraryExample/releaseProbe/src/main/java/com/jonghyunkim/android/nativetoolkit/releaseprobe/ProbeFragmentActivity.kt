package com.jonghyunkim.android.nativetoolkit.releaseprobe

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentManager
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager

/**
 * The checks across a process death on a FragmentActivity (Kotlin API design IT-03, IT-07): the
 * library's dialog or permission fragment is added here, the script kills the process from the
 * background and brings the task back, and the fragment the system restores must close without
 * showing or launching anything. Logs `RESULT <case> PASS|FAIL <detail>` like [ProbeActivity].
 */
class ProbeFragmentActivity : FragmentActivity() {

    private val main = Handler(Looper.getMainLooper())
    private val prefs by lazy { getSharedPreferences(ProbeActivity.PREFS, MODE_PRIVATE) }

    // The fragments the system recreated from saved state. The library closes a restored fragment
    // inside super.onCreate, so they are counted as they are created, not afterwards.
    private var restoredFragments = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] savedInstanceState: $savedInstanceState")
        supportFragmentManager.registerFragmentLifecycleCallbacks(object : FragmentManager.FragmentLifecycleCallbacks() {
            override fun onFragmentCreated(fm: FragmentManager, f: Fragment, savedInstanceState: Bundle?) {
                if (savedInstanceState != null) restoredFragments++
            }
        }, false)
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { text = "NTK probe fragment activity" })
        if (savedInstanceState != null) return
        when (val case = intent.getStringExtra(ProbeActivity.EXTRA_CASE)) {
            ProbeActivity.CASE_DIALOG_KILL -> main.postDelayed({ showDialog(case) }, 500)
            ProbeActivity.CASE_PERMISSION_KILL -> main.postDelayed({ requestPermission(case) }, 500)
            else -> report(case ?: "fragmentActivity", "FAIL", "unknown case")
        }
    }

    override fun onResume() {
        Log.d(TAG, "[onResume]")
        super.onResume()
        checkAfterKill()
    }

    private fun showDialog(case: String) {
        Log.d(TAG, "[showDialog] case: $case")
        AndroidDialogManager.getInstance(this).show(DialogRequest.Alert(title = KILL_DIALOG_TITLE, message = "Killed while shown")) { }
        main.postDelayed({
            if (supportFragmentManager.fragments.isEmpty()) return@postDelayed report(case, "FAIL", "no dialog fragment")
            expectAfterKill()
            report(case, "PASS", "shown on the FragmentActivity")
        }, 2_000)
    }

    private fun requestPermission(case: String) {
        Log.d(TAG, "[requestPermission] case: $case")
        val manager = AndroidNotificationManager.getInstance(this)
        if (manager.hasPermission()) return report(case, "FAIL", "the permission is granted")
        manager.requestPermission { Log.d(TAG, "[requestPermission] answer: $it") }
        main.postDelayed({
            if (supportFragmentManager.fragments.isEmpty()) return@postDelayed report(case, "FAIL", "no permission fragment")
            expectAfterKill()
            report(case, "PASS", "requested from a fragment")
        }, 2_500)
    }

    // The script kills the process next; the time tells the new process that it came after.
    private fun expectAfterKill() {
        prefs.edit().putBoolean(ProbeActivity.PREF_AFTER_KILL, true).putLong(ProbeActivity.PREF_KILLED_AT, System.currentTimeMillis()).commit()
    }

    // In the process started after the kill: the system restored the library's fragment here, and
    // it closed itself.
    private fun checkAfterKill() {
        val killedAt = prefs.getLong(ProbeActivity.PREF_KILLED_AT, Long.MAX_VALUE)
        if (!prefs.getBoolean(ProbeActivity.PREF_AFTER_KILL, false) || ProbeApplication.startedAt < killedAt) return
        Log.d(TAG, "[checkAfterKill] restoredFragments: $restoredFragments")
        prefs.edit().remove(ProbeActivity.PREF_AFTER_KILL).commit()
        main.postDelayed({
            val left = supportFragmentManager.fragments.size
            when {
                restoredFragments == 0 -> report(CASE_AFTER_KILL, "FAIL", "no fragment was restored")
                left != 0 -> report(CASE_AFTER_KILL, "FAIL", "$left fragment(s) left")
                else -> report(CASE_AFTER_KILL, "PASS", "the restored fragment closed")
            }
        }, 3_000)
    }

    private fun report(case: String, outcome: String, detail: String) {
        Log.i(TAG, "RESULT $case $outcome $detail")
    }

    companion object {
        private const val TAG = ProbeActivity.TAG
        const val CASE_AFTER_KILL = "afterKill"
        const val KILL_DIALOG_TITLE = "Probe kill dialog"
    }
}
