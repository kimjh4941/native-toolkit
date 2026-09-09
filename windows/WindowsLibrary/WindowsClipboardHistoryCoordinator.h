/**
 * @file WindowsClipboardHistoryCoordinator.h
 * @brief Application-layer request state machine for clipboard history (F-12).
 * @details
 *  Owns the Queued -> Running -> Finished lifecycle of history requests, the
 *  single-owner request table, cancellation, and the shutdown drain. Never
 *  touches WinRT types directly (see IClipboardHistoryBackend / Data layer).
 *
 *  Thread-safety: Request*() and CancelRequest() are callable from any
 *  thread. OnStartQueuedRequest(), OnDrainMessage(), SetHistoryCallbacks(),
 *  StopWatch() and CloseAndDrain() MUST be called on the owner UI thread.
 */
#pragma once

#include "WindowsClipboardHistoryBackend.h"
#include "WindowsClipboardLifecycle.h"
#include "WindowsClipboardManager.h"
#include <atomic>
#include <map>
#include <memory>
#include <mutex>
#include <vector>

// Messages posted to the dispatch window by this coordinator.
#define WM_APP_CLIPBOARD_REQUEST       (WM_APP + 1)
#define WM_APP_CLIPBOARD_CANCEL        (WM_APP + 2)
#define WM_APP_CLIPBOARD_DRAIN         (WM_APP + 3)
// History event notification: wParam = pending event id, lParam = watch
// generation. Posted from whichever thread WinRT invokes the backend handler
// on. The owner UI thread resolves the pending immutable callback snapshot and
// validates the generation before delivery.
#define WM_APP_CLIPBOARD_HISTORY_EVENT (WM_APP + 4)
enum ClipboardHistoryEventKind : WPARAM
{
    kHistoryChanged = 0,
    kHistoryEnabledChanged = 1,
    kRoamingEnabledChanged = 2,
};

class ClipboardHistoryCoordinator : public std::enable_shared_from_this<ClipboardHistoryCoordinator>
{
public:
    ClipboardHistoryCoordinator(std::unique_ptr<IClipboardHistoryBackend> backend, ClipboardLifecycle& lifecycle);

    void AttachDispatchWindow(HWND hwnd);
    void DetachDispatchWindow();

    // Bridge entry points (any thread).
    uint32_t RequestGetItems(ClipboardRequestCallback cb, DWORD* pError);
    uint32_t RequestRestoreItem(const std::wstring& id, ClipboardRequestCallback cb, DWORD* pError);
    uint32_t RequestDeleteItem(const std::wstring& id, ClipboardRequestCallback cb, DWORD* pError);
    uint32_t RequestClearUnpinned(ClipboardRequestCallback cb, DWORD* pError);
    uint32_t RequestGetAvailability(ClipboardRequestCallback cb, DWORD* pError);
    BOOL     CancelRequest(uint32_t id, DWORD* pError);

    // WndProc entry points (owner UI thread only).
    void OnStartQueuedRequest(uint32_t id);
    void OnCancelMessage(uint32_t id);
    void OnDrainMessage();
    void OnHistoryEventMessage(WPARAM eventId, LPARAM generation);

    // History event registration (owner UI thread only, synchronous).
    DWORD SetHistoryCallbacks(ClipboardHistoryChangedCallback onChanged,
                              ClipboardFlagChangedCallback onHistoryEnabled,
                              ClipboardFlagChangedCallback onRoamingEnabled);

    // Shutdown coordination (owner UI thread only).
    // Moves every still-queued/running-but-uncompleted entry's completion
    // right into the drain queue and posts (or retries posting) a single
    // WM_APP_CLIPBOARD_DRAIN. Returns true only when nothing remains to drain.
    bool CloseAndDrain();
    bool StopWatch();
    bool CanDestroy() const;

private:
    using StartFn = std::function<void(uint32_t, ClipboardLifecycle::Lease)>;

    struct RequestEntry
    {
        ClipboardRequestCallback callback = nullptr;             // completion right
        std::optional<StartFn> start;                            // Queued only
        std::optional<ClipboardLifecycle::Lease> lease;           // Queued only
    };

    struct HistoryCallbackSnapshot
    {
        uint64_t watchGeneration = 0;
        ClipboardHistoryChangedCallback historyChanged = nullptr;
        ClipboardFlagChangedCallback historyEnabled = nullptr;
        ClipboardFlagChangedCallback roamingEnabled = nullptr;
    };

    struct PendingHistoryEvent
    {
        ClipboardHistoryEventKind kind = kHistoryChanged;
        std::shared_ptr<const HistoryCallbackSnapshot> callbacks;
    };

    uint32_t Accept(ClipboardRequestCallback cb, DWORD* pError, StartFn start);
    void Complete(uint32_t id, DWORD error, const std::wstring* json);
    void CompleteItems(uint32_t id, DWORD error, const std::vector<ClipboardHistoryEntry>& items);
    void CompleteStatus(uint32_t id, DWORD error);
    void CompleteAvailability(uint32_t id, DWORD error, const ClipboardHistoryAvailability& avail);
    void PostHistoryEvent(ClipboardHistoryEventKind kind,
                          std::shared_ptr<const HistoryCallbackSnapshot> callbacks); // any thread
    void InvalidateHistoryEvents(); // owner UI thread

    std::unique_ptr<IClipboardHistoryBackend> backend_;
    ClipboardLifecycle& lifecycle_;

    mutable std::mutex mutex_;
    HWND dispatchHwnd_ = nullptr;
    uint32_t nextId_ = 1;
    std::map<uint32_t, RequestEntry> table_;

    // UI-thread-only (no lock needed: only touched from CloseAndDrain/OnDrainMessage,
    // both constrained to the owner UI thread).
    std::vector<std::pair<uint32_t, ClipboardRequestCallback>> pendingDrain_;
    std::atomic<size_t> pendingDrainCount_{ 0 }; // mirrors pendingDrain_.size() for lock-free CanDestroy()
    bool drainMessagePosted_ = false;

    bool isWatching_ = false; // UI-thread-only
    uint64_t watchGeneration_ = 1; // UI-thread-only; incremented after a successful stop

    // Posted event state. The immutable callback snapshot is retained until
    // the owner UI thread consumes the event. Stop invalidates the generation
    // and clears this table, so queued messages from an old watch session are
    // harmless even after a new registration starts.
    uint32_t nextHistoryEventId_ = 1; // guarded by mutex_
    std::map<uint32_t, PendingHistoryEvent> pendingHistoryEvents_; // guarded by mutex_
};
