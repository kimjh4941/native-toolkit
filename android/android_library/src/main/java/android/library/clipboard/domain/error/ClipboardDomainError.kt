package android.library.clipboard.domain.error

/**
 * Domain errors for clipboard operations.
 */
sealed class ClipboardDomainError : Exception() {
    /** Copy content is blank (HTML body or required text is empty). */
    data object EmptyContent : ClipboardDomainError()
    /** The item list for a multiple-text copy is empty. */
    data object EmptyItemList : ClipboardDomainError()
    /** The URI is blank or cannot be parsed. */
    data class InvalidUri(val uri: String) : ClipboardDomainError()
    /** ClipboardManager could not be obtained from the system. */
    data object ClipboardUnavailable : ClipboardDomainError()
    /**
     * Read was explicitly denied by the system (SecurityException).
     *
     * A plain null result (empty clipboard, or an implicit null caused by background read
     * restrictions) is not mapped to this error; it is treated as the normal empty case.
     */
    data object ReadNotAllowed : ClipboardDomainError()
}
