#include "pch.h"

#include "NativeToolkitC/Clipboard.h"

#include "Clipboard/CApiClipboardHarness.h"
#include "Clipboard/ClipboardConvert.h"

#include <cstring>
#include <map>
#include <string>
#include <thread>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace CApiClipboardHarness;

// ============================================================================
// Deferred rendering in the C ABI (stage 5 design, T-08, CT-13): when the
// provider is called, and that each reservation's release runs exactly once,
// at the moment and on the thread the table in 7.5.3 says.
//
// The fake clipboard sends the owner WM_DESTROYCLIPBOARD and WM_RENDERFORMAT
// as Windows does (CApiClipboardHarness.h), which is what ends a reservation
// and what asks for a format. One thing it cannot do is send
// WM_RENDERALLFORMATS when the session's window is destroyed, so the provider
// being called inside close is not exercised here.
// ============================================================================

namespace CApiClipboardDeferredTest
{

namespace
{
    // -- A caller's user_data: what its provider and release saw -------------

    struct Provider {
        std::map<std::string, std::vector<uint8_t>> bytes;  ///< What to render, by format name.
        ntk_clipboard_error answer = NTK_CLIPBOARD_ERROR_NONE;
        bool setTwice = false;
        bool skipSet = false;

        int calls = 0;
        std::vector<std::string> asked;
        ntk_clipboard_error secondSet = NTK_CLIPBOARD_ERROR_NONE;
        int releases = 0;
        DWORD releaseThread = 0;
        int callsAtRelease = -1;
    };

    ntk_clipboard_error NTK_CALL Render(void* userData, const char* formatName, ntk_clipboard_render_target* target)
    {
        auto* p = static_cast<Provider*>(userData);
        ++p->calls;
        p->asked.emplace_back(formatName);
        if (!p->skipSet) {
            const auto& bytes = p->bytes[formatName];
            ntk_clipboard_render_target_set(target, bytes.data(), bytes.size());
            if (p->setTwice) p->secondSet = ntk_clipboard_render_target_set(target, bytes.data(), bytes.size());
        }
        return p->answer;
    }

    void NTK_CALL Release(void* userData)
    {
        auto* p = static_cast<Provider*>(userData);
        ++p->releases;
        p->releaseThread = ::GetCurrentThreadId();
        p->callsAtRelease = p->calls;
    }

    void Ok(ntk_clipboard_error result, const wchar_t* what)
    {
        if (result != NTK_CLIPBOARD_ERROR_NONE) {
            throw Failure{std::wstring(what) + L" failed with " + std::to_wstring(result)};
        }
    }

    void Is(ntk_clipboard_error expected, ntk_clipboard_error actual, const wchar_t* what)
    {
        if (expected != actual) {
            throw Failure{std::wstring(what) + L": expected " + std::to_wstring(expected) + L", got " +
                          std::to_wstring(actual)};
        }
    }

