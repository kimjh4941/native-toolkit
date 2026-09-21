#include "pch.h"
#include "Support/ClipboardSessionForTest.h"
#include "Clipboard/WindowsClipboardManager.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"

#include <functional>
#include <string>
#include <thread>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// T-17 for the clipboard, and the guard for T-14.
//
// The notification payload taught this the hard way: what the C ABI does with
// a degenerate input - a null pointer, an empty string, a buffer of the wrong
// size - is a promise as much as what it does with a good one, and it is not
// written down anywhere that re-pointing the bridge would consult.
//
// So these drive the exported C functions themselves, against a clipboard that
// only stores what is put in it, and record the answers before the bridge is
// moved onto the C++ API. They are the thing that has to keep passing.
//
// The buffer convention is the part most at risk (CLP-64, CLP-140): the return
// value is a count of wchar_t for the string APIs and of bytes for the binary
// ones, it includes the terminator where there is one, and zero always means
// an error - it never means "nothing to paste".
// ============================================================================

namespace WindowsClipboardBridgeTest
{

using ClipboardSessionForTest::Check;
using ClipboardSessionForTest::PumpMessages;

namespace
{
    /// Runs the body on an STA thread with the fake clipboard in place and the
    /// C ABI initialised, then closes it however the body left things.
    std::wstring RunInitialised(const std::function<void()>& body)
    {
        std::wstring failure;
        std::thread worker([&] {
            if (FAILED(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) {
                failure = L"CoInitializeEx(STA) failed";
                return;
            }
            ClipboardSessionForTest::StoringClipboard clipboard;
            ClipboardSessionForTest::Current() = &clipboard;
            SetWin32ApiForTest(&clipboard);

            DWORD error = 0xFFFFFFFFu;
            initClipboardManager(nullptr, &error);
            try {
                Check(error == CLIPBOARD_ERROR_NONE, L"initClipboardManager failed");
                body();
            }
            catch (const ClipboardSessionForTest::Failure& f) { failure = f.message; }
            catch (...) { failure = L"the body threw something unknown"; }

            for (int attempt = 0; attempt < 6; ++attempt) {
                DWORD closeError = CLIPBOARD_ERROR_NONE;
                if (uninitClipboardManager(&closeError)) break;
                PumpMessages();
            }
            SetWin32ApiForTest(nullptr);
            ClipboardSessionForTest::Current() = nullptr;
            ::CoUninitialize();
        });
        worker.join();
        return failure;
    }

    DWORD Answer(const std::function<void(DWORD*)>& call)
    {
        DWORD error = 0xFFFFFFFFu;
        call(&error);
        return error;
    }
}

TEST_CLASS(ClipboardBridgeTest)
{
public:

    TEST_METHOD_CLEANUP(ReleaseTheProcess)
    {
        NativeToolkit::Clipboard::Detail::ClipboardTestAccess::ResetProcessState();
    }

    // --- Before anything is initialised --------------------------------------

    TEST_METHOD(Test_BeforeInit_TheSynchronousCallsReportNotInitialized)
    {
        const DWORD expected = CLIPBOARD_ERROR_NOT_INITIALIZED;
        Assert::AreEqual(expected, Answer([](DWORD* e) { copyPlainText(L"x", 0, e); }), L"copyPlainText");
        Assert::AreEqual(expected, Answer([](DWORD* e) { copyHtml(L"<b/>", L"b", 0, e); }), L"copyHtml");
        Assert::AreEqual(expected, Answer([](DWORD* e) { clearClipboard(e); }), L"clearClipboard");
        Assert::AreEqual(expected, Answer([](DWORD* e) { hasClipboardFormat(L"CF_UNICODETEXT", e); }),
                         L"hasClipboardFormat");
        Assert::AreEqual(expected, Answer([](DWORD* e) { recoverDeferredState(e); }), L"recoverDeferredState");
    }

    TEST_METHOD(Test_BeforeInit_ANullArgumentIsStillNotInitialized)
    {
        // The order matters: the initialisation check comes before the
        // argument check, so a null pointer passed to a closed clipboard is
        // NOT_INITIALIZED rather than INVALID_PARAMETER.
        Assert::AreEqual<DWORD>(CLIPBOARD_ERROR_NOT_INITIALIZED,
                                Answer([](DWORD* e) { copyPlainText(nullptr, 0, e); }));
    }

    TEST_METHOD(Test_BeforeInit_UninitSucceedsAndCanDestroyIsTrue)
    {
        DWORD error = 0xFFFFFFFFu;
        Assert::IsTrue(uninitClipboardManager(&error) != FALSE, L"uninit with nothing to close");
        Assert::AreEqual<DWORD>(CLIPBOARD_ERROR_NONE, error);

        error = 0xFFFFFFFFu;
        Assert::IsTrue(canDestroyClipboardManager(&error) != FALSE, L"canDestroy with nothing open");
        Assert::AreEqual<DWORD>(CLIPBOARD_ERROR_NONE, error);
    }

    // --- Initialising twice --------------------------------------------------

    TEST_METHOD(Test_ASecondInitFromTheOwnerThread_Succeeds)
    {
        Run([] {
            // Idempotent, and it does not take a new callback: the C ABI
            // returns before it would assign one (CLP-35..39).
            DWORD error = 0xFFFFFFFFu;
            initClipboardManager(nullptr, &error);
            Check(error == CLIPBOARD_ERROR_NONE, L"a second init from the owner thread");
        });
    }

    TEST_METHOD(Test_AnInitFromAnotherThread_ReportsWrongThread)
    {
        Run([] {
            DWORD error = 0xFFFFFFFFu;
            std::thread elsewhere([&] { initClipboardManager(nullptr, &error); });
            elsewhere.join();
            Check(error == CLIPBOARD_ERROR_WRONG_THREAD, L"an init from another thread");
        });
    }

    TEST_METHOD(Test_UninitFromAnotherThread_ReportsWrongThreadAndReturnsFalse)
    {
        Run([] {
            DWORD error = 0xFFFFFFFFu;
            BOOL closed = TRUE;
            std::thread elsewhere([&] { closed = uninitClipboardManager(&error); });
            elsewhere.join();
            Check(closed == FALSE, L"uninit from another thread returned TRUE");
            Check(error == CLIPBOARD_ERROR_WRONG_THREAD, L"uninit from another thread");
        });
    }

    // --- Arguments the copies refuse ----------------------------------------

    TEST_METHOD(Test_ANullArgument_IsInvalidParameter)
    {
        Run([] {
            const DWORD expected = CLIPBOARD_ERROR_INVALID_PARAMETER;
            Check(Answer([](DWORD* e) { copyPlainText(nullptr, 0, e); }) == expected, L"copyPlainText");
            Check(Answer([](DWORD* e) { copyHtml(nullptr, L"x", 0, e); }) == expected, L"copyHtml");
            Check(Answer([](DWORD* e) { copyFiles(nullptr, 0, e); }) == expected, L"copyFiles");
            Check(Answer([](DWORD* e) { copyImage(nullptr, 4, 0, e); }) == expected, L"copyImage");
            Check(Answer([](DWORD* e) { copyMultipleFormats(nullptr, 0, e); }) == expected,
                  L"copyMultipleFormats");
            Check(Answer([](DWORD* e) { hasClipboardFormat(nullptr, e); }) == expected,
                  L"hasClipboardFormat");
        });
    }

    TEST_METHOD(Test_AnEmptyByteRange_IsInvalidParameter)
    {
        Run([] {
            const BYTE byte = 0;
            const DWORD expected = CLIPBOARD_ERROR_INVALID_PARAMETER;
            Check(Answer([&](DWORD* e) { copyImage(&byte, 0, 0, e); }) == expected,
                  L"copyImage with no bytes");
            Check(Answer([&](DWORD* e) { copyCustomFormat(L"NT.Test", &byte, 0, 0, e); }) == expected,
                  L"copyCustomFormat with no bytes");
            Check(Answer([&](DWORD* e) { copyCustomFormat(nullptr, &byte, 1, 0, e); }) == expected,
                  L"copyCustomFormat with no name");
        });
    }

    TEST_METHOD(Test_AnEmptyFormatName_IsRefused)
    {
        // Not the same as a null one, and worth pinning: an empty name is not
        // a format the OS will register.
        Run([] {
            const BYTE byte = 7;
            const DWORD copied = Answer([&](DWORD* e) { copyCustomFormat(L"", &byte, 1, 0, e); });
            Check(copied != CLIPBOARD_ERROR_NONE, L"an empty format name was accepted");

            // Asking about an empty name is not an error: it is a name no
            // format has, so the answer is simply no. Only a null name is
            // refused. The C++ API must not be stricter here than the C ABI.
            DWORD error = 0xFFFFFFFFu;
            const BOOL present = hasClipboardFormat(L"", &error);
            Check(error == CLIPBOARD_ERROR_NONE, L"an empty name was treated as an error");
            Check(present == FALSE, L"an empty name was reported as present");
        });
    }

    TEST_METHOD(Test_AnEmptyStringIsAValidThingToCopy)
    {
        Run([] {
            Check(Answer([](DWORD* e) { copyPlainText(L"", 0, e); }) == CLIPBOARD_ERROR_NONE,
                  L"copying an empty string");
        });
    }

    // --- The buffer convention ----------------------------------------------

    TEST_METHOD(Test_PasteIntoTooSmallABuffer_ReturnsTheSizeAndSaysSo)
    {
        Run([] {
            Check(Answer([](DWORD* e) { copyPlainText(L"hello", 0, e); }) == CLIPBOARD_ERROR_NONE,
                  L"copyPlainText");

            wchar_t tooSmall[2] = {};
            DWORD error = 0xFFFFFFFFu;
            const DWORD needed = pastePlainText(tooSmall, 2, &error);

            Check(error == CLIPBOARD_ERROR_BUFFER_TOO_SMALL, L"not BUFFER_TOO_SMALL");
            // Characters including the terminator, not bytes.
            Check(needed == 6, L"the required size is wrong");
        });
    }

    TEST_METHOD(Test_PasteIntoABigEnoughBuffer_ReturnsWhatItWrote)
    {
        Run([] {
            Answer([](DWORD* e) { copyPlainText(L"hello", 0, e); });

            wchar_t buffer[32] = {};
            DWORD error = 0xFFFFFFFFu;
            const DWORD written = pastePlainText(buffer, 32, &error);

            Check(error == CLIPBOARD_ERROR_NONE, L"the paste failed");
            Check(written == 6, L"the count is wrong");
            Check(std::wstring(buffer) == L"hello", L"the text is wrong");
        });
    }

    TEST_METHOD(Test_PasteOfAnEmptyString_IsStillOneForTheTerminator)
    {
        // Zero is always an error, so an empty string comes back as 1: the
        // terminator on its own (CLP-140).
        Run([] {
            Answer([](DWORD* e) { copyPlainText(L"", 0, e); });

            wchar_t buffer[8] = {L'x'};
            DWORD error = 0xFFFFFFFFu;
            const DWORD written = pastePlainText(buffer, 8, &error);

            Check(error == CLIPBOARD_ERROR_NONE, L"the paste failed");
            Check(written == 1, L"an empty string did not come back as one");
            Check(buffer[0] == L'\0', L"the terminator was not written");
        });
    }

    TEST_METHOD(Test_PasteWithNothingOnTheClipboard_IsEmptyNotZero)
    {
        Run([] {
            Answer([](DWORD* e) { clearClipboard(e); });

            wchar_t buffer[8] = {};
            DWORD error = 0xFFFFFFFFu;
            const DWORD written = pastePlainText(buffer, 8, &error);

            Check(error != CLIPBOARD_ERROR_NONE, L"an empty clipboard pasted something");
            Check(written == 0, L"a failed paste returned a count");
            // Recorded rather than asserted by name: which of the two failures
            // it is depends on whether the format is absent or the read failed,
            // and the promise a caller relies on is that it is not success and
            // the count is zero.
            Check(error == CLIPBOARD_ERROR_EMPTY || error == CLIPBOARD_ERROR_FORMAT_UNAVAILABLE,
                  L"neither EMPTY nor FORMAT_UNAVAILABLE");
        });
    }

    TEST_METHOD(Test_TheBinaryPasteCountsBytes)
    {
        Run([] {
            const BYTE data[3] = {1, 2, 3};
            Check(Answer([&](DWORD* e) { copyCustomFormat(L"NT.Bridge", data, 3, 0, e); })
                      == CLIPBOARD_ERROR_NONE, L"copyCustomFormat");

            BYTE buffer[8] = {};
            DWORD error = 0xFFFFFFFFu;
            const DWORD written = pasteCustomFormat(L"NT.Bridge", buffer, 8, &error);

            Check(error == CLIPBOARD_ERROR_NONE, L"the paste failed");
            // Bytes, and no terminator: the unit differs from the string APIs.
            Check(written == 3, L"the byte count is wrong");
            Check(buffer[0] == 1 && buffer[2] == 3, L"the bytes are wrong");
        });
    }

    // --- JSON in and out -----------------------------------------------------

    TEST_METHOD(Test_FilesGoInAndComeBackAsJson)
    {
        Run([] {
            Check(Answer([](DWORD* e) {
                      copyFiles(LR"(["C:\\one.txt","C:\\dir\\two.txt"])", 0, e); })
                  == CLIPBOARD_ERROR_NONE, L"copyFiles");

            wchar_t buffer[256] = {};
            DWORD error = 0xFFFFFFFFu;
            const DWORD written = pasteFiles(buffer, 256, &error);

            Check(error == CLIPBOARD_ERROR_NONE, L"pasteFiles failed");
            Check(written > 0, L"pasteFiles returned nothing");
            const std::wstring json{buffer};
            Check(json.front() == L'[' && json.back() == L']', L"not a JSON array");
            Check(json.find(L"one.txt") != std::wstring::npos, L"the first path is missing");
            Check(json.find(L"two.txt") != std::wstring::npos, L"the second path is missing");
        });
    }

    TEST_METHOD(Test_MalformedJson_IsInvalidParameter)
    {
        Run([] {
            const DWORD expected = CLIPBOARD_ERROR_INVALID_PARAMETER;
            Check(Answer([](DWORD* e) { copyFiles(L"not json", 0, e); }) == expected, L"copyFiles");
            Check(Answer([](DWORD* e) { copyMultipleFormats(L"not json", 0, e); }) == expected,
                  L"copyMultipleFormats");
            Check(Answer([](DWORD* e) { reserveDeferredFormats(L"not json", nullptr, nullptr, e); })
                      == expected, L"reserveDeferredFormats");
        });
    }

    TEST_METHOD(Test_GetClipboardFormats_AnswersAJsonArray)
    {
        Run([] {
            Answer([](DWORD* e) { copyPlainText(L"hello", 0, e); });

            wchar_t buffer[1024] = {};
            DWORD error = 0xFFFFFFFFu;
            const DWORD written = getClipboardFormats(buffer, 1024, &error);

            Check(error == CLIPBOARD_ERROR_NONE, L"getClipboardFormats failed");
            Check(written > 0, L"nothing was written");
            Check(std::wstring(buffer).front() == L'[', L"not a JSON array");
        });
    }

    // --- The history ---------------------------------------------------------

    TEST_METHOD(Test_CancellingAnUnknownRequest_IsInvalidParameter)
    {
        Run([] {
            DWORD error = 0xFFFFFFFFu;
            const BOOL cancelled = cancelClipboardRequest(9999, &error);
            Check(cancelled == FALSE, L"an unknown request was cancelled");
            Check(error == CLIPBOARD_ERROR_INVALID_PARAMETER, L"not INVALID_PARAMETER");
        });
    }

    TEST_METHOD(Test_ARequestIdIsNeverZeroWhenItIsAccepted)
    {
        // Zero is how a caller tells a refusal from an acceptance, so an
        // accepted request must never be given it (CLP-06).
        Run([] {
            DWORD error = 0xFFFFFFFFu;
            const uint32_t id = getClipboardHistory(&IgnoreRequest, &error);
            if (error == CLIPBOARD_ERROR_NONE) {
                Check(id != 0, L"an accepted request was given the id zero");
            } else {
                Check(id == 0, L"a refused request was given an id");
            }
        });
    }

private:

    static void IgnoreRequest(uint32_t, DWORD, const wchar_t*) {}

    static void Run(const std::function<void()>& body)
    {
        const std::wstring failure = RunInitialised(body);
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }
};

}  // namespace WindowsClipboardBridgeTest
