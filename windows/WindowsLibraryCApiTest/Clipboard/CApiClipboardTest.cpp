#include "pch.h"

#include "NativeToolkitC/Clipboard.h"

#include "Clipboard/CApiClipboardHarness.h"
#include "Clipboard/ClipboardConvert.h"

#include <cstring>
#include <string>
#include <thread>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace CApiClipboardHarness;

// ============================================================================
// The clipboard session and the reads and writes of the C ABI (stage 5 design,
// T-07): CT-16 (the session's life), the clipboard's part of CT-05, CT-06,
// CT-07 and CT-14, and a round trip of every format through the C ABI.
//
// Every body runs on an STA owner thread of its own with the C++ API tests'
// fake clipboard in place (CApiClipboardHarness.h), so nothing here touches
// the real clipboard.
// ============================================================================

namespace CApiClipboardTest
{

namespace
{
    namespace Api = NativeToolkit::Clipboard;

    void Ok(ntk_clipboard_error result, const wchar_t* what)
    {
        Check(result == NTK_CLIPBOARD_ERROR_NONE, what);
    }

    void Is(ntk_clipboard_error expected, ntk_clipboard_error actual, const wchar_t* what)
    {
        if (expected != actual) {
            throw Failure{std::wstring(what) + L": expected " + std::to_wstring(expected) + L", got " +
                          std::to_wstring(actual)};
        }
    }

    ntk_clipboard_session* Open(const ntk_clipboard_session_options* options = nullptr)
    {
        ntk_clipboard_session* session = nullptr;
        Ok(ntk_clipboard_session_create(options, &session), L"create");
        Check(session != nullptr, L"create gave no session");
        return session;
    }

    void CloseAndFree(ntk_clipboard_session* session)
    {
        Ok(ntk_clipboard_session_close(session), L"close");
        ntk_clipboard_session_free(session);
    }

    void AssertPassed(const std::wstring& failure)
    {
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }

    std::string Read(const ntk_string* s)
    {
        return std::string(ntk_string_data(s), ntk_string_size(s));
    }

    // -- A caller's user_data ------------------------------------------------

    struct Counter {
        int calls = 0;
        int lastFlag = -1;
    };

    void NTK_CALL OnChanged(void* userData) { ++static_cast<Counter*>(userData)->calls; }
    void NTK_CALL OnChangedThrows(void* userData) { ++static_cast<Counter*>(userData)->calls; throw 42; }
    void NTK_CALL OnFlag(void* userData, int32_t enabled)
    {
        auto* counter = static_cast<Counter*>(userData);
        ++counter->calls;
        counter->lastFlag = enabled;
    }

    ntk_clipboard_session_options ListeningOptions(Counter& counter, ntk_clipboard_changed_fn fn = &OnChanged)
    {
        ntk_clipboard_session_options options{};
        options.struct_size = static_cast<uint32_t>(sizeof(options));
        options.on_clipboard_changed = fn;
        options.user_data = &counter;
        return options;
    }

    /// Makes the session's window hear that the clipboard changed.
    void TellTheWindowTheClipboardChanged()
    {
        const HWND window = SessionWindow();
        Check(window != nullptr, L"no session window to notify");
        ::SendMessageW(window, WM_CLIPBOARDUPDATE, 0, 0);
    }

    const char* const kBad = "\xFF";   // not UTF-8

    /// A struct twice the size this version knows, the tail set to fill.
    template <class T>
    struct Grown {
        T             known;
        unsigned char tail[sizeof(T)];
    };

