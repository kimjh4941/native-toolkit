package com.jonghyunkim.android.nativetoolkit.example

import android.content.Context
import android.library.clipboard.data.repository.ClipboardUseCases
import android.library.clipboard.domain.error.ClipboardDomainError
import android.library.clipboard.domain.model.ClipContent
import android.library.clipboard.domain.model.ClipDescriptionInfo
import android.library.clipboard.domain.model.ClipReadResult
import android.library.clipboard.presentation.ClipboardChangeMonitor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

private const val CLIPBOARD_TAG = "com.jonghyunkim.android.nativetoolkit.example.ClipboardSampleScreen"
private const val CLIPBOARD_FILE_PROVIDER_AUTHORITY_SUFFIX = ".native_toolkit.share.fileprovider"

/**
 * Clipboard feature sample screen.
 *
 * Demonstrates all clipboard operations provided by the android_library:
 * copy (plain text, HTML, URI, multiple text, sensitive text), read, hasClip, getDescription,
 * clear, and clipboard change observation.
 *
 * Uses only `android_library` (native), never `unity_android_plugin` — clipboard change
 * observation goes through [ClipboardChangeMonitor], which lives in the native library so it can
 * be used here without depending on the Unity bridge.
 *
 * @param modifier Modifier applied to the root layout.
 * @param onBack Called when the user taps the back button.
 */
@Composable
fun ClipboardSampleScreen(
    modifier: Modifier = Modifier,
    onBack: () -> Unit
) {
    Log.d(CLIPBOARD_TAG, "[ClipboardSampleScreen] onBack: $onBack")

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val clipboardUseCases = remember(context) { ClipboardUseCases(context) }
    val monitor = remember { ClipboardChangeMonitor() }
    val mainHandler = remember { Handler(Looper.getMainLooper()) }

    var statusText by remember { mutableStateOf("Result will be displayed here") }
    var changeCount by remember { mutableIntStateOf(0) }

    DisposableEffect(monitor) {
        onDispose {
            Log.d(CLIPBOARD_TAG, "[onDispose] stopping clipboard observation")
            monitor.stop()
        }
    }

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
            text = "Clipboard Example",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            lineHeight = 36.sp,
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp)
        )

        Text(
            text = statusText,
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp)
        )

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.Top)
        ) {

            // --- Copy ---
            item {
                Text(
                    text = "Copy",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp, bottom = 4.dp)
                )
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy Plain Text")
                        try {
                            clipboardUseCases.copyPlainText(
                                ClipContent.PlainText(text = "Hello from native-toolkit", label = "sample")
                            )
                            statusText = "✅ copyPlainText called"
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy Plain Text")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy Plain Text (empty)")
                        try {
                            clipboardUseCases.copyPlainText(ClipContent.PlainText(text = ""))
                            statusText = "✅ copyPlainText (empty) called"
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy Plain Text (empty, allowed)")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy HTML Text")
                        try {
                            clipboardUseCases.copyHtmlText(
                                ClipContent.HtmlText(plainText = "Hello", htmlText = "<b>Hello</b>")
                            )
                            statusText = "✅ copyHtmlText called"
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy HTML Text")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy URI")
                        statusText = "ℹ️ Preparing sample file..."
                        scope.launch(Dispatchers.IO) {
                            try {
                                val uri = prepareSampleUri(context)
                                withContext(Dispatchers.Main) {
                                    try {
                                        clipboardUseCases.copyUri(ClipContent.UriContent(uri = uri))
                                        statusText = "✅ copyUri called: $uri"
                                    } catch (e: ClipboardDomainError) {
                                        statusText = clipboardErrorMessage(e)
                                    } catch (e: Exception) {
                                        statusText = "❌ Unexpected: ${e.message}"
                                    }
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    statusText = "❌ File preparation failed: ${e.message}"
                                }
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy URI (content:// via FileProvider)")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy Multiple Text")
                        try {
                            clipboardUseCases.copyMultipleText(
                                ClipContent.MultipleText(texts = listOf("first", "second", "third"))
                            )
                            statusText = "✅ copyMultipleText called (3 items)"
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy Multiple Text")
                }
            }

            // --- Copy - Sensitive ---
            item {
                Text(
                    text = "Copy - Sensitive",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp, bottom = 4.dp)
                )
            }
            item {
                Text(
                    text = "Note: preview suppression only takes effect on Android 13+ (API 33+). " +
                        "On API 32 and below, this app shows its own confirmation toast instead.",
                    modifier = Modifier.fillMaxWidth()
                )
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy Sensitive Text")
                        try {
                            clipboardUseCases.copyPlainText(
                                ClipContent.PlainText(text = "P@ssw0rd-sample", isSensitive = true)
                            )
                            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2) {
                                Toast.makeText(context, "Copied (sensitive)", Toast.LENGTH_SHORT).show()
                            }
                            statusText = "✅ copySensitive called (preview suppressed on API 33+)"
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy Sensitive Text")
                }
            }

            // --- Read / Inspect ---
            item {
                Text(
                    text = "Read / Inspect",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp, bottom = 4.dp)
                )
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Read Clipboard")
                        try {
                            val result = clipboardUseCases.read()
                            statusText = if (result != null) {
                                "✅ Read: ${formatReadResult(result)}"
                            } else {
                                "ℹ️ Clipboard is empty (normal)"
                            }
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Read Clipboard")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Has Clip")
                        try {
                            statusText = "✅ hasClip = ${clipboardUseCases.hasClip()}"
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Has Clip")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Get Description")
                        try {
                            val info = clipboardUseCases.getDescription()
                            statusText = if (info != null) {
                                "✅ ${formatDescription(info)}"
                            } else {
                                "ℹ️ Clipboard is empty (normal)"
                            }
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Get Description")
                }
            }

            // --- Clear ---
            item {
                Text(
                    text = "Clear",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp, bottom = 4.dp)
                )
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Clear Clipboard")
                        try {
                            clipboardUseCases.clear()
                            statusText = "✅ clear called"
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Clear Clipboard")
                }
            }

            // --- Observe ---
            item {
                Text(
                    text = "Observe",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp, bottom = 4.dp)
                )
            }
            item {
                Text(
                    text = "Note: observation is only reliable while this app is in the foreground " +
                        "(Android 10+ background read restrictions).",
                    modifier = Modifier.fillMaxWidth()
                )
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Start Observing")
                        monitor.start(context) {
                            Log.d(CLIPBOARD_TAG, "[onChange] fired")
                            // Called on the system listener's callback thread; marshal to main.
                            mainHandler.post {
                                changeCount++
                                statusText = "ℹ️ Clipboard changed ($changeCount)"
                            }
                        }
                        statusText = if (monitor.isObserving()) {
                            "✅ observing started"
                        } else {
                            "❌ failed to start observing"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Start Observing")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Stop Observing")
                        monitor.stop()
                        statusText = "✅ observing stopped"
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Stop Observing")
                }
            }

            // --- Error Cases ---
            item {
                Text(
                    text = "Error Cases",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp, bottom = 4.dp)
                )
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy HTML (empty) -> EmptyContent")
                        try {
                            clipboardUseCases.copyHtmlText(
                                ClipContent.HtmlText(plainText = "Hello", htmlText = "")
                            )
                            statusText = "✅ copyHtmlText called"
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy HTML (empty) → EmptyContent")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy Multiple (empty list) -> EmptyItemList")
                        try {
                            clipboardUseCases.copyMultipleText(ClipContent.MultipleText(texts = emptyList()))
                            statusText = "✅ copyMultipleText called"
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy Multiple (empty list) → EmptyItemList")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy URI (blank) -> InvalidUri")
                        try {
                            clipboardUseCases.copyUri(ClipContent.UriContent(uri = ""))
                            statusText = "✅ copyUri called"
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy URI (blank) → InvalidUri")
                }
            }
            item {
                Button(
                    onClick = {
                        Log.d(CLIPBOARD_TAG, "[onClick] Copy URI (http scheme) -> InvalidUri")
                        try {
                            clipboardUseCases.copyUri(ClipContent.UriContent(uri = "http://example.com/x"))
                            statusText = "✅ copyUri called"
                        } catch (e: ClipboardDomainError) {
                            statusText = clipboardErrorMessage(e)
                        } catch (e: Exception) {
                            statusText = "❌ Unexpected: ${e.message}"
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = "Copy URI (http scheme) → InvalidUri")
                }
            }
        }
    }
}

