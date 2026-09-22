#include "pch.h"
#include "NativeToolkit/Error.h"
#include "Clipboard/ClipboardCodes.h"
#include "Notification/NotificationCodes.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// C-10 of the stage 3 design: every value of the new enumerations equals the
// C ABI constant it replaces.
//
// Both sides come from the sources - the enumerator from NativeToolkit/Error.h
// and the number from the CLIPBOARD_ERROR_* / NOTIFICATION_* macro - so a value
// that drifts on either side fails to compile rather than passing quietly. The
// count is pinned as well, so adding a case to one side without the other is
// caught too: CLP-86 fixes the clipboard set at twenty values, and the
// notification set at nine.
//
// The dialog enumeration has no C ABI counterpart (that feature passes raw OS
// values today), so it is only checked for its documented size.
// ============================================================================

namespace NativeToolkitPublicApiTest
{

namespace
{
    constexpr uint32_t Value(NativeToolkit::ClipboardError e) { return static_cast<uint32_t>(e); }
    constexpr uint32_t Value(NativeToolkit::NotificationError e) { return static_cast<uint32_t>(e); }
    constexpr uint32_t Value(NativeToolkit::DialogError e) { return static_cast<uint32_t>(e); }
}

// --- Clipboard: twenty values, each equal to its macro ----------------------
static_assert(Value(NativeToolkit::ClipboardError::None)                  == CLIPBOARD_ERROR_NONE);
static_assert(Value(NativeToolkit::ClipboardError::InvalidParameter)      == CLIPBOARD_ERROR_INVALID_PARAMETER);
static_assert(Value(NativeToolkit::ClipboardError::NotInitialized)        == CLIPBOARD_ERROR_NOT_INITIALIZED);
static_assert(Value(NativeToolkit::ClipboardError::Busy)                  == CLIPBOARD_ERROR_BUSY);
static_assert(Value(NativeToolkit::ClipboardError::Empty)                 == CLIPBOARD_ERROR_EMPTY);
static_assert(Value(NativeToolkit::ClipboardError::FormatUnavailable)     == CLIPBOARD_ERROR_FORMAT_UNAVAILABLE);
static_assert(Value(NativeToolkit::ClipboardError::InvalidData)           == CLIPBOARD_ERROR_INVALID_DATA);
static_assert(Value(NativeToolkit::ClipboardError::BufferTooSmall)        == CLIPBOARD_ERROR_BUFFER_TOO_SMALL);
static_assert(Value(NativeToolkit::ClipboardError::OutOfMemory)           == CLIPBOARD_ERROR_OUT_OF_MEMORY);
static_assert(Value(NativeToolkit::ClipboardError::AccessDenied)          == CLIPBOARD_ERROR_ACCESS_DENIED);
static_assert(Value(NativeToolkit::ClipboardError::HistoryDisabled)       == CLIPBOARD_ERROR_HISTORY_DISABLED);
static_assert(Value(NativeToolkit::ClipboardError::ItemDeleted)           == CLIPBOARD_ERROR_ITEM_DELETED);
static_assert(Value(NativeToolkit::ClipboardError::MonitorRegisterFailed) == CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED);
static_assert(Value(NativeToolkit::ClipboardError::PartialState)          == CLIPBOARD_ERROR_PARTIAL_STATE);
static_assert(Value(NativeToolkit::ClipboardError::WrongThread)           == CLIPBOARD_ERROR_WRONG_THREAD);
static_assert(Value(NativeToolkit::ClipboardError::Canceled)              == CLIPBOARD_ERROR_CANCELED);
static_assert(Value(NativeToolkit::ClipboardError::NotSupported)          == CLIPBOARD_ERROR_NOT_SUPPORTED);
static_assert(Value(NativeToolkit::ClipboardError::NotForeground)         == CLIPBOARD_ERROR_NOT_FOREGROUND);
static_assert(Value(NativeToolkit::ClipboardError::WrongApartment)        == CLIPBOARD_ERROR_WRONG_APARTMENT);
static_assert(Value(NativeToolkit::ClipboardError::Unknown)               == CLIPBOARD_ERROR_UNKNOWN);

// CLP-86: the set is closed at twenty. Unknown is the last value, so its number
// plus one is the count; a twenty-first case shifts it and fails here.
static_assert(Value(NativeToolkit::ClipboardError::Unknown) + 1 == 20,
              "the clipboard error set is fixed at twenty values (CLP-86)");

// --- Notification: nine values ---------------------------------------------
static_assert(Value(NativeToolkit::NotificationError::None)             == NOTIFICATION_SUCCESS);
static_assert(Value(NativeToolkit::NotificationError::NotInitialized)   == NOTIFICATION_ERROR_NOT_INITIALIZED);
static_assert(Value(NativeToolkit::NotificationError::Disabled)         == NOTIFICATION_ERROR_DISABLED);
static_assert(Value(NativeToolkit::NotificationError::InvalidPayload)   == NOTIFICATION_ERROR_INVALID_PAYLOAD);
static_assert(Value(NativeToolkit::NotificationError::ProgressNotFound) == NOTIFICATION_ERROR_PROGRESS_NOT_FOUND);
static_assert(Value(NativeToolkit::NotificationError::HResultFailure)   == NOTIFICATION_ERROR_HRESULT_FAILURE);
static_assert(Value(NativeToolkit::NotificationError::BadgeFailed)      == NOTIFICATION_ERROR_BADGE_FAILED);
static_assert(Value(NativeToolkit::NotificationError::InvalidParameter) == NOTIFICATION_ERROR_INVALID_PARAMETER);
static_assert(Value(NativeToolkit::NotificationError::NotSupported)     == NOTIFICATION_ERROR_NOT_SUPPORTED);
static_assert(Value(NativeToolkit::NotificationError::NotSupported) + 1 == 9,
              "the notification error set is fixed at nine values");

// --- Dialog: new in the C++ API --------------------------------------------
static_assert(Value(NativeToolkit::DialogError::Unknown) + 1 == 6,
              "the dialog error set is fixed at six values (design 11.3)");

// --- Write options ----------------------------------------------------------
// The C ABI flags are the two booleans of WriteOptions; SENSITIVE is both set.
static_assert(CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY == 0x1u);
static_assert(CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING == 0x2u);
static_assert((CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY | CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING)
              == CLIPBOARD_WRITE_OPTION_SENSITIVE,
              "SENSITIVE must stay the combination of the two exclusion flags");

TEST_CLASS(PublicApiErrorMappingTest)
{
public:

    // The static_asserts above carry the mapping; this keeps a runtime case so
    // the file reports as a test and a failure is visible in the run.
    TEST_METHOD(Test_EnumValues_MatchTheCAbiConstants)
    {
        Assert::AreEqual<uint32_t>(CLIPBOARD_ERROR_WRONG_APARTMENT,
                                   Value(NativeToolkit::ClipboardError::WrongApartment));
        Assert::AreEqual<uint32_t>(NOTIFICATION_ERROR_NOT_SUPPORTED,
                                   Value(NativeToolkit::NotificationError::NotSupported));
    }
};

}  // namespace NativeToolkitPublicApiTest