    template <class T>
    Grown<T> GrownFrom(const T& known, unsigned char fill)
    {
        Grown<T> grown{};
        grown.known = known;
        grown.known.struct_size = static_cast<uint32_t>(sizeof(grown));
        std::memset(grown.tail, fill, sizeof(grown.tail));
        return grown;
    }
}

TEST_CLASS(CApiClipboardTest)
{
public:
    // ------------------------------------------------------------------------
    // CT-16: the session's life
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Session_OpensAndClosesOnAnSta)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Check(ntk_last_system_code() == 0, L"a success leaves system code 0");
            Check(ntk_clipboard_session_can_close(session) == 0, L"an open session has not started closing");
            Ok(ntk_clipboard_session_close(session), L"close");
            Check(ntk_clipboard_session_can_close(session) != 0, L"a closed session has nothing left to wait for");
            ntk_clipboard_session_free(session);
        }));
    }

    TEST_METHOD(Test_Session_NullOutput_IsInvalid)
    {
        AssertPassed(RunOnOwner([] {
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_session_create(nullptr, nullptr), L"NULL output");
        }));
    }

    TEST_METHOD(Test_Session_OnAnMta_IsWrongApartment)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = reinterpret_cast<ntk_clipboard_session*>(1);
            Is(NTK_CLIPBOARD_ERROR_WRONG_APARTMENT, ntk_clipboard_session_create(nullptr, &session), L"MTA");
            Check(session == nullptr, L"the output is NULL on failure");
        }, COINIT_MULTITHREADED));
    }

    TEST_METHOD(Test_Session_SecondCreate_NotSupportedHereWrongThreadElsewhere)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            ntk_clipboard_session* second = nullptr;
            Is(NTK_CLIPBOARD_ERROR_NOT_SUPPORTED, ntk_clipboard_session_create(nullptr, &second), L"same thread");

            ntk_clipboard_error elsewhere = NTK_CLIPBOARD_ERROR_NONE;
            std::thread other([&] {
                ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
                ntk_clipboard_session* third = nullptr;
                elsewhere = ntk_clipboard_session_create(nullptr, &third);
                ::CoUninitialize();
            });
            other.join();
            Is(NTK_CLIPBOARD_ERROR_WRONG_THREAD, elsewhere, L"another thread");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Session_OptionsVersions)
    {
        AssertPassed(RunOnOwner([] {
            ntk_clipboard_session_options options{};
            options.struct_size = static_cast<uint32_t>(sizeof(options));
            ntk_clipboard_session* session = nullptr;

            auto reserved = options;
            reserved.reserved0 = 1;
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_session_create(&reserved, &session), L"reserved0");
            auto tooSmall = options;
            tooSmall.struct_size = 8;
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_session_create(&tooSmall, &session), L"too small");
            auto tooLarge = options;
            tooLarge.struct_size = 4097;
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_session_create(&tooLarge, &session), L"too large");
            auto newer = GrownFrom(options, 1);
            Is(NTK_CLIPBOARD_ERROR_NOT_SUPPORTED, ntk_clipboard_session_create(&newer.known, &session), L"newer");
            Check(session == nullptr, L"no session from a refused struct");

            auto zeroTail = GrownFrom(options, 0);
            Ok(ntk_clipboard_session_create(&zeroTail.known, &session), L"zero tail");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Session_Closed_EveryOperationIsNotInitialized)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Ok(ntk_clipboard_session_close(session), L"close");
            const auto closed = NTK_CLIPBOARD_ERROR_NOT_INITIALIZED;
            const char* paths[] = {"C:\\a.txt"};
            const uint8_t bytes[] = {1, 2, 3};
            ntk_string* text = nullptr;
            ntk_string_list* list = nullptr;
            ntk_bytes* data = nullptr;
            int32_t present = -1;

            Is(closed, ntk_clipboard_copy_text(session, "x", 0), L"copy_text");
            Is(closed, ntk_clipboard_paste_text(session, &text), L"paste_text");
            Is(closed, ntk_clipboard_copy_html(session, "<b>x</b>", nullptr, 0), L"copy_html");
            Is(closed, ntk_clipboard_paste_html(session, &text), L"paste_html");
            Is(closed, ntk_clipboard_copy_files(session, paths, 1, 0), L"copy_files");
            Is(closed, ntk_clipboard_paste_files(session, &list), L"paste_files");
            Is(closed, ntk_clipboard_copy_dib(session, bytes, sizeof(bytes), 0), L"copy_dib");
            Is(closed, ntk_clipboard_paste_dib(session, &data), L"paste_dib");
            Is(closed, ntk_clipboard_copy_custom(session, "Fmt", bytes, sizeof(bytes), 0), L"copy_custom");
            Is(closed, ntk_clipboard_paste_custom(session, "Fmt", &data), L"paste_custom");
            Is(closed, ntk_clipboard_has_format(session, "Fmt", &present), L"has_format");
            Is(closed, ntk_clipboard_get_formats(session, &list), L"get_formats");
            Is(closed, ntk_clipboard_get_preferred_format(session, &text), L"get_preferred_format");
            Is(closed, ntk_clipboard_clear(session), L"clear");
            Is(closed, ntk_clipboard_set_history_handlers(session, nullptr), L"set_history_handlers");
            Check(text == nullptr && list == nullptr && data == nullptr, L"outputs stay NULL");
            Check(present == -1, L"a value output is written only on success");
            ntk_clipboard_session_free(session);
        }));
    }

    TEST_METHOD(Test_Session_FreeWithoutClose_AbandonsAndStopsCallbacks)
    {
        AssertPassed(RunOnOwner([] {
            Counter counter;
            const auto options = ListeningOptions(counter);
            auto* session = Open(&options);
            Ok(ntk_clipboard_copy_text(session, "x", 0), L"copy");   // opens the fake with the session window
            const HWND window = SessionWindow();

            ntk_clipboard_session_free(session);   // not closed: abandoned
            ::SendMessageW(window, WM_CLIPBOARDUPDATE, 0, 0);
            Check(counter.calls == 0, L"a callback ran after free");

            ntk_clipboard_session* again = nullptr;
            Is(NTK_CLIPBOARD_ERROR_NOT_SUPPORTED, ntk_clipboard_session_create(nullptr, &again),
               L"no new session after abandoning one");
        }));
    }

    TEST_METHOD(Test_Session_NullHandle)
    {
        const auto invalid = NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
        ntk_string* text = reinterpret_cast<ntk_string*>(1);
        ntk_string_list* list = reinterpret_cast<ntk_string_list*>(1);
        ntk_bytes* data = reinterpret_cast<ntk_bytes*>(1);
        int32_t present = -1;
        const char* paths[] = {"C:\\a.txt"};

        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_session_close(nullptr));
        Assert::AreEqual<int32_t>(1, ntk_clipboard_session_can_close(nullptr));
        ntk_clipboard_session_free(nullptr);
        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_set_history_handlers(nullptr, nullptr));
        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_copy_text(nullptr, "x", 0));
        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_paste_text(nullptr, &text));
        Assert::IsNull(text);
        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_copy_html(nullptr, "x", nullptr, 0));
        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_copy_files(nullptr, paths, 1, 0));
        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_paste_files(nullptr, &list));
        Assert::IsNull(list);
        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_paste_dib(nullptr, &data));
        Assert::IsNull(data);
        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_has_format(nullptr, "x", &present));
        Assert::AreEqual<int32_t>(-1, present);
        Assert::AreEqual<int32_t>(invalid, ntk_clipboard_clear(nullptr));
    }

    // ------------------------------------------------------------------------
    // The change listener, and a C++ callback that throws (CT-14)
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_ChangeListener_GetsItsUserData)
    {
        AssertPassed(RunOnOwner([] {
            Counter counter;
            const auto options = ListeningOptions(counter);
            auto* session = Open(&options);
            Ok(ntk_clipboard_copy_text(session, "x", 0), L"copy");

            TellTheWindowTheClipboardChanged();
            Check(counter.calls == 1, L"the listener did not run once");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_ChangeListener_ThatThrows_DoesNotReachTheWindow)
    {
        AssertPassed(RunOnOwner([] {
            Counter counter;
            const auto options = ListeningOptions(counter, &OnChangedThrows);
            auto* session = Open(&options);
            Ok(ntk_clipboard_copy_text(session, "x", 0), L"copy");

            TellTheWindowTheClipboardChanged();
            TellTheWindowTheClipboardChanged();
            Check(counter.calls == 2, L"the listener should run both times");
            CloseAndFree(session);
        }));
    }

    // ------------------------------------------------------------------------
    // History handlers (OP-22)
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_HistoryHandlers_EachGetsItsEventAndTheUserData)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Counter counter;
            ntk_clipboard_history_handlers handlers{};
            handlers.struct_size = static_cast<uint32_t>(sizeof(handlers));
            handlers.on_history_changed = &OnChanged;
            handlers.on_history_enabled_changed = &OnFlag;
            handlers.user_data = &counter;
            Ok(ntk_clipboard_set_history_handlers(session, &handlers), L"set");

            Raise(&ClipboardHistoryEvents::onHistoryChanged);
            Check(counter.calls == 1, L"history changed");

            Script().historyEnabled = false;
            Raise(&ClipboardHistoryEvents::onHistoryEnabledChanged);
            Check(counter.calls == 2 && counter.lastFlag == 0, L"history enabled changed to off");

            // No roaming handler: raising it reaches nobody.
            Raise(&ClipboardHistoryEvents::onRoamingEnabledChanged);
            Check(counter.calls == 2, L"a NULL handler was called");

            Ok(ntk_clipboard_set_history_handlers(session, nullptr), L"remove");
            Raise(&ClipboardHistoryEvents::onHistoryChanged);
            Check(counter.calls == 2, L"a removed handler was called");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_HistoryHandlers_MalformedAndVersions)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            ntk_clipboard_history_handlers handlers{};
            handlers.struct_size = static_cast<uint32_t>(sizeof(handlers));

            auto reserved = handlers;
            reserved.reserved0 = 1;
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_set_history_handlers(session, &reserved), L"reserved0");
            auto tooSmall = handlers;
            tooSmall.struct_size = 8;
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_set_history_handlers(session, &tooSmall), L"too small");
            auto newer = GrownFrom(handlers, 1);
            Is(NTK_CLIPBOARD_ERROR_NOT_SUPPORTED, ntk_clipboard_set_history_handlers(session, &newer.known), L"newer");
            auto zeroTail = GrownFrom(handlers, 0);
            Ok(ntk_clipboard_set_history_handlers(session, &zeroTail.known), L"zero tail");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_HistoryHandlers_FromAnotherThread_IsWrongThread)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            ntk_clipboard_error result = NTK_CLIPBOARD_ERROR_NONE;
            std::thread other([&] { result = ntk_clipboard_set_history_handlers(session, nullptr); });
            other.join();
            Is(NTK_CLIPBOARD_ERROR_WRONG_THREAD, result, L"another thread");
            CloseAndFree(session);
        }));
    }

    // ------------------------------------------------------------------------
    // Round trips through the C ABI
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Text_RoundTripsInUtf8)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            // "caf\u00e9 \u65e5\u672c \U0001F600", written as bytes.
            const char* text = "caf\xC3\xA9 \xE6\x97\xA5\xE6\x9C\xAC \xF0\x9F\x98\x80";
            Ok(ntk_clipboard_copy_text(session, text, 0), L"copy");

            ntk_string* pasted = nullptr;
            Ok(ntk_clipboard_paste_text(session, &pasted), L"paste");
            Check(Read(pasted) == text, L"the text changed on the way");
            ntk_string_free(pasted);

            int32_t present = 0;
            Ok(ntk_clipboard_has_format(session, "CF_UNICODETEXT", &present), L"has_format");
            Check(present != 0, L"CF_UNICODETEXT should be there");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Text_ALoneSurrogateBecomesTheReplacementCharacter)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Ok(ntk_clipboard_copy_text(session, "x", 0), L"copy");

            // Another program put text with a lone surrogate on the clipboard.
            const wchar_t written[] = {L'a', wchar_t(0xD800), L'b', 0};
            HGLOBAL memory = ::GlobalAlloc(GMEM_MOVEABLE, sizeof(written));
            std::memcpy(::GlobalLock(memory), written, sizeof(written));
            ::GlobalUnlock(memory);
            Current()->SetClipboardData(CF_UNICODETEXT, memory);

            ntk_string* pasted = nullptr;
            Ok(ntk_clipboard_paste_text(session, &pasted), L"paste");
            Check(Read(pasted) == "a\xEF\xBF\xBD" "b", L"expected U+FFFD in place of the surrogate");
            ntk_string_free(pasted);
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Html_RoundTrips)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Ok(ntk_clipboard_copy_html(session, "<b>caf\xC3\xA9</b>", "caf\xC3\xA9", 0), L"copy");
            ntk_string* html = nullptr;
            Ok(ntk_clipboard_paste_html(session, &html), L"paste html");
            Check(Read(html) == "<b>caf\xC3\xA9</b>", L"the fragment changed on the way");
            ntk_string_free(html);

            ntk_string* text = nullptr;
            Ok(ntk_clipboard_paste_text(session, &text), L"paste text");
            Check(Read(text) == "caf\xC3\xA9", L"the plain text changed on the way");
            ntk_string_free(text);
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Files_RoundTrip)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            const char* paths[] = {"C:\\one.txt", "C:\\caf\xC3\xA9\\two.txt"};
            Ok(ntk_clipboard_copy_files(session, paths, 2, 0), L"copy");

            ntk_string_list* pasted = nullptr;
            Ok(ntk_clipboard_paste_files(session, &pasted), L"paste");
            Check(ntk_string_list_count(pasted) == 2, L"two paths");
            Check(std::string(ntk_string_list_at(pasted, 0, nullptr)) == paths[0], L"first path");
            Check(std::string(ntk_string_list_at(pasted, 1, nullptr)) == paths[1], L"second path");
            ntk_string_list_free(pasted);
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_DibAndCustom_RoundTrip)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            // The smallest DIB the C++ API accepts: a BITMAPINFOHEADER and one 32-bit pixel.
            BITMAPINFOHEADER header{};
            header.biSize = sizeof(header);
            header.biWidth = 1;
            header.biHeight = 1;
            header.biPlanes = 1;
            header.biBitCount = 32;
            header.biCompression = BI_RGB;
            std::vector<uint8_t> dib(sizeof(header) + 4, 0x7F);
            std::memcpy(dib.data(), &header, sizeof(header));
            Ok(ntk_clipboard_copy_dib(session, dib.data(), dib.size(), 0), L"copy dib");

            ntk_bytes* pastedDib = nullptr;
            Ok(ntk_clipboard_paste_dib(session, &pastedDib), L"paste dib");
            Check(ntk_bytes_size(pastedDib) >= dib.size() &&
                      std::memcmp(ntk_bytes_data(pastedDib), dib.data(), dib.size()) == 0,
                  L"the DIB changed on the way");
            ntk_bytes_free(pastedDib);

            const uint8_t data[] = {0, 1, 2, 250, 0};
            Ok(ntk_clipboard_copy_custom(session, "NativeToolkit.CApiTest", data, sizeof(data), 0), L"copy custom");
            ntk_bytes* pasted = nullptr;
            Ok(ntk_clipboard_paste_custom(session, "NativeToolkit.CApiTest", &pasted), L"paste custom");
            Check(ntk_bytes_size(pasted) == sizeof(data) && std::memcmp(ntk_bytes_data(pasted), data, sizeof(data)) == 0,
                  L"the custom bytes changed on the way");
            ntk_bytes_free(pasted);
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Formats_ListPreferAndClear)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Ok(ntk_clipboard_copy_html(session, "<i>x</i>", "x", 0), L"copy");

            ntk_string_list* formats = nullptr;
            Ok(ntk_clipboard_get_formats(session, &formats), L"get_formats");
            Check(ntk_string_list_count(formats) >= 2, L"HTML and text should both be listed");
            ntk_string_list_free(formats);

            ntk_string* preferred = nullptr;
            Ok(ntk_clipboard_get_preferred_format(session, &preferred), L"get_preferred_format");
            Check(ntk_string_size(preferred) > 0, L"a format should be preferred");
            ntk_string_free(preferred);

            Ok(ntk_clipboard_clear(session), L"clear");
            int32_t present = 1;
            Ok(ntk_clipboard_has_format(session, "CF_UNICODETEXT", &present), L"has_format after clear");
            Check(present == 0, L"the text should be gone");
            ntk_string* text = reinterpret_cast<ntk_string*>(1);
            Check(ntk_clipboard_paste_text(session, &text) != NTK_CLIPBOARD_ERROR_NONE, L"paste after clear");
            Check(text == nullptr, L"the output is NULL on failure");
            CloseAndFree(session);
        }));
    }

    // ------------------------------------------------------------------------
    // CT-05, CT-06: what the C ABI refuses before the C++ API sees it
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Refused_NullsBadUtf8AndUnknownFlags)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            const auto invalid = NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
            const uint8_t bytes[] = {1};
            const char* withNull[] = {"C:\\a.txt", nullptr};
            const char* withBad[] = {kBad};
            int32_t present = -1;

            Is(invalid, ntk_clipboard_copy_text(session, nullptr, 0), L"copy_text NULL");
            Is(invalid, ntk_clipboard_copy_text(session, kBad, 0), L"copy_text bad UTF-8");
            Is(invalid, ntk_clipboard_copy_text(session, "x", 4), L"copy_text flag 4");
            Is(invalid, ntk_clipboard_copy_text(session, "x", 0x80000000u), L"copy_text high flag");
            Is(invalid, ntk_clipboard_copy_html(session, nullptr, "x", 0), L"copy_html NULL fragment");
            Is(invalid, ntk_clipboard_copy_html(session, "x", kBad, 0), L"copy_html bad plain text");
            Is(invalid, ntk_clipboard_copy_files(session, nullptr, 1, 0), L"copy_files NULL array");
            Is(invalid, ntk_clipboard_copy_files(session, withNull, 2, 0), L"copy_files NULL entry");
            Is(invalid, ntk_clipboard_copy_files(session, withBad, 1, 0), L"copy_files bad entry");
            Is(invalid, ntk_clipboard_copy_dib(session, nullptr, 1, 0), L"copy_dib NULL with a size");
            Is(invalid, ntk_clipboard_copy_custom(session, nullptr, bytes, 1, 0), L"copy_custom NULL name");
            Is(invalid, ntk_clipboard_copy_custom(session, "Fmt", nullptr, 1, 0), L"copy_custom NULL data");
            Is(invalid, ntk_clipboard_paste_text(session, nullptr), L"paste_text NULL output");
            Is(invalid, ntk_clipboard_paste_html(session, nullptr), L"paste_html NULL output");
            Is(invalid, ntk_clipboard_paste_files(session, nullptr), L"paste_files NULL output");
            Is(invalid, ntk_clipboard_paste_dib(session, nullptr), L"paste_dib NULL output");
            Is(invalid, ntk_clipboard_paste_custom(session, nullptr, nullptr), L"paste_custom NULLs");
            ntk_bytes* data = reinterpret_cast<ntk_bytes*>(1);
            Is(invalid, ntk_clipboard_paste_custom(session, kBad, &data), L"paste_custom bad name");
            Check(data == nullptr, L"the output is NULL on failure");
            Is(invalid, ntk_clipboard_has_format(session, "x", nullptr), L"has_format NULL output");
            Is(invalid, ntk_clipboard_has_format(session, nullptr, &present), L"has_format NULL name");
            Check(present == -1, L"a value output is written only on success");
            Is(invalid, ntk_clipboard_get_formats(session, nullptr), L"get_formats NULL output");
            Is(invalid, ntk_clipboard_get_preferred_format(session, nullptr), L"get_preferred_format NULL output");

            // Nothing refused reached the clipboard.
            Check(Current()->FormatCount() == 0, L"a refused write reached the clipboard");
            CloseAndFree(session);
        }));
    }

    // ------------------------------------------------------------------------
    // The conversions on their own
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_WriteOptions_EachFlagAndNoOther)
    {
        using NativeToolkitC::Detail::Clipboard::ToWriteOptions;
        Api::WriteOptions options;
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ToWriteOptions(NTK_CLIPBOARD_WRITE_DEFAULT, options));
        Assert::IsFalse(options.excludeFromHistory || options.excludeFromRoaming);
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ToWriteOptions(NTK_CLIPBOARD_WRITE_EXCLUDE_HISTORY, options));
        Assert::IsTrue(options.excludeFromHistory && !options.excludeFromRoaming);
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ToWriteOptions(NTK_CLIPBOARD_WRITE_EXCLUDE_ROAMING, options));
        Assert::IsTrue(!options.excludeFromHistory && options.excludeFromRoaming);
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ToWriteOptions(NTK_CLIPBOARD_WRITE_SENSITIVE, options));
        Assert::IsTrue(options.excludeFromHistory && options.excludeFromRoaming);
        for (uint32_t bit = 2; bit < 32; ++bit) {
            Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ToWriteOptions(1u << bit, options));
        }
    }

    TEST_METHOD(Test_Bytes_EmptyMayBeNull)
    {
        using NativeToolkitC::Detail::Clipboard::ToBytes;
        std::vector<std::byte> out{std::byte{9}};
        Assert::IsTrue(ToBytes(nullptr, 0, out));
        Assert::IsTrue(out.empty());
        Assert::IsFalse(ToBytes(nullptr, 1, out));
        const uint8_t data[] = {1, 2};
        Assert::IsTrue(ToBytes(data, 2, out));
        Assert::AreEqual(size_t{2}, out.size());
    }
};

}  // namespace CApiClipboardTest
