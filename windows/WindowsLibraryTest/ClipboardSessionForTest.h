/**
 * @file ClipboardSessionForTest.h
 * @brief A clipboard that keeps what is put in it, and a session to use it.
 * @details
 *  Every clipboard test would otherwise write to the clipboard of whoever is
 *  running the tests. The Win32 clipboard sits behind IClipboardWin32Api, so
 *  it can be replaced by something that stores the handles in a map instead.
 *
 *  Two things are worth knowing about the fake:
 *
 *  It owns what it is given, exactly as the real clipboard does, and frees it
 *  on EmptyClipboard and on destruction.
 *
 *  It answers GetClipboardOwner with whoever opened it last. Deferred
 *  rendering checks that answer after placing each placeholder, so a fake that
 *  always answered null would fail every reservation for a reason that has
 *  nothing to do with the code under test.
 *
 *  Sessions need a thread that is an STA and that they can build a window on,
 *  so the harness here runs each body on one of its own, and brings back what
 *  went wrong rather than throwing an MSTest assertion across the boundary -
 *  the framework keeps its state on the thread it started the test on, and an
 *  assertion escaping a worker takes the host down.
 */
#pragma once

#include "Clipboard/Data/WindowsClipboardCore.h"
#include "Clipboard/WindowsClipboardApiInternal.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"

#include <cstring>
#include <functional>
#include <map>
#include <string>
#include <thread>
#include <vector>

namespace ClipboardSessionForTest {

/// A failed check inside a session body.
struct Failure { std::wstring message; };

/// The assertion of a session body.
inline void Check(bool condition, const wchar_t* message)
{
    if (!condition) throw Failure{message};
}

/// A clipboard that keeps what is put in it, and nothing else's.
class StoringClipboard final : public IClipboardWin32Api
{
public:
    ~StoringClipboard() override { Free(); }

    BOOL OpenClipboard(HWND owner) override { owner_ = owner; return TRUE; }
    BOOL CloseClipboard() override { return TRUE; }
    BOOL EmptyClipboard() override { Free(); return TRUE; }

    HANDLE SetClipboardData(UINT format, HANDLE hMem) override
    {
        // The real clipboard takes ownership; so does this.
        if (const auto existing = data_.find(format); existing != data_.end()) {
            ::GlobalFree(existing->second);
        }
        data_[format] = static_cast<HGLOBAL>(hMem);
        ::SetLastError(ERROR_SUCCESS);
        return hMem ? hMem : reinterpret_cast<HANDLE>(1);
    }

    HANDLE GetClipboardData(UINT format) override
    {
        const auto found = data_.find(format);
        return found == data_.end() ? nullptr : found->second;
    }

    /// Whoever opened it last, which is what a reservation checks against.
    HWND  GetClipboardOwner() override { return owner_; }
    BOOL  IsClipboardFormatAvailable(UINT format) override { return data_.count(format) ? TRUE : FALSE; }
    BOOL  AddClipboardFormatListener(HWND) override { return TRUE; }
    BOOL  RemoveClipboardFormatListener(HWND) override { return TRUE; }
    DWORD GetClipboardSequenceNumber() override { return ++sequence_; }

    /// The bytes under a format. A format that is reserved but not yet
    /// rendered holds the null placeholder, which reads as no bytes.
    std::vector<BYTE> BytesOf(UINT format) const
    {
        const auto found = data_.find(format);
        if (found == data_.end() || !found->second) return {};
        const SIZE_T size = ::GlobalSize(found->second);
        const void* locked = ::GlobalLock(found->second);
        std::vector<BYTE> bytes(size);
        if (locked && size) ::memcpy(bytes.data(), locked, size);
        if (locked) ::GlobalUnlock(found->second);
        return bytes;
    }

    bool   Holds(UINT format) const { return data_.count(format) != 0; }
    size_t FormatCount() const { return data_.size(); }

private:
    void Free()
    {
        for (auto& [format, handle] : data_) {
            if (handle) ::GlobalFree(handle);
        }
        data_.clear();
    }

    std::map<UINT, HGLOBAL> data_;
    HWND                    owner_ = nullptr;
    DWORD                   sequence_ = 1;
};

/// The fake in use for the body that is running, for reading back what a write
/// actually placed.
inline StoringClipboard*& Current()
{
    static thread_local StoringClipboard* clipboard = nullptr;
    return clipboard;
}

/// Delivers whatever the session posted to itself.
inline void PumpMessages()
{
    MSG message;
    while (::PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        ::TranslateMessage(&message);
        ::DispatchMessageW(&message);
    }
}

/// Puts the manager back, whatever the body did or left undone. Only the
/// owning thread may close it, and that thread is this one, about to exit.
inline void CloseTheManagerFromItsOwnerThread()
{
    auto& backing = ClipboardManager::GetInstance();
    for (int attempt = 0; attempt < 6; ++attempt) {
        DWORD error = CLIPBOARD_ERROR_NONE;
        if (backing.Uninit(&error)) return;
        // Another thread's business, not this one's to finish.
        if (error == CLIPBOARD_ERROR_WRONG_THREAD) return;
        PumpMessages();
    }
}

/**
 * @brief Runs the body on an STA thread, with a session open and the fake
 *        clipboard in place.
 * @return What went wrong, or an empty string.
 */
inline std::wstring Run(const std::function<void(NativeToolkit::Clipboard::Session&)>& body)
{
    namespace Api = NativeToolkit::Clipboard;

    std::wstring failure;
    std::thread worker([&] {
        if (FAILED(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) {
            failure = L"CoInitializeEx(STA) failed";
            return;
        }
        StoringClipboard clipboard;
        Current() = &clipboard;
        SetWin32ApiForTest(&clipboard);
        try {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed");
            // Closing is the body's job in the ordinary case too, but a failed
            // check leaves early and an unclosed session would be abandoned -
            // which asserts, and would bury the real failure.
            struct Closer {
                Api::Session& session;
                ~Closer() { for (int i = 0; i < 6 && !session.Close().has_value(); ++i) PumpMessages(); }
            } closer{session.value()};
            body(session.value());
        }
        catch (const Failure& f) { failure = f.message; }
        catch (...)              { failure = L"the session body threw something unknown"; }
        CloseTheManagerFromItsOwnerThread();
        SetWin32ApiForTest(nullptr);
        Current() = nullptr;
        ::CoUninitialize();
    });
    worker.join();
    return failure;
}

}  // namespace ClipboardSessionForTest
