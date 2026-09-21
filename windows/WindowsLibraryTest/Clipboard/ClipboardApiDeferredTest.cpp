#include "pch.h"
#include "Support/ClipboardSessionForTest.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"

#include <functional>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// OP-40 and OP-41: offering a format without producing it.
//
// The C ABI asks a provider twice - once for a size, once to fill a buffer -
// because a C caller has nowhere to put the bytes until it knows how many
// there are. A provider that returns a vector has already answered both, so
// the C++ API asks once (N-2). The two-phase adapter and its size-consistency
// tests are untouched and still cover the C path.
//
// What is left to check here is what happens at the far end of the
// reservation, where nobody is listening any more: the provider runs inside
// the message that collects the data, long after ReserveDeferred returned, so
// a provider that fails or throws can only mean an empty format and a line in
// the log (N-3). Those are the three outcomes below.
// ============================================================================

namespace WindowsClipboardApiDeferredTest
{

namespace Api = NativeToolkit::Clipboard;
using Api::ErrorCode;

namespace
{
    using ClipboardSessionForTest::Check;

    std::vector<std::byte> AsBytes(std::initializer_list<BYTE> raw)
    {
        std::vector<std::byte> bytes(raw.size());
        size_t index = 0;
        for (BYTE value : raw) bytes[index++] = static_cast<std::byte>(value);
        return bytes;
    }

    /// Delivers the message the OS sends when something wants the data.
    void AskForTheData(UINT format)
    {
        ClipboardManager::GetInstance().OnRenderFormat(format);
    }

