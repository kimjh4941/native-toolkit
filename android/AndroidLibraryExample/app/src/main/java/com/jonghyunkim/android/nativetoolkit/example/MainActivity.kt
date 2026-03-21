package com.jonghyunkim.android.nativetoolkit.example

import android.library.dialog.AndroidDialogFragment
import android.library.notification.presentation.permission.NotificationPermissionHelper
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import com.jonghyunkim.android.nativetoolkit.example.ui.theme.AndroidTheme

class MainActivity : AppCompatActivity() {

    private lateinit var notificationPermissionHelper: NotificationPermissionHelper

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "[onCreate]")
        notificationPermissionHelper = NotificationPermissionHelper(this)
        title = "Native Toolkit Example"
        enableEdgeToEdge()
        setContent {
            AndroidTheme {
                AppRouter(
                    activity = this,
                    permissionHelper = notificationPermissionHelper
                )
            }
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
