#include "pch.h"
#include "WindowsClipboardHistoryCoordinator.h"
#include "common.h"

using namespace winrt::Windows::Data::Json;

static const wchar_t* TAG = L"ClipboardHistoryCoordinator";

namespace
{
    void SetErr(DWORD* pError, DWORD value) { if (pError) *pError = value; }

    std::wstring EncodeItems(const std::vector<ClipboardHistoryEntry>& items)
    {
        JsonArray arr;
        for (const auto& item : items)
        {
            JsonObject obj;
            obj.SetNamedValue(L"id", JsonValue::CreateStringValue(item.id));
            obj.SetNamedValue(L"text", item.text ? JsonValue::CreateStringValue(*item.text)
                                                  : JsonValue::CreateNullValue());
            JsonArray types;
            for (const auto& t : item.contentTypes) types.Append(JsonValue::CreateStringValue(t));
            obj.SetNamedValue(L"contentTypes", types);
            // JSON numbers are doubles (53-bit mantissa); a 100ns FILETIME-scale
            // tick count exceeds that range, so encode as a decimal string to
            // preserve full int64 precision (M4) instead of silently rounding.
            obj.SetNamedValue(L"timestamp", JsonValue::CreateStringValue(std::to_wstring(item.timestampUtc)));
            arr.Append(obj);
        }
        return std::wstring(arr.Stringify());
    }

    std::wstring EncodeAvailability(const ClipboardHistoryAvailability& a)
    {
        JsonObject obj;
        obj.SetNamedValue(L"historyEnabled", JsonValue::CreateBooleanValue(a.historyEnabled));
        obj.SetNamedValue(L"roamingEnabled", JsonValue::CreateBooleanValue(a.roamingEnabled));
        return std::wstring(obj.Stringify());
    }
}

ClipboardHistoryCoordinator::ClipboardHistoryCoordinator(std::unique_ptr<IClipboardHistoryBackend> backend,
                                                          ClipboardLifecycle& lifecycle)
    : backend_(std::move(backend)), lifecycle_(lifecycle)
{
    DLog(TAG, L"[ClipboardHistoryCoordinator] constructed");
}

void ClipboardHistoryCoordinator::AttachDispatchWindow(HWND hwnd)
{
    DFLog(TAG, L"[AttachDispatchWindow] hwnd: %p", hwnd);
    std::lock_guard<std::mutex> lock(mutex_);
    dispatchHwnd_ = hwnd;
}

void ClipboardHistoryCoordinator::DetachDispatchWindow()
{
    DLog(TAG, L"[DetachDispatchWindow]");
    std::lock_guard<std::mutex> lock(mutex_);
    dispatchHwnd_ = nullptr;
    pendingHistoryEvents_.clear();
}

uint32_t ClipboardHistoryCoordinator::Accept(ClipboardRequestCallback cb, DWORD* pError, StartFn start)
{
    if (!cb) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return 0; }

    std::lock_guard<std::mutex> lock(mutex_); // coordinator mutex (outer)
    if (!dispatchHwnd_) { SetErr(pError, CLIPBOARD_ERROR_NOT_INITIALIZED); return 0; }

    auto lease = lifecycle_.TryEnter(); // lifecycle mutex (inner), released immediately
    if (!lease) { SetErr(pError, CLIPBOARD_ERROR_NOT_INITIALIZED); return 0; }

    uint32_t id = nextId_++;
    if (id == 0) id = nextId_++; // never hand out 0

    RequestEntry entry;
    entry.callback = cb;
    entry.start = std::move(start);
    entry.lease = std::move(*lease);
    table_.emplace(id, std::move(entry));

    if (!::PostMessageW(dispatchHwnd_, WM_APP_CLIPBOARD_REQUEST, static_cast<WPARAM>(id), 0))
    {
        DFLog(TAG, L"[Accept] PostMessage failed. err=%lu", ::GetLastError());
        table_.erase(id); // drops the Queued input + lease right here
        SetErr(pError, CLIPBOARD_ERROR_UNKNOWN);
        return 0;
    }

    SetErr(pError, CLIPBOARD_ERROR_NONE);
    return id;
}

