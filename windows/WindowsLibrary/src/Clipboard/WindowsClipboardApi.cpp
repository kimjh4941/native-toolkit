/**
 * @file WindowsClipboardApi.cpp
 * @brief The C++ API of the Clipboard feature, lifetime part (OP-21..OP-24).
 * @details
 *  Thin over the existing manager: the raw DWORD becomes a typed failure and
 *  the session becomes a thing with an owner and an end. No clipboard logic
 *  lives here.
 *
 *  Three differences from the C ABI are deliberate and are what this file is
 *  mostly about.
 *
 *  A second initClipboardManager from the owning thread succeeds and does
 *  nothing. A second Session::Create fails with NotSupported instead, because
 *  handing out a second object that owns the same thing would make it a matter
 *  of luck which one's destructor ran first. From another thread both report
 *  WrongThread.
 *
 *  Destroying a session that was never closed does not close it. The state it
 *  leaves behind is not recoverable, so the process is marked as such and every
 *  later Create is refused rather than handing out a session over wreckage.
 *
 *  The handlers are held here rather than on the Session because the callbacks
 *  the C ABI takes are plain function pointers with nowhere to carry a
 *  std::function. There is at most one session, so one set of slots is enough.
 */
#include "pch.h"

#include <crtdbg.h>
#include <cstring>
#include <mutex>
#include <optional>
#include <utility>
#include <vector>

#include "Clipboard/WindowsClipboardApiInternal.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"
#include "Common/CommonInternal.h"
#include "NativeToolkit/Clipboard.h"

namespace NativeToolkit::Clipboard {

namespace {

const wchar_t* TAG = L"NativeToolkit::Clipboard";

/// What this process has done with its one session.
enum class ProcessState {
    Free,       ///< No session; Create may proceed.
    Live,       ///< A session exists.
    Abandoned,  ///< A session was destroyed without being closed. Nothing can be done.
};

std::mutex   g_stateMutex;
ProcessState g_state      = ProcessState::Free;
DWORD        g_ownerThread = 0;

/// The handlers the one session installed.
std::mutex            g_handlerMutex;
std::function<void()> g_onClipboardChanged;
HistoryHandlers       g_historyHandlers;

void ForwardClipboardChanged()
{
    std::function<void()> handler;
    {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        handler = g_onClipboardChanged;
    }
    if (handler) handler();
}

void ForwardHistoryChanged()
{
    std::function<void()> handler;
    {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        handler = g_historyHandlers.onHistoryChanged;
    }
    if (handler) handler();
}

void ForwardHistoryEnabledChanged(BOOL enabled)
{
    std::function<void(bool)> handler;
    {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        handler = g_historyHandlers.onHistoryEnabledChanged;
    }
    if (handler) handler(enabled != FALSE);
}

void ForwardRoamingEnabledChanged(BOOL enabled)
{
    std::function<void(bool)> handler;
    {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        handler = g_historyHandlers.onRoamingEnabledChanged;
    }
    if (handler) handler(enabled != FALSE);
}

void ClearHandlers()
{
    std::lock_guard<std::mutex> lock(g_handlerMutex);
    g_onClipboardChanged = nullptr;
    g_historyHandlers = HistoryHandlers{};
}

/// Nothing on success, or the case the manager reported.
Result<void> ToResult(DWORD error)
{
    if (error == CLIPBOARD_ERROR_NONE) {
        return {};
    }
    return Unexpected{Error{static_cast<ErrorCode>(error), error}};
}

ClipboardManager& Backing() noexcept
{
    return ClipboardManager::GetInstance();
}

/// The failure a closed or moved-from session gives every data operation.
Error NotOpen()
{
    return Error{ErrorCode::NotInitialized, CLIPBOARD_ERROR_NOT_INITIALIZED};
}

/// The typed failure for a raw code the manager reported.
Error Fail(DWORD error)
{
    return Error{static_cast<ErrorCode>(error), error};
}

/**
 * @brief Takes an owned copy of a borrowed string, or says why it cannot.
 * @details
 *  A wstring_view need not be NUL terminated and may be a window into a larger
 *  string, so the only safe thing to do with one is copy exactly its length
 *  before handing it to anything that expects a C string.
 *
 *  A NUL inside the view is refused rather than silently truncated: every
 *  clipboard format underneath ends at the first NUL, so the rest of what the
 *  caller passed could not be written, and quietly writing a prefix is the
 *  kind of loss that is found much later.
 */
std::optional<Error> Borrow(std::wstring_view view, std::wstring& out)
{
    if (view.find(L'\0') != std::wstring_view::npos) {
        DLog(TAG, L"[Borrow] the argument contains an embedded NUL");
        return Error{ErrorCode::InvalidParameter, CLIPBOARD_ERROR_INVALID_PARAMETER};
    }
    out.assign(view.data(), view.size());
    return std::nullopt;
}

/// The flag word the C ABI uses for the same two choices.
DWORD ToOptionFlags(WriteOptions options)
{
    DWORD flags = CLIPBOARD_WRITE_OPTION_NONE;
    if (options.excludeFromHistory) flags |= CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY;
    if (options.excludeFromRoaming) flags |= CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING;
    return flags;
}

/// std::byte and BYTE are the same byte; the layers underneath spell it BYTE.
std::vector<BYTE> ToRawBytes(std::span<const std::byte> bytes)
{
    std::vector<BYTE> raw(bytes.size());
    if (!bytes.empty()) ::memcpy(raw.data(), bytes.data(), bytes.size());
    return raw;
}

std::vector<std::byte> FromRawBytes(const std::vector<BYTE>& raw)
{
    std::vector<std::byte> bytes(raw.size());
    if (!raw.empty()) ::memcpy(bytes.data(), raw.data(), raw.size());
    return bytes;
}

}  // namespace

// =============================================================================
// Lifetime (OP-21, OP-23, OP-24)
// =============================================================================

Result<Session> Session::Create(const SessionOptions& options)
{
    DLog(TAG, L"[Session::Create]");

    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        if (g_state != ProcessState::Free) {
            // Which of the two it is depends on the caller, not on whether the
            // earlier session is still usable: from another thread the answer
            // is the same one every owner-only call gives.
            const bool sameThread = ::GetCurrentThreadId() == g_ownerThread;
            DFLog(TAG, L"[Session::Create] refused. abandoned=%d, sameThread=%d",
                  g_state == ProcessState::Abandoned, sameThread);
            return Unexpected{Error{sameThread ? ErrorCode::NotSupported : ErrorCode::WrongThread, 0}};
        }
    }

