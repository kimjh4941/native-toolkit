/**
 * @file ClipboardBridge.cpp
 * @brief Exported C functions of the Clipboard feature.
 * @details
 *  These sit on NativeToolkit::Clipboard::Session (T-14), so there is one
 *  implementation and the C ABI is one of its callers. Everything a C caller
 *  can observe stays as it was; ClipboardBridgeTest recorded twenty of those
 *  answers before the move and still has to pass.
 *
 *  Three things this file owns, because the C++ API deliberately does not:
 *
 *  The session. The C ABI's init is idempotent from the owning thread while a
 *  second Session::Create is refused, so the bridge holds the one session a
 *  process may have and reads that refusal as the success the C ABI gives.
 *
 *  The two-call buffer protocol. A paste returns the size it needs and writes
 *  nothing when the buffer is too small; the count is of characters including
 *  the terminator for the string APIs and of bytes without one for the binary
 *  APIs, and zero is always an error (CLP-64, CLP-140).
 *
 *  The JSON. Files, the multi-format write and the format list are JSON on
 *  this side of the boundary and values on the other.
 *
 *  Seven functions stay on the manager and say so where they are defined:
 *  reserveDeferredFormats, whose provider is a two-phase C callback carrying a
 *  void* that no type can express (item 11 of the input inventory), and the
 *  six history functions, whose completion JSON is written by the delivery
 *  path that T-12 was told not to touch.
 *
 *  Every entry point is routed through SafeBridgeCall (H2/L1): it logs the
 *  name and turns an escaped exception into a pError value rather than letting
 *  it cross the C ABI boundary.
 *
 *  This translation unit belongs to the DLL only.
 */
#include "pch.h"

#include <winrt/Windows.Data.Json.h>

#include <cstring>
#include <optional>
#include <span>
#include <string>
#include <vector>

#include "Bridge/ClipboardPayloadJson.h"
#include "Clipboard/Domain/WindowsClipboardFormats.h"
#include "Clipboard/WindowsClipboardManager.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"
#include "Common/CommonInternal.h"
#include "NativeToolkit/Clipboard.h"

namespace {

const wchar_t* TAG = L"WindowsClipboardManager";

namespace Api = NativeToolkit::Clipboard;
using winrt::Windows::Data::Json::JsonArray;
using winrt::Windows::Data::Json::JsonObject;
using winrt::Windows::Data::Json::JsonValue;

void SetErr(DWORD* pError, DWORD value) { if (pError) *pError = value; }

/// The one session a process may have, held for as long as the C ABI wants it.
std::optional<Api::Session> g_session;

/// The raw value the C ABI reports for a typed failure. The enumerators were
/// given the values of the CLIPBOARD_ERROR_* constants for exactly this.
DWORD ToCError(const Api::Error& error) noexcept
{
    return static_cast<DWORD>(error.code);
}

void Report(const Api::Result<void>& result, DWORD* pError)
{
    SetErr(pError, result.has_value() ? CLIPBOARD_ERROR_NONE : ToCError(result.error()));
}

/// True when there is no session, with the answer already written. The manager
/// gave the same one, from the lease it could not take.
bool NotInitialized(DWORD* pError)
{
    if (g_session.has_value()) {
        return false;
    }
    SetErr(pError, CLIPBOARD_ERROR_NOT_INITIALIZED);
    return true;
}

std::span<const std::byte> AsBytes(const BYTE* data, DWORD size)
{
    return {reinterpret_cast<const std::byte*>(data), size};
}

std::vector<BYTE> FromBytes(const std::vector<std::byte>& bytes)
{
    std::vector<BYTE> raw(bytes.size());
    if (!bytes.empty()) ::memcpy(raw.data(), bytes.data(), bytes.size());
    return raw;
}

/// Writes a string into a caller buffer and reports the count of characters,
/// the terminator included. Zero is always an error.
DWORD WriteStringToBuffer(const std::wstring& value, wchar_t* buffer, DWORD bufferSize, DWORD* pError)
{
    size_t neededSize = 0;
    if (!ClipboardFormats::CheckedAdd(value.size(), 1, neededSize)) {
        SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
        return 0;
    }
    UINT needed = 0;
    if (!ClipboardFormats::CheckedToUInt(neededSize, needed)) {
        SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
        return 0;
    }
    if (!buffer || bufferSize < needed) {
        SetErr(pError, CLIPBOARD_ERROR_BUFFER_TOO_SMALL);
        return needed;
    }
    ::wcscpy_s(buffer, bufferSize, value.c_str());
    SetErr(pError, CLIPBOARD_ERROR_NONE);
    return needed;
}

/// The same for bytes, where the count is of bytes and there is no terminator.
DWORD WriteBytesToBuffer(const std::vector<BYTE>& data, BYTE* buffer, DWORD bufferSize, DWORD* pError)
{
    UINT needed = 0;
    if (!ClipboardFormats::CheckedToUInt(data.size(), needed)) {
        SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
        return 0;
    }
    if (!buffer || bufferSize < needed) {
        SetErr(pError, CLIPBOARD_ERROR_BUFFER_TOO_SMALL);
        return needed;
    }
    if (needed > 0) ::memcpy(buffer, data.data(), needed);
    SetErr(pError, CLIPBOARD_ERROR_NONE);
    return needed;
}

}  // namespace

