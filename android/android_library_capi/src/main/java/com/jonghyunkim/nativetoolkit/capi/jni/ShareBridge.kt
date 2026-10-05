package com.jonghyunkim.nativetoolkit.capi.jni

import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster
import com.jonghyunkim.nativetoolkit.share.AndroidShareManager
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.DirectShareTarget
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareChooserAction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareSelection

/**
 * The C ABI's entry to Share (C ABI design part 2, 5.1, 6.4). Opening the Sharesheet completes on
 * the main thread once the foreground is checked there (AC-15): NONE when it opened, or why not.
 * The selection waits pair the C request ID with Kotlin's token (AP-17); the chooser actions of
 * each text share replace the earlier ones (AP-7). Direct Share runs on the calling thread.
 */
internal object ShareBridge {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.ShareBridge"

    /** The ledger kinds. */
    const val KIND_OPEN = 400
    const val KIND_CHOOSER_ACTION = 401
    const val KIND_SELECTION = 402

    // ntk_share_error 6 to 16 (part 2, 11.4).
    private const val NOT_FOREGROUND = 6
    private const val EMPTY_CONTENT = 7
    private const val NO_SHARE_TARGET = 8
    private const val FILE_NOT_FOUND = 9
    private const val ILLEGAL_FILE_ACCESS = 10
    private const val INVALID_MIME_TYPE = 11
    private const val DIRECT_SHARE_REGISTRATION_FAILED = 12
    private const val EMPTY_ID_LIST = 13
    private const val EMPTY_FILE_LIST = 14
    private const val INVALID_ICON = 15
    private const val INVALID_CHOOSER_ACTION = 16

    /** Kotlin's selection token to the C request ID (AP-17). Main thread only. */
    private val selectionIds = HashMap<Long, Long>()

    // The one EventHub listener per kind (AP-21), added with the first C registration and never
    // removed. Share events are not kept (6.4). Main thread only.
    private var chooserHub: EventHub.Registration? = null
    private var selectionHub: EventHub.Registration? = null

    private fun context(): Context {
        Log.d(TAG, "[context]")
        return NtkRuntime.context()
    }

    private fun manager(): AndroidShareManager {
        Log.d(TAG, "[manager]")
        return AndroidShareManager.getInstance(context())
    }

    /** The value of ntk_share_error for a failure (part 2, 11.4). */
    fun errorOf(error: Throwable): Int {
        Log.d(TAG, "[errorOf] error: ${error.javaClass.name}")
        return when (error) {
            is ShareDomainError.EmptyContent -> EMPTY_CONTENT
            is ShareDomainError.NoShareTarget -> NO_SHARE_TARGET
            is ShareDomainError.FileNotFound -> FILE_NOT_FOUND
            is ShareDomainError.IllegalFileAccess -> ILLEGAL_FILE_ACCESS
            is ShareDomainError.InvalidMimeType -> INVALID_MIME_TYPE
            is ShareDomainError.DirectShareRegistrationFailed -> DIRECT_SHARE_REGISTRATION_FAILED
            is ShareDomainError.EmptyIdList -> EMPTY_ID_LIST
            is ShareDomainError.EmptyFileList -> EMPTY_FILE_LIST
            is ShareDomainError.InvalidBase64Icon -> INVALID_ICON
            is ShareDomainError.InvalidChooserAction -> INVALID_CHOOSER_ACTION
            else -> Errors.common(error)
        }
    }

    // --- opening the Sharesheet (OP-43 to OP-47, OP-50) ---

