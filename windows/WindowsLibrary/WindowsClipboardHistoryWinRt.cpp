// Requires C++20 (co_await) - see WindowsLibrary.vcxproj per-file LanguageStandard override.
#include "pch.h"
#include "WindowsClipboardHistoryWinRt.h"
#include "WindowsClipboardManager.h"
#include "common.h"
#include <algorithm>
#include <atomic>
#include <mutex>

using namespace winrt::Windows::ApplicationModel::DataTransfer;
using namespace winrt::Windows::Foundation;

static const wchar_t* TAG = L"ClipboardHistoryWinRt";

namespace
{
    bool IsSelfForeground()
    {
        HWND fg = ::GetForegroundWindow();
        if (!fg) return false;
        DWORD pid = 0;
        ::GetWindowThreadProcessId(fg, &pid);
        return pid == ::GetCurrentProcessId();
    }

    DWORD MapHistoryStatus(ClipboardHistoryItemsResultStatus status)
    {
        switch (status)
        {
        case ClipboardHistoryItemsResultStatus::Success:                  return CLIPBOARD_ERROR_NONE;
        case ClipboardHistoryItemsResultStatus::AccessDenied:             return CLIPBOARD_ERROR_ACCESS_DENIED;
        case ClipboardHistoryItemsResultStatus::ClipboardHistoryDisabled: return CLIPBOARD_ERROR_HISTORY_DISABLED;
        default:                                                          return CLIPBOARD_ERROR_UNKNOWN;
        }
    }

    DWORD MapSetHistoryItemStatus(SetHistoryItemAsContentStatus status)
    {
        switch (status)
        {
        case SetHistoryItemAsContentStatus::Success:      return CLIPBOARD_ERROR_NONE;
        case SetHistoryItemAsContentStatus::AccessDenied: return CLIPBOARD_ERROR_ACCESS_DENIED;
        case SetHistoryItemAsContentStatus::ItemDeleted:  return CLIPBOARD_ERROR_ITEM_DELETED;
        default:                                          return CLIPBOARD_ERROR_UNKNOWN;
        }
    }

    // Classifies the exception currently being handled (must be called from a catch block).
    // E_OUTOFMEMORY surfaces as std::bad_alloc in C++/WinRT, not hresult_error.
    DWORD ClassifyWinRtException()
    {
        try { throw; }
        catch (const winrt::hresult_error& e)
        {
            const HRESULT hr = e.code();
            DFLog(TAG, L"[ClassifyWinRtException] hr=0x%08lx msg=%ls", hr, e.message().c_str());
            switch (hr)
            {
            case E_ACCESSDENIED: return CLIPBOARD_ERROR_ACCESS_DENIED;
            case E_OUTOFMEMORY:  return CLIPBOARD_ERROR_OUT_OF_MEMORY;
            case E_INVALIDARG:   return CLIPBOARD_ERROR_INVALID_PARAMETER;
            default:             return CLIPBOARD_ERROR_UNKNOWN;
            }
        }
        catch (const std::bad_alloc&)
        {
            DLog(TAG, L"[ClassifyWinRtException] std::bad_alloc (E_OUTOFMEMORY)");
            return CLIPBOARD_ERROR_OUT_OF_MEMORY;
        }
        catch (const std::exception& e)
        {
            DFLog(TAG, L"[ClassifyWinRtException] std::exception: %hs", e.what());
            return CLIPBOARD_ERROR_UNKNOWN;
        }
        catch (...)
        {
            DLog(TAG, L"[ClassifyWinRtException] unknown exception");
            return CLIPBOARD_ERROR_UNKNOWN;
        }
    }

    // Shared state for in-flight event handlers, decoupled from the backend
    // object's own lifetime: handlers capture only this (never `this`), so a
    // handler that is already executing when Stop() runs cannot touch a
    // destroyed backend.
    struct WatchState
    {
        std::atomic<bool> alive{ false };
        std::atomic<int>  inFlight{ 0 };
        std::mutex        eventsMutex;
        std::shared_ptr<const ClipboardHistoryEvents> events;
    };

    template <typename Fn>
    void RaiseEvent(const std::shared_ptr<WatchState>& state, Fn&& fn)
    {
        if (!state->alive.load()) return;
        ++state->inFlight;
        struct Guard { std::shared_ptr<WatchState> s; ~Guard() { --s->inFlight; } } guard{ state };
        if (!state->alive.load()) return; // re-check after entering: Stop() may have raced us here

        std::shared_ptr<const ClipboardHistoryEvents> events;
        {
            std::lock_guard<std::mutex> lock(state->eventsMutex);
            events = state->events;
        }
        if (!events) return;
        // The public callback (fn -> ClipboardHistoryEvents::onXxx -> the raw C
        // function pointer supplied via setClipboardHistoryCallbacks) crosses the
        // C ABI boundary and must never let an exception escape this handler.
        try { fn(*events); }
        catch (...) { DLog(TAG, L"[RaiseEvent] handler threw"); }
    }
}

