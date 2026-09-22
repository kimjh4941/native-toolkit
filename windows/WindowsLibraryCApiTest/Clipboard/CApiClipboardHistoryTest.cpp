#include "pch.h"

#include "NativeToolkitC/Clipboard.h"

#include "Clipboard/CApiClipboardHarness.h"
#include "Clipboard/ClipboardConvert.h"

#include <string>
#include <thread>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace CApiClipboardHarness;

// ============================================================================
// The clipboard history through the C ABI (stage 5 design, T-09):
//
//  CT-12  a request's completion: the user_data arrives, exactly once after
//         acceptance and never for a refused request, on the owner thread,
//         with the system code as an argument; availability's flags are 0 on
//         failure. All five requests, and cancelling.
//  CT-17  after _free no callback of the session runs, and callbacks that nest
//         on one thread do not block each other.
//  CT-20  a WinRT timestamp read as Unix milliseconds.
//
// The history backend is scripted (CApiClipboardHarness.h): it answers a
// request when it starts, or holds it for the test to finish. The message
// pump is run by hand, so "later" has a definite moment.
// ============================================================================

namespace CApiClipboardHistoryTest
{

namespace
{
    using NativeToolkitC::Detail::Clipboard::TicksToUnixMs;

    constexpr int64_t kEpochTicks = 116444736000000000LL;   // 1970-01-01 as WinRT ticks

    // -- What the completions saw --------------------------------------------

    struct Completion {
        int         calls = 0;
        uint32_t    requestId = 0;
        int32_t     error = -1;
        uint32_t    systemCode = 0xFFFFFFFFu;
        DWORD       thread = 0;
        bool        hadHistory = false;
        int32_t     historyEnabled = -1;
        int32_t     roamingEnabled = -1;

        // What the history handle read as, during the call.
        size_t                    count = 0;
        std::vector<std::string>  ids;
        std::vector<bool>         hasText;
        std::vector<std::string>  texts;
        std::vector<size_t>       typeCounts;
        std::string               firstType;
        std::vector<int64_t>      unixMs;

        std::function<void()> inside;   ///< Run inside the completion, for nesting.
    };

    void Record(Completion& c, uint32_t id, ntk_clipboard_error error, uint32_t systemCode)
    {
        ++c.calls;
        c.requestId = id;
        c.error = error;
        c.systemCode = systemCode;
        c.thread = ::GetCurrentThreadId();
    }

    void NTK_CALL OnHistory(void* userData, uint32_t id, ntk_clipboard_error error, uint32_t systemCode,
                            const ntk_clipboard_history* history)
    {
        auto& c = *static_cast<Completion*>(userData);
        Record(c, id, error, systemCode);
        c.hadHistory = history != nullptr;
        c.count = ntk_clipboard_history_count(history);
        for (size_t i = 0; i < c.count; ++i) {
            c.ids.emplace_back(ntk_clipboard_history_item_id(history, i, nullptr));
            const char* text = ntk_clipboard_history_item_text(history, i, nullptr);
            c.hasText.push_back(text != nullptr);
            c.texts.emplace_back(text ? text : "");
            c.typeCounts.push_back(ntk_clipboard_history_item_content_type_count(history, i));
            c.unixMs.push_back(ntk_clipboard_history_item_timestamp_unix_ms(history, i));
        }
        if (c.count > 0) c.firstType = ntk_clipboard_history_item_content_type_at(history, 0, 0, nullptr);
        if (c.inside) c.inside();
    }

    void NTK_CALL OnStatus(void* userData, uint32_t id, ntk_clipboard_error error, uint32_t systemCode)
    {
        Record(*static_cast<Completion*>(userData), id, error, systemCode);
    }

    void NTK_CALL OnAvailability(void* userData, uint32_t id, ntk_clipboard_error error, uint32_t systemCode,
                                 int32_t history, int32_t roaming)
    {
        auto& c = *static_cast<Completion*>(userData);
        Record(c, id, error, systemCode);
        c.historyEnabled = history;
        c.roamingEnabled = roaming;
    }

    void Ok(ntk_clipboard_error result, const wchar_t* what)
    {
        if (result != NTK_CLIPBOARD_ERROR_NONE) {
            throw Failure{std::wstring(what) + L" failed with " + std::to_wstring(result)};
        }
    }

