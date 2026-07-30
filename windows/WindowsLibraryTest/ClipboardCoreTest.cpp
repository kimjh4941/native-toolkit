#include "pch.h"
#include "../WindowsLibrary/WindowsClipboardCore.h"
#include "../WindowsLibrary/WindowsClipboardManager.h"
#include <atomic>
#include <thread>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// Exercises WindowsClipboardCore's Win32 failure paths via the
// IClipboardWin32Api seam (SetWin32ApiForTest), with no real clipboard or
// window involved. Covers the review's M6 finding that SetClipboardData,
// EmptyClipboard and listener-unregister failures were reachable through the
// seam but had no test coverage, and the H6 fix (write-option marker failure
// must roll back instead of being silently ignored).
// ============================================================================

namespace WindowsClipboardCoreTest
{

namespace
{
    class MockWin32Api final : public IClipboardWin32Api
    {
    public:
        bool openClipboardResult = true;
        bool emptyClipboardResult = true;
        int  emptyClipboardCallCount = 0;
        int  emptyClipboardFailFromCall = -1; // -1 = never fail via this hook
        bool addListenerResult = true;
        bool removeListenerResult = true;
        HWND clipboardOwner = nullptr;
        std::shared_ptr<std::atomic<DWORD>> sequence =
            std::make_shared<std::atomic<DWORD>>(1);
        std::function<bool(UINT)> setClipboardDataShouldSucceed; // null = always succeed
        std::function<bool(UINT)> isFormatAvailableFn;           // null = always available

        BOOL OpenClipboard(HWND) override { return openClipboardResult ? TRUE : FALSE; }
        BOOL CloseClipboard() override { return TRUE; }
        BOOL EmptyClipboard() override
        {
            ++emptyClipboardCallCount;
            if (emptyClipboardFailFromCall > 0 && emptyClipboardCallCount >= emptyClipboardFailFromCall) return FALSE;
            return emptyClipboardResult ? TRUE : FALSE;
        }
        HANDLE SetClipboardData(UINT format, HANDLE hMem) override
        {
            const bool ok = setClipboardDataShouldSucceed ? setClipboardDataShouldSucceed(format) : true;
            if (!ok) { ::SetLastError(ERROR_OUTOFMEMORY); return nullptr; }
            ::SetLastError(ERROR_SUCCESS);
            return hMem ? hMem : reinterpret_cast<HANDLE>(1); // non-null sentinel for the deferred-reserve placeholder case
        }
        HANDLE GetClipboardData(UINT) override { return nullptr; }
        HWND   GetClipboardOwner() override { return clipboardOwner; }
        BOOL   IsClipboardFormatAvailable(UINT format) override
        {
            return (isFormatAvailableFn ? isFormatAvailableFn(format) : true) ? TRUE : FALSE;
        }
        BOOL  AddClipboardFormatListener(HWND) override { return addListenerResult ? TRUE : FALSE; }
        BOOL  RemoveClipboardFormatListener(HWND) override { return removeListenerResult ? TRUE : FALSE; }
        DWORD GetClipboardSequenceNumber() override { return sequence->load(); }
    };

