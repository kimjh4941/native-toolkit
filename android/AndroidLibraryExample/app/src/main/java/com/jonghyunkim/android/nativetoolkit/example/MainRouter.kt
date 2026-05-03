package com.jonghyunkim.android.nativetoolkit.example

import android.library.notification.presentation.permission.NotificationPermissionHelper
import androidx.activity.compose.BackHandler
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier

private enum class MainScreen {
    MAIN_MENU,
    ANDROID_DIALOG_TEST,
    NOTIFICATION_TEST
}

@Composable
fun AppRouter(
    activity: AppCompatActivity,
    permissionHelper: NotificationPermissionHelper
) {
    var currentScreen by rememberSaveable { mutableStateOf(MainScreen.MAIN_MENU) }
    var dialogResultText by rememberSaveable { mutableStateOf("Result will be displayed here") }

    BackHandler(enabled = currentScreen != MainScreen.MAIN_MENU) {
        currentScreen = MainScreen.MAIN_MENU
    }

    Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
        when (currentScreen) {
            MainScreen.MAIN_MENU -> {
                MainMenuScreen(
                    modifier = Modifier.padding(innerPadding),
                    onSelectDialogTest = { currentScreen = MainScreen.ANDROID_DIALOG_TEST },
                    onSelectNotificationTest = { currentScreen = MainScreen.NOTIFICATION_TEST }
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
        }
    }
}
