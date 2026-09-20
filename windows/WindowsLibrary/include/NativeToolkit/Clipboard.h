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
#include <string>
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
 * @details Passing a default-constructed value unregisters every handler.
 *          Handlers arrive on the thread that created the session.
 */
struct HistoryHandlers {
    std::function<void()>     onHistoryChanged;
    std::function<void(bool)> onHistoryEnabledChanged;
    std::function<void(bool)> onRoamingEnabledChanged;
};

/**
 * @brief What Session::Create needs.
 * @details onClipboardChanged is called when the clipboard changes because of
 *          something other than this session's own writes. It arrives on the
 *          creating thread, never inside the call that caused it.
 */
struct SessionOptions {
    std::function<void()> onClipboardChanged;
};

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
 *  Never destroy a session from inside one of its own callbacks, and never
 *  capture one in a handler you give it.
 */
class Session {
public:
    /// Opens the clipboard for this process on the calling thread.
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

    /// Installs or, with a default-constructed value, removes the history handlers.
    Result<void> SetHistoryHandlers(HistoryHandlers handlers);

private:
    Session() = default;

    /// Gives up an unclosed session without trying to close it.
    void Abandon() noexcept;

    bool held_ = false;
};

}  // namespace NativeToolkit::Clipboard