    HWND FakeOwner() { return reinterpret_cast<HWND>(static_cast<UINT_PTR>(0x1234)); }
}

TEST_CLASS(ClipboardCoreTest)
{
public:
    MockWin32Api mock_;

    TEST_METHOD_INITIALIZE(MethodSetup)
    {
        mock_ = MockWin32Api{};
        SetWin32ApiForTest(&mock_);
    }

    TEST_METHOD_CLEANUP(MethodCleanup)
    {
        SetWin32ApiForTest(nullptr);
    }

    // -------------------------------------------------------------------
    // OpenClipboard / EmptyClipboard / SetClipboardData failure injection
    // -------------------------------------------------------------------

    TEST_METHOD(Test_CopyPlainText_OpenClipboardFails_ReturnsBusy)
    {
        mock_.openClipboardResult = false;
        const DWORD err = CopyPlainText(FakeOwner(), L"hello", CLIPBOARD_WRITE_OPTION_NONE);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_BUSY), err);
    }

    TEST_METHOD(Test_CopyPlainText_EmptyClipboardFails_ReturnsUnknown)
    {
        mock_.emptyClipboardResult = false;
        const DWORD err = CopyPlainText(FakeOwner(), L"hello", CLIPBOARD_WRITE_OPTION_NONE);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_UNKNOWN), err);
    }

    TEST_METHOD(Test_CopyPlainText_SetClipboardDataFails_ReturnsUnknown)
    {
        mock_.setClipboardDataShouldSucceed = [](UINT) { return false; };
        const DWORD err = CopyPlainText(FakeOwner(), L"hello", CLIPBOARD_WRITE_OPTION_NONE);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_UNKNOWN), err);
    }

    TEST_METHOD(Test_CopyPlainText_InvalidWriteOptionBits_ReturnsInvalidParameter)
    {
        // Validated before any Win32 call, so the mock's failure knobs don't matter here.
        const DWORD err = CopyPlainText(FakeOwner(), L"hello", 0xFFFFFFFFu);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_INVALID_PARAMETER), err);
    }

    // -------------------------------------------------------------------
    // H6: write-option marker placement failure must roll back, not be
    // silently swallowed as success.
    // -------------------------------------------------------------------

    TEST_METHOD(Test_CopyPlainText_ExcludeHistoryMarkerFails_RollsBackAndReturnsUnknown)
    {
        // CF_UNICODETEXT succeeds (the main payload); any other format (the
        // CanIncludeInClipboardHistory marker) fails to place.
        mock_.setClipboardDataShouldSucceed = [](UINT fmt) { return fmt == CF_UNICODETEXT; };
        const DWORD err = CopyPlainText(FakeOwner(), L"hello", CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_UNKNOWN), err);
        // One EmptyClipboard for the initial write, one more for the rollback.
        Assert::AreEqual(2, mock_.emptyClipboardCallCount);
    }

    TEST_METHOD(Test_CopyPlainText_ExcludeHistoryMarkerFails_RollbackAlsoFails_ReturnsPartialState)
    {
        mock_.setClipboardDataShouldSucceed = [](UINT fmt) { return fmt == CF_UNICODETEXT; };
        mock_.emptyClipboardFailFromCall = 2; // 1st EmptyClipboard (initial) ok, 2nd (rollback) fails
        const DWORD err = CopyPlainText(FakeOwner(), L"hello", CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_PARTIAL_STATE), err);
    }

    // -------------------------------------------------------------------
    // CopyMultipleFormats partial-placement rollback
    // -------------------------------------------------------------------

    TEST_METHOD(Test_CopyMultipleFormats_SecondFormatFails_RollbackSucceeds_ReturnsUnknown)
    {
        constexpr UINT kFmtA = 0xC001;
        constexpr UINT kFmtB = 0xC002;
        mock_.setClipboardDataShouldSucceed = [kFmtA](UINT fmt) { return fmt == kFmtA; };

        std::vector<FormatPayload> items;
        items.push_back(FormatPayload{ kFmtA, { 1, 2, 3 } });
        items.push_back(FormatPayload{ kFmtB, { 4, 5, 6 } });

        const DWORD err = CopyMultipleFormats(FakeOwner(), items, CLIPBOARD_WRITE_OPTION_NONE);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_UNKNOWN), err);
        Assert::AreEqual(2, mock_.emptyClipboardCallCount);
    }

    TEST_METHOD(Test_CopyMultipleFormats_SecondFormatFails_RollbackAlsoFails_ReturnsPartialState)
    {
        constexpr UINT kFmtA = 0xC001;
        constexpr UINT kFmtB = 0xC002;
        mock_.setClipboardDataShouldSucceed = [kFmtA](UINT fmt) { return fmt == kFmtA; };
        mock_.emptyClipboardFailFromCall = 2;

        std::vector<FormatPayload> items;
        items.push_back(FormatPayload{ kFmtA, { 1, 2, 3 } });
        items.push_back(FormatPayload{ kFmtB, { 4, 5, 6 } });

        const DWORD err = CopyMultipleFormats(FakeOwner(), items, CLIPBOARD_WRITE_OPTION_NONE);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_PARTIAL_STATE), err);
    }

    // -------------------------------------------------------------------
    // Deferred mutation reporting
    // -------------------------------------------------------------------

    TEST_METHOD(Test_DeferredReserve_PlacementFailsAfterEmpty_ReportsMutation)
    {
        mock_.clipboardOwner = FakeOwner();
        mock_.setClipboardDataShouldSucceed = [](UINT) { return false; };

        DeferredClipboard deferred;
        std::map<UINT, DeferredClipboard::Renderer> renderers;
        renderers.emplace(0xC001, [] { return GlobalMem(1); });

        bool mutated = false;
        const DWORD err = deferred.Reserve(FakeOwner(), std::move(renderers), &mutated);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_UNKNOWN), err);
        Assert::IsTrue(mutated);
    }

    TEST_METHOD(Test_DeferredRecover_PartialStateSuccess_ReportsMutation)
    {
        mock_.clipboardOwner = FakeOwner();
        mock_.setClipboardDataShouldSucceed = [](UINT) { return false; };
        mock_.emptyClipboardFailFromCall = 2;

        DeferredClipboard deferred;
        std::map<UINT, DeferredClipboard::Renderer> renderers;
        renderers.emplace(0xC001, [] { return GlobalMem(1); });

        bool reserveMutated = false;
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_PARTIAL_STATE),
                         deferred.Reserve(FakeOwner(), std::move(renderers), &reserveMutated));
        Assert::IsTrue(reserveMutated);

        mock_.emptyClipboardFailFromCall = -1;
        bool recoverMutated = false;
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_NONE),
                         deferred.RecoverFromPartialState(&recoverMutated));
        Assert::IsTrue(recoverMutated);
    }

    // -------------------------------------------------------------------
    // ClipboardWatcher: listener register/unregister failure and retry
    // -------------------------------------------------------------------

    TEST_METHOD(Test_ClipboardWatcher_Start_AddListenerFails_ReturnsFalse)
    {
        mock_.addListenerResult = false;
        ClipboardWatcher watcher;
        Assert::IsFalse(watcher.Start(FakeOwner()));
        Assert::IsFalse(watcher.IsRegistered());
    }

    TEST_METHOD(Test_ClipboardWatcher_Stop_RemoveListenerFails_StaysRegisteredAndRetryable)
    {
        ClipboardWatcher watcher;
        Assert::IsTrue(watcher.Start(FakeOwner()));
        Assert::IsTrue(watcher.IsRegistered());

        mock_.removeListenerResult = false;
        Assert::IsFalse(watcher.Stop());
        Assert::IsTrue(watcher.IsRegistered()); // stays registered: retryable, not lost

        mock_.removeListenerResult = true;
        Assert::IsTrue(watcher.Stop());
        Assert::IsFalse(watcher.IsRegistered());
    }

    TEST_METHOD(Test_ClipboardWatcher_UpdateRacingSelfWrite_WaitsForSequenceRegistration)
    {
        ClipboardWatcher watcher;
        Assert::IsTrue(watcher.Start(FakeOwner()));

        std::atomic<int> callbackCount{ 0 };
        watcher.onChanged = [&callbackCount] { ++callbackCount; };
        std::atomic<bool> updateEntered{ false };
        std::atomic<bool> updateFinished{ false };
        std::thread updateThread;

        {
            auto transaction = watcher.BeginSelfWrite();
            mock_.sequence->store(2);
            updateThread = std::thread([&]
            {
                updateEntered.store(true);
                watcher.OnClipboardUpdate();
                updateFinished.store(true);
            });
            while (!updateEntered.load()) std::this_thread::yield();
            Assert::IsFalse(updateFinished.load());
            transaction.NoteMutation();
        }

        updateThread.join();
        Assert::AreEqual(0, callbackCount.load());
    }
};

} // namespace WindowsClipboardCoreTest
