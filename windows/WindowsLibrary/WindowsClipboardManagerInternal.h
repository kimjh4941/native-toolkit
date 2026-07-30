#pragma once

#include "WindowsClipboardManager.h"
#include "WindowsClipboardCore.h"
#include "WindowsClipboardLifecycle.h"
#include "WindowsClipboardHistoryBackend.h"
#include "WindowsClipboardHistoryCoordinator.h"
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace WindowsClipboardManagerTest { class ClipboardManagerTest; }

class ClipboardManager
{
public:
    static ClipboardManager& GetInstance();

    // Initialization / shutdown (Bridge entry points).
    void InitClipboardManager(ClipboardChangedCallback onChanged, DWORD* pError);
    BOOL Uninit(DWORD* pError);
    BOOL CanDestroy(DWORD* pError) const;
    void SetHistoryCallbacks(ClipboardHistoryChangedCallback onHistoryChanged,
                             ClipboardFlagChangedCallback onHistoryEnabledChanged,
                             ClipboardFlagChangedCallback onRoamingEnabledChanged,
                             DWORD* pError);

    // Win32 synchronous core (any thread).
    void   CopyPlainText(const wchar_t* text, DWORD options, DWORD* pError);
    DWORD  PastePlainText(wchar_t* buffer, DWORD bufferSize, DWORD* pError);
    void   CopyHtml(const wchar_t* html, const wchar_t* plainText, DWORD options, DWORD* pError);
    DWORD  PasteHtml(wchar_t* buffer, DWORD bufferSize, DWORD* pError);
    void   CopyFiles(const wchar_t* pathsJson, DWORD options, DWORD* pError);
    DWORD  PasteFiles(wchar_t* buffer, DWORD bufferSize, DWORD* pError);
    void   CopyImage(const BYTE* dib, DWORD dibSize, DWORD options, DWORD* pError);
    DWORD  PasteImage(BYTE* buffer, DWORD bufferSize, DWORD* pError);
    void   CopyCustomFormat(const wchar_t* formatName, const BYTE* data, DWORD size, DWORD options, DWORD* pError);
    DWORD  PasteCustomFormat(const wchar_t* formatName, BYTE* buffer, DWORD bufferSize, DWORD* pError);
    void   CopyMultipleFormats(const wchar_t* itemsJson, DWORD options, DWORD* pError);
    BOOL   HasClipboardFormat(const wchar_t* formatName, DWORD* pError);
    DWORD  GetClipboardFormats(wchar_t* buffer, DWORD bufferSize, DWORD* pError);
    DWORD  GetPreferredClipboardFormat(wchar_t* buffer, DWORD bufferSize, DWORD* pError);
    void   ClearClipboard(DWORD* pError);

    // Deferred rendering (owner UI thread only).
    void ReserveDeferredFormats(const wchar_t* formatNamesJson, ClipboardRenderCallback provider,
                                void* context, DWORD* pError);
    void RecoverDeferredState(DWORD* pError);

    // Async history (any thread for the request call; UI thread for callback delivery).
    uint32_t GetClipboardHistory(ClipboardRequestCallback cb, DWORD* pError);
    uint32_t RestoreHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError);
    uint32_t DeleteHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError);
    uint32_t ClearUnpinnedHistory(ClipboardRequestCallback cb, DWORD* pError);
    uint32_t GetClipboardHistoryAvailability(ClipboardRequestCallback cb, DWORD* pError);
    BOOL     CancelClipboardRequest(uint32_t requestId, DWORD* pError);

    // WndProc callbacks (owner UI thread only).
    void OnClipboardUpdate();
    void OnRenderFormat(UINT format);
    void OnRenderAllFormats(HWND hwnd);
    void OnDestroyClipboardMsg();
    void OnHistoryRequestMessage(uint32_t id);
    void OnHistoryCancelMessage(uint32_t id);
    void OnHistoryDrainMessage();
    void OnHistoryEventMessage(WPARAM eventId, LPARAM generation);

    // Test seam: replace the history backend with a mock for WinRT-free unit tests.
    // Must be called before InitClipboardManager (or after a full Uninit).
    void SetHistoryBackendFactoryForTest(std::unique_ptr<IClipboardHistoryBackend> (*factory)());

private:
    friend class WindowsClipboardManagerTest::ClipboardManagerTest;

    ClipboardManager();
    ClipboardManager(const ClipboardManager&) = delete;
    ClipboardManager& operator=(const ClipboardManager&) = delete;

    // Atomically (under initMutex_) checks initialized_, enters the lifecycle
    // lease, and snapshots dispatchHwnd_ in one step. Any-thread callers must
    // use this instead of reading initialized_/dispatchHwnd_/coordinator_
    // directly, because Uninit() flips that state under the same mutex.
    bool AcquireSyncLease(DWORD* pError, std::optional<ClipboardLifecycle::Lease>& outLease, HWND& outHwnd) const;
    // Same idea for the async history entry points: snapshots coordinator_
    // under initMutex_ so it can't be reset mid-call by a concurrent Uninit.
    bool AcquireHistoryCoordinator(DWORD* pError, std::shared_ptr<ClipboardHistoryCoordinator>& outCoordinator) const;
    // Atomically validates initialization and owner-thread affinity, acquires
    // a lifecycle lease, and snapshots UI-owned state. This makes wrong-thread
    // rejection safe while Uninit() updates the same state.
    bool AcquireOwnerContext(DWORD* pError,
                             std::optional<ClipboardLifecycle::Lease>& outLease,
                             HWND& outHwnd,
                             std::shared_ptr<ClipboardHistoryCoordinator>& outCoordinator) const;

    mutable std::mutex initMutex_;
    bool initialized_ = false;
    DWORD ownerThreadId_ = 0;
    HWND dispatchHwnd_ = nullptr;

    ClipboardChangedCallback onChanged_ = nullptr;

    mutable ClipboardLifecycle lifecycle_;
    ClipboardWatcher watcher_;
    DeferredClipboard deferred_;
    std::shared_ptr<ClipboardHistoryCoordinator> coordinator_;

    std::unique_ptr<IClipboardHistoryBackend> (*testBackendFactory_)() = nullptr;
};
