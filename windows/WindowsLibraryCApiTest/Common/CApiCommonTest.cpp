#include "pch.h"

#include "NativeToolkitC/Common.h"

#include "Common/CallbackGate.h"
#include "Common/Handles.h"
#include "Common/LastError.h"
#include "Common/ReleaseGuard.h"
#include "Common/StructInput.h"
#include "Common/Utf8.h"

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstring>
#include <future>
#include <memory>
#include <thread>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace NativeToolkitC::Detail;

// ============================================================================
// The shared part of the C ABI (stage 5 design, T-02): the output handles, the
// per-thread system code, UTF-8 at the edge, how input structs are read, and
// the two pieces that give callbacks a lifetime (the release guard and the
// callback gate). CT-01 and CT-02 are the two header files next to this one;
// they pass by compiling.
// ============================================================================

namespace CApiCommonTest
{

namespace
{
    /// A struct as a later version might grow it: 2.0.0 had up to `a`, and
    /// `b` came after. Only the reading rules are exercised, so any layout
    /// with struct_size first will do.
    struct Grown
    {
        uint32_t struct_size;
        uint32_t reserved0;
        int32_t  a;
        int32_t  b;
    };
    constexpr uint32_t kFirstSize = offsetof(Grown, b);

    /// The same struct seen by a caller whose header is newer than the DLL.
    struct Newer
    {
        Grown   known;
        int32_t added;
        int32_t reserved1;
    };

