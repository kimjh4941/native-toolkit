package android.library.clipboard.application.usecase

import android.library.clipboard.application.port.ClipboardRepository
import android.library.clipboard.domain.error.ClipboardDomainError
import android.library.clipboard.domain.model.ClipContent
import android.util.Log

/**
 * Use case for copying a URI (content://, including image and file references) to the clipboard.
 *
 * @param repository Clipboard repository.
 */
class CopyUriUseCase(private val repository: ClipboardRepository) {
    /**
     * Validates and copies [content] to the clipboard.
     *
     * The URI must be non-blank and use one of [ALLOWED_URI_SCHEMES]. `android.net.Uri` is not
     * used here (Application layer stays platform-agnostic); the actual platform-level URI
     * resolution happens in the Data layer when the clip is built.
     *
     * @param content URI content to copy.
     */
    operator fun invoke(content: ClipContent.UriContent) {
        Log.d(TAG, "[invoke] uriScheme: ${schemeOf(content.uri)}, label: ${content.label}, isSensitive: ${content.isSensitive}")
        if (content.uri.isBlank()) throw ClipboardDomainError.InvalidUri(content.uri)
        if (schemeOf(content.uri) !in ALLOWED_URI_SCHEMES) throw ClipboardDomainError.InvalidUri(content.uri)
        repository.copy(content)
    }

    private fun schemeOf(uri: String): String =
        uri.substringBefore("://", missingDelimiterValue = "")

    companion object {
        private const val TAG = "android.library.clipboard.application.usecase.CopyUriUseCase"
        private val ALLOWED_URI_SCHEMES = setOf("content", "file")
    }
}
