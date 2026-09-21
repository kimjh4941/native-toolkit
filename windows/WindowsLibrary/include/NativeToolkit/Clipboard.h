/**
 * @file Clipboard.h
 * @brief The clipboard session and the values its operations exchange.
 * @details
 *  Part of the public C++ API added in stage 3 of the windows-architecture
 *  topic (design sections 7.4.1 and 8). This header carries the session and
 *  its lifetime; the synchronous operations, deferred rendering and the
 *  history arrive with OP-25..OP-47.
 *
 *  Keep this header ASCII only.
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

#include "NativeToolkit/BuildStamp.h"
#include "NativeToolkit/Error.h"

namespace NativeToolkit::Clipboard {

/**
 * @brief Identifies an accepted asynchronous request.
 * @details A strong type, so that a request is never confused with a count and
 *          the value zero is never read as "no request".
 */
enum class RequestId : uint32_t {};

/// Text under a named format.
struct TextPayload { std::wstring formatName; std::wstring text; };

/// An HTML fragment. The CF_HTML header is built inside the library.
struct HtmlPayload { std::wstring formatName; std::wstring html; };

/// Arbitrary bytes under a named format.
struct BytesPayload { std::wstring formatName; std::vector<std::byte> bytes; };

/// One item of a multi-format write. A variant, so no item can be half text and half bytes.
using FormatPayload = std::variant<TextPayload, HtmlPayload, BytesPayload>;

/// An entry of the clipboard history.
struct HistoryItem {
    std::wstring                id;
    std::optional<std::wstring> text;            ///< Absent for an item that carries no text.
    std::vector<std::wstring>   contentTypes;    ///< As the OS reports them, unaltered.
    int64_t                     timestampTicks = 0;
};

/// Whether the OS has the history and its roaming turned on.
struct HistoryAvailability {
    bool historyEnabled = false;
    bool roamingEnabled = false;
};

/**
 * @brief What to be told about the history.
 * @details
 *  Passing a default-constructed value unregisters every handler.
 *
 *  Handlers arrive on the thread that created the session, and are not moved
 *  to any other (CLP-04). onHistoryChanged fires when an item is added, not
 *  when one is removed or the history is cleared (CLP-31).
 */
struct HistoryHandlers {
    std::function<void()>     onHistoryChanged;
    std::function<void(bool)> onHistoryEnabledChanged;
    std::function<void(bool)> onRoamingEnabledChanged;
};

/**
 * @brief What the OS may do with what is written.
 * @details Both default to allowed, which is what a write with no options
 *          means today. Setting both is what "sensitive" means.
 */
struct WriteOptions {
    bool excludeFromHistory = false;  ///< Keep it out of the clipboard history.
    bool excludeFromRoaming = false;  ///< Do not let it reach other devices.
};

/**
 * @brief What Session::Create needs.
 * @details onClipboardChanged is called when the clipboard changes because of
 *          something other than this session's own writes. It arrives on the
 *          creating thread, never inside the call that caused it. Leaving it
 *          empty skips registering the listener, which is also what makes a
 *          failure to register it survivable.
 */
struct SessionOptions {
    std::function<void()> onClipboardChanged;
};

/**
 * @brief Produces the bytes of a reserved format, when something asks for them.
 * @details
 *  Called on the thread that owns the session, from inside the message the OS
 *  sends to collect the data. That places three hard limits on what it may do:
 *  it must not call any clipboard operation, including this session's own; it
 *  must not block, because the asking application is waiting; and it must not
 *  capture the session, which would be a cycle.
 *
 *  Returning a failure, or throwing, means the format renders as nothing: by
 *  then the reservation has been made and the asking application is mid-paste,
 *  so there is no one left to report to. Both are logged.
 */
using RenderProvider = std::function<Result<std::vector<std::byte>>(std::wstring_view formatName)>;

/// Told how a request that produces no payload ended.
using CompletionHandler = std::function<void(RequestId, Result<void>)>;

/// Told what the history holds, or why it could not be read.
using HistoryItemsHandler = std::function<void(RequestId, Result<std::vector<HistoryItem>>)>;

/// Told what the OS has the history and its roaming set to.
using AvailabilityHandler = std::function<void(RequestId, Result<HistoryAvailability>)>;