// =============================================================================
// ClipboardHistoryWinRt
// =============================================================================

class ClipboardHistoryWinRt final : public IClipboardHistoryBackend
{
public:
    ~ClipboardHistoryWinRt() override { StopWatch(); }

    void GetAvailabilityAsync(HistoryAvailabilityCallback done) override;
    void GetItemsAsync(HistoryItemsCallback done) override;
    void SetItemAsContentAsync(const std::wstring& id, HistoryStatusCallback done) override;
    void DeleteItemAsync(const std::wstring& id, HistoryStatusCallback done) override;
    void ClearUnpinnedAsync(HistoryStatusCallback done) override;
    DWORD QueryHistoryEnabled(bool& enabled) override;
    DWORD QueryRoamingEnabled(bool& enabled) override;

    DWORD StartWatch(std::shared_ptr<const ClipboardHistoryEvents> events) override;
    void  ReplaceEvents(std::shared_ptr<const ClipboardHistoryEvents> events) override;
    bool  StopWatch() override;
    bool  CanDestroy() const override;

private:
    winrt::fire_and_forget RunGetItemsAsync(HistoryItemsCallback done);
    winrt::fire_and_forget RunSetItemAsContentAsync(std::wstring id, HistoryStatusCallback done);
    winrt::fire_and_forget RunDeleteItemAsync(std::wstring id, HistoryStatusCallback done);

    // Guards watching_/revokePending_/watchState_/retiredStates_: StartWatch/
    // StopWatch/ReplaceEvents are owner-UI-thread-only by contract, but
    // CanDestroy() is reachable from any thread (canDestroyClipboardManager
    // has no thread restriction), so these fields need real synchronization,
    // not same-thread-confinement reasoning (2026-07-29 v2 review H2).
    mutable std::mutex stateMutex_;
    std::shared_ptr<WatchState> watchState_;
    // States retired by a successful StopWatch(), kept alive only until their
    // in-flight callback count drains to 0 (see H4 in the v1 review: CanDestroy
    // must not go true while a callback launched under the old state is still
    // running). Fully-drained entries are pruned opportunistically in
    // StopWatch() so this cannot grow without bound (v2 review L1).
    std::vector<std::shared_ptr<WatchState>> retiredStates_;
    bool hasHistoryToken_ = false;
    bool hasHistoryEnabledToken_ = false;
    bool hasRoamingToken_ = false;
    winrt::event_token historyToken_{};
    winrt::event_token historyEnabledToken_{};
    winrt::event_token roamingToken_{};
    bool watching_ = false;
    bool revokePending_ = false;
};

void ClipboardHistoryWinRt::GetAvailabilityAsync(HistoryAvailabilityCallback done)
{
    DLog(TAG, L"[GetAvailabilityAsync]");
    DWORD error = CLIPBOARD_ERROR_NONE;
    ClipboardHistoryAvailability avail{};
    try
    {
        if (!IsSelfForeground())
        {
            error = CLIPBOARD_ERROR_NOT_FOREGROUND;
        }
        else
        {
            avail.historyEnabled = Clipboard::IsHistoryEnabled();
            avail.roamingEnabled = Clipboard::IsRoamingEnabled();
        }
    }
    catch (...) { error = ClassifyWinRtException(); }

    try { done(error, avail); }
    catch (...) { DLog(TAG, L"[GetAvailabilityAsync] completion callback threw"); }
}

DWORD ClipboardHistoryWinRt::QueryHistoryEnabled(bool& enabled)
{
    DLog(TAG, L"[QueryHistoryEnabled]");
    enabled = false;
    if (!IsSelfForeground()) return CLIPBOARD_ERROR_NOT_FOREGROUND;
    try
    {
        enabled = Clipboard::IsHistoryEnabled();
        return CLIPBOARD_ERROR_NONE;
    }
    catch (...) { return ClassifyWinRtException(); }
}