    // Inserts the request, checks the foreground on the main thread, opens, and completes: the
    // Sharesheet has no cancel, so the request leaves the ledger at once (6.4).
    private fun open(id: Long, name: String, block: (AndroidShareManager) -> Unit): Boolean {
        Log.d(TAG, "[open] id: $id, name: $name")
        return MainPoster.post {
            if (!Ledger.insertIfActive(id, KIND_OPEN)) return@post
            Ledger.remove(id)
            if (!Foreground.isForeground()) {
                nativeDone(id, NOT_FOREGROUND)
                return@post
            }
            val error = try {
                block(manager())
                Errors.NONE
            } catch (e: Throwable) {
                Log.e(TAG, "[$name] failed: ${e.javaClass.name}")
                errorOf(e)
            }
            nativeDone(id, error)
        }
    }

    private fun content(
        text: ByteArray,
        title: ByteArray?,
        subject: ByteArray?,
        mimeType: ByteArray?
    ): ShareContent {
        Log.d(TAG, "[content] text.size: ${text.size}")
        return ShareContent(
            Utf8.decode(text),
            Utf8.decodeOrNull(title),
            Utf8.decodeOrNull(subject),
            Utf8.decodeOrNull(mimeType) ?: "text/plain"
        )
    }

    private fun preview(title: ByteArray?, thumbnailPath: ByteArray?): SharePreviewOptions {
        Log.d(TAG, "[preview]")
        return SharePreviewOptions(Utf8.decodeOrNull(title), Utf8.decodeOrNull(thumbnailPath))
    }

    /** OP-43: always with actions, so that the actions of earlier shares stop (AP-7). */
    @JvmStatic
    fun shareText(
        id: Long,
        text: ByteArray,
        title: ByteArray?,
        subject: ByteArray?,
        mimeType: ByteArray?,
        previewTitle: ByteArray?,
        previewThumbnail: ByteArray?,
        actionIds: Array<ByteArray>,
        actionLabels: Array<ByteArray>,
        actionIcons: Array<ByteArray>
    ): Boolean {
        Log.d(TAG, "[shareText] id: $id, text.size: ${text.size}, actions: ${actionIds.size}")
        val content = content(text, title, subject, mimeType)
        val preview = preview(previewTitle, previewThumbnail)
        val actions = actionIds.indices.map {
            ShareChooserAction(Utf8.decode(actionIds[it]), Utf8.decode(actionLabels[it]), actionIcons[it])
        }
        return open(id, "shareText") { it.shareTextWithActions(content, actions, preview) }
    }

    @JvmStatic
    fun shareImage(id: Long, path: ByteArray, mimeType: ByteArray): Boolean {
        Log.d(TAG, "[shareImage] id: $id")
        val filePath = Utf8.decode(path)
        val mime = Utf8.decode(mimeType)
        return open(id, "shareImage") { it.shareImage(filePath, mime) }
    }

    @JvmStatic
    fun shareImages(id: Long, paths: Array<ByteArray>): Boolean {
        Log.d(TAG, "[shareImages] id: $id, paths: ${paths.size}")
        val filePaths = paths.map(Utf8::decode)
        return open(id, "shareImages") { it.shareImages(filePaths) }
    }

    @JvmStatic
    fun shareFile(id: Long, path: ByteArray): Boolean {
        Log.d(TAG, "[shareFile] id: $id")
        val filePath = Utf8.decode(path)
        return open(id, "shareFile") { it.shareFile(filePath) }
    }

    @JvmStatic
    fun shareFiles(id: Long, paths: Array<ByteArray>): Boolean {
        Log.d(TAG, "[shareFiles] id: $id, paths: ${paths.size}")
        val filePaths = paths.map(Utf8::decode)
        return open(id, "shareFiles") { it.shareFiles(filePaths) }
    }

    /**
     * OP-50: the token pairs with the C request ID [id] once Kotlin returns it (AP-17). The new
     * token replaces the earlier wait, so the earlier pairs go. On a failure the ledger stays.
     */
    @JvmStatic
    fun shareForSelection(
        id: Long,
        text: ByteArray,
        title: ByteArray?,
        subject: ByteArray?,
        mimeType: ByteArray?,
        previewTitle: ByteArray?,
        previewThumbnail: ByteArray?
    ): Boolean {
        Log.d(TAG, "[shareForSelection] id: $id, text.size: ${text.size}")
        val content = content(text, title, subject, mimeType)
        val preview = preview(previewTitle, previewThumbnail)
        return open(id, "shareForSelection") { manager ->
            val token = manager.shareForSelection(content, preview)
            selectionIds.clear()
            selectionIds[token] = id
        }
    }

