package com.jonghyunkim.android.nativetoolkit.example

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.jonghyunkim.nativetoolkit.share.AndroidShareManager
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.DirectShareTarget
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareChooserAction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File

private const val SHARE_TAG = "ShareSampleScreen"

/**
 * Share feature sample screen.
 *
 * Demonstrates all share operations of [AndroidShareManager]: text, URL, image, multiple images,
 * file, multiple files, Direct Share Target, share with callback, typed chooser actions and the
 * selection event.
 *
 * @param modifier Modifier applied to the root layout.
 * @param activity Host activity used as the context for [AndroidShareManager].
 * @param onBack Called when the user taps the back button.
 */
@Composable
fun ShareSampleScreen(
    modifier: Modifier = Modifier,
    activity: AppCompatActivity,
    onBack: () -> Unit
) {
    Log.d(SHARE_TAG, "[ShareSampleScreen] activity: $activity, onBack: $onBack")

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val shareManager = remember(activity) { AndroidShareManager.getInstance(activity) }

    var statusText by remember { mutableStateOf("Result will be displayed here") }
    // The token of the Sharesheet opened by shareForSelection, while its pick is awaited.
    var selectionToken by remember { mutableStateOf<Long?>(null) }

    // Leaving the screen stops waiting for both shareWithCallback and shareForSelection: the
    // library keeps one wait (sample app design 4.4).
    DisposableEffect(shareManager) {
        val registration = shareManager.selections.addListener { selection, _ ->
            Log.d(SHARE_TAG, "[onSelection] token: ${selection.token}")
            if (selection.token == selectionToken) selectionToken = null
            statusText = "✅ Selected (token=${selection.token}): ${selection.packageName ?: "(unknown package)"}"
        }
        onDispose {
            registration.remove()
            shareManager.cancelPendingCallback()
        }
    }
    val listState = rememberLazyListState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Button(
            onClick = onBack,
            modifier = Modifier.fillMaxWidth().testTag("share.back")
        ) {
            Text(text = "← Back to Main")
        }

        Text(
            text = "Share Example",
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
                .testTag("share.status")
                .fillMaxWidth()
                .padding(8.dp)
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(end = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.Top)
            ) {

                // --- Text Share ---
                item {
                    Text(
                        text = "Text Share",
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
                            try {
                                shareManager.shareText(
                                    ShareContent(text = "Hello from native-toolkit")
                                )
                                statusText = "✅ shareText called"
                            } catch (e: ShareDomainError) {
                                statusText = "❌ ${e.message}"
                            } catch (e: Exception) {
                                statusText = "❌ Unexpected: ${e.message}"
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.shareText")
                    ) {
                        Text(text = "Share Text")
                    }
                }
                item {
                    Button(
                        onClick = {
                            try {
                                shareManager.shareText(
                                    ShareContent(text = "https://developer.android.com/", mimeType = "text/plain")
                                )
                                statusText = "✅ shareText (URL) called"
                            } catch (e: ShareDomainError) {
                                statusText = "❌ ${e.message}"
                            } catch (e: Exception) {
                                statusText = "❌ Unexpected: ${e.message}"
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.shareUrl")
                    ) {
                        Text(text = "Share URL")
                    }
                }
                item {
                    Button(
                        onClick = {
                            statusText = "ℹ️ Preparing preview thumbnail..."
                            scope.launch(Dispatchers.IO) {
                                try {
                                    val bmp = BitmapFactory.decodeResource(
                                        context.resources,
                                        android.R.mipmap.sym_def_app_icon
                                    ) ?: run {
                                        withContext(Dispatchers.Main) { statusText = "❌ Bitmap decode failed" }
                                        return@launch
                                    }
                                    val file = File(context.cacheDir, "share_preview.png")
                                    file.outputStream().use {
                                        bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
                                    }
                                    withContext(Dispatchers.Main) {
                                        try {
                                            shareManager.shareText(
                                                ShareContent(
                                                    text = "https://developer.android.com/",
                                                    mimeType = "text/plain"
                                                ),
                                                SharePreviewOptions(
                                                    title = "Introducing content previews",
                                                    thumbnailPath = file.absolutePath
                                                )
                                            )
                                            statusText = "✅ shareText (rich preview) called"
                                        } catch (e: ShareDomainError) {
                                            statusText = "❌ ${e.message}"
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
                        modifier = Modifier.fillMaxWidth().testTag("share.shareTextWithRichPreview")
                    ) {
                        Text(text = "Share Text with Rich Preview")
                    }
                }

                item {
                    Button(
                        onClick = {
                            Log.d(SHARE_TAG, "[onClick] Share Text with Custom Action")
                            statusText = "ℹ️ Preparing custom action icon..."
                            scope.launch(Dispatchers.IO) {
                                try {
                                    val bmp = BitmapFactory.decodeResource(
                                        context.resources,
                                        android.R.drawable.ic_menu_edit
                                    ) ?: run {
                                        withContext(Dispatchers.Main) { statusText = "❌ Bitmap decode failed" }
                                        return@launch
                                    }
                                    val iconBytes = ByteArrayOutputStream().use { baos ->
                                        bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
                                        baos.toByteArray()
                                    }
                                    Log.d(SHARE_TAG, "[onClick] icon size: ${iconBytes.size}")
                                    withContext(Dispatchers.Main) {
                                        try {
                                            shareManager.shareTextWithActions(
                                                ShareContent(
                                                    text = "Shared with a custom chooser action",
                                                    mimeType = "text/plain"
                                                ),
                                                listOf(ShareChooserAction(id = "custom", label = "Custom", iconBytes = iconBytes))
                                            )
                                            statusText = "✅ shareText (custom action) called"
                                        } catch (e: ShareDomainError) {
                                            statusText = "❌ ${e.message}"
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
                        modifier = Modifier.fillMaxWidth().testTag("share.shareTextWithCustomAction")
                    ) {
                        Text(text = "Share Text with Custom Action")
                    }
                }
                item {
                    Button(
                        onClick = {
                            Log.d(SHARE_TAG, "[onClick] Share Text with Invalid Action")
                            // Two actions with the same ID and a readable icon: rejected for the ID
                            // alone, before the Sharesheet opens.
                            val icon = ByteArrayOutputStream().use { out ->
                                Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, out)
                                out.toByteArray()
                            }
                            statusText = try {
                                shareManager.shareTextWithActions(
                                    ShareContent(text = "This share is rejected"),
                                    listOf(ShareChooserAction("dup", "First", icon), ShareChooserAction("dup", "Second", icon))
                                )
                                "❌ Unexpected: the share was not rejected"
                            } catch (e: ShareDomainError.InvalidChooserAction) {
                                "❌ InvalidChooserAction: ${e.id}"
                            } catch (e: Exception) {
                                "❌ Unexpected: ${e.message}"
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.shareTextWithInvalidAction")
                    ) {
                        Text(text = "Share Text with Invalid Action")
                    }
                }
                item {
                    Button(
                        onClick = {
                            Log.d(SHARE_TAG, "[onClick] Share with Subject & Title")
                            try {
                                shareManager.shareText(
                                    ShareContent(
                                        text = "Body text shared from native-toolkit",
                                        title = "Choose an app",
                                        subject = "Sample subject line",
                                        mimeType = "text/plain"
                                    )
                                )
                                statusText = "✅ shareText (subject & title) called"
                            } catch (e: ShareDomainError) {
                                statusText = "❌ ${e.message}"
                            } catch (e: Exception) {
                                statusText = "❌ Unexpected: ${e.message}"
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.shareWithSubjectTitle")
                    ) {
                        Text(text = "Share with Subject & Title")
                    }
                }

                // --- Image Share ---
                item {
                    Text(
                        text = "Image Share",
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
                            statusText = "ℹ️ Preparing image..."
                            scope.launch(Dispatchers.IO) {
                                try {
                                    val bmp = BitmapFactory.decodeResource(
                                        context.resources,
                                        android.R.drawable.ic_menu_share
                                    ) ?: run {
                                        withContext(Dispatchers.Main) { statusText = "❌ Bitmap decode failed" }
                                        return@launch
                                    }
                                    val file = File(context.cacheDir, "share_sample.png")
                                    file.outputStream().use {
                                        bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
                                    }
                                    withContext(Dispatchers.Main) {
                                        try {
                                            shareManager.shareImage(file.absolutePath, "image/png")
                                            statusText = "✅ shareImage called"
                                        } catch (e: ShareDomainError) {
                                            statusText = "❌ ${e.message}"
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
                        modifier = Modifier.fillMaxWidth().testTag("share.shareImage")
                    ) {
                        Text(text = "Share Image")
                    }
                }

                // --- Multiple Images ---
                item {
                    Text(
                        text = "Multiple Images",
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
                            statusText = "ℹ️ Preparing images..."
                            scope.launch(Dispatchers.IO) {
                                try {
                                    val bmp = BitmapFactory.decodeResource(
                                        context.resources,
                                        android.R.drawable.ic_menu_share
                                    ) ?: run {
                                        withContext(Dispatchers.Main) { statusText = "❌ Bitmap decode failed" }
                                        return@launch
                                    }
                                    val file1 = File(context.cacheDir, "share_sample_1.png")
                                    val file2 = File(context.cacheDir, "share_sample_2.png")
                                    file1.outputStream().use {
                                        bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
                                    }
                                    file2.outputStream().use {
                                        bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
                                    }
                                    withContext(Dispatchers.Main) {
                                        try {
                                            shareManager.shareImages(
                                                listOf(file1.absolutePath, file2.absolutePath)
                                            )
                                            statusText = "✅ shareImages called"
                                        } catch (e: ShareDomainError) {
                                            statusText = "❌ ${e.message}"
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
                        modifier = Modifier.fillMaxWidth().testTag("share.shareMultipleImages")
                    ) {
                        Text(text = "Share Multiple Images")
                    }
                }

                // --- File Share ---
                item {
                    Text(
                        text = "File Share",
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
                            statusText = "ℹ️ Preparing file..."
                            scope.launch(Dispatchers.IO) {
                                try {
                                    val file = File(context.cacheDir, "share_sample.txt")
                                        .apply { writeText("Share sample from native-toolkit") }
                                    withContext(Dispatchers.Main) {
                                        try {
                                            shareManager.shareFile(file.absolutePath)
                                            statusText = "✅ shareFile called"
                                        } catch (e: ShareDomainError) {
                                            statusText = "❌ ${e.message}"
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
                        modifier = Modifier.fillMaxWidth().testTag("share.shareFile")
                    ) {
                        Text(text = "Share File")
                    }
                }

                // --- Multiple Files ---
                item {
                    Text(
                        text = "Multiple Files",
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
                            statusText = "ℹ️ Preparing files..."
                            scope.launch(Dispatchers.IO) {
                                try {
                                    val file1 = File(context.cacheDir, "share_sample_1.txt")
                                        .apply { writeText("Share sample 1 from native-toolkit") }
                                    val file2 = File(context.cacheDir, "share_sample_2.txt")
                                        .apply { writeText("Share sample 2 from native-toolkit") }
                                    withContext(Dispatchers.Main) {
                                        try {
                                            shareManager.shareFiles(
                                                listOf(file1.absolutePath, file2.absolutePath)
                                            )
                                            statusText = "✅ shareFiles called"
                                        } catch (e: ShareDomainError) {
                                            statusText = "❌ ${e.message}"
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
                        modifier = Modifier.fillMaxWidth().testTag("share.shareMultipleFiles")
                    ) {
                        Text(text = "Share Multiple Files")
                    }
                }

                // --- Direct Share Target ---
                item {
                    Text(
                        text = "Direct Share Target",
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
                            statusText = "ℹ️ Preparing icon..."
                            scope.launch(Dispatchers.IO) {
                                try {
                                    val bmp = BitmapFactory.decodeResource(
                                        context.resources,
                                        android.R.mipmap.sym_def_app_icon
                                    ) ?: run {
                                        withContext(Dispatchers.Main) { statusText = "❌ Bitmap decode failed" }
                                        return@launch
                                    }
                                    val baos = ByteArrayOutputStream()
                                    bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
                                    val iconBytes = baos.toByteArray()
                                    withContext(Dispatchers.Main) {
                                        try {
                                            shareManager.registerDirectShareTarget(
                                                DirectShareTarget(
                                                    id = "sample_1",
                                                    label = "Sample User",
                                                    category = "android.shortcut.conversation"
                                                ),
                                                iconBytes
                                            )
                                            statusText = "✅ registerDirectShareTarget called"
                                        } catch (e: ShareDomainError) {
                                            statusText = "❌ ${e.message}"
                                        } catch (e: Exception) {
                                            statusText = "❌ Unexpected: ${e.message}"
                                        }
                                    }
                                } catch (e: Exception) {
                                    withContext(Dispatchers.Main) {
                                        statusText = "❌ Icon preparation failed: ${e.message}"
                                    }
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.registerDirectShareTarget")
                    ) {
                        Text(text = "Register Direct Share Target")
                    }
                }
                item {
                    Button(
                        onClick = {
                            try {
                                shareManager.removeDirectShareTargets(listOf("sample_1"))
                                statusText = "✅ removeDirectShareTargets called"
                            } catch (e: ShareDomainError) {
                                statusText = "❌ ${e.message}"
                            } catch (e: Exception) {
                                statusText = "❌ Unexpected: ${e.message}"
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.removeDirectShareTarget")
                    ) {
                        Text(text = "Remove Direct Share Target")
                    }
                }

                // --- Share with Callback ---
                item {
                    Text(
                        text = "Share with Callback",
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
                            try {
                                shareManager.shareWithCallback(
                                    ShareContent(text = "Hello with callback from native-toolkit"),
                                    onResult = { pkg ->
                                        // onResult fires only on selection; pkg == null means selected but the package was unavailable.
                                        statusText = if (pkg != null) {
                                            "✅ Selected: $pkg"
                                        } else {
                                            "ℹ️ Shared (package unavailable)"
                                        }
                                    }
                                )
                                statusText = "ℹ️ Sharesheet opened, waiting for result..."
                            } catch (e: ShareDomainError) {
                                statusText = "❌ ${e.message}"
                            } catch (e: Exception) {
                                statusText = "❌ Unexpected: ${e.message}"
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.shareWithCallback")
                    ) {
                        Text(text = "Share with Callback")
                    }
                }
                item {
                    Button(
                        onClick = {
                            Log.d(SHARE_TAG, "[onClick] Share with Callback + Rich Preview")
                            statusText = "ℹ️ Preparing callback preview thumbnail..."
                            scope.launch(Dispatchers.IO) {
                                try {
                                    val bmp = BitmapFactory.decodeResource(
                                        context.resources,
                                        android.R.mipmap.sym_def_app_icon
                                    ) ?: run {
                                        withContext(Dispatchers.Main) { statusText = "❌ Bitmap decode failed" }
                                        return@launch
                                    }
                                    val file = File(context.cacheDir, "callback_preview.png")
                                    file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                                    withContext(Dispatchers.Main) {
                                        try {
                                            shareManager.shareWithCallback(
                                                ShareContent(
                                                    text = "https://developer.android.com/",
                                                    mimeType = "text/plain"
                                                ),
                                                SharePreviewOptions(
                                                    title = "Callback with rich preview",
                                                    thumbnailPath = file.absolutePath
                                                ),
                                                onResult = { pkg ->
                                                    Log.d(SHARE_TAG, "[onResult] pkg: $pkg")
                                                    statusText = if (pkg != null) {
                                                        "✅ Selected: $pkg"
                                                    } else {
                                                        "ℹ️ Shared (package unavailable)"
                                                    }
                                                },
                                                onFinished = {
                                                    Log.d(SHARE_TAG, "[onFinished] callback + preview")
                                                }
                                            )
                                            statusText = "ℹ️ Sharesheet (callback + preview) opened..."
                                        } catch (e: ShareDomainError) {
                                            statusText = "❌ ${e.message}"
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
                        modifier = Modifier.fillMaxWidth().testTag("share.shareWithCallbackRichPreview")
                    ) {
                        Text(text = "Share with Callback + Rich Preview")
                    }
                }
                item {
                    Button(
                        onClick = {
                            Log.d(SHARE_TAG, "[onClick] Cancel Pending Callback")
                            try {
                                shareManager.cancelPendingCallback()
                                statusText = "✅ cancelPendingCallback called"
                            } catch (e: Exception) {
                                statusText = "❌ Unexpected: ${e.message}"
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.cancelPendingCallback")
                    ) {
                        Text(text = "Cancel Pending Callback")
                    }
                }
                item {
                    Text(
                        text = "Selection Event",
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
                            Log.d(SHARE_TAG, "[onClick] Share For Selection")
                            statusText = try {
                                val token = shareManager.shareForSelection(
                                    ShareContent(text = "Hello with a selection event from native-toolkit")
                                )
                                selectionToken = token
                                "ℹ️ Sharesheet opened (token=$token), waiting for selection..."
                            } catch (e: ShareDomainError) {
                                "❌ ${e.javaClass.simpleName}"
                            } catch (e: Exception) {
                                "❌ Unexpected: ${e.message}"
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.shareForSelection")
                    ) {
                        Text(text = "Share For Selection")
                    }
                }
                item {
                    Button(
                        onClick = {
                            Log.d(SHARE_TAG, "[onClick] Cancel Share Selection")
                            val token = selectionToken
                            statusText = if (token == null) {
                                "ℹ️ No selection is pending."
                            } else {
                                shareManager.cancelShareSelection(token)
                                selectionToken = null
                                "✅ cancelShareSelection called (token=$token)"
                            }
                        },
                        modifier = Modifier.fillMaxWidth().testTag("share.cancelShareSelection")
                    ) {
                        Text(text = "Cancel Share Selection")
                    }
                }
            }

            ShareSampleScrollbar(
                listState = listState,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(vertical = 8.dp)
                    .offset(x = 12.dp)
            )
        }
    }
}

@Composable
private fun ShareSampleScrollbar(
    listState: LazyListState,
    modifier: Modifier = Modifier
) {
    val density = LocalDensity.current
    val minThumbHeightPx = with(density) { 36.dp.toPx() }
    val metrics = calculateShareScrollbarMetrics(
        listState = listState,
        minThumbHeightPx = minThumbHeightPx
    )

    if (!metrics.canScroll) return

    Box(
        modifier = modifier
            .offset { IntOffset(0, metrics.offsetPx.toInt()) }
            .clip(RoundedCornerShape(999.dp))
            .background(Color.Black.copy(alpha = 0.45f))
            .width(4.dp)
            .height(with(density) { metrics.thumbHeightPx.toDp() })
    )
}

private data class ShareScrollbarMetrics(
    val canScroll: Boolean,
    val thumbHeightPx: Float,
    val offsetPx: Float
)

private fun calculateShareScrollbarMetrics(
    listState: LazyListState,
    minThumbHeightPx: Float
): ShareScrollbarMetrics {
    val layoutInfo = listState.layoutInfo
    val visibleItems = layoutInfo.visibleItemsInfo
    if (visibleItems.isEmpty()) {
        return ShareScrollbarMetrics(false, minThumbHeightPx, 0f)
    }

    val viewportHeightPx = (layoutInfo.viewportEndOffset - layoutInfo.viewportStartOffset).toFloat()
    if (viewportHeightPx <= 0f) {
        return ShareScrollbarMetrics(false, minThumbHeightPx, 0f)
    }

    val averageItemSizePx = visibleItems.map { it.size }.average().toFloat().coerceAtLeast(1f)
    val totalItemsCount = layoutInfo.totalItemsCount.coerceAtLeast(1)
    val estimatedContentHeightPx = averageItemSizePx * totalItemsCount
    if (estimatedContentHeightPx <= viewportHeightPx) {
        return ShareScrollbarMetrics(false, viewportHeightPx, 0f)
    }

    val estimatedScrollOffsetPx =
        (listState.firstVisibleItemIndex * averageItemSizePx) + listState.firstVisibleItemScrollOffset
    val maxScrollOffsetPx = (estimatedContentHeightPx - viewportHeightPx).coerceAtLeast(1f)
    val thumbHeightPx =
        (viewportHeightPx * (viewportHeightPx / estimatedContentHeightPx))
            .coerceAtLeast(minThumbHeightPx)
            .coerceAtMost(viewportHeightPx)
    val availableTrackHeightPx = (viewportHeightPx - thumbHeightPx).coerceAtLeast(0f)
    val offsetRatio = (estimatedScrollOffsetPx / maxScrollOffsetPx).coerceIn(0f, 1f)

    return ShareScrollbarMetrics(
        canScroll = true,
        thumbHeightPx = thumbHeightPx,
        offsetPx = availableTrackHeightPx * offsetRatio
    )
}
