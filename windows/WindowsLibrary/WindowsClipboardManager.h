/**
 * @file WindowsClipboardManager.h
 * @brief Public C Bridge API for the Windows Clipboard Manager.
 * @details
 *  Provides clipboard copy/paste (text, HTML, files, images, custom formats),
 *  content inspection, change monitoring, deferred rendering, and clipboard
 *  history access via WinRT Windows.ApplicationModel.DataTransfer.Clipboard.
 *  Minimum OS: Windows 11.
 *
 *  See artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md
 *  for the full concurrency and lifecycle contract summarized in the notes
 *  below.
 */
#pragma once

#include <windows.h>
#include <cstdint>

#ifdef WINDOWSLIBRARY_EXPORTS
#define WINDOWSCLIPBOARDMANAGER_API __declspec(dllexport)
#else
#define WINDOWSCLIPBOARDMANAGER_API __declspec(dllimport)
#endif

// ---------------------------------------------------------------------------
// Error codes (0 = success, non-success values 1-19)
// ---------------------------------------------------------------------------
#define CLIPBOARD_ERROR_NONE                     0
#define CLIPBOARD_ERROR_INVALID_PARAMETER        1
#define CLIPBOARD_ERROR_NOT_INITIALIZED          2
#define CLIPBOARD_ERROR_BUSY                     3
#define CLIPBOARD_ERROR_EMPTY                    4
#define CLIPBOARD_ERROR_FORMAT_UNAVAILABLE       5
#define CLIPBOARD_ERROR_INVALID_DATA             6
#define CLIPBOARD_ERROR_BUFFER_TOO_SMALL         7
#define CLIPBOARD_ERROR_OUT_OF_MEMORY            8
#define CLIPBOARD_ERROR_ACCESS_DENIED            9
#define CLIPBOARD_ERROR_HISTORY_DISABLED         10
#define CLIPBOARD_ERROR_ITEM_DELETED             11
#define CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED  12
#define CLIPBOARD_ERROR_PARTIAL_STATE            13
#define CLIPBOARD_ERROR_WRONG_THREAD             14
#define CLIPBOARD_ERROR_CANCELED                 15
#define CLIPBOARD_ERROR_NOT_SUPPORTED            16
#define CLIPBOARD_ERROR_NOT_FOREGROUND           17
#define CLIPBOARD_ERROR_WRONG_APARTMENT          18
#define CLIPBOARD_ERROR_UNKNOWN                  19

// ---------------------------------------------------------------------------
// Write options shared by every copy API (bit flags).
// ---------------------------------------------------------------------------
#define CLIPBOARD_WRITE_OPTION_NONE              0x00000000u
#define CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY   0x00000001u  // CanIncludeInClipboardHistory = 0
#define CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING   0x00000002u  // CanUploadToCloudClipboard = 0
#define CLIPBOARD_WRITE_OPTION_SENSITIVE         0x00000003u  // both of the above

// ---------------------------------------------------------------------------
// Callback types
// ---------------------------------------------------------------------------

/** @brief Invoked on the owner UI thread when the clipboard contents change. */
typedef void (*ClipboardChangedCallback)(void);

/** @brief Invoked on the owner UI thread when a NEW ITEM is added to the clipboard history. */
typedef void (*ClipboardHistoryChangedCallback)(void);

/** @brief Invoked on the owner UI thread when the history/roaming OS setting is toggled. */
typedef void (*ClipboardFlagChangedCallback)(BOOL enabled);

/**
 * @brief Terminal completion callback for an accepted request.
 * @param requestId The id returned by the originating call.
 * @param error     CLIPBOARD_ERROR_* value.
 * @param json      Result payload, or nullptr on failure or when the operation has
 *                  no payload. VALID ONLY DURING THIS CALLBACK - the caller must
 *                  copy it before returning. The buffer is freed by the toolkit
 *                  afterwards.
 * @note Runs on the owner UI thread, exactly once per accepted request. After a
 *       request is accepted (nonzero request id), the function pointer must
 *       remain valid through its single terminal callback. P/Invoke callers must
 *       keep the delegate strongly rooted for that period. An acceptance failure
 *       (id 0) does not retain the callback.
 */