    /// What a write actually placed.
    std::vector<BYTE> PlacedBytes(UINT format)
    {
        return ClipboardSessionForTest::Current()->BytesOf(format);
    }
}

TEST_CLASS(ClipboardApiDeferredTest)
{
public:

    TEST_METHOD_CLEANUP(ReleaseTheProcess)
    {
        Api::Detail::ClipboardTestAccess::ResetProcessState();
    }

    // --- The three outcomes of a provider -----------------------------------

    TEST_METHOD(Test_AProviderThatSucceeds_IsAskedOnceAndItsBytesArePlaced)
    {
        Run([](Api::Session& session) {
            int calls = 0;
            std::wstring askedFor;
            const std::vector<std::wstring> formats{L"NativeToolkit.Deferred"};

            const auto reserved = session.ReserveDeferred(formats,
                [&](std::wstring_view name) -> Api::Result<std::vector<std::byte>> {
                    ++calls;
                    askedFor = name;
                    return AsBytes({0xde, 0xad, 0xbe, 0xef});
                });
            Check(reserved.has_value(), L"ReserveDeferred failed");

            // Reserving offers the format without producing anything.
            Check(calls == 0, L"the provider ran before anything asked for the data");
            const auto has = session.HasFormat(L"NativeToolkit.Deferred");
            Check(has.has_value() && has.value(), L"the format was not offered");

            const UINT format = ::RegisterClipboardFormatW(L"NativeToolkit.Deferred");
            AskForTheData(format);

            Check(calls == 1, L"the provider was not asked exactly once");
            Check(askedFor == L"NativeToolkit.Deferred", L"the provider was told the wrong name");

            const std::vector<BYTE> placed = PlacedBytes(format);
            Check(placed.size() == 4, L"the wrong number of bytes was placed");
            Check(placed[0] == 0xde && placed[3] == 0xef, L"the bytes were placed wrong");
        });
    }

    TEST_METHOD(Test_AProviderThatFails_RendersNothing)
    {
        // The reservation is long made and an application is waiting
        // mid-paste, so a failure can only mean an empty format.
        Run([](Api::Session& session) {
            const std::vector<std::wstring> formats{L"NativeToolkit.Failing"};
            const auto reserved = session.ReserveDeferred(formats,
                [](std::wstring_view) -> Api::Result<std::vector<std::byte>> {
                    return NativeToolkit::Unexpected{Api::Error{ErrorCode::InvalidData, 0}};
                });
            Check(reserved.has_value(), L"ReserveDeferred failed");

            const UINT format = ::RegisterClipboardFormatW(L"NativeToolkit.Failing");
            AskForTheData(format);

            Check(PlacedBytes(format).empty(), L"a failed provider placed bytes anyway");
        });
    }

    TEST_METHOD(Test_AProviderThatThrows_RendersNothingAndDoesNotEscape)
    {
        Run([](Api::Session& session) {
            const std::vector<std::wstring> formats{L"NativeToolkit.Throwing"};
            const auto reserved = session.ReserveDeferred(formats,
                [](std::wstring_view) -> Api::Result<std::vector<std::byte>> {
                    throw std::runtime_error("the provider gave up");
                });
            Check(reserved.has_value(), L"ReserveDeferred failed");

            const UINT format = ::RegisterClipboardFormatW(L"NativeToolkit.Throwing");
            AskForTheData(format);  // must not let the exception out

            Check(PlacedBytes(format).empty(), L"a throwing provider placed bytes anyway");
        });
    }

    TEST_METHOD(Test_AProviderThatReturnsNothing_RendersNothing)
    {
        Run([](Api::Session& session) {
            const std::vector<std::wstring> formats{L"NativeToolkit.Empty"};
            const auto reserved = session.ReserveDeferred(formats,
                [](std::wstring_view) -> Api::Result<std::vector<std::byte>> {
                    return std::vector<std::byte>{};
                });
            Check(reserved.has_value(), L"ReserveDeferred failed");

            const UINT format = ::RegisterClipboardFormatW(L"NativeToolkit.Empty");
            AskForTheData(format);

            Check(PlacedBytes(format).empty(), L"an empty result placed bytes anyway");
        });
    }

    // --- Copies -------------------------------------------------------------

    TEST_METHOD(Test_TheNamesAndTheProviderAreCopied)
    {
        // Neither has to outlive the call: the names arrive as a span into the
        // caller's storage, and the provider is whatever it was built from.
        Run([](Api::Session& session) {
            bool called = false;
            {
                std::vector<std::wstring> temporaryNames{L"NativeToolkit.Copied"};
                std::string owned = "captured by value";
                const auto reserved = session.ReserveDeferred(temporaryNames,
                    [&called, owned](std::wstring_view) -> Api::Result<std::vector<std::byte>> {
                        called = true;
                        return AsBytes({static_cast<BYTE>(owned.size())});
                    });
                Check(reserved.has_value(), L"ReserveDeferred failed");
            }
            // The names vector and the lambda that was passed are both gone.

            const UINT format = ::RegisterClipboardFormatW(L"NativeToolkit.Copied");
            AskForTheData(format);

            Check(called, L"the provider did not survive its caller");
            const std::vector<BYTE> placed = PlacedBytes(format);
            Check(placed.size() == 1 && placed[0] == 17, L"the captured value did not survive");
        });
    }

    TEST_METHOD(Test_SeveralFormats_EachGetTheirOwnName)
    {
        Run([](Api::Session& session) {
            std::vector<std::wstring> asked;
            const std::vector<std::wstring> formats{L"NativeToolkit.A", L"NativeToolkit.B"};

            const auto reserved = session.ReserveDeferred(formats,
                [&](std::wstring_view name) -> Api::Result<std::vector<std::byte>> {
                    asked.emplace_back(name);
                    return AsBytes({0x01});
                });
            Check(reserved.has_value(), L"ReserveDeferred failed");

            AskForTheData(::RegisterClipboardFormatW(L"NativeToolkit.A"));
            AskForTheData(::RegisterClipboardFormatW(L"NativeToolkit.B"));

            Check(asked.size() == 2, L"the wrong number of providers ran");
            Check(asked[0] == L"NativeToolkit.A", L"the first format was named wrong");
            Check(asked[1] == L"NativeToolkit.B", L"the second format was named wrong");
        });
    }

    // --- Refusals -----------------------------------------------------------

    TEST_METHOD(Test_NoFormats_IsRefused)
    {
        Run([](Api::Session& session) {
            const auto result = session.ReserveDeferred({},
                [](std::wstring_view) -> Api::Result<std::vector<std::byte>> {
                    return std::vector<std::byte>{};
                });

            Check(!result.has_value(), L"an empty reservation was accepted");
            Check(ErrorCode::InvalidParameter == result.error().code, L"not InvalidParameter");
        });
    }

    TEST_METHOD(Test_NoProvider_IsRefused)
    {
        Run([](Api::Session& session) {
            const std::vector<std::wstring> formats{L"NativeToolkit.Deferred"};
            const auto result = session.ReserveDeferred(formats, Api::RenderProvider{});

            Check(!result.has_value(), L"a reservation with no provider was accepted");
            Check(ErrorCode::InvalidParameter == result.error().code, L"not InvalidParameter");
        });
    }

    TEST_METHOD(Test_ReserveFromAnotherThread_IsRefused)
    {
        // The provider runs on the thread the messages arrive on, so only that
        // thread may set one up.
        Run([](Api::Session& session) {
            ErrorCode seen = ErrorCode::None;
            std::thread elsewhere([&] {
                const std::vector<std::wstring> formats{L"NativeToolkit.Deferred"};
                const auto result = session.ReserveDeferred(formats,
                    [](std::wstring_view) -> Api::Result<std::vector<std::byte>> {
                        return std::vector<std::byte>{};
                    });
                if (!result.has_value()) seen = result.error().code;
            });
            elsewhere.join();

            Check(ErrorCode::WrongThread == seen, L"a non-owner thread reserved formats");
        });
    }

    // --- Recovery -----------------------------------------------------------

    TEST_METHOD(Test_RecoverDeferredState_SucceedsWhenThereIsNothingToRecover)
    {
        Run([](Api::Session& session) {
            Check(session.RecoverDeferredState().has_value(),
                  L"recovery failed with nothing to recover");
        });
    }

    TEST_METHOD(Test_RecoverFromAnotherThread_IsRefused)
    {
        Run([](Api::Session& session) {
            ErrorCode seen = ErrorCode::None;
            std::thread elsewhere([&] {
                const auto result = session.RecoverDeferredState();
                if (!result.has_value()) seen = result.error().code;
            });
            elsewhere.join();

            Check(ErrorCode::WrongThread == seen, L"a non-owner thread recovered the state");
        });
    }

    // --- A session that is not open -----------------------------------------

    TEST_METHOD(Test_OnAClosedSession_BothReportNotInitialized)
    {
        Run([](Api::Session& session) {
            Check(session.Close().has_value(), L"Close failed");

            const std::vector<std::wstring> formats{L"NativeToolkit.Deferred"};
            const auto reserved = session.ReserveDeferred(formats,
                [](std::wstring_view) -> Api::Result<std::vector<std::byte>> {
                    return std::vector<std::byte>{};
                });
            Check(!reserved.has_value() && ErrorCode::NotInitialized == reserved.error().code,
                  L"ReserveDeferred did not report NotInitialized");

            const auto recovered = session.RecoverDeferredState();
            Check(!recovered.has_value() && ErrorCode::NotInitialized == recovered.error().code,
                  L"RecoverDeferredState did not report NotInitialized");
        });
    }

private:

    static void Run(const std::function<void(Api::Session&)>& body)
    {
        const std::wstring failure = ClipboardSessionForTest::Run(body);
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }
};

}  // namespace WindowsClipboardApiDeferredTest
