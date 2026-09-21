#pragma once
// Runs a clipboard test of the C ABI on an owner thread of its own.
//
// The fake clipboard is the C++ API tests' StoringClipboard (design 12.1: the
// same fakes), so nothing a test writes reaches the clipboard of whoever runs
// it. Unlike ClipboardSessionForTest::Run, the body creates the session itself
// through the C ABI: creating it is part of what is under test.

#include "Support/ClipboardSessionForTest.h"

#include "Clipboard/Application/WindowsClipboardHistoryBackend.h"
#include "Clipboard/WindowsClipboardApiInternal.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"

#include <functional>
#include <memory>
#include <string>
#include <thread>

namespace CApiClipboardHarness {

using ClipboardSessionForTest::Check;
using ClipboardSessionForTest::Current;
using ClipboardSessionForTest::Failure;
using ClipboardSessionForTest::PumpMessages;

/// A history backend that keeps the events it was handed, so a test can
/// raise them, and answers every query with "on".
struct EventScript {
    std::shared_ptr<const ClipboardHistoryEvents> events;
    bool historyEnabled = true;
    bool roamingEnabled = true;
};

inline EventScript& Script()
{
    static EventScript script;
    return script;
}

class EventBackend final : public IClipboardHistoryBackend
{
public:
    void GetAvailabilityAsync(HistoryAvailabilityCallback) override {}
    void GetItemsAsync(HistoryItemsCallback) override {}
    void SetItemAsContentAsync(const std::wstring&, HistoryStatusCallback) override {}
    void DeleteItemAsync(const std::wstring&, HistoryStatusCallback) override {}
    void ClearUnpinnedAsync(HistoryStatusCallback) override {}

    DWORD QueryHistoryEnabled(bool& enabled) override { enabled = Script().historyEnabled; return CLIPBOARD_ERROR_NONE; }
    DWORD QueryRoamingEnabled(bool& enabled) override { enabled = Script().roamingEnabled; return CLIPBOARD_ERROR_NONE; }

    DWORD StartWatch(std::shared_ptr<const ClipboardHistoryEvents> events) override
    {
        Script().events = std::move(events);
        return CLIPBOARD_ERROR_NONE;
    }
    void ReplaceEvents(std::shared_ptr<const ClipboardHistoryEvents> events) override { Script().events = std::move(events); }
    bool StopWatch() override { Script().events.reset(); return true; }
    bool CanDestroy() const override { return true; }
};

inline std::unique_ptr<IClipboardHistoryBackend> MakeEventBackend()
{
    Script() = EventScript{};
    return std::make_unique<EventBackend>();
}

/// Raises one of the backend's events the way the OS would, and delivers it.
inline void Raise(std::function<void()> ClipboardHistoryEvents::*event)
{
    const auto events = Script().events;
    if (events && (*events).*event) ((*events).*event)();
    PumpMessages();
}

/// The session's hidden window: the fake remembers whoever opened it last.
inline HWND SessionWindow()
{
    return Current() ? Current()->GetClipboardOwner() : nullptr;
}

/**
 * @brief Runs body on an STA thread with the fake clipboard and the event
 *        backend in place, then puts every piece of process state back -
 *        including a session the body abandoned.
 * @return What went wrong, or an empty string.
 */
inline std::wstring RunOnOwner(const std::function<void()>& body, DWORD apartment = COINIT_APARTMENTTHREADED)
{
    std::wstring failure;
    std::thread owner([&] {
        if (FAILED(::CoInitializeEx(nullptr, apartment))) {
            failure = L"CoInitializeEx failed";
            return;
        }
        ClipboardManager::GetInstance().SetHistoryBackendFactoryForTest(&MakeEventBackend);
        ClipboardSessionForTest::StoringClipboard clipboard;
        Current() = &clipboard;
        SetWin32ApiForTest(&clipboard);
        try {
            body();
        }
        catch (const Failure& f) { failure = f.message; }
        catch (...)              { failure = L"the body threw something unknown"; }
        ClipboardSessionForTest::CloseTheManagerFromItsOwnerThread();
        NativeToolkit::Clipboard::Detail::ClipboardTestAccess::ResetProcessState();
        SetWin32ApiForTest(nullptr);
        ClipboardManager::GetInstance().SetHistoryBackendFactoryForTest(nullptr);
        Script() = EventScript{};
        Current() = nullptr;
        ::CoUninitialize();
    });
    owner.join();
    return failure;
}

}  // namespace CApiClipboardHarness