typedef void (*ClipboardRequestCallback)(uint32_t requestId, DWORD error, const wchar_t* json);

/**
 * @brief Produces the payload for a deferred clipboard format on demand.
 * @param formatName    Registered or standard format name being requested.
 * @param context       Opaque pointer supplied at reservation time.
 * @param buffer        Destination buffer, or nullptr to query the required size.
 * @param buffer_size   Size of buffer in bytes (0 when querying).
 * @param pRequiredSize Out: required size in bytes. Must be set in both phases.
 * @return CLIPBOARD_ERROR_NONE on success, CLIPBOARD_ERROR_BUFFER_TOO_SMALL when
 *         buffer is null or too small (with *pRequiredSize set), otherwise an error.
 * @note Invoked on the owner UI thread, inside WM_RENDERFORMAT handling.
 *       Must not call any clipboard API, must not block, and must not throw.
 */
typedef DWORD (*ClipboardRenderCallback)(const wchar_t* formatName,
                                         void* context,
                                         BYTE* buffer,
                                         DWORD buffer_size,
                                         DWORD* pRequiredSize);

// ---------------------------------------------------------------------------
// Initialization / shutdown
// ---------------------------------------------------------------------------

/**
 * @brief Initializes the clipboard manager.
 * @param onChanged Invoked when the clipboard contents change (nullable).
 * @param pError    Out error code.
 * @note PRECONDITIONS for the calling thread, which is adopted as the owner UI thread:
 *       1) It must run a message pump for the lifetime of the manager. This cannot be
 *          verified at runtime, so it is a caller contract, not a checked error.
 *       2) It must already be initialized as an STA (CoInitializeEx with
 *          COINIT_APARTMENTTHREADED, or winrt::init_apartment(single_threaded)).
 *          This IS checked: an uninitialized or MTA thread returns
 *          CLIPBOARD_ERROR_WRONG_APARTMENT and the manager is not initialized.
 *       The toolkit never initializes or uninitializes the apartment: it belongs to
 *       the host. Calling init again from a different thread returns
 *       CLIPBOARD_ERROR_WRONG_THREAD. Calling it again from the same thread is
 *       idempotent success.
 *       The function pointer must stay valid until uninitClipboardManager returns TRUE.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void initClipboardManager(ClipboardChangedCallback onChanged, DWORD* pError);

/**
 * @brief Registers (or clears) history event callbacks and starts/stops watching.
 * @note Synchronous, and MUST be called from the owner UI thread; otherwise
 *       CLIPBOARD_ERROR_WRONG_THREAD. Not callable from inside a callback.
 *       Passing all three as nullptr stops watching and clears the registration.
 *       Replacing an existing registration only swaps an internal snapshot and
 *       therefore cannot fail. Partial failure - and the "previous registration is
 *       kept" rule - applies only to the FIRST registration, where the underlying
 *       event tokens are acquired. If a previous stop failed to revoke every token,
 *       re-registration is refused until a later call succeeds in stopping.
 *       The function pointers must stay valid until they are replaced or until
 *       uninitClipboardManager returns TRUE.
 *       onHistoryChanged fires only when a NEW ITEM is added; deletions and
 *       ClearHistory are not guaranteed to raise it. Re-query after your own
 *       delete/clear calls.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void setClipboardHistoryCallbacks(ClipboardHistoryChangedCallback onHistoryChanged,
                                  ClipboardFlagChangedCallback onHistoryEnabledChanged,
                                  ClipboardFlagChangedCallback onRoamingEnabledChanged,
                                  DWORD* pError);

/**
 * @brief Shuts the manager down. Expects to be called more than once.
 * @return TRUE when shutdown completed and all resources were released.
 *         FALSE when any of the following is still outstanding - call again after
 *         pumping messages:
 *           - a clipboard listener or history event token could not be revoked
 *           - queued cancellation completions have not been delivered yet
 *           - a request coroutine is still running (even after cancellation)
 *           - an any-thread synchronous API call is still in flight
 * @note MUST be called from the owner UI thread, and never from inside a callback.
 *       The first call always returns FALSE when any request is pending, because
 *       cancellations are queued rather than fired inline. Keep the message pump
 *       running between retries; do not spin while blocking the UI thread.
 *       The toolkit never calls uninit_apartment: the apartment belongs to the host.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
BOOL uninitClipboardManager(DWORD* pError);

/**
 * @brief Non-blocking query of whether shutdown can complete.
 * @return TRUE when no listener, event token, queued drain callback, request
 *         coroutine or in-flight synchronous call remains. This is a state query
 *         only: it does NOT promise that the next uninit succeeds, because that
 *         call can still fail on partial-state recovery or an OS API error.
 *         Judge the final result by the uninit return value.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
BOOL canDestroyClipboardManager(DWORD* pError);

// ---------------------------------------------------------------------------
// Synchronous API - Win32 core (F-01 .. F-08, F-10, F-11)
// ---------------------------------------------------------------------------

/** @brief Copies plain text to the clipboard. @param options CLIPBOARD_WRITE_OPTION_* flags. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void copyPlainText(const wchar_t* text, DWORD options, DWORD* pError);

/**
 * @brief Reads plain text from the clipboard.
 * @return Required buffer size in wchar_t (including terminator). If buffer is
 *         null or buffer_size is too small, returns the required size and sets
 *         *pError to CLIPBOARD_ERROR_BUFFER_TOO_SMALL.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
DWORD pastePlainText(wchar_t* buffer, DWORD buffer_size, DWORD* pError);

/** @brief Copies an HTML fragment (with a plain-text fallback) to the clipboard. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void copyHtml(const wchar_t* htmlFragment, const wchar_t* plainText, DWORD options, DWORD* pError);

/** @brief Reads the HTML fragment (UTF-16, decoded from CF_HTML's UTF-8 payload) from the clipboard. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
DWORD pasteHtml(wchar_t* buffer, DWORD buffer_size, DWORD* pError);

/** @brief Copies a list of file paths (JSON array of strings) to the clipboard as CF_HDROP. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void copyFiles(const wchar_t* pathsJson, DWORD options, DWORD* pError);

/** @brief Reads a CF_HDROP file list from the clipboard as a JSON array of strings. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
DWORD pasteFiles(wchar_t* buffer, DWORD buffer_size, DWORD* pError);

/** @brief Copies a device-independent bitmap (CF_DIB) to the clipboard. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void copyImage(const BYTE* dib, DWORD dibSize, DWORD options, DWORD* pError);

/**
 * @brief Reads a device-independent bitmap (CF_DIB) from the clipboard.
 * @return Required buffer size in bytes. If buffer is null or too small, returns
 *         the required size and sets *pError to CLIPBOARD_ERROR_BUFFER_TOO_SMALL.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
DWORD pasteImage(BYTE* buffer, DWORD buffer_size, DWORD* pError);

/** @brief Copies raw bytes to the clipboard under a registered custom format name. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void copyCustomFormat(const wchar_t* formatName, const BYTE* data, DWORD size, DWORD options, DWORD* pError);

/** @brief Reads raw bytes from the clipboard under a registered custom format name. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
DWORD pasteCustomFormat(const wchar_t* formatName, BYTE* buffer, DWORD buffer_size, DWORD* pError);

/**
 * @brief Places several formats on the clipboard in one operation (F-06).
 * @param itemsJson JSON array, richest format first. Each item has exactly one
 *        payload key: "text" (text-shaped formats only), "html" (builds a full
 *        CF_HTML payload; text-shaped formats only), or "base64" (raw bytes,
 *        any format; structurally validated when the format is a known binary
 *        one such as CF_DIB/CF_DIBV5/CF_HDROP), e.g.
 *        [{"format":"CF_UNICODETEXT","text":"..."},{"format":"HTML Format","html":"..."},
 *         {"format":"CF_DIB","base64":"..."}]
 *        Duplicate `format` entries and a payload kind that doesn't match the
 *        target format (e.g. "text" under CF_HDROP) are rejected with
 *        CLIPBOARD_ERROR_INVALID_PARAMETER before anything is placed.
 * @note best-effort rollback: on partial failure the clipboard is emptied again.
 *       If that rollback also fails, *pError is CLIPBOARD_ERROR_PARTIAL_STATE and
 *       some formats may remain on the clipboard.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void copyMultipleFormats(const wchar_t* itemsJson, DWORD options, DWORD* pError);

/** @brief Returns whether the clipboard currently holds the given format (name or CF_* constant name). */
extern "C" WINDOWSCLIPBOARDMANAGER_API
BOOL hasClipboardFormat(const wchar_t* formatName, DWORD* pError);