// =============================================================================
// Bridge (extern "C")
// =============================================================================

namespace
{
    template <typename Fn>
    auto SafeBridgeCall(const wchar_t* name, DWORD* pError, Fn&& fn)
    {
        DFLog(TAG, L"[Bridge] %ls", name);
        using R = decltype(fn());
        if constexpr (std::is_void_v<R>)
        {
            try { fn(); }
            catch (const std::bad_alloc&) { SetErr(pError, CLIPBOARD_ERROR_OUT_OF_MEMORY); }
            catch (...) { DFLog(TAG, L"[Bridge] %ls threw", name); SetErr(pError, CLIPBOARD_ERROR_UNKNOWN); }
        }
        else
        {
            try { return fn(); }
            catch (const std::bad_alloc&) { SetErr(pError, CLIPBOARD_ERROR_OUT_OF_MEMORY); }
            catch (...) { DFLog(TAG, L"[Bridge] %ls threw", name); SetErr(pError, CLIPBOARD_ERROR_UNKNOWN); }
            return R{};
        }
    }
}

// --- Lifetime ---------------------------------------------------------------

void initClipboardManager(ClipboardChangedCallback onChanged, DWORD* pError)
{
    SafeBridgeCall(L"initClipboardManager", pError, [&]
    {
        Api::SessionOptions options;
        if (onChanged) options.onClipboardChanged = [onChanged] { onChanged(); };

        auto created = Api::Session::Create(options);
        if (created.has_value()) {
            g_session.emplace(std::move(created).value());
            SetErr(pError, CLIPBOARD_ERROR_NONE);
            return;
        }
        // A second session is refused, and from the owning thread that refusal
        // is the idempotent success the C ABI has always given. From any other
        // thread it is the wrong thread, and that passes straight through.
        SetErr(pError, created.error().code == Api::ErrorCode::NotSupported
                           ? CLIPBOARD_ERROR_NONE : ToCError(created.error()));
    });
}

void setClipboardHistoryCallbacks(ClipboardHistoryChangedCallback onHistoryChanged,
                                  ClipboardFlagChangedCallback onHistoryEnabledChanged,
                                  ClipboardFlagChangedCallback onRoamingEnabledChanged,
                                  DWORD* pError)
{
    SafeBridgeCall(L"setClipboardHistoryCallbacks", pError, [&]
    {
        if (NotInitialized(pError)) return;

        // All three left null is how they are taken away (CLP-112), and an
        // empty std::function says the same thing.
        Api::HistoryHandlers handlers;
        if (onHistoryChanged) handlers.onHistoryChanged = [onHistoryChanged] { onHistoryChanged(); };
        if (onHistoryEnabledChanged) {
            handlers.onHistoryEnabledChanged =
                [onHistoryEnabledChanged](bool enabled) { onHistoryEnabledChanged(enabled ? TRUE : FALSE); };
        }
        if (onRoamingEnabledChanged) {
            handlers.onRoamingEnabledChanged =
                [onRoamingEnabledChanged](bool enabled) { onRoamingEnabledChanged(enabled ? TRUE : FALSE); };
        }
        Report(g_session->SetHistoryHandlers(std::move(handlers)), pError);
    });
}

BOOL uninitClipboardManager(DWORD* pError)
{
    return SafeBridgeCall(L"uninitClipboardManager", pError, [&] -> BOOL
    {
        if (!g_session.has_value()) {
            SetErr(pError, CLIPBOARD_ERROR_NONE);
            return TRUE;
        }
        const auto closed = g_session->Close();
        if (!closed.has_value()) {
            // The session stays open and stays the bridge's to close, so the
            // caller can pump messages and try again.
            SetErr(pError, ToCError(closed.error()));
            return FALSE;
        }
        g_session.reset();
        SetErr(pError, CLIPBOARD_ERROR_NONE);
        return TRUE;
    });
}

