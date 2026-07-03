package com.jonghyunkim.android.nativetoolkit.example

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Card
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jonghyunkim.android.nativetoolkit.example.ui.theme.AndroidTheme

@Composable
fun MainMenuScreen(
    modifier: Modifier = Modifier,
    onSelectDialogTest: () -> Unit,
    onSelectNotificationTest: () -> Unit,
    onSelectShareTest: () -> Unit
) {
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.Top)
    ) {
        item {
            Text(
                text = "Native Toolkit Example",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                lineHeight = 36.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp)
            )
        }
        item {
            MainMenuListItem(
                title = "Dialog Example",
                description = "Explore dialog samples.",
                onClick = onSelectDialogTest
            )
        }
        item {
            MainMenuListItem(
                title = "Notification Example",
                description = "Explore notification permission, display, and scheduling samples.",
                onClick = onSelectNotificationTest
            )
        }
        item {
            MainMenuListItem(
                title = "Share Example",
                description = "Explore text, image, file, and direct share samples.",
                onClick = onSelectShareTest
            )
        }
    }
}

@Composable
private fun MainMenuListItem(
    title: String,
    description: String,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(text = title, fontWeight = FontWeight.Bold, fontSize = 20.sp)
            Text(text = description)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun MainMenuPreview() {
    AndroidTheme {
        MainMenuScreen(
            onSelectDialogTest = {},
            onSelectNotificationTest = {},
            onSelectShareTest = {}
        )
    }
}

