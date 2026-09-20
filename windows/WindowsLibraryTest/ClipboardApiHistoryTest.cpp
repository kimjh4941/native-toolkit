#include "pch.h"
#include "ClipboardSessionForTest.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"

#include <functional>
#include <stdexcept>
#include <string>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// C-1..C-4 of the stage 3 design, for the clipboard history (OP-42..OP-47).
//
// These five operations ask and come back; the answer arrives later, through a
// handler. Four promises make that usable, and all four are about counting:
//
//  C-1  a request that was accepted is answered exactly once;
//  C-2  a request that was not accepted is never answered at all;
//  C-3  the answer never arrives inside the call that asked for it;
//  C-4  cancelling stops the request, not its answer - the handler is still
//       called once, with Canceled, and never a second time.
//
// The backend is scripted so the test decides when a request finishes, and the
// message pump is run by hand so "later" has a definite moment.
// ============================================================================

namespace WindowsClipboardApiHistoryTest
{

namespace Api = NativeToolkit::Clipboard;
using Api::ErrorCode;
using ClipboardSessionForTest::Check;
using ClipboardSessionForTest::PumpMessages;

namespace
{
    /// A history the test writes the answers for.
    class ScriptedBackend final : public IClipboardHistoryBackend
    {
    public:
        std::vector<ClipboardHistoryEntry> items;
        ClipboardHistoryAvailability       availability{true, false};

        /// Whether a request finishes as soon as it starts, or waits to be told.
        bool finishOnStart = true;
        DWORD nextError = CLIPBOARD_ERROR_NONE;

        HistoryItemsCallback        heldItems;
        HistoryAvailabilityCallback heldAvailability;
        HistoryStatusCallback       heldStatus;

        void GetItemsAsync(HistoryItemsCallback done) override
        {
            if (finishOnStart) done(nextError, items);
            else               heldItems = std::move(done);
        }
        void GetAvailabilityAsync(HistoryAvailabilityCallback done) override
        {
            if (finishOnStart) done(nextError, availability);
            else               heldAvailability = std::move(done);
        }
        void SetItemAsContentAsync(const std::wstring&, HistoryStatusCallback done) override { Status(std::move(done)); }
        void DeleteItemAsync(const std::wstring&, HistoryStatusCallback done) override       { Status(std::move(done)); }
        void ClearUnpinnedAsync(HistoryStatusCallback done) override                         { Status(std::move(done)); }

        DWORD QueryHistoryEnabled(bool& enabled) override { enabled = availability.historyEnabled; return CLIPBOARD_ERROR_NONE; }
        DWORD QueryRoamingEnabled(bool& enabled) override { enabled = availability.roamingEnabled; return CLIPBOARD_ERROR_NONE; }

        DWORD StartWatch(std::shared_ptr<const ClipboardHistoryEvents>) override { return CLIPBOARD_ERROR_NONE; }
        void  ReplaceEvents(std::shared_ptr<const ClipboardHistoryEvents>) override {}
        bool  StopWatch() override { return true; }
        bool  CanDestroy() const override { return true; }

        /// Finishes whatever is waiting.
        void FinishNow()
        {
            if (heldItems)        { auto done = std::move(heldItems);        heldItems = nullptr;        done(nextError, items); }
            if (heldAvailability) { auto done = std::move(heldAvailability); heldAvailability = nullptr; done(nextError, availability); }
            if (heldStatus)       { auto done = std::move(heldStatus);       heldStatus = nullptr;       done(nextError); }
        }

    private:
        void Status(HistoryStatusCallback done)
        {
            if (finishOnStart) done(nextError);
            else               heldStatus = std::move(done);
        }
    };

    ScriptedBackend* g_backend = nullptr;

    std::unique_ptr<IClipboardHistoryBackend> MakeScriptedBackend()
    {
        auto backend = std::make_unique<ScriptedBackend>();
        g_backend = backend.get();
        return backend;
    }