    std::atomic<int> g_released{0};
    void CountRelease(void* userData)
    {
        ++g_released;
        if (userData) *static_cast<int*>(userData) += 1;
    }
}

TEST_CLASS(CApiCommonTest)
{
public:

    // --- CT-09: handles -----------------------------------------------------

    TEST_METHOD(Test_FreeingNull_DoesNothing)
    {
        ntk_string_free(nullptr);
        ntk_bytes_free(nullptr);
        ntk_string_list_free(nullptr);
    }

    TEST_METHOD(Test_ReadingANullHandle_GivesNullOrZero)
    {
        Assert::IsNull(ntk_string_data(nullptr));
        Assert::AreEqual<size_t>(0, ntk_string_size(nullptr));
        Assert::IsNull(ntk_bytes_data(nullptr));
        Assert::AreEqual<size_t>(0, ntk_bytes_size(nullptr));
        Assert::AreEqual<size_t>(0, ntk_string_list_count(nullptr));
        size_t size = 99;
        Assert::IsNull(ntk_string_list_at(nullptr, 0, &size));
        Assert::AreEqual<size_t>(0, size);
    }

    TEST_METHOD(Test_AString_IsUtf8AndItsSizeLeavesOutTheTerminator)
    {
        ntk_string* s = NewString(L"h\u00e9llo");
        Assert::AreEqual("h\xC3\xA9llo", ntk_string_data(s));
        Assert::AreEqual<size_t>(6, ntk_string_size(s));
        ntk_string_free(s);
    }

    TEST_METHOD(Test_EmptyBytes_StillHaveANonNullPointer)
    {
        ntk_bytes* b = NewBytes(nullptr, 0);
        Assert::AreEqual<size_t>(0, ntk_bytes_size(b));
        Assert::IsNotNull(ntk_bytes_data(b));
        ntk_bytes_free(b);
    }

    TEST_METHOD(Test_Bytes_AreACopy)
    {
        uint8_t source[] = {1, 2, 3};
        ntk_bytes* b = NewBytes(source, sizeof(source));
        source[0] = 9;
        Assert::AreEqual<size_t>(3, ntk_bytes_size(b));
        Assert::AreEqual<int>(1, ntk_bytes_data(b)[0]);
        ntk_bytes_free(b);
    }

    TEST_METHOD(Test_AList_ReadsBackItsItemsAndRefusesOutOfRange)
    {
        ntk_string_list* list = NewStringList({L"a", L"\u00fc", L""});
        Assert::AreEqual<size_t>(3, ntk_string_list_count(list));

        size_t size = 0;
        Assert::AreEqual("\xC3\xBC", ntk_string_list_at(list, 1, &size));
        Assert::AreEqual<size_t>(2, size);
        Assert::AreEqual("", ntk_string_list_at(list, 2, &size));
        Assert::AreEqual<size_t>(0, size);
        Assert::AreEqual("a", ntk_string_list_at(list, 0, nullptr));  // out_size may be NULL

        size = 99;
        Assert::IsNull(ntk_string_list_at(list, 3, &size));
        Assert::AreEqual<size_t>(0, size);
        ntk_string_list_free(list);
    }

    // --- CT-08: the system code is per thread --------------------------------

    TEST_METHOD(Test_TheSystemCode_BelongsToTheThreadThatSetIt)
    {
        SetLastSystemCode(5);
        const uint32_t elsewhere = std::async(std::launch::async, [] {
            const uint32_t before = ntk_last_system_code();
            SetLastSystemCode(7);
            return before;
        }).get();

        Assert::AreEqual<uint32_t>(0, elsewhere, L"another thread saw this thread's value");
        Assert::AreEqual<uint32_t>(5, ntk_last_system_code(), L"another thread's value leaked here");

        SetLastSystemCode(0);
        Assert::AreEqual<uint32_t>(0, ntk_last_system_code());
    }

    // --- UTF-8 at the edge (E-16) ---------------------------------------------

    TEST_METHOD(Test_ValidUtf8_BecomesUtf16)
    {
        std::wstring out;
        Assert::IsTrue(Utf8ToWide("h\xC3\xA9 \xF0\x9F\x98\x80", out));
        Assert::AreEqual(std::wstring(L"h\u00e9 \U0001F600"), out);
        Assert::IsTrue(Utf8ToWide("", out));
        Assert::IsTrue(out.empty());
    }

    TEST_METHOD(Test_InvalidUtf8_IsRefused)
    {
        std::wstring out;
        Assert::IsFalse(Utf8ToWide("\xC3\x28", out), L"a broken two-byte sequence");
        Assert::IsFalse(Utf8ToWide("\xED\xA0\x80", out), L"an encoded surrogate");
        Assert::IsFalse(Utf8ToWide("\xFF", out), L"a byte UTF-8 never uses");
    }

    TEST_METHOD(Test_AnUnpairedSurrogate_BecomesTheReplacementCharacter)
    {
        const wchar_t lone[] = {L'a', static_cast<wchar_t>(0xD800), L'b', 0};
        Assert::AreEqual(std::string("a\xEF\xBF\xBD" "b"), WideToUtf8(lone));
    }

    // --- CT-07: reading input structs (7.8) ------------------------------------

    TEST_METHOD(Test_AStructOfTheSizeThisVersionKnows_IsRead)
    {
        Grown in{};
        in.struct_size = sizeof(Grown);
        in.a = 1;
        in.b = 2;
        Grown out{};
        Assert::IsTrue(StructCheck::Ok == ReadInputStruct(&in, out, kFirstSize));
        Assert::AreEqual(1, out.a);
        Assert::AreEqual(2, out.b);
    }

    TEST_METHOD(Test_AnOlderShorterStruct_IsReadWithTheMissingFieldsAtTheirDefault)
    {
        Grown in{};
        in.struct_size = kFirstSize;
        in.a = 1;
        in.b = 77;  // past the caller's struct_size: must not be read
        Grown out{};
        Assert::IsTrue(StructCheck::Ok == ReadInputStruct(&in, out, kFirstSize));
        Assert::AreEqual(1, out.a);
        Assert::AreEqual(0, out.b, L"a field beyond struct_size was read");
    }

    TEST_METHOD(Test_TooSmallOrTooLargeOrNull_IsInvalid)
    {
        Grown in{};
        Grown out{};
        in.struct_size = kFirstSize - 1;
        Assert::IsTrue(StructCheck::InvalidParameter == ReadInputStruct(&in, out, kFirstSize));
        in.struct_size = kMaxStructSize + 1;
        Assert::IsTrue(StructCheck::InvalidParameter == ReadInputStruct(&in, out, kFirstSize));
        Assert::IsTrue(StructCheck::InvalidParameter == ReadInputStruct<Grown>(nullptr, out, kFirstSize));
    }

    TEST_METHOD(Test_ANewerLongerStruct_IsAcceptedOnlyWhenTheUnknownPartIsZero)
    {
        Newer in{};
        in.known.struct_size = sizeof(Newer);
        in.known.a = 1;
        Grown out{};
        Assert::IsTrue(StructCheck::Ok == ReadInputStruct(&in.known, out, kFirstSize));

        in.added = 3;
        Assert::IsTrue(StructCheck::NotSupported == ReadInputStruct(&in.known, out, kFirstSize),
                       L"a field this version does not know was silently dropped");
    }

    // --- The release guard ------------------------------------------------------

    TEST_METHOD(Test_TheReleaseGuard_ReleasesOnceWhenTheLastCopyGoes)
    {
        int count = 0;
        {
            auto guard = std::make_shared<ReleaseGuard>(&CountRelease, &count);
            auto copy = guard;
            guard.reset();
            Assert::AreEqual(0, count, L"released while a copy still held it");
        }
        Assert::AreEqual(1, count);
    }

    TEST_METHOD(Test_TheReleaseGuard_ReleasesOnceWhenFiredEarly)
    {
        int count = 0;
        {
            auto guard = std::make_shared<ReleaseGuard>(&CountRelease, &count);
            guard->Fire();
            Assert::AreEqual(1, count);
            Assert::IsTrue(guard->IsFired());
            guard->Fire();
        }
        Assert::AreEqual(1, count, L"released a second time");
    }

    TEST_METHOD(Test_TheReleaseGuard_AcceptsNoCallback)
    {
        ReleaseGuard guard(nullptr, nullptr);
        guard.Fire();
    }

    // --- The callback gate (7.5.2) ----------------------------------------------

    TEST_METHOD(Test_TheGate_StopsCallbacksOnceShut)
    {
        CallbackGate gate;
        int runs = 0;
        Assert::IsTrue(gate.Run([&] { ++runs; }));
        gate.Shut();
        Assert::IsFalse(gate.Run([&] { ++runs; }));
        Assert::AreEqual(1, runs);
        Assert::IsFalse(gate.IsOpen());
    }

    TEST_METHOD(Test_ANestedCallbackOnTheSameThread_DoesNotBlock)
    {
        CallbackGate gate;
        int inner = 0;
        gate.Run([&] { gate.Run([&] { ++inner; }); });
        Assert::AreEqual(1, inner);
    }

    TEST_METHOD(Test_ShuttingInsideACallback_DoesNotWaitForItself)
    {
        CallbackGate gate;
        gate.Run([&] { gate.Shut(); });
        Assert::IsFalse(gate.IsOpen());
    }

    TEST_METHOD(Test_Shut_WaitsForACallbackRunningOnAnotherThread)
    {
        CallbackGate gate;
        std::promise<void> entered;
        std::promise<void> letGo;
        std::atomic<bool> finished{false};

        std::thread worker([&] {
            gate.Run([&] {
                entered.set_value();
                letGo.get_future().wait();
                finished = true;
            });
        });
        entered.get_future().wait();

        auto shut = std::async(std::launch::async, [&] { gate.Shut(); });
        Assert::IsTrue(shut.wait_for(std::chrono::milliseconds(200)) == std::future_status::timeout,
                       L"Shut returned while a callback was still running elsewhere");

        letGo.set_value();
        shut.get();
        Assert::IsTrue(finished.load(), L"Shut returned before the callback finished");
        worker.join();
    }
};

}  // namespace CApiCommonTest
