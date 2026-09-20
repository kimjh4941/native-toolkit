#include "pch.h"
#include "NativeToolkit/Types.h"
#include "NativeToolkit/Error.h"
#include <string>
#include <type_traits>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// U-A of the stage 3 design: the shape of Result<T, E>, Failure<Code> and
// Unexpected<E>.
//
// Most of what has to hold is a property of the type rather than of a call, so
// it is asserted at compile time. The runtime cases below cover what a
// static_assert cannot see: that the active member is the one that was stored,
// that assignment between the two states destroys the old member, and that a
// move-only payload survives a move.
//
// The enumerations are checked against the C ABI constants in
// PublicApiErrorMappingTest.cpp.
// ============================================================================

namespace NativeToolkitPublicApiTest
{

namespace
{
    // Stands in for Session and Manager, which are move only.
    class MoveOnly
    {
    public:
        explicit MoveOnly(int v = 0) : value_(v) {}
        MoveOnly(MoveOnly&& other) noexcept : value_(other.value_) { other.value_ = -1; }
        MoveOnly& operator=(MoveOnly&& other) noexcept { value_ = other.value_; other.value_ = -1; return *this; }
        MoveOnly(const MoveOnly&) = delete;
        MoveOnly& operator=(const MoveOnly&) = delete;
        int value() const { return value_; }
    private:
        int value_;
    };

    // Counts destructions so a test can tell whether the right member was destroyed.
    struct Counted
    {
        static int liveCount;
        Counted() { ++liveCount; }
        Counted(const Counted&) { ++liveCount; }
        Counted(Counted&&) noexcept { ++liveCount; }
        Counted& operator=(const Counted&) = default;
        Counted& operator=(Counted&&) noexcept = default;
        ~Counted() { --liveCount; }
    };
    int Counted::liveCount = 0;

