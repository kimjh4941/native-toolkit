package com.jonghyunkim.android.nativetoolkit.example

import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private const val RECEIVED_SHARE_TAG = "ReceivedShareScreen"

/**
 * Screen that displays the share content received from another app or a Direct Share target.
 *
 * @param modifier Modifier applied to the root layout.
 * @param content Received share content; shows an empty state when null.
 * @param onBack Called when the back button is tapped.
 */
@Composable
fun ReceivedShareScreen(
    modifier: Modifier = Modifier,
    content: ReceivedShareContent?,
    onBack: () -> Unit
) {
    Log.d(RECEIVED_SHARE_TAG, "[ReceivedShareScreen] content: $content")

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Button(
            onClick = onBack,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(text = "← Back to Main")
        }

        Text(
            text = "Received Share",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            lineHeight = 36.sp,
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp)
        )

        if (content == null) {
            Text(
                text = "No shared content received.",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp)
            )
        } else {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                ReceivedShareField(label = "Action", value = content.action)
                HorizontalDivider()
                ReceivedShareField(label = "MIME type", value = content.mimeType ?: "(none)")
                HorizontalDivider()
                ReceivedShareField(label = "Text", value = content.text ?: "(none)")
                HorizontalDivider()
                ReceivedShareField(
                    label = "Stream URIs",
                    value = if (content.streamUris.isEmpty()) {
                        "(none)"
                    } else {
                        "${content.streamUris.size} URI(s):\n" + content.streamUris.joinToString("\n")
                    }
                )
                if (content.shortcutId != null) {
                    HorizontalDivider()
                    ReceivedShareField(label = "Direct Share target", value = content.shortcutId)
                }
            }
        }
    }
}

@Composable
private fun ReceivedShareField(label: String, value: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
    ) {
        Text(
            text = label,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = value,
            fontSize = 14.sp,
            modifier = Modifier.padding(start = 8.dp, top = 2.dp)
        )
    }
}
