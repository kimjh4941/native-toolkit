package android.unity.clipboard

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

internal object UnityClipboardJsonParser {

    private const val TAG = "android.unity.clipboard.UnityClipboardJsonParser"

    fun parseCopyPlainText(json: String): UnityCopyPlainTextSpec {
        Log.d(TAG, "[parseCopyPlainText] jsonLength: ${json.length}")
        val obj = JSONObject(json)
        return UnityCopyPlainTextSpec(
            text = obj.getString("text"),
            label = obj.optString("label"),
            isSensitive = obj.optBoolean("isSensitive", false)
        )
    }

    fun parseCopyHtmlText(json: String): UnityCopyHtmlTextSpec {
        Log.d(TAG, "[parseCopyHtmlText] jsonLength: ${json.length}")
        val obj = JSONObject(json)
        return UnityCopyHtmlTextSpec(
            plainText = obj.optString("plainText"),
            htmlText = obj.getString("htmlText"),
            label = obj.optString("label"),
            isSensitive = obj.optBoolean("isSensitive", false)
        )
    }

    fun parseCopyUri(json: String): UnityCopyUriSpec {
        Log.d(TAG, "[parseCopyUri] jsonLength: ${json.length}")
        val obj = JSONObject(json)
        return UnityCopyUriSpec(
            uri = obj.getString("uri"),
            label = obj.optString("label"),
            isSensitive = obj.optBoolean("isSensitive", false)
        )
    }

    fun parseCopyMultipleText(json: String): UnityCopyMultipleTextSpec {
        Log.d(TAG, "[parseCopyMultipleText] jsonLength: ${json.length}")
        val obj = JSONObject(json)
        val texts = parseStringArray(obj.getJSONArray("texts"))
        return UnityCopyMultipleTextSpec(
            texts = texts,
            label = obj.optString("label"),
            isSensitive = obj.optBoolean("isSensitive", false)
        )
    }

    private fun parseStringArray(array: JSONArray): List<String> {
        return (0 until array.length()).map { array.getString(it) }
    }
}