/**
 * @brief The clipboard of this process.
 * @details
 *  Create must be called from a thread that is already an initialised STA and
 *  that runs a message pump: the clipboard is a windowed, thread-affine part
 *  of Windows, and the session builds a window on that thread to receive its
 *  messages. That thread owns the session; the synchronous operations may be
 *  called from any thread, but the ones marked owner-only may not.
 *
 *  There is one clipboard per process, so a second Create fails: NotSupported
 *  when it comes from the owning thread, WrongThread from any other.
 *
 *  **Closing is the caller's job.** Close reports the same five reasons the C
 *  ABI reports, and a caller that gets one is expected to deal with it and try
 *  again - that is why Close returns a Result and the destructor does not.
 *
 *  **The destructor abandons.** Destroying a session that has not been closed
 *  successfully leaves its window, its listeners and its pending requests in
 *  place until the process exits, asserts in a debug build and logs in a
 *  release one. It does not try to tidy up on another thread: no Win32 call
 *  tells us whether a message pump will run again, so a destructor that posted
 *  work could only pretend to have cleaned up. From then on Create keeps
 *  failing and there is no way back.
 *
 *  **Inside a callback**, do not destroy the session, and do not call Close or
 *  SetHistoryHandlers on it: both change the gate the callback is running
 *  under, and a debug build asserts (CLP-05, CLP-34). Do not capture the
 *  session in a handler you give it either - that is a cycle.
 */
class Session {
public:
    /**
     * @brief Opens the clipboard for this process on the calling thread.
     * @retval WrongApartment        The calling thread is not an initialised STA.
     * @retval MonitorRegisterFailed onClipboardChanged was given and its listener could not be registered.
     * @retval OutOfMemory           The session could not be built.
     * @retval Unknown               The window that receives the session's messages could not be created.
     * @retval NotSupported          A session already exists, and this is its thread; or one was abandoned.
     * @retval WrongThread           A session already exists on another thread.
     */
    static Result<Session> Create(const SessionOptions& options);

    Session(Session&& other) noexcept;
    Session& operator=(Session&& other) noexcept;
    Session(const Session&) = delete;
    Session& operator=(const Session&) = delete;

    /// Abandons an unclosed session; see the class note.
    ~Session();

    /**
     * @brief Closes the session.
     * @details Must be called from the owning thread. Closing an already
     *          closed session succeeds, so a retry loop can call it until it
     *          does.
     * @retval WrongThread           Called from a thread other than the owner.
     * @retval MonitorRegisterFailed A clipboard or history listener could not be dropped.
     * @retval Canceled              Requests were still being drained.
     * @retval Busy                  Something still holds the session open.
     * @retval PartialState          A half-finished write could not be rolled back.
     */
    Result<void> Close();

    /**
     * @brief Whether a shutdown that is under way can finish.
     * @details
     *  This answers "is there anything left to wait for" - no listener, no
     *  event token, no queued completion, no synchronous call in progress -
     *  which is the question a retry loop between two Close attempts wants
     *  answered. A session that has not started closing has not closed its
     *  gate, so this is false for an open one; a closed session is true.
     *
     *  Callable from any thread, and advice only: it can be stale the moment
     *  it is returned, and a Close that follows a true can still fail on
     *  rolling back a half-finished write. Close is what decides.
     */
    bool CanClose() const noexcept;

    /**
     * @brief Installs or, with a default-constructed value, removes the history handlers.
     * @details Owner thread only, and never from inside one of the session's
     *          own callbacks (CLP-05).
     * @retval NotInitialized        Closed, or moved from.
     * @retval WrongThread           Called from a thread other than the owner.
     * @retval MonitorRegisterFailed The history event could not be subscribed to.
     */
    Result<void> SetHistoryHandlers(HistoryHandlers handlers);

    // --- The synchronous core (OP-25..OP-39) -------------------------------
    //
    // Callable from any thread. Each one opens and closes the clipboard for
    // itself, so between two of them anything may have changed it.
    //
    // A wstring_view argument is read only up to its own length: it does not
    // have to be NUL terminated, and a view into the middle of a larger string
    // is fine. A NUL inside one is InvalidParameter rather than a silent
    // truncation, because the clipboard formats underneath are NUL terminated
    // and could not carry the rest.

    /**
     * @brief Writes text as CF_UNICODETEXT.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL, or one the format cannot take.
     * @retval Busy             Another process kept the clipboard open.
     * @retval OutOfMemory      The data could not be copied into place.
     * @retval Unknown          The clipboard refused the write.
     */
    Result<void> CopyText(std::wstring_view text, WriteOptions options = {});

    /**
     * @brief Reads CF_UNICODETEXT.
     * @retval NotInitialized    Closed, or moved from.
     * @retval Busy              Another process kept the clipboard open.
     * @retval Empty             The clipboard holds nothing.
     * @retval FormatUnavailable The clipboard holds something, but not this.
     * @retval InvalidData       What is there is not in the shape this format promises.
     * @retval OutOfMemory       The data could not be copied out.
     */
    Result<std::wstring> PasteText();

    /**
     * @brief Writes an HTML fragment as CF_HTML, with plainText as the text fallback.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL, or one the format cannot take.
     * @retval Busy             Another process kept the clipboard open.
     * @retval OutOfMemory      The data could not be copied into place.
     * @retval Unknown          The clipboard refused the write.
     */
    Result<void> CopyHtml(std::wstring_view fragment, std::wstring_view plainText,
                          WriteOptions options = {});