    {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        g_onClipboardChanged = options.onClipboardChanged;
    }

    // Registering the change listener is only worth doing when someone asked
    // to hear about it; the manager treats a null callback as permission to
    // carry on without the listener.
    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().InitClipboardManager(
        options.onClipboardChanged ? &ForwardClipboardChanged : nullptr, &error);
    if (error != CLIPBOARD_ERROR_NONE) {
        ClearHandlers();
        return Unexpected{Error{static_cast<ErrorCode>(error), error}};
    }

    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        g_state = ProcessState::Live;
        g_ownerThread = ::GetCurrentThreadId();
    }

    Session session;
    session.held_ = true;
    return session;
}

Session::Session(Session&& other) noexcept : held_(other.held_)
{
    other.held_ = false;
}

Session& Session::operator=(Session&& other) noexcept
{
    if (this != &other) {
        // Not Close(): this session may not be closable from here, and an
        // assignment is no place to decide that. Whatever it held is abandoned
        // by the same rule the destructor uses.
        Abandon();
        held_ = other.held_;
        other.held_ = false;
    }
    return *this;
}

Session::~Session()
{
    Abandon();
}

Result<void> Session::Close()
{
    if (!held_) {
        // A closed or moved-from session is already in the state Close is
        // meant to reach, so saying so is the honest answer and lets a retry
        // loop stop.
        return {};
    }
    DLog(TAG, L"[Session::Close]");

    DWORD error = CLIPBOARD_ERROR_NONE;
    if (!Backing().Uninit(&error)) {
        // The session stays open and stays this object's to close; the caller
        // is expected to act on the reason and try again.
        return Unexpected{Error{static_cast<ErrorCode>(error), error}};
    }

    ClearHandlers();
    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        g_state = ProcessState::Free;
        g_ownerThread = 0;
    }
    held_ = false;
    return {};
}

