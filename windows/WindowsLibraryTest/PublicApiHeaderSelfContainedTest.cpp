// U-D of the stage 3 design: every header a consumer can include has to compile
// on its own.
//
// This file includes each header first and alone in its own translation unit -
// no pch, no windows.h before it - which is the situation a consumer creates
// when the header is the first thing their .cpp names. The T-03 spike found
// WindowsDialogManagerInternal.h relying on whoever included it to have
// pulled in commdlg.h, which is why the internal headers are covered here too
// and not only the public ones.
//
// There is nothing to assert at run time: the check is that this file builds.
// Deleting an include from one of the headers below breaks the build, which is
// the failure this is meant to catch.

// --- Public headers, with nothing included before them ----------------------
#include "NativeToolkit/Types.h"
#include "NativeToolkit/Error.h"
#include "NativeToolkit/BuildStamp.h"

// --- Internal headers -------------------------------------------------------
#include "Common/CommonInternal.h"
#include "Dialog/WindowsDialogManagerInternal.h"

// --- Public headers again, now that windows.h has arrived through the ones
//     above, to prove they are include-order independent ---------------------
#include "NativeToolkit/Types.h"
#include "NativeToolkit/Error.h"

#include <CppUnitTest.h>
#include <type_traits>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

namespace NativeToolkitPublicApiTest
{

// With windows.h in scope, WindowHandle and HWND have to be the same type; a
// consumer passing an HWND straight into the API depends on it.
static_assert(std::is_same_v<NativeToolkit::WindowHandle, HWND>,
              "WindowHandle must be HWND under the STRICT handle model");

TEST_CLASS(PublicApiHeaderSelfContainedTest)
{
public:

    TEST_METHOD(Test_HeadersCompileStandalone_AndWindowHandleIsHwnd)
    {
        HWND native = nullptr;
        NativeToolkit::WindowHandle handle = native;   // implicit both ways
        HWND back = handle;

        Assert::IsNull(back);
    }
};

}  // namespace NativeToolkitPublicApiTest