void ClipboardHistoryCoordinator::Complete(uint32_t id, DWORD error, const std::wstring* json)
{
    ClipboardRequestCallback cb = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = table_.find(id);
        if (it == table_.end()) return; // already completed/cancelled/drained
        cb = it->second.callback;
        table_.erase(it);
    }
    if (!cb) return;
    try { cb(id, error, json ? json->c_str() : nullptr); }
    catch (...) { DLog(TAG, L"[Complete] callback threw"); }
}

void ClipboardHistoryCoordinator::CompleteItems(uint32_t id, DWORD error, const std::vector<ClipboardHistoryEntry>& items)
{
    if (error != CLIPBOARD_ERROR_NONE) { Complete(id, error, nullptr); return; }
    // Called from a `noexcept` completion lambda: EncodeItems can throw
    // (WinRT JSON object allocation, std::bad_alloc from std::wstring/vector),
    // and letting that escape here would std::terminate the process (H2).
    try
    {
        const std::wstring json = EncodeItems(items);
        Complete(id, error, &json);
    }
    catch (const std::bad_alloc&) { Complete(id, CLIPBOARD_ERROR_OUT_OF_MEMORY, nullptr); }
    catch (...)
    {
        DLog(TAG, L"[CompleteItems] JSON encode threw");
        Complete(id, CLIPBOARD_ERROR_UNKNOWN, nullptr);
    }
}

void ClipboardHistoryCoordinator::CompleteStatus(uint32_t id, DWORD error)
{
    Complete(id, error, nullptr);
}

void ClipboardHistoryCoordinator::CompleteAvailability(uint32_t id, DWORD error, const ClipboardHistoryAvailability& avail)
{
    if (error != CLIPBOARD_ERROR_NONE) { Complete(id, error, nullptr); return; }
    try
    {
        const std::wstring json = EncodeAvailability(avail);
        Complete(id, error, &json);
    }
    catch (const std::bad_alloc&) { Complete(id, CLIPBOARD_ERROR_OUT_OF_MEMORY, nullptr); }
    catch (...)
    {
        DLog(TAG, L"[CompleteAvailability] JSON encode threw");
        Complete(id, CLIPBOARD_ERROR_UNKNOWN, nullptr);
    }
}

uint32_t ClipboardHistoryCoordinator::RequestGetItems(ClipboardRequestCallback cb, DWORD* pError)
{
    DLog(TAG, L"[RequestGetItems]");
    auto self = shared_from_this();
    return Accept(cb, pError, [self](uint32_t id, ClipboardLifecycle::Lease lease)
    {
        // Wrapped in a shared_ptr because Lease is move-only and std::function
        // (HistoryItemsCallback) requires a copy-constructible target.
        auto sharedLease = std::make_shared<ClipboardLifecycle::Lease>(std::move(lease));
        self->backend_->GetItemsAsync(
            [self, id, sharedLease](DWORD error, std::vector<ClipboardHistoryEntry> items) noexcept
            {
                self->CompleteItems(id, error, items);
            });
    });
}

uint32_t ClipboardHistoryCoordinator::RequestRestoreItem(const std::wstring& id_, ClipboardRequestCallback cb, DWORD* pError)
{
    DFLog(TAG, L"[RequestRestoreItem] id: %ls", id_.c_str());
    if (id_.empty()) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return 0; }
    auto self = shared_from_this();
    return Accept(cb, pError, [self, id_](uint32_t id, ClipboardLifecycle::Lease lease)
    {
        auto sharedLease = std::make_shared<ClipboardLifecycle::Lease>(std::move(lease));
        self->backend_->SetItemAsContentAsync(id_,
            [self, id, sharedLease](DWORD error) noexcept
            {
                self->CompleteStatus(id, error);
            });
    });
}