    void Is(int64_t expected, int64_t actual, const wchar_t* what)
    {
        if (expected != actual) {
            throw Failure{std::wstring(what) + L": expected " + std::to_wstring(expected) + L", got " +
                          std::to_wstring(actual)};
        }
    }

    void AssertPassed(const std::wstring& failure)
    {
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }

    ntk_clipboard_session* Open()
    {
        ntk_clipboard_session* session = nullptr;
        Ok(ntk_clipboard_session_create(nullptr, &session), L"create");
        return session;
    }

    void CloseAndFree(ntk_clipboard_session* session)
    {
        Ok(ntk_clipboard_session_close(session), L"close");
        ntk_clipboard_session_free(session);
    }

    ClipboardHistoryEntry Entry(std::wstring id, std::optional<std::wstring> text, int64_t ticks)
    {
        ClipboardHistoryEntry entry;
        entry.id = std::move(id);
        entry.text = std::move(text);
        entry.contentTypes = {L"Text", L"Html"};
        entry.timestampUtc = ticks;
        return entry;
    }
}

TEST_CLASS(CApiClipboardHistoryTest)
{
public:
    // ------------------------------------------------------------------------
    // CT-12: the five requests
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_GetHistory_HandsTheItemsOverInUtf8OnTheOwnerThread)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Script().items = {
                Entry(L"one", std::wstring(L"caf") + wchar_t(0x00E9), kEpochTicks + 1767225600000LL * 10000),
                Entry(L"two", std::nullopt, 0),
            };
            Completion c;
            uint32_t id = 0;
            Ok(ntk_clipboard_get_history(session, &OnHistory, &c, &id), L"get_history");
            Is(0, c.calls, L"completed inside the call that asked");

            PumpMessages();
            Is(1, c.calls, L"completions");
            Is(id, c.requestId, L"request id");
            Is(NTK_CLIPBOARD_ERROR_NONE, c.error, L"error");
            Is(0, c.systemCode, L"system code");
            Check(c.thread == ::GetCurrentThreadId(), L"completed off the owner thread");
            Check(c.hadHistory && c.count == 2, L"two items");
            Check(c.ids[0] == "one" && c.ids[1] == "two", L"ids");
            Check(c.hasText[0] && c.texts[0] == "caf\xC3\xA9", L"the first item's text");
            Check(!c.hasText[1], L"an item without text read as having some");
            Check(c.typeCounts[0] == 2 && c.firstType == "Text", L"content types");
            Is(1767225600000LL, c.unixMs[0], L"2026-01-01 in Unix ms");
            Is(0, c.unixMs[1], L"an unread time");