bool Session::CanClose() const noexcept
{
    if (!held_) {
        return true;
    }
    DWORD error = CLIPBOARD_ERROR_NONE;
    return Backing().CanDestroy(&error) != FALSE;
}

// =============================================================================
// History handlers (OP-22)
// =============================================================================

Result<void> Session::SetHistoryHandlers(HistoryHandlers handlers)
{
    if (!held_) {
        return Unexpected{Error{ErrorCode::NotInitialized, CLIPBOARD_ERROR_NOT_INITIALIZED}};
    }
    DLog(TAG, L"[Session::SetHistoryHandlers]");

    const bool wantsChanged = static_cast<bool>(handlers.onHistoryChanged);
    const bool wantsEnabled = static_cast<bool>(handlers.onHistoryEnabledChanged);
    const bool wantsRoaming = static_cast<bool>(handlers.onRoamingEnabledChanged);

    {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        g_historyHandlers = std::move(handlers);
    }

    // A handler the caller left empty is passed on as a null pointer, so that
    // a default-constructed HistoryHandlers unregisters everything rather than
    // registering three callbacks that do nothing.
    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().SetHistoryCallbacks(wantsChanged ? &ForwardHistoryChanged : nullptr,
                                  wantsEnabled ? &ForwardHistoryEnabledChanged : nullptr,
                                  wantsRoaming ? &ForwardRoamingEnabledChanged : nullptr,
                                  &error);
    return ToResult(error);
}


// =============================================================================
// The synchronous core (OP-25..OP-39)
// =============================================================================

Result<void> Session::CopyText(std::wstring_view text, WriteOptions options)
{
    if (!held_) return Unexpected{NotOpen()};
    std::wstring owned;
    if (const auto bad = Borrow(text, owned)) return Unexpected{*bad};

    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().CopyText(owned, ToOptionFlags(options), &error);
    return ToResult(error);
}

Result<std::wstring> Session::PasteText()
{
    if (!held_) return Unexpected{NotOpen()};

    std::wstring text;
    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().PasteText(text, &error);
    if (error != CLIPBOARD_ERROR_NONE) return Unexpected{Fail(error)};
    return text;
}

Result<void> Session::CopyHtml(std::wstring_view fragment, std::wstring_view plainText,
                               WriteOptions options)
{
    if (!held_) return Unexpected{NotOpen()};
    std::wstring ownedFragment;
    std::wstring ownedPlain;
    if (const auto bad = Borrow(fragment, ownedFragment)) return Unexpected{*bad};
    if (const auto bad = Borrow(plainText, ownedPlain))   return Unexpected{*bad};

    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().CopyHtmlFragment(ownedFragment, ownedPlain, ToOptionFlags(options), &error);
    return ToResult(error);
}

Result<std::wstring> Session::PasteHtml()
{
    if (!held_) return Unexpected{NotOpen()};

    std::wstring fragment;
    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().PasteHtmlFragmentValue(fragment, &error);
    if (error != CLIPBOARD_ERROR_NONE) return Unexpected{Fail(error)};
    return fragment;
}

Result<void> Session::CopyFiles(std::span<const std::wstring> paths, WriteOptions options)
{
    if (!held_) return Unexpected{NotOpen()};

    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().CopyFilePaths(std::vector<std::wstring>(paths.begin(), paths.end()),
                            ToOptionFlags(options), &error);
    return ToResult(error);
}

Result<std::vector<std::wstring>> Session::PasteFiles()
{
    if (!held_) return Unexpected{NotOpen()};

    std::vector<std::wstring> paths;
    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().PasteFilePaths(paths, &error);
    if (error != CLIPBOARD_ERROR_NONE) return Unexpected{Fail(error)};
    return paths;
}

Result<void> Session::CopyDib(std::span<const std::byte> dib, WriteOptions options)
{
    if (!held_) return Unexpected{NotOpen()};

    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().CopyImageBytes(ToRawBytes(dib), ToOptionFlags(options), &error);
    return ToResult(error);
}