BOOL canDestroyClipboardManager(DWORD* pError)
{
    return SafeBridgeCall(L"canDestroyClipboardManager", pError, [&] -> BOOL
    {
        SetErr(pError, CLIPBOARD_ERROR_NONE);
        return !g_session.has_value() || g_session->CanClose() ? TRUE : FALSE;
    });
}

// --- The synchronous core ---------------------------------------------------

void copyPlainText(const wchar_t* text, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyPlainText", pError, [&]
    {
        if (NotInitialized(pError)) return;
        if (!text) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }
        Report(g_session->CopyText(text, Api::WriteOptions{
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY) != 0,
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING) != 0}), pError);
    });
}

DWORD pastePlainText(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pastePlainText", pError, [&] -> DWORD
    {
        if (NotInitialized(pError)) return 0;
        auto pasted = g_session->PasteText();
        if (!pasted.has_value()) { SetErr(pError, ToCError(pasted.error())); return 0; }
        return WriteStringToBuffer(pasted.value(), buffer, buffer_size, pError);
    });
}

void copyHtml(const wchar_t* htmlFragment, const wchar_t* plainText, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyHtml", pError, [&]
    {
        if (NotInitialized(pError)) return;
        if (!htmlFragment) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }
        Report(g_session->CopyHtml(htmlFragment, plainText ? plainText : L"",
                                   Api::WriteOptions{
                                       (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY) != 0,
                                       (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING) != 0}), pError);
    });
}

DWORD pasteHtml(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteHtml", pError, [&] -> DWORD
    {
        if (NotInitialized(pError)) return 0;
        auto pasted = g_session->PasteHtml();
        if (!pasted.has_value()) { SetErr(pError, ToCError(pasted.error())); return 0; }
        return WriteStringToBuffer(pasted.value(), buffer, buffer_size, pError);
    });
}

void copyFiles(const wchar_t* pathsJson, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyFiles", pError, [&]
    {
        if (NotInitialized(pError)) return;
        if (!pathsJson) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

        std::vector<std::wstring> paths;
        if (!ClipboardPayloadJson::ReadStringArray(pathsJson, paths)) {
            SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER);
            return;
        }
        Report(g_session->CopyFiles(paths, Api::WriteOptions{
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY) != 0,
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING) != 0}), pError);
    });
}

DWORD pasteFiles(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteFiles", pError, [&] -> DWORD
    {
        if (NotInitialized(pError)) return 0;
        auto pasted = g_session->PasteFiles();
        if (!pasted.has_value()) { SetErr(pError, ToCError(pasted.error())); return 0; }
        return WriteStringToBuffer(ClipboardPayloadJson::WriteStringArray(pasted.value()), buffer, buffer_size, pError);
    });
}

void copyImage(const BYTE* dib, DWORD dibSize, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyImage", pError, [&]
    {
        if (NotInitialized(pError)) return;
        if (!dib || dibSize == 0) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }
        Report(g_session->CopyDib(AsBytes(dib, dibSize), Api::WriteOptions{
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY) != 0,
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING) != 0}), pError);
    });
}

DWORD pasteImage(BYTE* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteImage", pError, [&] -> DWORD
    {
        if (NotInitialized(pError)) return 0;
        auto pasted = g_session->PasteDib();
        if (!pasted.has_value()) { SetErr(pError, ToCError(pasted.error())); return 0; }
        return WriteBytesToBuffer(FromBytes(pasted.value()), buffer, buffer_size, pError);
    });
}

void copyCustomFormat(const wchar_t* formatName, const BYTE* data, DWORD size, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyCustomFormat", pError, [&]
    {
        if (NotInitialized(pError)) return;
        if (!formatName || !data || size == 0) {
            SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER);
            return;
        }
        Report(g_session->CopyCustom(formatName, AsBytes(data, size), Api::WriteOptions{
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY) != 0,
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING) != 0}), pError);
    });
}

DWORD pasteCustomFormat(const wchar_t* formatName, BYTE* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteCustomFormat", pError, [&] -> DWORD
    {
        if (NotInitialized(pError)) return 0;
        if (!formatName) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return 0; }
        auto pasted = g_session->PasteCustom(formatName);
        if (!pasted.has_value()) { SetErr(pError, ToCError(pasted.error())); return 0; }
        return WriteBytesToBuffer(FromBytes(pasted.value()), buffer, buffer_size, pError);
    });
}