DWORD ClipboardHistoryWinRt::QueryRoamingEnabled(bool& enabled)
{
    DLog(TAG, L"[QueryRoamingEnabled]");
    enabled = false;
    if (!IsSelfForeground()) return CLIPBOARD_ERROR_NOT_FOREGROUND;
    try
    {
        enabled = Clipboard::IsRoamingEnabled();
        return CLIPBOARD_ERROR_NONE;
    }
    catch (...) { return ClassifyWinRtException(); }
}

void ClipboardHistoryWinRt::GetItemsAsync(HistoryItemsCallback done)
{
    DLog(TAG, L"[GetItemsAsync]");
    RunGetItemsAsync(std::move(done)); // may throw synchronously on coroutine-frame allocation failure
}

winrt::fire_and_forget ClipboardHistoryWinRt::RunGetItemsAsync(HistoryItemsCallback done)
{
    DWORD error = CLIPBOARD_ERROR_NONE;
    std::vector<ClipboardHistoryEntry> items;
    try
    {
        if (!IsSelfForeground())
        {
            error = CLIPBOARD_ERROR_NOT_FOREGROUND;
        }
        else if (!Clipboard::IsHistoryEnabled())
        {
            error = CLIPBOARD_ERROR_HISTORY_DISABLED;
        }
        else
        {
            ClipboardHistoryItemsResult result = co_await Clipboard::GetHistoryItemsAsync();
            error = MapHistoryStatus(result.Status());
            if (error == CLIPBOARD_ERROR_NONE)
            {
                for (auto const& histItem : result.Items())
                {
                    ClipboardHistoryEntry entry;
                    entry.id = std::wstring(histItem.Id());
                    entry.timestampUtc = histItem.Timestamp().time_since_epoch().count();

                    DataPackageView view = histItem.Content();
                    for (auto const& fmt : view.AvailableFormats())
                    {
                        entry.contentTypes.emplace_back(fmt);
                    }
                    if (view.Contains(StandardDataFormats::Text()))
                    {
                        try
                        {
                            winrt::hstring text = co_await view.GetTextAsync();
                            entry.text = std::wstring(text);
                        }
                        catch (...)
                        {
                            // Per-item failure does not fail the whole request; leave text unset.
                            DLog(TAG, L"[RunGetItemsAsync] per-item GetTextAsync failed");
                        }
                    }
                    items.push_back(std::move(entry));
                }
            }
        }
    }
    catch (...)
    {
        error = ClassifyWinRtException();
        items.clear();
    }

    try { done(error, std::move(items)); }
    catch (...) { DLog(TAG, L"[RunGetItemsAsync] completion callback threw"); }
}

void ClipboardHistoryWinRt::SetItemAsContentAsync(const std::wstring& id, HistoryStatusCallback done)
{
    DFLog(TAG, L"[SetItemAsContentAsync] id: %ls", id.c_str());
    RunSetItemAsContentAsync(id, std::move(done));
}

winrt::fire_and_forget ClipboardHistoryWinRt::RunSetItemAsContentAsync(std::wstring id, HistoryStatusCallback done)
{
    DWORD error = CLIPBOARD_ERROR_NONE;
    try
    {
        if (!IsSelfForeground())
        {
            error = CLIPBOARD_ERROR_NOT_FOREGROUND;
        }
        else if (!Clipboard::IsHistoryEnabled())
        {
            error = CLIPBOARD_ERROR_HISTORY_DISABLED;
        }
        else
        {
            ClipboardHistoryItemsResult result = co_await Clipboard::GetHistoryItemsAsync();
            error = MapHistoryStatus(result.Status());
            if (error == CLIPBOARD_ERROR_NONE)
            {
                bool found = false;
                for (auto const& item : result.Items())
                {
                    if (std::wstring(item.Id()) == id)
                    {
                        error = MapSetHistoryItemStatus(Clipboard::SetHistoryItemAsContent(item));
                        found = true;
                        break;
                    }
                }
                if (!found) error = CLIPBOARD_ERROR_ITEM_DELETED;
            }
        }
    }
    catch (...) { error = ClassifyWinRtException(); }

    try { done(error); }
    catch (...) { DLog(TAG, L"[RunSetItemAsContentAsync] completion callback threw"); }
}

void ClipboardHistoryWinRt::DeleteItemAsync(const std::wstring& id, HistoryStatusCallback done)
{
    DFLog(TAG, L"[DeleteItemAsync] id: %ls", id.c_str());
    RunDeleteItemAsync(id, std::move(done));
}

