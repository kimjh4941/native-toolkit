package com.jonghyunkim.android.nativetoolkit.example

import android.content.Intent
import android.library.notification.presentation.permission.NotificationPermissionHelper
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import com.jonghyunkim.android.nativetoolkit.example.ui.theme.AndroidTheme

/** Hosts the native-toolkit sample screens and receives incoming share intents. */
class MainActivity : AppCompatActivity() {

    private lateinit var notificationPermissionHelper: NotificationPermissionHelper

    /** Received share content; updated on receipt and observed by Compose to navigate to the received screen. */
    var receivedShare by mutableStateOf<ReceivedShareContent?>(null)
        private set

    // testTagsAsResourceId is still experimental in the Compose version this sample uses.
    @OptIn(ExperimentalComposeUiApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] intent: $intent")
        super.onCreate(savedInstanceState)
        notificationPermissionHelper = NotificationPermissionHelper(this)
        title = "Native Toolkit Example"
        enableEdgeToEdge()
        handleIncomingShare(intent)
        setContent {
            AndroidTheme {
                // Expose Compose test tags as resource IDs so UiAutomator can find them too.
                Box(modifier = Modifier.semantics { testTagsAsResourceId = true }) {
                    AppRouter(
                        activity = this@MainActivity,
                        permissionHelper = notificationPermissionHelper
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        Log.d(TAG, "[onNewIntent] intent: $intent")
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingShare(intent)
    }

    /** Parses the received intent and updates receivedShare when it is a share. */
    private fun handleIncomingShare(intent: Intent?) {
        Log.d(TAG, "[handleIncomingShare] intent: $intent")
        val received = IncomingShareParser.parse(intent)
        if (received != null) {
            receivedShare = received
        }
    }

    private fun consumeCurrentShareIntent() {
        Log.d(TAG, "[consumeCurrentShareIntent]")
        setIntent(
            Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
            }
        )
    }

    /** Clears the received content after it has been shown (called when leaving the received screen). */
    fun clearReceivedShare() {
        Log.d(TAG, "[clearReceivedShare]")
        receivedShare = null
        consumeCurrentShareIntent()
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