            PumpMessages();
            Is(1, c.calls, L"completed a second time");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_GetHistory_AFailureComesWithItsSystemCodeAndNoHistory)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Script().nextError = CLIPBOARD_ERROR_HISTORY_DISABLED;
            Completion c;
            Ok(ntk_clipboard_get_history(session, &OnHistory, &c, nullptr), L"get_history");
            PumpMessages();
            Is(1, c.calls, L"completions");
            Is(NTK_CLIPBOARD_ERROR_HISTORY_DISABLED, c.error, L"error");
            Is(CLIPBOARD_ERROR_HISTORY_DISABLED, c.systemCode, L"system code");
            Check(!c.hadHistory, L"a failure came with a history");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Availability_FlagsAndTheirZerosOnFailure)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Script().availability = {true, false};
            Completion ok;
            Ok(ntk_clipboard_get_history_availability(session, &OnAvailability, &ok, nullptr), L"availability");
            PumpMessages();
            Is(1, ok.calls, L"completions");
            Check(ok.historyEnabled == 1 && ok.roamingEnabled == 0, L"the flags");

            Script().availability = {true, true};
            Script().nextError = CLIPBOARD_ERROR_ACCESS_DENIED;
            Completion failed;
            Ok(ntk_clipboard_get_history_availability(session, &OnAvailability, &failed, nullptr), L"availability");
            PumpMessages();
            Is(NTK_CLIPBOARD_ERROR_ACCESS_DENIED, failed.error, L"error");
            Check(failed.historyEnabled == 0 && failed.roamingEnabled == 0, L"the flags are 0 on failure");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_StatusRequests_EachCompletesOnceWithItsUserData)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Completion restore, remove, clear;
            Ok(ntk_clipboard_restore_history_item(session, "item-\xC3\xA9", &OnStatus, &restore, nullptr), L"restore");
            PumpMessages();
            Check(Script().lastItemId == std::wstring(L"item-") + wchar_t(0x00E9), L"the id reached the backend");
            Ok(ntk_clipboard_delete_history_item(session, "gone", &OnStatus, &remove, nullptr), L"delete");
            PumpMessages();
            Check(Script().lastItemId == L"gone", L"the id reached the backend");
            Ok(ntk_clipboard_clear_unpinned_history(session, &OnStatus, &clear, nullptr), L"clear unpinned");
            PumpMessages();

            for (const Completion* c : {&restore, &remove, &clear}) {
                Is(1, c->calls, L"completions");
                Is(NTK_CLIPBOARD_ERROR_NONE, c->error, L"error");
            }
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_RefusedRequests_NeverComplete)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Completion c;
            uint32_t id = 12345;
            const auto invalid = NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
            Is(invalid, ntk_clipboard_get_history(session, nullptr, &c, &id), L"NULL callback");
            Is(invalid, ntk_clipboard_restore_history_item(session, nullptr, &OnStatus, &c, &id), L"NULL item id");
            Is(invalid, ntk_clipboard_delete_history_item(session, "\xFF", &OnStatus, &c, &id), L"bad item id");
            Is(invalid, ntk_clipboard_delete_history_item(session, "x", nullptr, &c, &id), L"NULL callback");
            Is(invalid, ntk_clipboard_clear_unpinned_history(session, nullptr, &c, &id), L"NULL callback");
            Is(invalid, ntk_clipboard_get_history_availability(session, nullptr, &c, &id), L"NULL callback");
            Is(invalid, ntk_clipboard_get_history(nullptr, &OnHistory, &c, &id), L"NULL session");

            Ok(ntk_clipboard_session_close(session), L"close");
            Is(NTK_CLIPBOARD_ERROR_NOT_INITIALIZED, ntk_clipboard_get_history(session, &OnHistory, &c, &id), L"closed");
            PumpMessages();
            Is(0, c.calls, L"a refused request completed");
            Is(12345, id, L"the id of a refused request was written");
            ntk_clipboard_session_free(session);
        }));
    }

    TEST_METHOD(Test_Cancel_CompletesOnceWithCanceled)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Script().finishOnStart = false;
            Completion c;
            uint32_t id = 0;
            Ok(ntk_clipboard_get_history(session, &OnHistory, &c, &id), L"get_history");
            PumpMessages();   // starts it; the backend holds it
            Ok(ntk_clipboard_cancel_request(session, id), L"cancel");
            PumpMessages();
            Is(1, c.calls, L"completions after cancel");
            Is(NTK_CLIPBOARD_ERROR_CANCELED, c.error, L"error");

            FinishHeld();   // the OS answers after all
            PumpMessages();
            Is(1, c.calls, L"completed again after the late answer");
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_cancel_request(session, id), L"cancel a finished request");
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_cancel_request(session, 987654), L"cancel an unknown request");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_RequestFromAnotherThread_CompletesOnTheOwner)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Completion c;
            ntk_clipboard_error accepted = NTK_CLIPBOARD_ERROR_UNKNOWN;
            RunElsewhereWhilePumping([&] { accepted = ntk_clipboard_get_history_availability(session, &OnAvailability, &c, nullptr); });
            Ok(accepted, L"accepted elsewhere");
            PumpMessages();
            Is(1, c.calls, L"completions");
            Check(c.thread == ::GetCurrentThreadId(), L"completed off the owner thread");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Close_DeliversTheCancellationItself)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Script().finishOnStart = false;
            Completion c;
            Ok(ntk_clipboard_get_history(session, &OnHistory, &c, nullptr), L"get_history");
            // Not started: the request is still queued when close comes.
            Ok(ntk_clipboard_session_close(session), L"close");
            Is(1, c.calls, L"completions by the time close returned");
            Is(NTK_CLIPBOARD_ERROR_CANCELED, c.error, L"error");
            ntk_clipboard_session_free(session);
        }));
    }

    // ------------------------------------------------------------------------
    // CT-17: after free, and nesting
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Free_NoCallbackRunsAfterIt)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Completion history;
            int changed = 0;
            ntk_clipboard_history_handlers handlers{};
            handlers.struct_size = static_cast<uint32_t>(sizeof(handlers));
            handlers.on_history_changed = [](void* userData) { ++*static_cast<int*>(userData); };
            handlers.user_data = &changed;
            Ok(ntk_clipboard_set_history_handlers(session, &handlers), L"handlers");

            Script().finishOnStart = false;
            Ok(ntk_clipboard_get_history(session, &OnHistory, &history, nullptr), L"get_history");
            PumpMessages();   // started and held

            ntk_clipboard_session_free(session);   // abandoned with a request in flight
            FinishHeld();
            PumpMessages();
            Raise(&ClipboardHistoryEvents::onHistoryChanged);
            Is(0, history.calls, L"a completion ran after free");
            Is(0, changed, L"a history handler ran after free");
        }));
    }

    TEST_METHOD(Test_NestedCallbacksOnOneThread_DoNotBlock)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            // A deferred format read inside a completion calls the provider
            // inside the completion: two callbacks of the session, nested.
            struct Nest { int renders = 0; } nest;
            const char* formats[] = {"NativeToolkit.CApiNested"};
            Ok(ntk_clipboard_reserve_deferred(session, formats, 1,
                   [](void* userData, const char*, ntk_clipboard_render_target* target) -> ntk_clipboard_error {
                       ++static_cast<Nest*>(userData)->renders;
                       const uint8_t byte = 42;
                       return ntk_clipboard_render_target_set(target, &byte, 1);
                   },
                   &nest, nullptr),
               L"reserve");

            Completion c;
            ntk_clipboard_error readInside = NTK_CLIPBOARD_ERROR_UNKNOWN;
            c.inside = [&] {
                ntk_bytes* data = nullptr;
                readInside = ntk_clipboard_paste_custom(session, "NativeToolkit.CApiNested", &data);
                ntk_bytes_free(data);
            };
            Ok(ntk_clipboard_get_history(session, &OnHistory, &c, nullptr), L"get_history");
            PumpMessages();
            Is(1, c.calls, L"completions");
            Ok(readInside, L"the read inside the completion");
            Is(1, nest.renders, L"the nested provider ran");
            CloseAndFree(session);
        }));
    }

    // ------------------------------------------------------------------------
    // CT-20: the timestamp
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Ticks_AsUnixMilliseconds)
    {
        Assert::AreEqual(0LL, static_cast<long long>(TicksToUnixMs(kEpochTicks)));
        Assert::AreEqual(1767225600000LL, static_cast<long long>(TicksToUnixMs(kEpochTicks + 1767225600000LL * 10000)));
        Assert::AreEqual(1767225600000LL, static_cast<long long>(TicksToUnixMs(kEpochTicks + 1767225600000LL * 10000 + 9999)));
        Assert::AreEqual(0LL, static_cast<long long>(TicksToUnixMs(0)));
        Assert::AreEqual(-1LL, static_cast<long long>(TicksToUnixMs(kEpochTicks - 1)));
        Assert::AreEqual(-11644473600000LL, static_cast<long long>(TicksToUnixMs(1)));
    }

    TEST_METHOD(Test_HistoryHandle_OutOfRangeAndNull)
    {
        ntk_clipboard_history history;
        ntk_clipboard_history::Item item;
        item.id = "one";
        item.contentTypes = {"Text"};
        history.items.push_back(item);
        size_t size = 99;

        Assert::IsNull(ntk_clipboard_history_item_text(&history, 0, &size));   // no text
        Assert::AreEqual(size_t{0}, size);
        Assert::IsNull(ntk_clipboard_history_item_id(&history, 1, nullptr));
        Assert::IsNull(ntk_clipboard_history_item_content_type_at(&history, 0, 1, nullptr));
        Assert::AreEqual(size_t{0}, ntk_clipboard_history_item_content_type_count(&history, 1));
        Assert::AreEqual(0LL, static_cast<long long>(ntk_clipboard_history_item_timestamp_unix_ms(&history, 1)));
        Assert::AreEqual(size_t{0}, ntk_clipboard_history_count(nullptr));
        Assert::IsNull(ntk_clipboard_history_item_id(nullptr, 0, &size));
        Assert::AreEqual(size_t{0}, size);
    }
};

}  // namespace CApiClipboardHistoryTest