winrt::fire_and_forget ClipboardHistoryWinRt::RunDeleteItemAsync(std::wstring id, HistoryStatusCallback done)
{
    DWORD error = CLIPBOARD_ERROR_NONE;
    try
    {
        if (!IsSelfForeground())
        {
            error = CLIPBOARD_ERROR_NOT_FOREGROUND;
        }
        else if (!Clipboard::IsHistoryEnabled())
        {
            error = CLIPBOARD_ERROR_HISTORY_DISABLED;
        }
        else
        {
            ClipboardHistoryItemsResult result = co_await Clipboard::GetHistoryItemsAsync();
            error = MapHistoryStatus(result.Status());
            if (error == CLIPBOARD_ERROR_NONE)
            {
                bool found = false;
                for (auto const& item : result.Items())
                {
                    if (std::wstring(item.Id()) == id)
                    {
                        // false only means "not successful"; the docs give no reason, so it
                        // is not classified as ACCESS_DENIED.
                        error = Clipboard::DeleteItemFromHistory(item) ? CLIPBOARD_ERROR_NONE : CLIPBOARD_ERROR_UNKNOWN;
                        found = true;
                        break;
                    }
                }
                if (!found) error = CLIPBOARD_ERROR_ITEM_DELETED;
            }
        }
    }
    catch (...) { error = ClassifyWinRtException(); }

    try { done(error); }
    catch (...) { DLog(TAG, L"[RunDeleteItemAsync] completion callback threw"); }
}

void ClipboardHistoryWinRt::ClearUnpinnedAsync(HistoryStatusCallback done)
{
    // Note: ClearHistory does NOT remove pinned items (documented OS behavior).
    DLog(TAG, L"[ClearUnpinnedAsync]");
    DWORD error = CLIPBOARD_ERROR_NONE;
    try
    {
        if (!IsSelfForeground())
        {
            error = CLIPBOARD_ERROR_NOT_FOREGROUND;
        }
        else if (!Clipboard::IsHistoryEnabled())
        {
            error = CLIPBOARD_ERROR_HISTORY_DISABLED;
        }
        else
        {
            error = Clipboard::ClearHistory() ? CLIPBOARD_ERROR_NONE : CLIPBOARD_ERROR_UNKNOWN;
        }
    }
    catch (...) { error = ClassifyWinRtException(); }

    try { done(error); }
    catch (...) { DLog(TAG, L"[ClearUnpinnedAsync] completion callback threw"); }
}

DWORD ClipboardHistoryWinRt::StartWatch(std::shared_ptr<const ClipboardHistoryEvents> events)
{
    DLog(TAG, L"[StartWatch]");
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        if (watching_) return CLIPBOARD_ERROR_NONE; // coordinator should not call this twice; guard anyway
        // A prior StopWatch() left at least one token un-revoked; refuse a fresh
        // registration until a later StopWatch() fully clears it (H3, v1 review).
        if (revokePending_) return CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED;
    }

    auto state = std::make_shared<WatchState>();
    state->events = events; // `alive` stays false until every token below commits

    try
    {
        historyToken_ = Clipboard::HistoryChanged([state](auto const&, auto const&)
        {
            RaiseEvent(state, [](const ClipboardHistoryEvents& e) { if (e.onHistoryChanged) e.onHistoryChanged(); });
        });
        hasHistoryToken_ = true;

        historyEnabledToken_ = Clipboard::HistoryEnabledChanged([state](auto const&, auto const&)
        {
            RaiseEvent(state, [](const ClipboardHistoryEvents& e)
            {
                if (e.onHistoryEnabledChanged) e.onHistoryEnabledChanged();
            });
        });
        hasHistoryEnabledToken_ = true;

        roamingToken_ = Clipboard::RoamingEnabledChanged([state](auto const&, auto const&)
        {
            RaiseEvent(state, [](const ClipboardHistoryEvents& e)
            {
                if (e.onRoamingEnabledChanged) e.onRoamingEnabledChanged();
            });
        });
        hasRoamingToken_ = true;
    }
    catch (...)
    {
        DFLog(TAG, L"[StartWatch] registration failed. err=%lu", ClassifyWinRtException());
        // Roll back whatever was registered before the failure. Only clear a
        // token flag when the unregister call itself succeeds; a failed
        // unregister leaves the flag set (and revokePending_ true) so
        // StopWatch() can retry it later instead of the token being lost.
        bool rollbackOk = true;
        if (hasHistoryToken_)
        {
            try { Clipboard::HistoryChanged(historyToken_); hasHistoryToken_ = false; }
            catch (...) { DLog(TAG, L"[StartWatch] rollback revoke failed: HistoryChanged"); rollbackOk = false; }
        }
        if (hasHistoryEnabledToken_)
        {
            try { Clipboard::HistoryEnabledChanged(historyEnabledToken_); hasHistoryEnabledToken_ = false; }
            catch (...) { DLog(TAG, L"[StartWatch] rollback revoke failed: HistoryEnabledChanged"); rollbackOk = false; }
        }
        if (hasRoamingToken_)
        {
            try { Clipboard::RoamingEnabledChanged(roamingToken_); hasRoamingToken_ = false; }
            catch (...) { DLog(TAG, L"[StartWatch] rollback revoke failed: RoamingEnabledChanged"); rollbackOk = false; }
        }
        // `state->alive` was never set true, so any handler invocation that
        // slipped in between registration and here already observed
        // alive == false and returned without dispatching.
        std::lock_guard<std::mutex> lock(stateMutex_);
        watching_ = false;
        revokePending_ = !rollbackOk;
        return CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED;
    }

    state->alive = true; // gate opens only once all 3 registrations committed
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        watchState_ = state;
        watching_ = true;
        revokePending_ = false;
    }
    return CLIPBOARD_ERROR_NONE;
}