    /**
     * @brief Reads the fragment out of CF_HTML, without its header.
     * @retval NotInitialized    Closed, or moved from.
     * @retval Busy              Another process kept the clipboard open.
     * @retval Empty             The clipboard holds nothing.
     * @retval FormatUnavailable The clipboard holds something, but not this.
     * @retval InvalidData       What is there is not in the shape this format promises.
     * @retval OutOfMemory       The data could not be copied out.
     */
    Result<std::wstring> PasteHtml();

    /**
     * @brief Writes paths as CF_HDROP.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL, or one the format cannot take.
     * @retval Busy             Another process kept the clipboard open.
     * @retval OutOfMemory      The data could not be copied into place.
     * @retval Unknown          The clipboard refused the write.
     */
    Result<void> CopyFiles(std::span<const std::wstring> paths, WriteOptions options = {});

    /**
     * @brief Reads the paths of CF_HDROP.
     * @retval NotInitialized    Closed, or moved from.
     * @retval Busy              Another process kept the clipboard open.
     * @retval Empty             The clipboard holds nothing.
     * @retval FormatUnavailable The clipboard holds something, but not this.
     * @retval InvalidData       What is there is not in the shape this format promises.
     * @retval OutOfMemory       The data could not be copied out.
     */
    Result<std::vector<std::wstring>> PasteFiles();

    /**
     * @brief Writes an image as CF_DIB.
     * @details The bytes are a device-independent bitmap, header first and
     *          with no BITMAPFILEHEADER: this is the clipboard's own shape,
     *          not a .bmp file, and the library does not convert one to the
     *          other.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL, or one the format cannot take.
     * @retval Busy             Another process kept the clipboard open.
     * @retval OutOfMemory      The data could not be copied into place.
     * @retval Unknown          The clipboard refused the write.
     * @retval InvalidData      The bytes are not a well-formed bitmap.
     */
    Result<void> CopyDib(std::span<const std::byte> dib, WriteOptions options = {});

    /**
     * @brief Reads CF_DIB, in the same shape CopyDib takes.
     * @retval NotInitialized    Closed, or moved from.
     * @retval Busy              Another process kept the clipboard open.
     * @retval Empty             The clipboard holds nothing.
     * @retval FormatUnavailable The clipboard holds something, but not this.
     * @retval InvalidData       What is there is not in the shape this format promises.
     * @retval OutOfMemory       The data could not be copied out.
     */
    Result<std::vector<std::byte>> PasteDib();

    /**
     * @brief Writes bytes under a registered format name.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL, or one the format cannot take.
     * @retval Busy             Another process kept the clipboard open.
     * @retval OutOfMemory      The data could not be copied into place.
     * @retval Unknown          The clipboard refused the write.
     */
    Result<void> CopyCustom(std::wstring_view formatName, std::span<const std::byte> data,
                            WriteOptions options = {});

    /**
     * @brief Reads the bytes of a registered format.
     * @retval NotInitialized    Closed, or moved from.
     * @retval Busy              Another process kept the clipboard open.
     * @retval Empty             The clipboard holds nothing.
     * @retval FormatUnavailable The clipboard holds something, but not this.
     * @retval InvalidData       What is there is not in the shape this format promises.
     * @retval OutOfMemory       The data could not be copied out.
     * @retval InvalidParameter  A format name with an embedded NUL.
     */
    Result<std::vector<std::byte>> PasteCustom(std::wstring_view formatName);

    /**
     * @brief Writes several formats of one thing in a single operation.
     * @details
     *  The items are placed in the order given, so put the richest first: that
     *  is the order a reader walks. Every item is checked before anything is
     *  placed, so a bad one leaves the clipboard untouched rather than half
     *  written. Naming the same format twice is InvalidParameter.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL, or one the format cannot take.
     * @retval Busy             Another process kept the clipboard open.
     * @retval OutOfMemory      The data could not be copied into place.
     * @retval Unknown          The clipboard refused the write.
     * @retval InvalidData      A bitmap or a file list that is not well formed.
     * @retval PartialState     A placement failed and so did the rollback.
     */
    Result<void> CopyMultiple(std::span<const FormatPayload> items, WriteOptions options = {});

    /**
     * @brief Whether the clipboard currently offers that format.
     * @details
     *  A name no format has, including an empty one, is simply absent rather
     *  than an error.
     *
     *  Asking registers the name with the OS as a side effect: a clipboard
     *  format name is registered the first time anything looks it up, and it
     *  stays registered for the session of the machine (CLP-141).
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter A name with an embedded NUL.
     */
    Result<bool> HasFormat(std::wstring_view formatName);

