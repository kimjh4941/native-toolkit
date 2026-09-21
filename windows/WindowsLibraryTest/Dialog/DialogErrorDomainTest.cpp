#include "pch.h"
#include "Dialog/Domain/WindowsDialogError.h"
#include <windows.h>
#include <commdlg.h>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// U-C of the stage 3 design, for the part that can be tested without showing a
// dialog: how a raw outcome of the Win32 dialogs becomes a DialogError.
//
// The C ABI has no error space of its own. It returns TRUE even when the user
// cancels and marks that case by writing -1 to *pError (DLG-01, DLG-08), so a
// caller cannot tell "chose nothing" from "failed" without reading that
// sentinel. The classification below is what gives the C++ API those as
// separate cases, and the raw value stays in systemCode either way.
// ============================================================================

namespace WindowsDialogErrorDomainTest
{

namespace Domain = NativeToolkit::Dialog::Domain;
using NativeToolkit::DialogError;

TEST_CLASS(DialogErrorDomainTest)
{
public:

    TEST_METHOD(Test_Success_IsNone)
    {
        const auto result = Domain::Classify(true, 0u);

        Assert::IsTrue(DialogError::None == result.code);
        Assert::AreEqual(0u, result.systemCode);
        Assert::IsTrue(Domain::Succeeded(result));
    }

    TEST_METHOD(Test_CancelSentinel_IsCanceled)
    {
        // The C ABI writes -1 and still returns TRUE for the single-select
        // dialogs, so the sentinel has to win over the success flag.
        const auto asSuccess = Domain::Classify(true, Domain::kCanceledSentinel);
        const auto asFailure = Domain::Classify(false, Domain::kCanceledSentinel);

        Assert::IsTrue(DialogError::Canceled == asSuccess.code);
        Assert::IsTrue(DialogError::Canceled == asFailure.code);
        Assert::IsFalse(Domain::Succeeded(asSuccess));
    }

    TEST_METHOD(Test_CommonDialogError_IsSystemErrorAndKeepsTheRawValue)
    {
        const auto result = Domain::Classify(false, CDERR_MEMALLOCFAILURE);

        Assert::IsTrue(DialogError::SystemError == result.code);
        Assert::AreEqual<uint32_t>(CDERR_MEMALLOCFAILURE, result.systemCode);
    }

    TEST_METHOD(Test_InsufficientBuffer_IsSystemErrorAndKeepsTheRawValue)
    {
        // The folder dialogs report a too-small buffer this way (DLG-17).
        const auto result = Domain::Classify(false, ERROR_INSUFFICIENT_BUFFER);

        Assert::IsTrue(DialogError::SystemError == result.code);
        Assert::AreEqual<uint32_t>(ERROR_INSUFFICIENT_BUFFER, result.systemCode);
    }

    TEST_METHOD(Test_FailureWithoutARawValue_IsUnknown)
    {
        // GetOpenFileNameW returning FALSE with CommDlgExtendedError() == 0 is
        // how a cancel looks at the Win32 level; the bridge turns that into the
        // sentinel, so reaching here means something failed with nothing to
        // report.
        const auto result = Domain::Classify(false, 0u);

        Assert::IsTrue(DialogError::Unknown == result.code);
        Assert::AreEqual(0u, result.systemCode);
    }

    TEST_METHOD(Test_SentinelValue_MatchesWhatTheCAbiWrites)
    {
        // DLG-08: the C ABI documents the cancel marker as -1 in a DWORD.
        Assert::AreEqual(static_cast<uint32_t>(-1), Domain::kCanceledSentinel);
    }
};

}  // namespace WindowsDialogErrorDomainTest
