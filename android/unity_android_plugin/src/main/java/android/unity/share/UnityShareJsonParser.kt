package android.unity.share

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

internal object UnityShareJsonParser {

    private const val TAG = "UnityShareJsonParser"

    fun parseShareText(json: String): UnityShareTextSpec {
        Log.d(TAG, "[parseShareText] json: $json")
        val obj = JSONObject(json)
        val text = obj.getString("text")
        require(text.isNotBlank()) { "text is required" }
        val chooserActions = parseChooserActions(obj.optJSONArray("chooserActions"))
        return UnityShareTextSpec(
            text = text,
            title = obj.optString("title").takeIf { it.isNotBlank() },
            subject = obj.optString("subject").takeIf { it.isNotBlank() },
            mimeType = obj.optString("mimeType").ifBlank { "text/plain" },
            chooserActions = chooserActions,
            previewTitle = obj.optString("previewTitle").takeIf { it.isNotBlank() },
            previewThumbnailPath = obj.optString("previewThumbnailPath").takeIf { it.isNotBlank() }
        )
    }

    fun parseShareImage(json: String): UnityShareImageSpec {
        Log.d(TAG, "[parseShareImage] json: $json")
        val obj = JSONObject(json)
        val filePath = obj.getString("filePath")
        require(filePath.isNotBlank()) { "filePath is required" }
        return UnityShareImageSpec(
            filePath = filePath,
            mimeType = obj.optString("mimeType").ifBlank { "image/*" }
        )
    }

    fun parseShareImages(json: String): UnityShareFileSpec {
        Log.d(TAG, "[parseShareImages] json: $json")
        val obj = JSONObject(json)
        val filePaths = parseStringArray(obj.getJSONArray("filePaths"))
        require(filePaths.isNotEmpty()) { "filePaths must not be empty" }
        return UnityShareFileSpec(filePaths = filePaths)
    }

    fun parseShareFile(json: String): UnityShareFileSpec {
        Log.d(TAG, "[parseShareFile] json: $json")
        val obj = JSONObject(json)
        val filePath = obj.getString("filePath")
        require(filePath.isNotBlank()) { "filePath is required" }
        return UnityShareFileSpec(filePath = filePath)
    }

    fun parseShareFiles(json: String): UnityShareFileSpec {
        Log.d(TAG, "[parseShareFiles] json: $json")
        val obj = JSONObject(json)
        val filePaths = parseStringArray(obj.getJSONArray("filePaths"))
        require(filePaths.isNotEmpty()) { "filePaths must not be empty" }
        return UnityShareFileSpec(filePaths = filePaths)
    }

    fun parseRegisterDirectShareTarget(json: String): UnityDirectShareTargetSpec {
        Log.d(TAG, "[parseRegisterDirectShareTarget] json: $json")
        val obj = JSONObject(json)
        val id = obj.getString("id")
        require(id.isNotBlank()) { "id is required" }
        val label = obj.getString("label")
        require(label.isNotBlank()) { "label is required" }
        val iconBase64 = obj.getString("iconBase64")
        require(iconBase64.isNotBlank()) { "iconBase64 is required" }
        return UnityDirectShareTargetSpec(
            id = id,
            label = label,
            iconBase64 = iconBase64,
            category = obj.optString("category").ifBlank { "android.shortcut.conversation" }
        )
    }

    fun parseRemoveDirectShareTargets(json: String): UnityRemoveDirectShareTargetsSpec {
        Log.d(TAG, "[parseRemoveDirectShareTargets] json: $json")
        val obj = JSONObject(json)
        val ids = parseStringArray(obj.getJSONArray("ids"))
        require(ids.isNotEmpty()) { "ids must not be empty" }
        return UnityRemoveDirectShareTargetsSpec(ids = ids)
    }

    private fun parseChooserActions(array: JSONArray?): List<UnityChooserActionSpec> {
        array ?: return emptyList()
        return (0 until array.length()).mapNotNull { i ->
            val obj = array.getJSONObject(i)
            val label = obj.optString("label").takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val iconBase64 = obj.optString("iconBase64").takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val intentAction = obj.optString("intentAction").takeIf { it.isNotBlank() } ?: return@mapNotNull null
            UnityChooserActionSpec(
                label = label,
                iconBase64 = iconBase64,
                intentAction = intentAction
            )
        }
    }

    private fun parseStringArray(array: JSONArray): List<String> {
        return (0 until array.length()).map { array.getString(it) }
    }
}
