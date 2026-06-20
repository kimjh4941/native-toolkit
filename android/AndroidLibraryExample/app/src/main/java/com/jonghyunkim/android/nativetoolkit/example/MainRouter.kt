package com.jonghyunkim.android.nativetoolkit.example

import android.library.notification.presentation.permission.NotificationPermissionHelper
import android.util.Log
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier

private const val MAIN_ROUTER_TAG = "MainRouter"

private enum class MainScreen {
    MAIN_MENU,
    ANDROID_DIALOG_TEST,
    NOTIFICATION_TEST,
    SHARE_TEST,
    RECEIVED_SHARE
}

/**
 * Routes between the sample app screens and opens received share content automatically.
 *
 * @param activity Host activity that owns received share state.
 * @param permissionHelper Notification permission helper used by the notification sample.
 */
@Composable
fun AppRouter(
    activity: MainActivity,
    permissionHelper: NotificationPermissionHelper
) {
    Log.d(MAIN_ROUTER_TAG, "[AppRouter] activity: $activity, permissionHelper: $permissionHelper")
    var currentScreen by rememberSaveable { mutableStateOf(MainScreen.MAIN_MENU) }
    var dialogResultText by rememberSaveable { mutableStateOf("Result will be displayed here") }

    val received = activity.receivedShare
    LaunchedEffect(received) {
        if (received != null) {
            currentScreen = MainScreen.RECEIVED_SHARE
        }
    }

    BackHandler(enabled = currentScreen != MainScreen.MAIN_MENU) {
        if (currentScreen == MainScreen.RECEIVED_SHARE) {
            activity.clearReceivedShare()
        }
        currentScreen = MainScreen.MAIN_MENU
    }

    Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
        when (currentScreen) {
            MainScreen.MAIN_MENU -> {
                MainMenuScreen(
                    modifier = Modifier.padding(innerPadding),
                    onSelectDialogTest = { currentScreen = MainScreen.ANDROID_DIALOG_TEST },
                    onSelectNotificationTest = { currentScreen = MainScreen.NOTIFICATION_TEST },
                    onSelectShareTest = { currentScreen = MainScreen.SHARE_TEST }
                )
            }

            MainScreen.ANDROID_DIALOG_TEST -> {
                AndroidDialogFragmentTestScreen(
                    modifier = Modifier.padding(innerPadding),
                    resultText = dialogResultText,
                    onBack = { currentScreen = MainScreen.MAIN_MENU },
                    onButtonClick = { buttonType ->
                        activity.handleAndroidDialogTestButtonClick(buttonType) { updatedText ->
                            dialogResultText = updatedText
                        }
                    }
                )
            }

            MainScreen.NOTIFICATION_TEST -> {
                NotificationSampleScreen(
                    modifier = Modifier.padding(innerPadding),
                    activity = activity,
                    permissionHelper = permissionHelper,
                    onBack = { currentScreen = MainScreen.MAIN_MENU }
                )
            }

            MainScreen.SHARE_TEST -> {
                ShareSampleScreen(
                    modifier = Modifier.padding(innerPadding),
                    activity = activity,
                    onBack = { currentScreen = MainScreen.MAIN_MENU }
                )
            }

            MainScreen.RECEIVED_SHARE -> {
                ReceivedShareScreen(
                    modifier = Modifier.padding(innerPadding),
                    content = activity.receivedShare,
                    onBack = {
                        activity.clearReceivedShare()
                        currentScreen = MainScreen.MAIN_MENU
                    }
                )
            }
        }
    }
}
