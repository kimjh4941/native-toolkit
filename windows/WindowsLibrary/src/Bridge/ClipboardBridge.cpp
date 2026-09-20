/**
 * @file ClipboardBridge.cpp
 * @brief Exported C functions of the Clipboard feature.
 * @details
 *  Thin wrappers over ClipboardManager, each routed through SafeBridgeCall so no
 *  exception crosses the C ABI boundary. This translation unit belongs to the DLL
 *  only; the implementation it calls is built into the library.
 */
#include "pch.h"
#include "Clipboard/WindowsClipboardManager.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"
#include "Clipboard/Domain/WindowsClipboardFormats.h"
#include "Common/CommonInternal.h"
#include <set>
#include <string>
#include <vector>

namespace {
const wchar_t* TAG = L"WindowsClipboardManager";
void SetErr(DWORD* pError, DWORD value) { if (pError) *pError = value; }
}

// =============================================================================
// Bridge (extern "C")
// =============================================================================
//
// Every Bridge entry point is routed through SafeBridgeCall (H2/L1): it logs
// the entry point name (satisfying the "log at every Bridge method" rule
// without repeating it at each call site) and converts any exception that
// escapes the Manager call (std::vector/std::wstring/std::make_shared/WinRT
// JSON allocation failures, etc.) into a pError value instead of letting it
// cross the C ABI boundary undefined.

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

void initClipboardManager(ClipboardChangedCallback onChanged, DWORD* pError)
{
    SafeBridgeCall(L"initClipboardManager", pError, [&] { ClipboardManager::GetInstance().InitClipboardManager(onChanged, pError); });
}

void setClipboardHistoryCallbacks(ClipboardHistoryChangedCallback onHistoryChanged,
                                  ClipboardFlagChangedCallback onHistoryEnabledChanged,
                                  ClipboardFlagChangedCallback onRoamingEnabledChanged,
                                  DWORD* pError)
{
    SafeBridgeCall(L"setClipboardHistoryCallbacks", pError, [&]
    {
        ClipboardManager::GetInstance().SetHistoryCallbacks(onHistoryChanged, onHistoryEnabledChanged, onRoamingEnabledChanged, pError);
    });
}

BOOL uninitClipboardManager(DWORD* pError)
{
    return SafeBridgeCall(L"uninitClipboardManager", pError, [&] { return ClipboardManager::GetInstance().Uninit(pError); });
}

BOOL canDestroyClipboardManager(DWORD* pError)
{
    return SafeBridgeCall(L"canDestroyClipboardManager", pError, [&] { return ClipboardManager::GetInstance().CanDestroy(pError); });
}

void copyPlainText(const wchar_t* text, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyPlainText", pError, [&] { ClipboardManager::GetInstance().CopyPlainText(text, options, pError); });
}

DWORD pastePlainText(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pastePlainText", pError, [&] { return ClipboardManager::GetInstance().PastePlainText(buffer, buffer_size, pError); });
}

void copyHtml(const wchar_t* htmlFragment, const wchar_t* plainText, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyHtml", pError, [&] { ClipboardManager::GetInstance().CopyHtml(htmlFragment, plainText, options, pError); });
}

DWORD pasteHtml(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteHtml", pError, [&] { return ClipboardManager::GetInstance().PasteHtml(buffer, buffer_size, pError); });
}

void copyFiles(const wchar_t* pathsJson, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyFiles", pError, [&] { ClipboardManager::GetInstance().CopyFiles(pathsJson, options, pError); });
}

DWORD pasteFiles(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteFiles", pError, [&] { return ClipboardManager::GetInstance().PasteFiles(buffer, buffer_size, pError); });
}

void copyImage(const BYTE* dib, DWORD dibSize, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyImage", pError, [&] { ClipboardManager::GetInstance().CopyImage(dib, dibSize, options, pError); });
}

DWORD pasteImage(BYTE* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteImage", pError, [&] { return ClipboardManager::GetInstance().PasteImage(buffer, buffer_size, pError); });
}

void copyCustomFormat(const wchar_t* formatName, const BYTE* data, DWORD size, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyCustomFormat", pError, [&] { ClipboardManager::GetInstance().CopyCustomFormat(formatName, data, size, options, pError); });
}

DWORD pasteCustomFormat(const wchar_t* formatName, BYTE* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteCustomFormat", pError, [&] { return ClipboardManager::GetInstance().PasteCustomFormat(formatName, buffer, buffer_size, pError); });
}

void copyMultipleFormats(const wchar_t* itemsJson, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyMultipleFormats", pError, [&] { ClipboardManager::GetInstance().CopyMultipleFormats(itemsJson, options, pError); });
}

BOOL hasClipboardFormat(const wchar_t* formatName, DWORD* pError)
{
    return SafeBridgeCall(L"hasClipboardFormat", pError, [&] { return ClipboardManager::GetInstance().HasClipboardFormat(formatName, pError); });
}

DWORD getClipboardFormats(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"getClipboardFormats", pError, [&] { return ClipboardManager::GetInstance().GetClipboardFormats(buffer, buffer_size, pError); });
}

DWORD getPreferredClipboardFormat(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"getPreferredClipboardFormat", pError, [&] { return ClipboardManager::GetInstance().GetPreferredClipboardFormat(buffer, buffer_size, pError); });
}

void clearClipboard(DWORD* pError)
{
    SafeBridgeCall(L"clearClipboard", pError, [&] { ClipboardManager::GetInstance().ClearClipboard(pError); });
}

void reserveDeferredFormats(const wchar_t* formatNamesJson, ClipboardRenderCallback provider, void* context, DWORD* pError)
{
    SafeBridgeCall(L"reserveDeferredFormats", pError, [&] { ClipboardManager::GetInstance().ReserveDeferredFormats(formatNamesJson, provider, context, pError); });
}

void recoverDeferredState(DWORD* pError)
{
    SafeBridgeCall(L"recoverDeferredState", pError, [&] { ClipboardManager::GetInstance().RecoverDeferredState(pError); });
}

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
