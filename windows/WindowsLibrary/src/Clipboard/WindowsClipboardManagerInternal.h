#pragma once

#include "Clipboard/WindowsClipboardManager.h"
#include "NativeToolkit/Clipboard.h"
#include "Clipboard/Data/WindowsClipboardCore.h"
#include "Clipboard/Application/WindowsClipboardLifecycle.h"
#include "Clipboard/Application/WindowsClipboardHistoryBackend.h"
#include "Clipboard/Application/WindowsClipboardHistoryCoordinator.h"
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace WindowsClipboardManagerTest { class ClipboardManagerTest; }
namespace WindowsClipboardApiTest { class ClipboardApiTest; }

class ClipboardManager
{
public:
    static ClipboardManager& GetInstance();

    // Initialization / shutdown (Bridge entry points).
    void InitClipboardManager(ClipboardChangedCallback onChanged, DWORD* pError);
    BOOL Uninit(DWORD* pError);
    BOOL CanDestroy(DWORD* pError) const;

    /// Delivers the cancellations an Uninit that returned CANCELED posted to
    /// the dispatch window, and nothing else. Owner thread only; returns how
    /// many messages it dispatched. Takes no lock while dispatching, because
    /// the completions it delivers run caller code (stage 5 design E-19).
    size_t DispatchPendingDrain();
    void SetHistoryCallbacks(ClipboardHistoryChangedCallback onHistoryChanged,
                             ClipboardFlagChangedCallback onHistoryEnabledChanged,
                             ClipboardFlagChangedCallback onRoamingEnabledChanged,
                             DWORD* pError);

    // Win32 synchronous core (any thread). Empties the clipboard; everything
    // else here is below, in values.
    void   ClearClipboard(DWORD* pError);

    // The operations in values. The C ABI's buffers and JSON are the bridge's
    // to translate, so these are the only way to the clipboard.
    void CopyText(const std::wstring& text, DWORD options, DWORD* pError);
    void PasteText(std::wstring& out, DWORD* pError);
    void CopyHtmlFragment(const std::wstring& fragment, const std::wstring& plainText,
                          DWORD options, DWORD* pError);
    void PasteHtmlFragmentValue(std::wstring& out, DWORD* pError);
    void CopyFilePaths(const std::vector<std::wstring>& paths, DWORD options, DWORD* pError);
    void PasteFilePaths(std::vector<std::wstring>& out, DWORD* pError);
    void CopyImageBytes(const std::vector<BYTE>& dib, DWORD options, DWORD* pError);
    void PasteImageBytes(std::vector<BYTE>& out, DWORD* pError);
    void CopyCustomBytes(const std::wstring& formatName, const std::vector<BYTE>& data,
                         DWORD options, DWORD* pError);
    void PasteCustomBytes(const std::wstring& formatName, std::vector<BYTE>& out, DWORD* pError);
    void CopyFormatPayloads(const std::vector<NativeToolkit::Clipboard::FormatPayload>& items,
                            DWORD options, DWORD* pError);
    bool HasFormatNamed(const std::wstring& formatName, DWORD* pError);
    void ListFormatNames(std::vector<std::wstring>& out, DWORD* pError);
    void PreferredFormatName(std::wstring& out, DWORD* pError);

    // Deferred rendering (owner UI thread only).
    void ReserveDeferredFormats(const wchar_t* formatNamesJson, ClipboardRenderCallback provider,
                                void* context, DWORD* pError);

    /// The same reservation from a list of names and a C++ provider. The names
    /// and the provider are copied, so neither has to outlive the call.
    void ReserveDeferredProviders(const std::vector<std::wstring>& formatNames,
                                  NativeToolkit::Clipboard::RenderProvider provider,
                                  DWORD* pError);
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
    /// Drives Session against the real manager on an STA thread; see
    /// ClipboardApiTest (stage 3, T-09).
    friend class WindowsClipboardApiTest::ClipboardApiTest;

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