    /** OP-51: always on the main thread, after the opening it follows (AP-17). */
    @JvmStatic
    fun cancelSelection(id: Long): Boolean {
        Log.d(TAG, "[cancelSelection] id: $id")
        return MainPoster.post {
            val token = selectionIds.entries.firstOrNull { it.value == id }?.key ?: return@post
            selectionIds.remove(token)
            try {
                manager().cancelShareSelection(token)
            } catch (e: Throwable) {
                Log.e(TAG, "[cancelSelection] failed: ${e.javaClass.name}")
            }
        }
    }

    // --- Direct Share (OP-48, OP-49), on the calling thread ---

    @JvmStatic
    fun registerDirectTarget(id: ByteArray, label: ByteArray, category: ByteArray, icon: ByteArray): Int {
        Log.d(TAG, "[registerDirectTarget] icon.size: ${icon.size}")
        return try {
            val target = DirectShareTarget(Utf8.decode(id), Utf8.decode(label), Utf8.decode(category))
            manager().registerDirectShareTarget(target, icon)
            Errors.NONE
        } catch (e: Throwable) {
            Log.e(TAG, "[registerDirectTarget] failed: ${e.javaClass.name}")
            errorOf(e)
        }
    }

    @JvmStatic
    fun removeDirectTargets(ids: Array<ByteArray>): Int {
        Log.d(TAG, "[removeDirectTargets] ids: ${ids.size}")
        return try {
            manager().removeDirectShareTargets(ids.map(Utf8::decode))
            Errors.NONE
        } catch (e: Throwable) {
            Log.e(TAG, "[removeDirectTargets] failed: ${e.javaClass.name}")
            errorOf(e)
        }
    }

    // --- events (OP-52 to OP-54) ---

    @JvmStatic
    fun addChooserActionListener(id: Long): Boolean {
        Log.d(TAG, "[addChooserActionListener] id: $id")
        return MainPoster.post {
            if (!Ledger.insertIfActive(id, KIND_CHOOSER_ACTION)) return@post
            if (chooserHub == null) chooserHub = manager().chooserActions.addListener { event, _ -> onChooserAction(event) }
        }
    }

    @JvmStatic
    fun addSelectionListener(id: Long): Boolean {
        Log.d(TAG, "[addSelectionListener] id: $id")
        return MainPoster.post {
            if (!Ledger.insertIfActive(id, KIND_SELECTION)) return@post
            if (selectionHub == null) selectionHub = manager().selections.addListener { event, _ -> onSelection(event) }
        }
    }

    private fun onChooserAction(actionId: String) {
        Log.d(TAG, "[onChooserAction] actionId: $actionId")
        val bytes = Utf8.encode(actionId)
        for (id in Ledger.idsOf(KIND_CHOOSER_ACTION)) nativeChooserAction(id, bytes)
    }

    // A token with no C request (a share Kotlin opened directly, or a canceled one) is dropped.
    private fun onSelection(selection: ShareSelection) {
        Log.d(TAG, "[onSelection] selection: $selection")
        val requestId = selectionIds.remove(selection.token) ?: return
        val packageName = Utf8.encodeOrNull(selection.packageName)
        for (id in Ledger.idsOf(KIND_SELECTION)) nativeSelection(id, requestId, packageName)
    }

    /** Completes an opening. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeDone(id: Long, error: Int)

    /** Delivers a chooser action to one C registration. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeChooserAction(id: Long, actionId: ByteArray)

    /** Delivers a selection to one C registration. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeSelection(id: Long, requestId: Long, packageName: ByteArray?)
}