uint32_t ClipboardHistoryCoordinator::RequestDeleteItem(const std::wstring& id_, ClipboardRequestCallback cb, DWORD* pError)
{
    DFLog(TAG, L"[RequestDeleteItem] id: %ls", id_.c_str());
    if (id_.empty()) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return 0; }
    auto self = shared_from_this();
    return Accept(cb, pError, [self, id_](uint32_t id, ClipboardLifecycle::Lease lease)
    {
        auto sharedLease = std::make_shared<ClipboardLifecycle::Lease>(std::move(lease));
        self->backend_->DeleteItemAsync(id_,
            [self, id, sharedLease](DWORD error) noexcept
            {
                self->CompleteStatus(id, error);
            });
    });
}

uint32_t ClipboardHistoryCoordinator::RequestClearUnpinned(ClipboardRequestCallback cb, DWORD* pError)
{
    DLog(TAG, L"[RequestClearUnpinned]");
    auto self = shared_from_this();
    return Accept(cb, pError, [self](uint32_t id, ClipboardLifecycle::Lease lease)
    {
        auto sharedLease = std::make_shared<ClipboardLifecycle::Lease>(std::move(lease));
        self->backend_->ClearUnpinnedAsync(
            [self, id, sharedLease](DWORD error) noexcept
            {
                self->CompleteStatus(id, error);
            });
    });
}

uint32_t ClipboardHistoryCoordinator::RequestGetAvailability(ClipboardRequestCallback cb, DWORD* pError)
{
    DLog(TAG, L"[RequestGetAvailability]");
    auto self = shared_from_this();
    return Accept(cb, pError, [self](uint32_t id, ClipboardLifecycle::Lease lease)
    {
        auto sharedLease = std::make_shared<ClipboardLifecycle::Lease>(std::move(lease));
        self->backend_->GetAvailabilityAsync(
            [self, id, sharedLease](DWORD error, ClipboardHistoryAvailability avail) noexcept
            {
                self->CompleteAvailability(id, error, avail);
            });
    });
}

BOOL ClipboardHistoryCoordinator::CancelRequest(uint32_t id, DWORD* pError)
{
    DFLog(TAG, L"[CancelRequest] id: %u", id);
    if (id == 0) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return FALSE; }

    HWND hwnd;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (table_.find(id) == table_.end()) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return FALSE; }
        hwnd = dispatchHwnd_;
    }
    if (!hwnd || !::PostMessageW(hwnd, WM_APP_CLIPBOARD_CANCEL, static_cast<WPARAM>(id), 0))
    {
        SetErr(pError, CLIPBOARD_ERROR_UNKNOWN);
        return FALSE;
    }
    SetErr(pError, CLIPBOARD_ERROR_NONE);
    return TRUE;
}

void ClipboardHistoryCoordinator::OnStartQueuedRequest(uint32_t id)
{
    DFLog(TAG, L"[OnStartQueuedRequest] id: %u", id);
    std::optional<StartFn> start;
    std::optional<ClipboardLifecycle::Lease> lease;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = table_.find(id);
        if (it == table_.end() || !it->second.start) return; // already cancelled/drained
        start = std::move(it->second.start);
        lease = std::move(it->second.lease);
        it->second.start.reset();
        it->second.lease.reset();
    }

    try
    {
        (*start)(id, std::move(*lease));
    }
    catch (...)
    {
        DFLog(TAG, L"[OnStartQueuedRequest] start threw during launch. id=%u", id);
        Complete(id, CLIPBOARD_ERROR_OUT_OF_MEMORY, nullptr);
    }
}

void ClipboardHistoryCoordinator::OnCancelMessage(uint32_t id)
{
    DFLog(TAG, L"[OnCancelMessage] id: %u", id);
    Complete(id, CLIPBOARD_ERROR_CANCELED, nullptr);
}