/**
 * Creates a sample file under [Context.getCacheDir] and returns a `content://` URI for it via
 * the FileProvider declared by android_library (reused from the share feature's provider).
 */
private fun prepareSampleUri(context: Context): String {
    val file = File(context.cacheDir, "clipboard_sample.txt")
    file.writeText("Clipboard sample file content")
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}$CLIPBOARD_FILE_PROVIDER_AUTHORITY_SUFFIX",
        file
    )
    return uri.toString()
}

private fun clipboardErrorMessage(e: ClipboardDomainError): String = when (e) {
    is ClipboardDomainError.EmptyContent -> "❌ EmptyContent: HTML body is empty"
    is ClipboardDomainError.EmptyItemList -> "❌ EmptyItemList: no items to copy"
    is ClipboardDomainError.InvalidUri -> "❌ InvalidUri: ${e.uri}"
    is ClipboardDomainError.ClipboardUnavailable -> "❌ ClipboardUnavailable"
    is ClipboardDomainError.ReadNotAllowed -> "❌ ReadNotAllowed: app must be in foreground"
}

private fun formatReadResult(result: ClipReadResult): String {
    val items = result.items.joinToString(prefix = "[", postfix = "]") { item ->
        "{text=${item.text}, htmlText=${item.htmlText}, uri=${item.uri}, coercedText=${item.coercedText}}"
    }
    return "label=${result.label}, mimeTypes=${result.mimeTypes}, items=$items"
}

private fun formatDescription(info: ClipDescriptionInfo): String {
    return "label=${info.label}, mimeTypes=${info.mimeTypes}, " +
        "isStyledText=${info.isStyledText}, classificationStatus=${info.classificationStatus}"
}
