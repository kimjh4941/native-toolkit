package com.jonghyunkim.android.nativetoolkit.example

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jonghyunkim.android.nativetoolkit.example.ui.theme.AndroidTheme

class NotificationFullScreenSampleActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        title = "FullScreen Notification Sample"
        enableEdgeToEdge()
        setContent {
            AndroidTheme {
                NotificationFullScreenSampleContent(
                    onClose = { finish() }
                )
            }
        }
    }
}

@Composable
private fun NotificationFullScreenSampleContent(
    onClose: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "FullScreenIntent Reference Sample",
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(bottom = 12.dp)
        )
        Text(
            text = "This screen was launched from a fullScreenIntent sample notification. Depending on Android policy and device state, the notification may appear as a heads-up notification instead.",
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(bottom = 24.dp)
        )
        Button(onClick = onClose) {
            Text(text = "Close")
        }
    }
}

