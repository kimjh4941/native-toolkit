#pragma once
// Runs a clipboard test of the C ABI on an owner thread of its own.
//
// The fake clipboard here stores what it is given, as the C++ API tests'
// StoringClipboard does, and also sends the owner the messages Windows sends:
// WM_DESTROYCLIPBOARD when the clipboard is emptied, and WM_RENDERFORMAT when
// a program reads a format that was only reserved. Deferred rendering and the
// release of its user_data turn on exactly those messages (design 7.5.3), so
// a fake without them could not test either. Unlike
// ClipboardSessionForTest::Run, the body creates the session itself through
// the C ABI: creating it is part of what is under test.

#include "Support/ClipboardSessionForTest.h"

#include "Clipboard/Application/WindowsClipboardHistoryBackend.h"
#include "Clipboard/Data/WindowsClipboardCore.h"
#include "Clipboard/WindowsClipboardApiInternal.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"

#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace CApiClipboardHarness {

using ClipboardSessionForTest::Check;
using ClipboardSessionForTest::Failure;
using ClipboardSessionForTest::PumpMessages;

/// A clipboard that keeps what is put in it and talks to its owner as
/// Windows does. Single-threaded use from the owner thread, plus a write from
/// another thread that sends its messages across.
class OwnerClipboard final : public IClipboardWin32Api
{
public:
    ~OwnerClipboard() override { Free(); }

    BOOL OpenClipboard(HWND window) override { opener_ = window; return TRUE; }
    BOOL CloseClipboard() override { return TRUE; }

    BOOL EmptyClipboard() override
    {
        if (failEmpty > 0) {
            --failEmpty;
            ::SetLastError(ERROR_ACCESS_DENIED);
            return FALSE;
        }
        // Windows tells the owner it is losing the clipboard, synchronously,
        // before the new owner is set.
        if (owner_) ::SendMessageW(owner_, WM_DESTROYCLIPBOARD, 0, 0);
        Free();
        owner_ = opener_;
        return TRUE;
    }

    HANDLE SetClipboardData(UINT format, HANDLE memory) override
    {
        if (!memory && failPlaceholder) {
            if (failRollback) failEmpty = 1;   // the rollback that follows fails too
            ::SetLastError(ERROR_ACCESS_DENIED);
            return nullptr;
        }
        if (const auto existing = data_.find(format); existing != data_.end() && existing->second) {
            ::GlobalFree(existing->second);
        }
        data_[format] = static_cast<HGLOBAL>(memory);
        ::SetLastError(ERROR_SUCCESS);
        return memory ? memory : reinterpret_cast<HANDLE>(1);
    }

    HANDLE GetClipboardData(UINT format) override
    {
        auto found = data_.find(format);
        if (found == data_.end()) return nullptr;
        // A reserved format: Windows asks the owner to render it now.
        if (!found->second && owner_) {
            ::SendMessageW(owner_, WM_RENDERFORMAT, format, 0);
            found = data_.find(format);
        }
        return found == data_.end() ? nullptr : found->second;
    }

    HWND  GetClipboardOwner() override { return owner_; }
    BOOL  IsClipboardFormatAvailable(UINT format) override { return data_.count(format) ? TRUE : FALSE; }
    BOOL  AddClipboardFormatListener(HWND) override { return TRUE; }
    BOOL  RemoveClipboardFormatListener(HWND) override { return TRUE; }
    DWORD GetClipboardSequenceNumber() override { return ++sequence_; }

    /// Stands in for another program emptying the clipboard.
    void EmptyByAnotherProgram()
    {
        const HWND previous = owner_;
        if (previous) ::SendMessageW(previous, WM_DESTROYCLIPBOARD, 0, 0);
        Free();
        owner_ = nullptr;
    }

    std::vector<BYTE> BytesOf(UINT format) const
    {
        const auto found = data_.find(format);
        if (found == data_.end() || !found->second) return {};
        const SIZE_T size = ::GlobalSize(found->second);
        const void* locked = ::GlobalLock(found->second);
        std::vector<BYTE> bytes(size);
        if (locked && size) std::memcpy(bytes.data(), locked, size);
        if (locked) ::GlobalUnlock(found->second);
        return bytes;
    }

    bool   Holds(UINT format) const { return data_.count(format) != 0; }
    bool   IsReserved(UINT format) const { const auto f = data_.find(format); return f != data_.end() && !f->second; }
    size_t FormatCount() const { return data_.size(); }

    int  failEmpty = 0;           ///< The next N EmptyClipboard calls fail.
    bool failPlaceholder = false; ///< Every SetClipboardData(format, NULL) fails.
    bool failRollback = false;    ///< With failPlaceholder: the EmptyClipboard after it fails too.

private:
    void Free()
    {
        for (auto& [format, handle] : data_) {
            if (handle) ::GlobalFree(handle);
        }
        data_.clear();
    }

    std::map<UINT, HGLOBAL> data_;
    HWND                    opener_ = nullptr;
    HWND                    owner_ = nullptr;
    DWORD                   sequence_ = 1;
};

/// The fake in use for the body that is running.
inline OwnerClipboard*& Current()
{
    static OwnerClipboard* clipboard = nullptr;
    return clipboard;
}

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

/// The session's hidden window: the clipboard's owner since the last write.
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
        OwnerClipboard clipboard;
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

/// Runs work on another thread while the owner keeps handling messages, as an
/// owner with a message loop would: a write from there sends the owner
/// WM_DESTROYCLIPBOARD and waits for it to be handled.
inline void RunElsewhereWhilePumping(const std::function<void()>& work)
{
    std::thread other(work);
    const HANDLE handle = other.native_handle();
    for (;;) {
        const DWORD woke = ::MsgWaitForMultipleObjects(1, &handle, FALSE, 10000, QS_ALLINPUT);
        if (woke == WAIT_OBJECT_0) break;
        if (woke != WAIT_OBJECT_0 + 1) {
            other.join();
            throw Failure{L"the other thread did not finish"};
        }
        PumpMessages();
    }
    other.join();
}

}  // namespace CApiClipboardHarness