void ClipboardHistoryCoordinator::OnDrainMessage()
{
    DLog(TAG, L"[OnDrainMessage]");
    drainMessagePosted_ = false;
    std::vector<std::pair<uint32_t, ClipboardRequestCallback>> local;
    local.swap(pendingDrain_);
    pendingDrainCount_.store(0, std::memory_order_relaxed);
    for (auto& [id, cb] : local)
    {
        if (cb)
        {
            try { cb(id, CLIPBOARD_ERROR_CANCELED, nullptr); }
            catch (...) { DLog(TAG, L"[OnDrainMessage] callback threw"); }
        }
        lifecycle_.ReleaseDrainWork();
    }
}

DWORD ClipboardHistoryCoordinator::SetHistoryCallbacks(ClipboardHistoryChangedCallback onChanged,
                                                        ClipboardFlagChangedCallback onHistoryEnabled,
                                                        ClipboardFlagChangedCallback onRoamingEnabled)
{
    DLog(TAG, L"[SetHistoryCallbacks]");
    if (!onChanged && !onHistoryEnabled && !onRoamingEnabled)
    {
        return StopWatch() ? CLIPBOARD_ERROR_NONE : CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED;
    }

    auto callbacks = std::make_shared<HistoryCallbackSnapshot>();
    callbacks->watchGeneration = watchGeneration_;
    callbacks->historyChanged = onChanged;
    callbacks->historyEnabled = onHistoryEnabled;
    callbacks->roamingEnabled = onRoamingEnabled;

    std::weak_ptr<ClipboardHistoryCoordinator> weakSelf = shared_from_this();
    auto events = std::make_shared<ClipboardHistoryEvents>();
    events->onHistoryChanged = [weakSelf, callbacks]()
    {
        if (auto self = weakSelf.lock()) self->PostHistoryEvent(kHistoryChanged, callbacks);
    };
    events->onHistoryEnabledChanged = [weakSelf, callbacks]()
    {
        if (auto self = weakSelf.lock()) self->PostHistoryEvent(kHistoryEnabledChanged, callbacks);
    };
    events->onRoamingEnabledChanged = [weakSelf, callbacks]()
    {
        if (auto self = weakSelf.lock()) self->PostHistoryEvent(kRoamingEnabledChanged, callbacks);
    };

    if (!isWatching_)
    {
        const DWORD err = backend_->StartWatch(events);
        if (err != CLIPBOARD_ERROR_NONE) return err;
        isWatching_ = true;
        return CLIPBOARD_ERROR_NONE;
    }
    backend_->ReplaceEvents(events);
    return CLIPBOARD_ERROR_NONE;
}

void ClipboardHistoryCoordinator::PostHistoryEvent(
    ClipboardHistoryEventKind kind,
    std::shared_ptr<const HistoryCallbackSnapshot> callbacks)
{
    DFLog(TAG, L"[PostHistoryEvent] kind: %llu", static_cast<unsigned long long>(kind));
    HWND hwnd = nullptr;
    uint32_t eventId = 0;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        hwnd = dispatchHwnd_;
        if (!hwnd || !callbacks) return;
        eventId = nextHistoryEventId_++;
        if (eventId == 0) eventId = nextHistoryEventId_++;
        pendingHistoryEvents_.emplace(eventId, PendingHistoryEvent{ kind, callbacks });
    }
    if (!::PostMessageW(hwnd, WM_APP_CLIPBOARD_HISTORY_EVENT,
                        static_cast<WPARAM>(eventId),
                        static_cast<LPARAM>(callbacks->watchGeneration)))
    {
        DFLog(TAG, L"[PostHistoryEvent] PostMessage failed. err=%lu", ::GetLastError());
        std::lock_guard<std::mutex> lock(mutex_);
        pendingHistoryEvents_.erase(eventId);
    }
}