void copyMultipleFormats(const wchar_t* itemsJson, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyMultipleFormats", pError, [&]
    {
        if (NotInitialized(pError)) return;
        if (!itemsJson) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

        std::vector<Api::FormatPayload> items;
        if (!ClipboardPayloadJson::ReadFormatItems(itemsJson, items)) {
            SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER);
            return;
        }

        Report(g_session->CopyMultiple(items, Api::WriteOptions{
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY) != 0,
                   (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING) != 0}), pError);
    });
}

BOOL hasClipboardFormat(const wchar_t* formatName, DWORD* pError)
{
    return SafeBridgeCall(L"hasClipboardFormat", pError, [&] -> BOOL
    {
        if (NotInitialized(pError)) return FALSE;
        if (!formatName) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return FALSE; }
        const auto present = g_session->HasFormat(formatName);
        if (!present.has_value()) { SetErr(pError, ToCError(present.error())); return FALSE; }
        SetErr(pError, CLIPBOARD_ERROR_NONE);
        return present.value() ? TRUE : FALSE;
    });
}

DWORD getClipboardFormats(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"getClipboardFormats", pError, [&] -> DWORD
    {
        if (NotInitialized(pError)) return 0;
        auto formats = g_session->GetFormats();
        if (!formats.has_value()) { SetErr(pError, ToCError(formats.error())); return 0; }
        return WriteStringToBuffer(ClipboardPayloadJson::WriteStringArray(formats.value()), buffer, buffer_size, pError);
    });
}

DWORD getPreferredClipboardFormat(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"getPreferredClipboardFormat", pError, [&] -> DWORD
    {
        if (NotInitialized(pError)) return 0;
        auto preferred = g_session->GetPreferredFormat();
        if (!preferred.has_value()) { SetErr(pError, ToCError(preferred.error())); return 0; }
        // No format at all is an empty name, which comes back as one: the
        // terminator on its own, because zero would mean an error.
        return WriteStringToBuffer(preferred.value(), buffer, buffer_size, pError);
    });
}

void clearClipboard(DWORD* pError)
{
    SafeBridgeCall(L"clearClipboard", pError, [&]
    {
        if (NotInitialized(pError)) return;
        Report(g_session->Clear(), pError);
    });
}

// --- Deferred rendering -----------------------------------------------------

void reserveDeferredFormats(const wchar_t* formatNamesJson, ClipboardRenderCallback provider, void* context, DWORD* pError)
{
    // Still on the manager. The provider is asked twice and carries a void*,
    // which is item 11 of the input inventory - a protocol no type expresses -
    // and S-3 keeps a way for the bridge to reach the layer that speaks it.
    SafeBridgeCall(L"reserveDeferredFormats", pError, [&]
    {
        ClipboardManager::GetInstance().ReserveDeferredFormats(formatNamesJson, provider, context, pError);
    });
}

void recoverDeferredState(DWORD* pError)
{
    SafeBridgeCall(L"recoverDeferredState", pError, [&]
    {
        if (NotInitialized(pError)) return;
        Report(g_session->RecoverDeferredState(), pError);
    });
}

// --- The history ------------------------------------------------------------
//
// All six stay on the manager. Their completions carry the JSON the
// coordinator writes, and going through the C++ API would read that JSON into
// values and write it out again - a round trip with nothing to gain, past a
// delivery path T-12 was told to leave alone.

uint32_t getClipboardHistory(ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"getClipboardHistory", pError, [&] { return ClipboardManager::GetInstance().GetClipboardHistory(cb, pError); });
}

uint32_t restoreHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"restoreHistoryItem", pError, [&] { return ClipboardManager::GetInstance().RestoreHistoryItem(itemId, cb, pError); });
}

uint32_t deleteHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"deleteHistoryItem", pError, [&] { return ClipboardManager::GetInstance().DeleteHistoryItem(itemId, cb, pError); });
}

uint32_t clearUnpinnedHistory(ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"clearUnpinnedHistory", pError, [&] { return ClipboardManager::GetInstance().ClearUnpinnedHistory(cb, pError); });
}

uint32_t getClipboardHistoryAvailability(ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"getClipboardHistoryAvailability", pError, [&] { return ClipboardManager::GetInstance().GetClipboardHistoryAvailability(cb, pError); });
}

BOOL cancelClipboardRequest(uint32_t requestId, DWORD* pError)
{
    return SafeBridgeCall(L"cancelClipboardRequest", pError, [&] { return ClipboardManager::GetInstance().CancelClipboardRequest(requestId, pError); });
}