Result<std::vector<std::byte>> Session::PasteDib()
{
    if (!held_) return Unexpected{NotOpen()};

    std::vector<BYTE> raw;
    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().PasteImageBytes(raw, &error);
    if (error != CLIPBOARD_ERROR_NONE) return Unexpected{Fail(error)};
    return FromRawBytes(raw);
}

Result<void> Session::CopyCustom(std::wstring_view formatName, std::span<const std::byte> data,
                                 WriteOptions options)
{
    if (!held_) return Unexpected{NotOpen()};
    std::wstring ownedName;
    if (const auto bad = Borrow(formatName, ownedName)) return Unexpected{*bad};

    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().CopyCustomBytes(ownedName, ToRawBytes(data), ToOptionFlags(options), &error);
    return ToResult(error);
}

Result<std::vector<std::byte>> Session::PasteCustom(std::wstring_view formatName)
{
    if (!held_) return Unexpected{NotOpen()};
    std::wstring ownedName;
    if (const auto bad = Borrow(formatName, ownedName)) return Unexpected{*bad};

    std::vector<BYTE> raw;
    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().PasteCustomBytes(ownedName, raw, &error);
    if (error != CLIPBOARD_ERROR_NONE) return Unexpected{Fail(error)};
    return FromRawBytes(raw);
}

Result<void> Session::CopyMultiple(std::span<const FormatPayload> items, WriteOptions options)
{
    if (!held_) return Unexpected{NotOpen()};

    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().CopyFormatPayloads(std::vector<FormatPayload>(items.begin(), items.end()),
                                 ToOptionFlags(options), &error);
    return ToResult(error);
}

Result<bool> Session::HasFormat(std::wstring_view formatName)
{
    if (!held_) return Unexpected{NotOpen()};
    std::wstring ownedName;
    if (const auto bad = Borrow(formatName, ownedName)) return Unexpected{*bad};

    DWORD error = CLIPBOARD_ERROR_NONE;
    const bool has = Backing().HasFormatNamed(ownedName, &error);
    if (error != CLIPBOARD_ERROR_NONE) return Unexpected{Fail(error)};
    return has;
}

Result<std::vector<std::wstring>> Session::GetFormats()
{
    if (!held_) return Unexpected{NotOpen()};

    std::vector<std::wstring> names;
    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().ListFormatNames(names, &error);
    if (error != CLIPBOARD_ERROR_NONE) return Unexpected{Fail(error)};
    return names;
}

Result<std::wstring> Session::GetPreferredFormat()
{
    if (!held_) return Unexpected{NotOpen()};

    std::wstring name;
    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().PreferredFormatName(name, &error);
    if (error != CLIPBOARD_ERROR_NONE) return Unexpected{Fail(error)};
    return name;
}

Result<void> Session::Clear()
{
    if (!held_) return Unexpected{NotOpen()};

    DWORD error = CLIPBOARD_ERROR_NONE;
    Backing().ClearClipboard(&error);
    return ToResult(error);
}

// =============================================================================
// Abandonment (N-5)
// =============================================================================

void Session::Abandon() noexcept
{
    if (!held_) {
        return;
    }
    DLog(TAG, L"[Session] destroyed without a successful Close; its window, listeners "
              L"and pending requests are left in place until the process exits, and "
              L"no further session can be created");
    // _ASSERTE rather than assert, so that the test covering this path can
    // turn the report off and still observe what abandonment does. Both are
    // debug-only; a release build has the log above and nothing else.
    _ASSERTE(!"Clipboard::Session destroyed without a successful Close()");

    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        g_state = ProcessState::Abandoned;
    }
    held_ = false;
}

// =============================================================================
// Test seam
// =============================================================================

namespace Detail {

void ClipboardTestAccess::ResetProcessState()
{
    ClearHandlers();
    std::lock_guard<std::mutex> lock(g_stateMutex);
    g_state = ProcessState::Free;
    g_ownerThread = 0;
}

bool ClipboardTestAccess::IsAbandoned()
{
    std::lock_guard<std::mutex> lock(g_stateMutex);
    return g_state == ProcessState::Abandoned;
}

}  // namespace Detail

}  // namespace NativeToolkit::Clipboard
