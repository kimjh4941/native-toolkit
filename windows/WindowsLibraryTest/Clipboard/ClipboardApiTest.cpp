#include "pch.h"
#include "Clipboard/WindowsClipboardApiInternal.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"

#include <crtdbg.h>

#include <functional>
#include <string>
#include <thread>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// C-5..C-8 of the stage 3 design, for the clipboard session.
//
// The session is where the C++ API departs from the C ABI most, and every
// departure is about ownership:
//
//  - a second initClipboardManager from the owning thread succeeds quietly; a
//    second Session::Create is refused, because two owners of one clipboard
//    would make shutdown a race (C-7);
//  - Close reports why it could not close and is expected to be retried, so it
//    has to stay callable, and succeed, once it has (C-6);
//  - destroying a session that was never closed does not close it, and cannot
//    be recovered from (C-8).
//
// All of it needs a real STA thread, because Create builds a window, so each
// test runs its body on one of its own. MSTest's assertions must not be thrown
// from those threads - the framework keeps its state on the thread it started
// the test on, and an assertion escaping a worker takes the host down instead
// of failing the test - so the bodies use Check() and the failure is raised
// back on the test thread.
//
// This is the first suite to link WindowsClipboardManager.cpp; the clipboard
// result report of 2026-07-30 lists "AcquireOwnerContext and a concurrent
// Uninit" as untested for exactly that reason, and this is the arrangement
// that would let it be tested.
// ============================================================================

namespace WindowsClipboardApiTest
{

namespace Api = NativeToolkit::Clipboard;
using Api::ErrorCode;

namespace
{
    /// A failed check inside an STA body. Plain and copyable, so it can cross
    /// a thread boundary in a way an MSTest assertion cannot.
    struct StaFailure { std::wstring message; };

    /// The assertion of an STA body.
    void Check(bool condition, const wchar_t* message)
    {
        if (!condition) throw StaFailure{message};
    }

    /// A history backend that accepts everything and finishes nothing, so a
    /// request can be left in flight on purpose.
    class NeverCompletingBackend final : public IClipboardHistoryBackend
    {
    public:
        void GetAvailabilityAsync(HistoryAvailabilityCallback) override {}
        void GetItemsAsync(HistoryItemsCallback) override {}
        void SetItemAsContentAsync(const std::wstring&, HistoryStatusCallback) override {}
        void DeleteItemAsync(const std::wstring&, HistoryStatusCallback) override {}
        void ClearUnpinnedAsync(HistoryStatusCallback) override {}

        DWORD QueryHistoryEnabled(bool& enabled) override { enabled = true; return CLIPBOARD_ERROR_NONE; }
        DWORD QueryRoamingEnabled(bool& enabled) override { enabled = true; return CLIPBOARD_ERROR_NONE; }

        DWORD StartWatch(std::shared_ptr<const ClipboardHistoryEvents>) override { return CLIPBOARD_ERROR_NONE; }
        void  ReplaceEvents(std::shared_ptr<const ClipboardHistoryEvents>) override {}
        bool  StopWatch() override { return true; }
        bool  CanDestroy() const override { return true; }
    };

    std::unique_ptr<IClipboardHistoryBackend> MakeNeverCompletingBackend()
    {
        return std::make_unique<NeverCompletingBackend>();
    }

    /// Delivers whatever the session posted to itself. Nothing here runs a
    /// real message loop, so the drain only happens when it is asked for.
    void PumpMessages()
    {
        MSG message;
        while (::PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            ::TranslateMessage(&message);
            ::DispatchMessageW(&message);
        }
    }

    /// Closes, pumping between attempts, the way the design says a caller does.
    Api::Result<void> CloseWithRetries(Api::Session& session, int attempts = 5)
    {
        Api::Result<void> result = session.Close();
        for (int i = 0; i < attempts && !result.has_value(); ++i) {
            PumpMessages();
            result = session.Close();
        }
        return result;
    }

    /// Puts the manager back, whatever the body did or left undone.
    ///
    /// Only the owning thread may close it, and that thread is this one, about
    /// to exit. Without this, one failed check would leave a session owned by a
    /// dead thread and every later test would be told WrongThread - which is
    /// how a single failure turns into a suite of them.
    void CloseTheManagerFromItsOwnerThread()
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

