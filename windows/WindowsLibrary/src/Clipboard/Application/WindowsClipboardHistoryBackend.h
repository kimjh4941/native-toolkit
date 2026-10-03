/**
 * @file WindowsClipboardHistoryBackend.h
 * @brief Port for clipboard history access (Domain types only; no winrt:: types).
 * @details
 *  Request methods are asynchronous (completion callback) even where the
 *  underlying WinRT API is synchronous (GetAvailabilityAsync), because the
 *  Port must let a mock control completion timing for pending/cancel/drain
 *  tests. Event-value queries are synchronous and owner-UI-thread-only.
 */
#pragma once

#include <windows.h>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

struct ClipboardHistoryEntry
{
    std::wstring id;
    std::optional<std::wstring> text;         // nullopt when the item carries no text
    std::vector<std::wstring>   contentTypes; // format names available on the item
    int64_t                     timestampUtc = 0;
};

struct ClipboardHistoryAvailability
{
    bool historyEnabled = false;
    bool roamingEnabled = false;
};

// Completion callbacks: platform-independent, invoked on the owner UI thread,
// exactly once per request, and MUST NOT throw (implementations catch and log
// any violation rather than propagate it).
using HistoryItemsCallback        = std::function<void(DWORD error, std::vector<ClipboardHistoryEntry>)>;
using HistoryStatusCallback       = std::function<void(DWORD error)>;
using HistoryAvailabilityCallback = std::function<void(DWORD error, ClipboardHistoryAvailability)>;

// Event callbacks raised by the backend while watching. Individually nullable.
struct ClipboardHistoryEvents
{
    std::function<void()> onHistoryChanged;         // a NEW ITEM was added
    std::function<void()> onHistoryEnabledChanged;  // value is queried later on the owner UI thread
    std::function<void()> onRoamingEnabledChanged;  // value is queried later on the owner UI thread
};

// ---------------------------------------------------------------------------
// Port
// ---------------------------------------------------------------------------

class IClipboardHistoryBackend
{
public:
    virtual ~IClipboardHistoryBackend() = default;

    // All of these must be called on the owner UI thread. They return
    // immediately; completion is delivered through the callback, on the same
    // thread, exactly once.
    virtual void GetAvailabilityAsync(HistoryAvailabilityCallback done) = 0;
    virtual void GetItemsAsync(HistoryItemsCallback done) = 0;
    virtual void SetItemAsContentAsync(const std::wstring& id, HistoryStatusCallback done) = 0;
    virtual void DeleteItemAsync(const std::wstring& id, HistoryStatusCallback done) = 0;
    virtual void ClearUnpinnedAsync(HistoryStatusCallback done) = 0;

    // Synchronous event-value queries. These MUST be called on the focused
    // owner UI thread. Event handlers only signal that a value changed; they
    // must not call Clipboard APIs on the WinRT event thread.
    virtual DWORD QueryHistoryEnabled(bool& enabled) = 0;
    virtual DWORD QueryRoamingEnabled(bool& enabled) = 0;

    // Event subscription. The internal WinRT handler (if any) is registered
    // once and stays stable; user-facing callbacks are an immutable snapshot
    // swapped atomically via ReplaceEvents, so replacement never re-registers
    // the underlying event.
    virtual DWORD StartWatch(std::shared_ptr<const ClipboardHistoryEvents> events) = 0;
    virtual void  ReplaceEvents(std::shared_ptr<const ClipboardHistoryEvents> events) = 0;
    virtual bool  StopWatch() = 0;        // true only when every subscription was fully revoked
    virtual bool  CanDestroy() const = 0; // false while a subscription or in-flight callback remains
};