    ClipboardHistoryEntry MakeEntry(std::wstring id, std::optional<std::wstring> text, int64_t ticks)
    {
        ClipboardHistoryEntry entry;
        entry.id = std::move(id);
        entry.text = std::move(text);
        entry.contentTypes = {L"Text", L"Html"};
        entry.timestampUtc = ticks;
        return entry;
    }
}

TEST_CLASS(ClipboardApiHistoryTest)
{
public:

    TEST_METHOD_CLEANUP(ReleaseTheProcess)
    {
        Api::Detail::ClipboardTestAccess::ResetProcessState();
        g_backend = nullptr;
    }

    // --- What comes back ----------------------------------------------------

    TEST_METHOD(Test_GetHistory_HandsBackTheItemsAsValues)
    {
        Run([](Api::Session& session) {
            g_backend->items = {
                MakeEntry(L"one", L"first", 133000000000000000LL),
                MakeEntry(L"two", std::nullopt, 7),
            };

            std::vector<Api::HistoryItem> received;
            bool called = false;
            const auto accepted = session.GetHistory(
                [&](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>> result) {
                    called = true;
                    if (result.has_value()) received = std::move(result).value();
                });
            Check(accepted.has_value(), L"the request was not accepted");

            PumpMessages();

            Check(called, L"the handler was never called");
            Check(received.size() == 2, L"the wrong number of items came back");
            Check(received[0].id == L"one", L"the first id came back wrong");
            Check(received[0].text.has_value() && *received[0].text == L"first",
                  L"the first text came back wrong");
            Check(received[0].contentTypes.size() == 2, L"the content types were lost");

            // An item that carries no text is not an item whose text is empty
            // (CLP-118).
            Check(!received[1].text.has_value(), L"an absent text came back as a present one");

            // A tick count past what a JSON number can hold must survive
            // unrounded.
            Check(received[0].timestampTicks == 133000000000000000LL,
                  L"the timestamp lost precision");
        }, &MakeScriptedBackend);
    }

    TEST_METHOD(Test_GetHistoryAvailability_HandsBackBothFlags)
    {
        Run([](Api::Session& session) {
            g_backend->availability = {true, true};

            Api::HistoryAvailability received;
            bool called = false;
            const auto accepted = session.GetHistoryAvailability(
                [&](Api::RequestId, Api::Result<Api::HistoryAvailability> result) {
                    called = true;
                    if (result.has_value()) received = result.value();
                });
            Check(accepted.has_value(), L"the request was not accepted");

            PumpMessages();

            Check(called, L"the handler was never called");
            Check(received.historyEnabled, L"historyEnabled came back wrong");
            Check(received.roamingEnabled, L"roamingEnabled came back wrong");
        }, &MakeScriptedBackend);
    }

    TEST_METHOD(Test_TheRequestsWithNoPayload_JustSayWhetherTheyWorked)
    {
        Run([](Api::Session& session) {
            int calls = 0;
            bool allSucceeded = true;
            const auto record = [&](Api::RequestId, Api::Result<void> result) {
                ++calls;
                if (!result.has_value()) allSucceeded = false;
            };

            Check(session.RestoreHistoryItem(L"one", record).has_value(), L"restore was not accepted");
            Check(session.DeleteHistoryItem(L"one", record).has_value(), L"delete was not accepted");
            Check(session.ClearUnpinnedHistory(record).has_value(), L"clear was not accepted");

            PumpMessages();

            Check(calls == 3, L"the three handlers were not all called once");
            Check(allSucceeded, L"one of them reported a failure");
        }, &MakeScriptedBackend);
    }

    TEST_METHOD(Test_AFailureReachesTheHandlerAsOne)
    {
        Run([](Api::Session& session) {
            g_backend->nextError = CLIPBOARD_ERROR_HISTORY_DISABLED;

            ErrorCode seen = ErrorCode::None;
            const auto accepted = session.GetHistory(
                [&](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>> result) {
                    if (!result.has_value()) seen = result.error().code;
                });
            Check(accepted.has_value(), L"the request was not accepted");

            PumpMessages();

            Check(ErrorCode::HistoryDisabled == seen, L"the failure did not reach the handler");
        }, &MakeScriptedBackend);
    }

    TEST_METHOD(Test_TheIdTheHandlerIsGiven_IsTheIdTheRequestReturned)
    {
        Run([](Api::Session& session) {
            Api::RequestId reported{0};
            const auto accepted = session.GetHistory(
                [&](Api::RequestId id, Api::Result<std::vector<Api::HistoryItem>>) { reported = id; });
            Check(accepted.has_value(), L"the request was not accepted");

            PumpMessages();

            Check(reported == accepted.value(), L"the handler was told a different id");
        }, &MakeScriptedBackend);
    }

    // --- Exactly once (C-1) -------------------------------------------------

    TEST_METHOD(Test_AnAcceptedRequest_IsAnsweredExactlyOnce)
    {
        Run([](Api::Session& session) {
            int calls = 0;
            const auto accepted = session.GetHistory(
                [&](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>>) { ++calls; });
            Check(accepted.has_value(), L"the request was not accepted");

            PumpMessages();
            Check(calls == 1, L"the handler was not called once");

            // Nothing later brings a second one.
            PumpMessages();
            PumpMessages();
            Check(calls == 1, L"the handler was called again");
        }, &MakeScriptedBackend);
    }

    // --- Never, when it was not accepted (C-2) ------------------------------

    TEST_METHOD(Test_ARequestThatIsRefused_IsNeverAnswered)
    {
        // The id is refused before anything is registered, so there is nothing
        // to answer into.
        Run([](Api::Session& session) {
            const std::wstring backing(L"bad\0id", 6);
            const std::wstring_view badId(backing.data(), backing.size());

            int calls = 0;
            const auto refused = session.RestoreHistoryItem(badId,
                [&](Api::RequestId, Api::Result<void>) { ++calls; });

            Check(!refused.has_value(), L"an item id with an embedded NUL was accepted");
            Check(ErrorCode::InvalidParameter == refused.error().code, L"not InvalidParameter");

            PumpMessages();
            PumpMessages();
            Check(calls == 0, L"a refused request answered anyway");
        }, &MakeScriptedBackend);
    }

    TEST_METHOD(Test_ARequestOnAClosedSession_IsNeverAnswered)
    {
        Run([](Api::Session& session) {
            Check(session.Close().has_value(), L"Close failed");

            int calls = 0;
            const auto refused = session.GetHistory(
                [&](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>>) { ++calls; });

            Check(!refused.has_value(), L"a closed session accepted a request");
            Check(ErrorCode::NotInitialized == refused.error().code, L"not NotInitialized");

            PumpMessages();
            Check(calls == 0, L"a refused request answered anyway");
        }, &MakeScriptedBackend);
    }

    // --- Not inside the call (C-3) ------------------------------------------

    TEST_METHOD(Test_TheHandlerIsNotCalledInsideTheCallThatAsked)
    {
        // Even when the backend finishes the moment it is started, the answer
        // has to come back through the message queue, so a caller can rely on
        // its own state still being its own until it returns.
        Run([](Api::Session& session) {
            bool calledDuringTheRequest = false;
            bool insideTheRequest = true;

            const auto accepted = session.GetHistory(
                [&](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>>) {
                    if (insideTheRequest) calledDuringTheRequest = true;
                });
            insideTheRequest = false;

            Check(accepted.has_value(), L"the request was not accepted");
            Check(!calledDuringTheRequest, L"the handler ran inside the call that asked");

            PumpMessages();
        }, &MakeScriptedBackend);
    }

    // --- Cancelling (C-4) ---------------------------------------------------

    TEST_METHOD(Test_ACancelledRequest_IsAnsweredOnceWithCanceled)
    {
        Run([](Api::Session& session) {
            g_backend->finishOnStart = false;

            int calls = 0;
            ErrorCode seen = ErrorCode::None;
            const auto accepted = session.GetHistory(
                [&](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>> result) {
                    ++calls;
                    if (!result.has_value()) seen = result.error().code;
                });
            Check(accepted.has_value(), L"the request was not accepted");

            Check(session.CancelRequest(accepted.value()).has_value(), L"the cancellation was refused");
            PumpMessages();

            Check(calls == 1, L"the cancelled request was not answered once");
            Check(ErrorCode::Canceled == seen, L"it was not answered with Canceled");

            // The backend finishing afterwards must not bring a second answer.
            g_backend->FinishNow();
            PumpMessages();
            Check(calls == 1, L"the late completion brought a second answer");
        }, &MakeScriptedBackend);
    }

    TEST_METHOD(Test_CancellingSomethingThatIsNotThere_IsRefused)
    {
        Run([](Api::Session& session) {
            const auto result = session.CancelRequest(Api::RequestId{9999});

            Check(!result.has_value(), L"an unknown id was cancelled");
            Check(ErrorCode::InvalidParameter == result.error().code, L"not InvalidParameter");
        }, &MakeScriptedBackend);
    }

    TEST_METHOD(Test_CancellingAFinishedRequest_IsRefused)
    {
        Run([](Api::Session& session) {
            const auto accepted = session.GetHistory(
                [](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>>) {});
            Check(accepted.has_value(), L"the request was not accepted");

            PumpMessages();

            const auto result = session.CancelRequest(accepted.value());
            Check(!result.has_value(), L"a finished request was cancelled");
            Check(ErrorCode::InvalidParameter == result.error().code, L"not InvalidParameter");
        }, &MakeScriptedBackend);
    }

    TEST_METHOD(Test_AHandlerThatThrows_DoesNotStopTheNextOne)
    {
        // A handler is the caller's code running on the thread that delivers
        // every other completion. If it could throw from there, one careless
        // handler would leave every later request unanswered.
        Run([](Api::Session& session) {
            const auto first = session.GetHistory(
                [](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>>) {
                    throw std::runtime_error("the handler gave up");
                });
            Check(first.has_value(), L"the first request was not accepted");

            PumpMessages();

            bool secondAnswered = false;
            const auto second = session.GetHistory(
                [&](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>>) { secondAnswered = true; });
            Check(second.has_value(), L"the second request was not accepted");

            PumpMessages();
            Check(secondAnswered, L"a throwing handler stopped the next one");
        }, &MakeScriptedBackend);
    }

    TEST_METHOD(Test_RequestsCanBeMadeFromAnyThread)
    {
        Run([](Api::Session& session) {
            bool accepted = false;
            std::thread elsewhere([&] {
                accepted = session.GetHistory(
                    [](Api::RequestId, Api::Result<std::vector<Api::HistoryItem>>) {}).has_value();
            });
            elsewhere.join();

            Check(accepted, L"a request from another thread was refused");
            PumpMessages();
        }, &MakeScriptedBackend);
    }

    // --- A session that is not open -----------------------------------------

    TEST_METHOD(Test_EveryHistoryOperationOnAClosedSession_ReportsNotInitialized)
    {
        Run([](Api::Session& session) {
            Check(session.Close().has_value(), L"Close failed");

            Check(Refused(session.GetHistory(nullptr)), L"GetHistory");
            Check(Refused(session.RestoreHistoryItem(L"one", nullptr)), L"RestoreHistoryItem");
            Check(Refused(session.DeleteHistoryItem(L"one", nullptr)), L"DeleteHistoryItem");
            Check(Refused(session.ClearUnpinnedHistory(nullptr)), L"ClearUnpinnedHistory");
            Check(Refused(session.GetHistoryAvailability(nullptr)), L"GetHistoryAvailability");
            Check(Refused(session.CancelRequest(Api::RequestId{1})), L"CancelRequest");
        }, &MakeScriptedBackend);
    }

private:

    template <class T>
    static bool Refused(const Api::Result<T>& result)
    {
        return !result.has_value() && ErrorCode::NotInitialized == result.error().code;
    }

    static void Run(const std::function<void(Api::Session&)>& body,
                    std::unique_ptr<IClipboardHistoryBackend> (*factory)())
    {
        const std::wstring failure = ClipboardSessionForTest::Run(body, factory);
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }
};

}  // namespace WindowsClipboardApiHistoryTest