    /**
     * @brief Every format the clipboard offers, in the order the OS reports them.
     * @details A format with no registered name is reported as "0x____".
     * @retval NotInitialized Closed, or moved from.
     * @retval Busy           Another process kept the clipboard open.
     * @retval Unknown        The list could not be read.
     */
    Result<std::vector<std::wstring>> GetFormats();

    /**
     * @brief The format a reader should prefer, or an empty name when there is none.
     * @retval NotInitialized Closed, or moved from.
     */
    Result<std::wstring> GetPreferredFormat();

    /**
     * @brief Empties the clipboard.
     * @retval NotInitialized Closed, or moved from.
     * @retval Busy           Another process kept the clipboard open.
     * @retval Unknown        The clipboard refused.
     */
    Result<void> Clear();

    // --- Deferred rendering (OP-40, OP-41) ---------------------------------
    //
    // Owner thread only: these run on the same thread the messages arrive on.

    /**
     * @brief Offers formats without producing them, until someone asks.
     * @details
     *  Use it when the data is expensive and most pastes will not want it. The
     *  names and the provider are copied, so neither has to outlive the call.
     *
     *  Only formats the OS can hold as a block of memory can be deferred; a
     *  handle format such as CF_BITMAP cannot.
     *
     *  Naming the same format twice is not an error here: the later one takes
     *  its place. CopyMultiple refuses the same thing, and the difference is
     *  kept rather than silently changed (CLP-138).
     *
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter No formats, an unknown name, or no provider.
     * @retval WrongThread      Called from a thread other than the owner.
     * @retval PartialState     The reservation failed partway and could not be
     *                          rolled back; call RecoverDeferredState.
     * @retval Unknown          The clipboard refused the reservation.
     */
    Result<void> ReserveDeferred(std::span<const std::wstring> formats, RenderProvider provider);

    /**
     * @brief Retries the rollback a failed reservation left undone.
     * @details Succeeds, and does nothing, when there is nothing to recover.
     *          Owner thread only.
     * @retval NotInitialized Closed, or moved from.
     * @retval WrongThread    Called from a thread other than the owner.
     * @retval PartialState   The rollback failed again.
     */
    Result<void> RecoverDeferredState();

    // --- The clipboard history (OP-42..OP-47) ------------------------------
    //
    // These five ask; they do not answer. Each returns as soon as the request
    // is accepted, and the handler is called later, on the thread that owns
    // the session, exactly once - never inside the call that made the request.
    // A request that is not accepted has no handler call at all.
    //
    // The requests themselves may be made from any thread.

    /**
     * @brief Asks for what the history holds.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL.
     * @retval OutOfMemory      The request could not be recorded.
     * @retval Unknown          The request could not be handed to the owning thread.
     */
    Result<RequestId> GetHistory(HistoryItemsHandler handler);

    /**
     * @brief Asks for an item to be put back on the clipboard.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL.
     * @retval OutOfMemory      The request could not be recorded.
     * @retval Unknown          The request could not be handed to the owning thread.
     */
    Result<RequestId> RestoreHistoryItem(std::wstring_view itemId, CompletionHandler handler);

    /**
     * @brief Asks for an item to be removed from the history.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL.
     * @retval OutOfMemory      The request could not be recorded.
     * @retval Unknown          The request could not be handed to the owning thread.
     */
    Result<RequestId> DeleteHistoryItem(std::wstring_view itemId, CompletionHandler handler);

    /**
     * @brief Asks for the history to be emptied.
     * @details Pinned items stay (CLP-82).
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL.
     * @retval OutOfMemory      The request could not be recorded.
     * @retval Unknown          The request could not be handed to the owning thread.
     */
    Result<RequestId> ClearUnpinnedHistory(CompletionHandler handler);

    /**
     * @brief Asks whether the OS has the history, and its roaming, turned on.
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter An argument with an embedded NUL.
     * @retval OutOfMemory      The request could not be recorded.
     * @retval Unknown          The request could not be handed to the owning thread.
     */
    Result<RequestId> GetHistoryAvailability(AvailabilityHandler handler);

    /**
     * @brief Gives up on a request.
     * @details
     *  Callable from any thread. This cancels the request, not its answer: a
     *  completion already on its way is still delivered, with Canceled, so the
     *  handler is called exactly once either way.
     *
     * @retval NotInitialized   Closed, or moved from.
     * @retval InvalidParameter No such request, or it has already finished.
     * @retval Unknown          The cancellation could not be handed to the owning thread.
     */
    Result<void> CancelRequest(RequestId id);

private:
    Session() = default;

    /// Gives up an unclosed session without trying to close it.
    void Abandon() noexcept;

    bool held_ = false;
};

}  // namespace NativeToolkit::Clipboard