    using ClipError = NativeToolkit::Failure<NativeToolkit::ClipboardError>;
    using DlgError  = NativeToolkit::Failure<NativeToolkit::DialogError>;
}

// ---------------------------------------------------------------------------
// Compile-time properties
// ---------------------------------------------------------------------------

// Each feature binds Result to its own error type, so the aliases are distinct
// types and an error cannot be passed from one feature to another by mistake.
static_assert(!std::is_same_v<NativeToolkit::Clipboard::Result<std::wstring>,
                              NativeToolkit::Dialog::Result<std::wstring>>,
              "the per-feature Result aliases must be distinct types");
static_assert(std::is_same_v<NativeToolkit::Clipboard::Result<>,
                             NativeToolkit::Clipboard::Result<void>>,
              "Result<> must mean Result<void>");

// A move-only payload makes the whole Result move only. Session and Manager
// depend on this.
static_assert(!std::is_copy_constructible_v<NativeToolkit::Clipboard::Result<MoveOnly>>,
              "Result<MoveOnly> must not be copyable");
static_assert(std::is_move_constructible_v<NativeToolkit::Clipboard::Result<MoveOnly>>,
              "Result<MoveOnly> must be movable");

// A copyable payload keeps Result copyable.
static_assert(std::is_copy_constructible_v<NativeToolkit::Clipboard::Result<int>>,
              "Result<int> should be copyable");

// Both alternatives trivially destructible means Result is too.
static_assert(std::is_trivially_destructible_v<NativeToolkit::Clipboard::Result<int>>,
              "Result<int> should be trivially destructible");
static_assert(!std::is_trivially_destructible_v<NativeToolkit::Clipboard::Result<std::wstring>>,
              "Result<std::wstring> owns memory and cannot be trivially destructible");

// T == E has to stay unambiguous; Unexpected is what tells the two apart.
static_assert(std::is_constructible_v<NativeToolkit::Result<ClipError, ClipError>, ClipError>,
              "Result<E, E> must accept a value");

// The public headers must not drag in windows.h; WindowHandle is usable anyway.
static_assert(std::is_pointer_v<NativeToolkit::WindowHandle>,
              "WindowHandle must be a pointer");

TEST_CLASS(PublicApiResultTest)
{
public:

    TEST_METHOD(Test_Value_IsReturnedAndHasValueIsTrue)
    {
        NativeToolkit::Clipboard::Result<std::wstring> r{std::wstring(L"hello")};

        Assert::IsTrue(r.has_value());
        Assert::IsTrue(static_cast<bool>(r));
        Assert::AreEqual(std::wstring(L"hello"), r.value());
    }

    TEST_METHOD(Test_Error_CarriesTheFeatureEnumAndSystemCode)
    {
        NativeToolkit::Clipboard::Result<std::wstring> r{
            NativeToolkit::Unexpected{ClipError{NativeToolkit::ClipboardError::Busy, 5u}}};

        Assert::IsFalse(r.has_value());
        Assert::IsFalse(static_cast<bool>(r));
        Assert::IsTrue(NativeToolkit::ClipboardError::Busy == r.error().code);
        Assert::AreEqual(5u, r.error().systemCode);
    }

    TEST_METHOD(Test_VoidResult_DefaultIsSuccess)
    {
        NativeToolkit::Clipboard::Result<> ok{};
        Assert::IsTrue(ok.has_value());

        NativeToolkit::Clipboard::Result<> failed{
            NativeToolkit::Unexpected{ClipError{NativeToolkit::ClipboardError::WrongThread, 0u}}};
        Assert::IsFalse(failed.has_value());
        Assert::IsTrue(NativeToolkit::ClipboardError::WrongThread == failed.error().code);
    }

    TEST_METHOD(Test_ValueOr_ReturnsTheFallbackOnFailure)
    {
        NativeToolkit::Clipboard::Result<int> ok{7};
        NativeToolkit::Clipboard::Result<int> failed{
            NativeToolkit::Unexpected{ClipError{NativeToolkit::ClipboardError::Empty, 0u}}};

        Assert::AreEqual(7, ok.value_or(99));
        Assert::AreEqual(99, failed.value_or(99));
    }

    TEST_METHOD(Test_MoveOnlyPayload_SurvivesAMove)
    {
        NativeToolkit::Clipboard::Result<MoveOnly> r{MoveOnly{42}};
        MoveOnly taken = std::move(r).value();

        Assert::AreEqual(42, taken.value());
    }

    TEST_METHOD(Test_Assignment_DestroysTheMemberThatWasActive)
    {
        Counted::liveCount = 0;
        {
            NativeToolkit::Clipboard::Result<Counted> r{Counted{}};
            Assert::AreEqual(1, Counted::liveCount);

            // Switching to the error side has to destroy the value side.
            r = NativeToolkit::Clipboard::Result<Counted>{
                NativeToolkit::Unexpected{ClipError{NativeToolkit::ClipboardError::Canceled, 0u}}};
            Assert::AreEqual(0, Counted::liveCount);
            Assert::IsFalse(r.has_value());

            // And back again.
            r = NativeToolkit::Clipboard::Result<Counted>{Counted{}};
            Assert::AreEqual(1, Counted::liveCount);
        }
        Assert::AreEqual(0, Counted::liveCount);
    }

    TEST_METHOD(Test_SameTypeForValueAndError_IsUnambiguous)
    {
        const ClipError payload{NativeToolkit::ClipboardError::None, 1u};

        NativeToolkit::Result<ClipError, ClipError> asValue{payload};
        NativeToolkit::Result<ClipError, ClipError> asError{NativeToolkit::Unexpected{payload}};

        Assert::IsTrue(asValue.has_value());
        Assert::IsFalse(asError.has_value());
    }

    TEST_METHOD(Test_WriteOptions_DefaultToNothingExcluded)
    {
        NativeToolkit::WriteOptions options;

        Assert::IsFalse(options.excludeHistory);
        Assert::IsFalse(options.excludeRoaming);
    }
};

}  // namespace NativeToolkitPublicApiTest