void ClipboardHistoryCoordinator::OnHistoryEventMessage(WPARAM eventId, LPARAM generation)
{
    DFLog(TAG, L"[OnHistoryEventMessage] eventId: %llu, generation: %llu",
          static_cast<unsigned long long>(eventId),
          static_cast<unsigned long long>(generation));

    PendingHistoryEvent event;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = pendingHistoryEvents_.find(static_cast<uint32_t>(eventId));
        if (it == pendingHistoryEvents_.end()) return;
        event = std::move(it->second);
        pendingHistoryEvents_.erase(it);
    }
    if (!event.callbacks ||
        event.callbacks->watchGeneration != static_cast<uint64_t>(generation) ||
        event.callbacks->watchGeneration != watchGeneration_)
    {
        return;
    }

    switch (event.kind)
    {
    case kHistoryChanged:
        if (event.callbacks->historyChanged)
        {
            try { event.callbacks->historyChanged(); }
            catch (...) { DLog(TAG, L"[OnHistoryEventMessage] onHistoryChanged threw"); }
        }
        break;
    case kHistoryEnabledChanged:
        if (event.callbacks->historyEnabled)
        {
            bool enabled = false;
            const DWORD err = backend_->QueryHistoryEnabled(enabled);
            if (err != CLIPBOARD_ERROR_NONE)
            {
                DFLog(TAG, L"[OnHistoryEventMessage] QueryHistoryEnabled failed. err=%lu", err);
                break;
            }
            try { event.callbacks->historyEnabled(enabled ? TRUE : FALSE); }
            catch (...) { DLog(TAG, L"[OnHistoryEventMessage] onHistoryEnabledChanged threw"); }
        }
        break;
    case kRoamingEnabledChanged:
        if (event.callbacks->roamingEnabled)
        {
            bool enabled = false;
            const DWORD err = backend_->QueryRoamingEnabled(enabled);
            if (err != CLIPBOARD_ERROR_NONE)
            {
                DFLog(TAG, L"[OnHistoryEventMessage] QueryRoamingEnabled failed. err=%lu", err);
                break;
            }
            try { event.callbacks->roamingEnabled(enabled ? TRUE : FALSE); }
            catch (...) { DLog(TAG, L"[OnHistoryEventMessage] onRoamingEnabledChanged threw"); }
        }
        break;
    default:
        break;
    }
}

void ClipboardHistoryCoordinator::InvalidateHistoryEvents()
{
    DLog(TAG, L"[InvalidateHistoryEvents]");
    ++watchGeneration_;
    if (watchGeneration_ == 0) ++watchGeneration_;
    std::lock_guard<std::mutex> lock(mutex_);
    pendingHistoryEvents_.clear();
}

bool ClipboardHistoryCoordinator::CloseAndDrain()
{
    DLog(TAG, L"[CloseAndDrain]");
    HWND hwnd;
    size_t newlyQueued = 0;
    {
        std::lock_guard<std::mutex> lock(mutex_); // coordinator mutex (outer)
        hwnd = dispatchHwnd_;
        if (!table_.empty())
        {
            for (auto& [id, entry] : table_) pendingDrain_.emplace_back(id, entry.callback);
            newlyQueued = table_.size();
            table_.clear(); // drops any remaining Queued input + lease right here
            pendingDrainCount_.store(pendingDrain_.size(), std::memory_order_relaxed);
        }
        lifecycle_.CloseAndReserveDrainWork(newlyQueued); // lifecycle mutex (inner)
    }

    if (!pendingDrain_.empty() && !drainMessagePosted_)
    {
        if (hwnd && ::PostMessageW(hwnd, WM_APP_CLIPBOARD_DRAIN, 0, 0))
        {
            drainMessagePosted_ = true;
        }
        else
        {
            DFLog(TAG, L"[CloseAndDrain] drain PostMessage failed. err=%lu", ::GetLastError());
        }
    }
    return pendingDrain_.empty();
}

bool ClipboardHistoryCoordinator::StopWatch()
{
    DLog(TAG, L"[StopWatch]");
    if (!isWatching_)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        pendingHistoryEvents_.clear();
        return true;
    }
    if (!backend_->StopWatch()) return false;
    isWatching_ = false;
    InvalidateHistoryEvents();
    return true;
}

bool ClipboardHistoryCoordinator::CanDestroy() const
{
    return backend_->CanDestroy() && pendingDrainCount_.load(std::memory_order_relaxed) == 0;
}