    void Released(const Provider& p, int times, const wchar_t* what)
    {
        if (p.releases != times) {
            throw Failure{std::wstring(what) + L": released " + std::to_wstring(p.releases) + L" times, expected " +
                          std::to_wstring(times)};
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

    ntk_clipboard_error Reserve(ntk_clipboard_session* session, Provider& p, std::vector<const char*> formats)
    {
        return ntk_clipboard_reserve_deferred(session, formats.data(), formats.size(), &Render, &p, &Release);
    }

    UINT FormatId(const wchar_t* name)
    {
        return ::RegisterClipboardFormatW(name);
    }

    const char* const kA = "NativeToolkit.CApiDeferredA";
    const char* const kB = "NativeToolkit.CApiDeferredB";
}

TEST_CLASS(CApiClipboardDeferredTest)
{
public:
    // ------------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Reserve_RendersEachFormatWhenRead)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider p;
            p.bytes[kA] = {1, 2, 3};
            p.bytes[kB] = {9};
            Ok(Reserve(session, p, {kA, kB}), L"reserve");
            Check(Current()->IsReserved(FormatId(L"NativeToolkit.CApiDeferredA")), L"A is not reserved");
            Check(p.calls == 0, L"a provider ran before anything was read");

            ntk_bytes* data = nullptr;
            Ok(ntk_clipboard_paste_custom(session, kA, &data), L"paste A");
            Check(ntk_bytes_size(data) == 3 && ntk_bytes_data(data)[2] == 3, L"A's bytes");
            ntk_bytes_free(data);
            Check(p.calls == 1 && p.asked.back() == kA, L"the provider was asked for A");
            Released(p, 0, L"while reserved");

            CloseAndFree(session);
            Released(p, 1, L"after close");
        }));
    }

    TEST_METHOD(Test_Reserve_FormatNameReachesTheProviderInUtf8)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider p;
            const char* name = "NativeToolkit.caf\xC3\xA9";
            p.bytes[name] = {7};
            Ok(Reserve(session, p, {name}), L"reserve");
            ntk_bytes* data = nullptr;
            Ok(ntk_clipboard_paste_custom(session, name, &data), L"paste");
            ntk_bytes_free(data);
            Check(p.asked.size() == 1 && p.asked[0] == name, L"the name changed on the way");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_RenderTarget_TheContract)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            ntk_bytes* data = nullptr;

            Provider twice;
            twice.bytes[kA] = {1};
            twice.setTwice = true;
            Ok(Reserve(session, twice, {kA}), L"reserve twice");
            Ok(ntk_clipboard_paste_custom(session, kA, &data), L"paste twice");
            ntk_bytes_free(data);
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, twice.secondSet, L"a second set");

            Provider failing;
            failing.bytes[kA] = {1};
            failing.answer = NTK_CLIPBOARD_ERROR_INVALID_DATA;
            Ok(Reserve(session, failing, {kA}), L"reserve failing");
            Check(ntk_clipboard_paste_custom(session, kA, &data) != NTK_CLIPBOARD_ERROR_NONE,
                  L"a provider that failed after setting rendered something");
            Check(data == nullptr, L"no bytes after a failed render");

            Provider silent;
            silent.skipSet = true;
            Ok(Reserve(session, silent, {kA}), L"reserve silent");
            Check(ntk_clipboard_paste_custom(session, kA, &data) != NTK_CLIPBOARD_ERROR_NONE,
                  L"a provider that set nothing rendered something");
            Check(silent.calls == 1, L"the silent provider was asked");

            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_render_target_set(nullptr, nullptr, 0), L"NULL target");
            ntk_clipboard_render_target target;
            Is(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_render_target_set(&target, nullptr, 1), L"NULL data");
            Ok(ntk_clipboard_render_target_set(&target, nullptr, 0), L"no bytes");
            CloseAndFree(session);
        }));
    }

    // ------------------------------------------------------------------------
    // CT-13: when release runs
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Release_OnceForAReservationOfSeveralFormats)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider p;
            Ok(Reserve(session, p, {kA, kB, "NativeToolkit.CApiDeferredC"}), L"reserve");
            Ok(ntk_clipboard_clear(session), L"clear");
            Released(p, 1, L"after clear");
            CloseAndFree(session);
            Released(p, 1, L"after close");
        }));
    }

    TEST_METHOD(Test_Release_WhenTheNextReservationEmptiesTheClipboard)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider first, second;
            Ok(Reserve(session, first, {kA}), L"first");
            Ok(Reserve(session, second, {kB}), L"second");
            Released(first, 1, L"the first after the second");
            Check(first.releaseThread == ::GetCurrentThreadId(), L"released off the owner thread");
            Released(second, 0, L"the second while it stands");
            CloseAndFree(session);
            Released(second, 1, L"the second after close");
        }));
    }

    TEST_METHOD(Test_Release_WhenThisSessionWritesOnTheOwnerThread)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider p;
            Ok(Reserve(session, p, {kA}), L"reserve");
            Ok(ntk_clipboard_copy_text(session, "x", 0), L"copy");
            Released(p, 1, L"after the write returned");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Release_WhenAnotherThreadWrites_OnTheOwnerBeforeTheWriteReturns)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider p;
            Ok(Reserve(session, p, {kA}), L"reserve");
            const DWORD owner = ::GetCurrentThreadId();

            ntk_clipboard_error written = NTK_CLIPBOARD_ERROR_UNKNOWN;
            int releasesSeenByTheWriter = -1;
            RunElsewhereWhilePumping([&] {
                written = ntk_clipboard_copy_text(session, "from elsewhere", 0);
                releasesSeenByTheWriter = p.releases;
            });
            Ok(written, L"the other thread's write");
            Check(releasesSeenByTheWriter == 1, L"the release had not run when the write returned");
            Check(p.releaseThread == owner, L"released off the owner thread");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Release_WhenAnotherProgramEmptiesTheClipboard)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider p;
            Ok(Reserve(session, p, {kA}), L"reserve");
            Current()->EmptyByAnotherProgram();
            Released(p, 1, L"after another program emptied it");
            CloseAndFree(session);
            Released(p, 1, L"after close");
        }));
    }

    TEST_METHOD(Test_Release_WhenAReservationFails_BeforeItReturns)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider standing, failing;
            Ok(Reserve(session, standing, {kA}), L"the standing reservation");

            Current()->failPlaceholder = true;
            const auto result = Reserve(session, failing, {kB});
            Current()->failPlaceholder = false;
            Check(result != NTK_CLIPBOARD_ERROR_NONE && result != NTK_CLIPBOARD_ERROR_PARTIAL_STATE,
                  L"the reservation should fail and roll back");
            Released(failing, 1, L"the failed reservation");
            Check(failing.releaseThread == ::GetCurrentThreadId(), L"released off the calling thread");
            // It got as far as emptying the clipboard, which ends the one before.
            Released(standing, 1, L"the standing reservation");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Release_PartialStateKeepsItUntilRecovery)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider p;
            Current()->failPlaceholder = true;
            Current()->failRollback = true;
            Is(NTK_CLIPBOARD_ERROR_PARTIAL_STATE, Reserve(session, p, {kA}), L"reserve");
            Current()->failPlaceholder = false;
            Current()->failRollback = false;
            Released(p, 0, L"after PARTIAL_STATE");

            Ok(ntk_clipboard_recover_deferred_state(session), L"recover");
            Released(p, 1, L"after recovery");
            CloseAndFree(session);
            Released(p, 1, L"after close");
        }));
    }

    TEST_METHOD(Test_Release_WhenTheCApiRefusesTheReservation)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            const char* withNull[] = {kA, nullptr};
            const char* withBad[] = {"\xFF"};
            const auto invalid = NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
            struct Case {
                const wchar_t* name;
                std::function<ntk_clipboard_error(Provider&)> call;
            };
            const Case cases[] = {
                {L"NULL session", [&](Provider& p) { return ntk_clipboard_reserve_deferred(nullptr, withNull, 1, &Render, &p, &Release); }},
                {L"NULL formats", [&](Provider& p) { return ntk_clipboard_reserve_deferred(session, nullptr, 1, &Render, &p, &Release); }},
                {L"no formats", [&](Provider& p) { return ntk_clipboard_reserve_deferred(session, withNull, 0, &Render, &p, &Release); }},
                {L"NULL format", [&](Provider& p) { return ntk_clipboard_reserve_deferred(session, withNull, 2, &Render, &p, &Release); }},
                {L"bad format", [&](Provider& p) { return ntk_clipboard_reserve_deferred(session, withBad, 1, &Render, &p, &Release); }},
                {L"NULL provider", [&](Provider& p) { return ntk_clipboard_reserve_deferred(session, withNull, 1, nullptr, &p, &Release); }},
            };
            for (const auto& c : cases) {
                Provider p;
                Is(invalid, c.call(p), c.name);
                Released(p, 1, c.name);
            }

            Provider elsewhere;
            ntk_clipboard_error result = NTK_CLIPBOARD_ERROR_NONE;
            DWORD caller = 0;
            std::thread other([&] {
                caller = ::GetCurrentThreadId();
                result = Reserve(session, elsewhere, {kA});
            });
            other.join();
            Is(NTK_CLIPBOARD_ERROR_WRONG_THREAD, result, L"from another thread");
            Released(elsewhere, 1, L"from another thread");
            Check(elsewhere.releaseThread == caller, L"released off the calling thread");
            CloseAndFree(session);
        }));
    }

    TEST_METHOD(Test_Release_OnCloseBeforeItReturns)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider p;
            Ok(Reserve(session, p, {kA}), L"reserve");
            Ok(ntk_clipboard_session_close(session), L"close");
            Released(p, 1, L"when close returned");
            Check(p.releaseThread == ::GetCurrentThreadId(), L"released off the owner thread");
            ntk_clipboard_session_free(session);
            Released(p, 1, L"after free");
        }));
    }

    TEST_METHOD(Test_Release_OnFreeOfAnUnclosedSession)
    {
        AssertPassed(RunOnOwner([] {
            auto* session = Open();
            Provider p;
            p.bytes[kA] = {1};
            Ok(Reserve(session, p, {kA}), L"reserve");
            const HWND window = SessionWindow();

            ntk_clipboard_session_free(session);   // abandoned
            Released(p, 1, L"in free");

            // The abandoned window still answers the OS; the provider must not.
            ::SendMessageW(window, WM_RENDERFORMAT, FormatId(L"NativeToolkit.CApiDeferredA"), 0);
            Check(p.calls == 0, L"a provider ran after free");
            Released(p, 1, L"after the late request");
        }));
    }
};

}  // namespace CApiClipboardDeferredTest