/** @brief Returns the currently available clipboard formats as a JSON array of format names. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
DWORD getClipboardFormats(wchar_t* buffer, DWORD buffer_size, DWORD* pError);

/** @brief Returns the name of the most descriptive available format the caller understands. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
DWORD getPreferredClipboardFormat(wchar_t* buffer, DWORD buffer_size, DWORD* pError);

/** @brief Empties the clipboard. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void clearClipboard(DWORD* pError);

/**
 * @brief Reserves one or more formats for delayed rendering (F-10).
 * @param formatNamesJson JSON array of format names to reserve.
 * @note UI-thread-limited synchronous API. Non-owner threads get CLIPBOARD_ERROR_WRONG_THREAD.
 *       On partial failure the reservation is rolled back (best-effort; see
 *       CLIPBOARD_ERROR_PARTIAL_STATE).
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void reserveDeferredFormats(const wchar_t* formatNamesJson, ClipboardRenderCallback provider,
                            void* context, DWORD* pError);

/** @brief Retries recovery from a CLIPBOARD_ERROR_PARTIAL_STATE left by a failed rollback. UI-thread-limited. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void recoverDeferredState(DWORD* pError);

// ---------------------------------------------------------------------------
// Asynchronous API - WinRT clipboard history (F-12)
// ---------------------------------------------------------------------------

/**
 * @brief Requests the clipboard history list.
 * @return Nonzero request id on acceptance (0 on rejection; callback not invoked).
 * @note On success, cb receives a JSON array. `timestamp` is a decimal string
 *       (100ns FILETIME-scale ticks since 1601) rather than a JSON number,
 *       because a JSON number's double precision cannot represent the full
 *       int64 range without loss:
 *       [{"id":"...","text":"..."|null,"contentTypes":["Text","Bitmap"],"timestamp":"<int64>"}]
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
uint32_t getClipboardHistory(ClipboardRequestCallback cb, DWORD* pError);

/** @brief Restores a clipboard history item as the current clipboard content. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
uint32_t restoreHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError);

/** @brief Deletes one clipboard history item. */
extern "C" WINDOWSCLIPBOARDMANAGER_API
uint32_t deleteHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError);

/** @brief Clears the clipboard history. Pinned items are not removed (OS behavior). */
extern "C" WINDOWSCLIPBOARDMANAGER_API
uint32_t clearUnpinnedHistory(ClipboardRequestCallback cb, DWORD* pError);

/**
 * @brief Queries clipboard history/roaming availability.
 * @note On success, cb receives: {"historyEnabled":true,"roamingEnabled":false}
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
uint32_t getClipboardHistoryAvailability(ClipboardRequestCallback cb, DWORD* pError);

/**
 * @brief Requests cancellation of a pending request.
 * @return TRUE when the cancellation was queued to the owner UI thread.
 *         FALSE when the id is unknown, already completed, or the post failed
 *         (see pError). A FALSE return does NOT suppress a completion that is
 *         already on its way.
 * @note Callable from any thread. The callback still fires exactly once, on the
 *       owner UI thread, with CLIPBOARD_ERROR_CANCELED when cancellation wins.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
BOOL cancelClipboardRequest(uint32_t requestId, DWORD* pError);
