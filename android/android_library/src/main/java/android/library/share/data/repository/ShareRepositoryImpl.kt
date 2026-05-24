package android.library.share.data.repository

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.library.share.application.port.ShareRepository
import android.library.share.domain.error.ShareDomainError
import android.library.share.domain.model.DirectShareTarget
import android.library.share.domain.model.ShareContent
import android.os.Build
import android.service.chooser.ChooserAction
import android.service.chooser.ChooserResult
import android.util.Base64
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import org.json.JSONArray
import java.io.File

class ShareRepositoryImpl(private val context: Context) : ShareRepository {

    override fun shareText(content: ShareContent, chooserActionsJson: String) {
        Log.d(TAG, "[shareText] content: $content, chooserActionsJson: $chooserActionsJson")
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = content.mimeType
            putExtra(Intent.EXTRA_TEXT, content.text)
            content.subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
        }
        val chooserIntent = Intent.createChooser(shareIntent, content.title)
        addChooserActionsIfSupported(chooserIntent, chooserActionsJson)
        startActivity(chooserIntent)
    }

    override fun shareImage(filePath: String, mimeType: String) {
        Log.d(TAG, "[shareImage] filePath: $filePath, mimeType: $mimeType")
        val uri = fileToContentUri(filePath)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, null))
    }

    override fun shareImages(filePaths: List<String>) {
        Log.d(TAG, "[shareImages] filePaths: $filePaths")
        val uris = ArrayList(filePaths.map { fileToContentUri(it) })
        val mimeType = filePaths
            .map { ShareMimeTypeHelper.getMimeType(File(it)) }
            .distinct()
            .let { if (it.size == 1) it.first() else "image/*" }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = mimeType
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, null))
    }

    override fun shareFile(filePath: String) {
        Log.d(TAG, "[shareFile] filePath: $filePath")
        val uri = fileToContentUri(filePath)
        val mimeType = ShareMimeTypeHelper.getMimeType(File(filePath))
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, null))
    }

    override fun shareFiles(filePaths: List<String>) {
        Log.d(TAG, "[shareFiles] filePaths: $filePaths")
        val uris = ArrayList(filePaths.map { fileToContentUri(it) })
        val mimeType = filePaths
            .map { ShareMimeTypeHelper.getMimeType(File(it)) }
            .distinct()
            .let { if (it.size == 1) it.first() else "*/*" }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = mimeType
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, null))
    }

    override fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray) {
        Log.d(TAG, "[registerDirectShareTarget] target: $target")
        val maxCount = ShortcutManagerCompat.getMaxShortcutCountPerActivity(context)
        val currentCount = ShortcutManagerCompat.getDynamicShortcuts(context).size
        if (currentCount >= maxCount) {
            throw ShareDomainError.DirectShareRegistrationFailed("quota_exceeded")
        }

        val bitmap = BitmapFactory.decodeByteArray(iconBytes, 0, iconBytes.size)
            ?: throw ShareDomainError.InvalidBase64Icon(target.id)
        val icon = IconCompat.createWithBitmap(bitmap)

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_DEFAULT)

        val shortcut = ShortcutInfoCompat.Builder(context, target.id)
            .setShortLabel(target.label)
            .setIcon(icon)
            .setCategories(setOf(target.category))
            .setIntent(launchIntent)
            .setLongLived(true)
            .build()

        val result = ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
        if (!result) {
            throw ShareDomainError.DirectShareRegistrationFailed("push_failed")
        }
    }

    override fun removeDirectShareTargets(ids: List<String>) {
        Log.d(TAG, "[removeDirectShareTargets] ids: $ids")
        ShortcutManagerCompat.removeLongLivedShortcuts(context, ids)
    }

    override fun shareWithCallback(content: ShareContent, onResult: (String?) -> Unit) {
        Log.d(TAG, "[shareWithCallback] content: $content")
        val callbackAction = "${context.packageName}.SHARE_CALLBACK"

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                Log.d(TAG, "[onReceive] intent: $intent")
                ctx?.unregisterReceiver(this)
                val packageName = extractSelectedPackage(intent)
                onResult(packageName)
            }
        }

        val filter = IntentFilter(callbackAction)
        ContextCompat.registerReceiver(
            context,
            receiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        val callbackIntent = Intent(callbackAction).setPackage(context.packageName)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            SHARE_CALLBACK_REQUEST_CODE,
            callbackIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = content.mimeType
            putExtra(Intent.EXTRA_TEXT, content.text)
            content.subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
        }

        val chooserIntent = Intent.createChooser(shareIntent, content.title, pendingIntent.intentSender)
        startActivity(chooserIntent)
    }

    private fun fileToContentUri(filePath: String): android.net.Uri {
        val file = File(filePath)
        if (!file.exists()) throw ShareDomainError.FileNotFound(filePath)
        return try {
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        } catch (e: IllegalArgumentException) {
            throw ShareDomainError.IllegalFileAccess(filePath)
        }
    }

    private fun startActivity(intent: Intent) {
        if (context !is android.app.Activity) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            throw ShareDomainError.NoShareTarget
        }
    }

    @SuppressLint("NewApi")
    private fun addChooserActionsIfSupported(chooserIntent: Intent, chooserActionsJson: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        if (chooserActionsJson.isBlank() || chooserActionsJson == "[]") return
        try {
            buildChooserActions(chooserActionsJson).let { actions ->
                if (actions.isNotEmpty()) {
                    chooserIntent.putExtra(
                        Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS,
                        actions.toTypedArray<ChooserAction>()
                    )
                }
            }
        } catch (_: Exception) {
            Log.w(TAG, "[addChooserActionsIfSupported] failed to parse chooserActionsJson")
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun buildChooserActions(chooserActionsJson: String): List<ChooserAction> {
        val array = JSONArray(chooserActionsJson)
        val actions = mutableListOf<ChooserAction>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            val label = obj.optString("label").takeIf { it.isNotBlank() } ?: continue
            val iconBase64 = obj.optString("iconBase64").takeIf { it.isNotBlank() } ?: continue
            val intentAction = obj.optString("intentAction").ifBlank { Intent.ACTION_SEND }

            val iconBytes = runCatching { Base64.decode(iconBase64, Base64.DEFAULT) }.getOrNull() ?: continue
            val bitmap = BitmapFactory.decodeByteArray(iconBytes, 0, iconBytes.size) ?: continue
            val icon = android.graphics.drawable.Icon.createWithBitmap(bitmap)

            val actionIntent = PendingIntent.getBroadcast(
                context,
                label.hashCode(),
                Intent(intentAction).setPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            actions.add(ChooserAction.Builder(icon, label, actionIntent).build())
        }
        return actions
    }

    private fun extractSelectedPackage(intent: Intent?): String? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            extractSelectedPackageApi34(intent)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra<ComponentName>(Intent.EXTRA_CHOSEN_COMPONENT)?.packageName
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun extractSelectedPackageApi34(intent: Intent?): String? {
        val extras = intent?.extras ?: return null
        val result = extras.getParcelable("android.intent.extra.CHOOSER_RESULT", ChooserResult::class.java)
        return result?.selectedComponent?.packageName
    }

    private companion object {
        private const val TAG = "ShareRepositoryImpl"
        private const val SHARE_CALLBACK_REQUEST_CODE = 0
    }
}