void ClipboardHistoryWinRt::ReplaceEvents(std::shared_ptr<const ClipboardHistoryEvents> events)
{
    DLog(TAG, L"[ReplaceEvents]");
    std::shared_ptr<WatchState> state;
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        state = watchState_;
    }
    if (!state) return; // StartWatch was never called; coordinator should not do this
    std::lock_guard<std::mutex> lock(state->eventsMutex);
    state->events = std::move(events);
}

bool ClipboardHistoryWinRt::StopWatch()
{
    DLog(TAG, L"[StopWatch]");
    std::shared_ptr<WatchState> currentState;
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        if (!watching_ && !revokePending_) return true;
        currentState = watchState_;
    }

    // Close the gate before revoking tokens: once alive is false, no handler
    // that has not already passed the alive check can dispatch, even if the
    // OS fires the event again in the instant before the token is revoked.
    if (currentState) currentState->alive = false;

    bool allRevoked = true;
    if (hasHistoryToken_)
    {
        try { Clipboard::HistoryChanged(historyToken_); hasHistoryToken_ = false; }
        catch (...) { DLog(TAG, L"[StopWatch] revoke failed: HistoryChanged"); allRevoked = false; }
    }
    if (hasHistoryEnabledToken_)
    {
        try { Clipboard::HistoryEnabledChanged(historyEnabledToken_); hasHistoryEnabledToken_ = false; }
        catch (...) { DLog(TAG, L"[StopWatch] revoke failed: HistoryEnabledChanged"); allRevoked = false; }
    }
    if (hasRoamingToken_)
    {
        try { Clipboard::RoamingEnabledChanged(roamingToken_); hasRoamingToken_ = false; }
        catch (...) { DLog(TAG, L"[StopWatch] revoke failed: RoamingEnabledChanged"); allRevoked = false; }
    }

    std::lock_guard<std::mutex> lock(stateMutex_);
    if (allRevoked)
    {
        watching_ = false;
        revokePending_ = false;
        // Retire rather than drop the state: a callback that had already
        // passed the alive check before this call may still be running and
        // must keep decrementing the SAME WatchState's inFlight counter, and
        // CanDestroy() must keep observing it until that reaches 0 (H4).
        if (watchState_) retiredStates_.push_back(std::move(watchState_));
        watchState_.reset();
        // L1 (v2 review): prune already-drained retired states so this vector
        // cannot grow without bound across repeated stop/start cycles.
        retiredStates_.erase(
            std::remove_if(retiredStates_.begin(), retiredStates_.end(),
                           [](const std::shared_ptr<WatchState>& s) { return s->inFlight.load() == 0; }),
            retiredStates_.end());
    }
    else
    {
        revokePending_ = true;
    }
    return allRevoked;
}

bool ClipboardHistoryWinRt::CanDestroy() const
{
    // Reachable from any thread (H2, v2 review); stateMutex_ makes this a
    // consistent snapshot against StartWatch/StopWatch on the UI thread.
    std::lock_guard<std::mutex> lock(stateMutex_);
    if (watching_ || revokePending_) return false;
    if (watchState_ && watchState_->inFlight.load() != 0) return false;
    for (const auto& retired : retiredStates_)
    {
        if (retired->inFlight.load() != 0) return false;
    }
    return true;
}

std::unique_ptr<IClipboardHistoryBackend> MakeClipboardHistoryWinRtBackend()
{
    return std::make_unique<ClipboardHistoryWinRt>();
}
