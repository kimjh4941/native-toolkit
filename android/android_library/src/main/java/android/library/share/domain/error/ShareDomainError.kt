package android.library.share.domain.error

/**
 * Domain errors for share operations.
 */
sealed class ShareDomainError : Exception() {
    /** Share text is blank. */
    data object EmptyContent : ShareDomainError()
    /** No app is available to handle the share intent. */
    data object NoShareTarget : ShareDomainError()
    /** The specified file does not exist at the given path. */
    data class FileNotFound(val path: String) : ShareDomainError()
    /** The file cannot be shared because the path is outside the FileProvider scope. */
    data class IllegalFileAccess(val path: String) : ShareDomainError()
    /** The MIME type is blank or invalid. */
    data class InvalidMimeType(val mimeType: String) : ShareDomainError()
    /** Direct Share target registration failed. */
    data class DirectShareRegistrationFailed(val reason: String) : ShareDomainError()
    /** Shortcut ID list for removal is empty. */
    data object EmptyIdList : ShareDomainError()
    /** File path list for multi-file share is empty. */
    data object EmptyFileList : ShareDomainError()
    /** Base64 icon decoding failed for the given target ID. */
    data class InvalidBase64Icon(val id: String) : ShareDomainError()
}