    /// Runs the body on a thread that is an STA, which is what Create needs.
    /// Returns the failure message, or an empty string.
    std::wstring RunOnStaCollecting(const std::function<void()>& body)
    {
        std::wstring failure;
        std::thread worker([&] {
            const HRESULT hr = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
            if (FAILED(hr)) {
                failure = L"CoInitializeEx(STA) failed";
                return;
            }
            try                        { body(); }
            catch (const StaFailure& f){ failure = f.message; }
            catch (const std::exception& e) { failure = L"the STA body threw: "
                                                        + std::wstring(e.what(), e.what() + strlen(e.what())); }
            catch (...)                { failure = L"the STA body threw something unknown"; }
            CloseTheManagerFromItsOwnerThread();
            ::CoUninitialize();
        });
        worker.join();
        return failure;
    }
}

TEST_CLASS(ClipboardApiTest)
{
public:

    TEST_METHOD_CLEANUP(ReleaseTheProcess)
    {
        // Nothing should be left open, but a failed check leaves a body early,
        // and one leaked session would fail every test after it.
        Api::Detail::ClipboardTestAccess::ResetProcessState();
        ClipboardManager::GetInstance().SetHistoryBackendFactoryForTest(nullptr);
    }

    // --- Opening and closing ------------------------------------------------

    TEST_METHOD(Test_CreateAndClose_Succeed)
    {
        RunOnSta([] {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed on an STA thread");
            Check(CloseWithRetries(session.value()).has_value(), L"Close failed");
        });
    }

    TEST_METHOD(Test_CreateFromAThreadThatIsNotAnSta_ReportsWrongApartment)
    {
        // The clipboard is windowed and thread-affine; an MTA thread has no
        // place to put the window.
        std::wstring failure;
        std::thread worker([&] {
            ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
            try {
                const auto session = Api::Session::Create(Api::SessionOptions{});
                Check(!session.has_value(), L"Create succeeded on an MTA thread");
                Check(ErrorCode::WrongApartment == session.error().code, L"not WrongApartment");
            } catch (const StaFailure& f) { failure = f.message; }
            ::CoUninitialize();
        });
        worker.join();
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }

    TEST_METHOD(Test_CloseAfterClose_Succeeds)
    {
        // C-6. The retry loop of the C ABI is "call it until it works", so the
        // call after the one that worked has to work too.
        RunOnSta([] {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed");

            Check(CloseWithRetries(session.value()).has_value(), L"the first Close failed");
            Check(session.value().Close().has_value(), L"the second Close failed");
            Check(session.value().Close().has_value(), L"the third Close failed");
        });
    }

    TEST_METHOD(Test_AfterAClosedSession_AnotherCanBeCreated)
    {
        RunOnSta([] {
            {
                auto first = Api::Session::Create(Api::SessionOptions{});
                Check(first.has_value(), L"Create failed");
                Check(CloseWithRetries(first.value()).has_value(), L"Close failed");
            }
            auto second = Api::Session::Create(Api::SessionOptions{});
            Check(second.has_value(), L"the closed session did not release the process");
            Check(CloseWithRetries(second.value()).has_value(), L"the second Close failed");
        });
    }

    // --- A second session ---------------------------------------------------

    TEST_METHOD(Test_SecondCreateFromTheOwningThread_ReportsNotSupported)
    {
        // C-7. initClipboardManager would succeed here and hand back nothing;
        // Create cannot, because it would hand back a second owner.
        RunOnSta([] {
            auto first = Api::Session::Create(Api::SessionOptions{});
            Check(first.has_value(), L"Create failed");

            const auto second = Api::Session::Create(Api::SessionOptions{});
            Check(!second.has_value(), L"a second session was handed out");
            Check(ErrorCode::NotSupported == second.error().code, L"not NotSupported");

            Check(CloseWithRetries(first.value()).has_value(), L"Close failed");
        });
    }

    TEST_METHOD(Test_SecondCreateFromAnotherThread_ReportsWrongThread)
    {
        // C-7, the other half: from elsewhere the answer is the one every
        // owner-only call gives, not NotSupported.
        RunOnSta([] {
            auto first = Api::Session::Create(Api::SessionOptions{});
            Check(first.has_value(), L"Create failed");

            const std::wstring inner = RunOnStaCollecting([] {
                const auto second = Api::Session::Create(Api::SessionOptions{});
                Check(!second.has_value(), L"a second session was handed out to another thread");
                Check(ErrorCode::WrongThread == second.error().code, L"not WrongThread");
            });
            Check(inner.empty(), inner.empty() ? L"" : inner.c_str());

            Check(CloseWithRetries(first.value()).has_value(), L"Close failed");
        });
    }

    // --- Close's reasons ----------------------------------------------------

    TEST_METHOD(Test_CloseFromAnotherThread_ReportsWrongThread)
    {
        RunOnSta([] {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed");

            const std::wstring inner = RunOnStaCollecting([&] {
                const auto result = session.value().Close();
                Check(!result.has_value(), L"a non-owner closed the session");
                Check(ErrorCode::WrongThread == result.error().code, L"not WrongThread");
            });
            Check(inner.empty(), inner.empty() ? L"" : inner.c_str());

            // The refusal left the session open, so it is still this thread's
            // to close.
            Check(CloseWithRetries(session.value()).has_value(), L"Close failed");
        });
    }

    TEST_METHOD(Test_CloseWhileSomethingHoldsTheSessionOpen_ReportsBusy)
    {
        RunOnSta([] {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed");

            auto& backing = ClipboardManager::GetInstance();
            {
                // A synchronous call in progress on another thread looks like
                // this from here.
                auto lease = backing.lifecycle_.TryEnter();
                Check(lease.has_value(), L"the lifecycle refused a lease");

                const auto result = session.value().Close();
                Check(!result.has_value(), L"Close succeeded with work in flight");
                Check(ErrorCode::Busy == result.error().code, L"not Busy");
            }
            Check(CloseWithRetries(session.value()).has_value(), L"Close failed once the lease was gone");
        });
    }

    TEST_METHOD(Test_CloseWithARequestStillInFlight_ReportsCanceled)
    {
        // An accepted request that has not been delivered yet is what Canceled
        // means: the session is closing, and that request will be answered
        // with a cancellation rather than a result.
        ClipboardManager::GetInstance().SetHistoryBackendFactoryForTest(&MakeNeverCompletingBackend);

        RunOnSta([] {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed");

            auto& backing = ClipboardManager::GetInstance();
            DWORD error = CLIPBOARD_ERROR_NONE;
            const uint32_t id = backing.GetClipboardHistory(&IgnoreRequest, &error);
            Check(error == CLIPBOARD_ERROR_NONE, L"the request was not accepted");
            Check(id != 0, L"the request has no id");

            const auto result = session.value().Close();
            Check(!result.has_value(), L"Close succeeded with a request still queued");
            Check(ErrorCode::Canceled == result.error().code, L"not Canceled");

            // Delivering the cancellation is what lets the retry succeed.
            Check(CloseWithRetries(session.value()).has_value(), L"Close never succeeded");
        });
    }

    // --- CanClose -----------------------------------------------------------

    TEST_METHOD(Test_CanClose_IsFalseUntilTheShutdownCanFinish)
    {
        // It answers "is there anything left to wait for", which an open
        // session has not even started asking. The useful moment is between
        // two Close attempts.
        ClipboardManager::GetInstance().SetHistoryBackendFactoryForTest(&MakeNeverCompletingBackend);

        RunOnSta([] {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed");
            Check(!session.value().CanClose(), L"an open session claimed shutdown could finish");

            DWORD error = CLIPBOARD_ERROR_NONE;
            ClipboardManager::GetInstance().GetClipboardHistory(&IgnoreRequest, &error);

            Check(!session.value().Close().has_value(), L"Close succeeded with a request queued");
            Check(!session.value().CanClose(), L"the undelivered completion was not waited for");

            PumpMessages();
            Check(session.value().CanClose(), L"the drain did not finish");
            Check(session.value().Close().has_value(), L"Close failed after the drain");

            Check(session.value().CanClose(), L"a closed session said shutdown could not finish");
        });
    }

    TEST_METHOD(Test_CanClose_AnswersFromAnyThread)
    {
        RunOnSta([] {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed");

            bool answeredWithoutFaulting = false;
            std::thread elsewhere([&] {
                session.value().CanClose();
                answeredWithoutFaulting = true;
            });
            elsewhere.join();
            Check(answeredWithoutFaulting, L"CanClose did not answer another thread");

            Check(CloseWithRetries(session.value()).has_value(), L"Close failed");
        });
    }

    // --- Moving -------------------------------------------------------------

    TEST_METHOD(Test_MovedFromSession_IsAClosedSession)
    {
        RunOnSta([] {
            auto created = Api::Session::Create(Api::SessionOptions{});
            Check(created.has_value(), L"Create failed");

            Api::Session moved = std::move(created.value());

            // The source owns nothing now: closing it succeeds without
            // touching the clipboard, and destroying it later abandons
            // nothing.
            Check(created.value().Close().has_value(), L"closing a moved-from session failed");
            Check(created.value().CanClose(), L"a moved-from session is not a closed one");

            Check(CloseWithRetries(moved).has_value(), L"closing the move destination failed");
        });
    }

    TEST_METHOD(Test_MovingOntoAClosedSessionIsOrdinary)
    {
        RunOnSta([] {
            auto created = Api::Session::Create(Api::SessionOptions{});
            Check(created.has_value(), L"Create failed");

            Api::Session destination = std::move(created.value());
            Check(CloseWithRetries(destination).has_value(), L"Close failed");

            Api::Session other = std::move(created.value());
            destination = std::move(other);
            Check(destination.Close().has_value(), L"closing the assigned session failed");
        });
    }

    // --- Abandonment --------------------------------------------------------

    TEST_METHOD(Test_DestroyingAnUnclosedSession_AbandonsTheProcess)
    {
        // C-8. Nothing is released, and no later session can be had. The last
        // part is the point: the alternative would be handing someone a
        // session on top of a window and listeners that are still registered.
        RunOnSta([] {
            {
                auto session = Api::Session::Create(Api::SessionOptions{});
                Check(session.has_value(), L"Create failed");

                // Abandonment asserts in a debug build, which is the behaviour
                // under test; turn the report off so the test can see what
                // happens next.
                const int previous = _CrtSetReportMode(_CRT_ASSERT, 0);
                { Api::Session doomed = std::move(session.value()); }
                _CrtSetReportMode(_CRT_ASSERT, previous);
            }

            Check(Api::Detail::ClipboardTestAccess::IsAbandoned(), L"the process was not marked abandoned");

            const auto again = Api::Session::Create(Api::SessionOptions{});
            Check(!again.has_value(), L"a session was handed out over an abandoned one");
            Check(ErrorCode::NotSupported == again.error().code, L"not NotSupported");

            // Abandonment is meant to be final, so there is no API that undoes
            // it. A test suite has to carry on, so it reaches under the API and
            // closes the manager directly - from the owning thread, which is
            // this one.
            DWORD error = CLIPBOARD_ERROR_NONE;
            Check(ClipboardManager::GetInstance().Uninit(&error) != FALSE,
                  L"the abandoned manager could not be closed from underneath");
        });
    }

    TEST_METHOD(Test_AbandonmentKeepsRefusingFromAnotherThread)
    {
        RunOnSta([] {
            {
                auto session = Api::Session::Create(Api::SessionOptions{});
                Check(session.has_value(), L"Create failed");
                const int previous = _CrtSetReportMode(_CRT_ASSERT, 0);
                { Api::Session doomed = std::move(session.value()); }
                _CrtSetReportMode(_CRT_ASSERT, previous);
            }

            const std::wstring inner = RunOnStaCollecting([] {
                const auto again = Api::Session::Create(Api::SessionOptions{});
                Check(!again.has_value(), L"a session was handed out over an abandoned one");
                Check(ErrorCode::WrongThread == again.error().code, L"not WrongThread");
            });
            Check(inner.empty(), inner.empty() ? L"" : inner.c_str());

            DWORD error = CLIPBOARD_ERROR_NONE;
            ClipboardManager::GetInstance().Uninit(&error);
        });
    }

    // --- History handlers ---------------------------------------------------

    TEST_METHOD(Test_SetHistoryHandlers_OnAClosedSession_ReportsNotInitialized)
    {
        RunOnSta([] {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed");
            Check(CloseWithRetries(session.value()).has_value(), L"Close failed");

            const auto result = session.value().SetHistoryHandlers(Api::HistoryHandlers{});

            Check(!result.has_value(), L"a closed session accepted handlers");
            Check(ErrorCode::NotInitialized == result.error().code, L"not NotInitialized");
        });
    }

    TEST_METHOD(Test_SetHistoryHandlers_AcceptsHandlersAndTheirRemoval)
    {
        ClipboardManager::GetInstance().SetHistoryBackendFactoryForTest(&MakeNeverCompletingBackend);

        RunOnSta([] {
            auto session = Api::Session::Create(Api::SessionOptions{});
            Check(session.has_value(), L"Create failed");

            Api::HistoryHandlers handlers;
            handlers.onHistoryChanged = [] {};
            handlers.onHistoryEnabledChanged = [](bool) {};
            handlers.onRoamingEnabledChanged = [](bool) {};
            Check(session.value().SetHistoryHandlers(std::move(handlers)).has_value(),
                  L"the handlers were refused");

            // A default-constructed value is how they are taken away again.
            Check(session.value().SetHistoryHandlers(Api::HistoryHandlers{}).has_value(),
                  L"removing the handlers was refused");

            Check(CloseWithRetries(session.value()).has_value(), L"Close failed");
        });
    }

private:

    /// Runs the body on an STA thread and fails this test with whatever it
    /// reported.
    static void RunOnSta(const std::function<void()>& body)
    {
        const std::wstring failure = RunOnStaCollecting(body);
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }

    static void IgnoreRequest(uint32_t, DWORD, const wchar_t*) {}
};

}  // namespace WindowsClipboardApiTest
