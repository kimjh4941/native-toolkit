#include "pch.h"
#include "ClipboardSessionForTest.h"
#include "Clipboard/WindowsClipboardManagerInternal.h"

#include <cstring>
#include <functional>
#include <string>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// U-B and C-12 of the stage 3 design, for the synchronous clipboard core
// (OP-25..OP-39).
//
// These fifteen are the C ABI's fifteen with the encoding taken off the
// caller: no two-call buffer sizing, no JSON in or out. What is worth testing
// is that nothing was lost on the way:
//
//  - what goes in comes back out, for every payload shape (the round trips);
//  - the multi-format write, whose rules about which payload a format may
//    carry lived in the JSON parser, still applies them to the struct (U-B);
//  - a wstring_view is read to its own length and no further, and a NUL
//    inside one is refused rather than quietly truncating the rest (C-12).
//
// The Win32 clipboard is replaced by a fake that stores what is put in it, so
// none of this touches the clipboard of whoever is running the tests. Two
// operations cannot be faked - GetFormats and GetPreferredFormat call
// CountClipboardFormats and GetPriorityClipboardFormat, which are not behind
// the IClipboardWin32Api seam - so those are only checked for answering at
// all, and their contents belong to the C ABI's own tests.
// ============================================================================

namespace WindowsClipboardApiCoreTest
{

namespace Api = NativeToolkit::Clipboard;
using Api::ErrorCode;
using ClipboardSessionForTest::Check;

namespace
{
    std::vector<BYTE> MakeMinimalDib(LONG width, LONG height, WORD bitCount)
    {
        BITMAPINFOHEADER header{};
        header.biSize = sizeof(BITMAPINFOHEADER);
        header.biWidth = width;
        header.biHeight = height;
        header.biPlanes = 1;
        header.biBitCount = bitCount;
        header.biCompression = BI_RGB;

        const size_t stride = ((static_cast<size_t>(width) * bitCount + 31) / 32) * 4;
        std::vector<BYTE> dib(sizeof(BITMAPINFOHEADER) + stride * static_cast<size_t>(height), 0);
        ::memcpy(dib.data(), &header, sizeof(header));
        return dib;
    }

    std::vector<std::byte> AsBytes(const std::vector<BYTE>& raw)
    {
        std::vector<std::byte> bytes(raw.size());
        if (!raw.empty()) ::memcpy(bytes.data(), raw.data(), raw.size());
        return bytes;
    }
}

TEST_CLASS(ClipboardApiCoreTest)
{
public:

    TEST_METHOD_CLEANUP(ReleaseTheProcess)
    {
        Api::Detail::ClipboardTestAccess::ResetProcessState();
    }

    // --- Round trips --------------------------------------------------------

    TEST_METHOD(Test_Text_GoesInAndComesBack)
    {
        Run([](Api::Session& session) {
            Check(session.CopyText(L"hello, clipboard").has_value(), L"CopyText failed");

            const auto pasted = session.PasteText();
            Check(pasted.has_value(), L"PasteText failed");
            Check(pasted.value() == L"hello, clipboard", L"the text came back different");
        });
    }

    TEST_METHOD(Test_EmptyTextIsStillText)
    {
        Run([](Api::Session& session) {
            Check(session.CopyText(L"").has_value(), L"CopyText failed for an empty string");

            const auto pasted = session.PasteText();
            Check(pasted.has_value(), L"PasteText failed");
            Check(pasted.value().empty(), L"an empty string came back as something else");
        });
    }

    TEST_METHOD(Test_Html_GoesInAndComesBackWithoutItsHeader)
    {
        Run([](Api::Session& session) {
            Check(session.CopyHtml(L"<b>bold</b>", L"bold").has_value(), L"CopyHtml failed");

            const auto pasted = session.PasteHtml();
            Check(pasted.has_value(), L"PasteHtml failed");
            Check(pasted.value() == L"<b>bold</b>", L"the fragment came back different");

            // The plain fallback is written too, so a reader that wants text
            // is not left with markup.
            const auto text = session.PasteText();
            Check(text.has_value() && text.value() == L"bold", L"the plain fallback was lost");
        });
    }

    TEST_METHOD(Test_Files_GoInAndComeBack)
    {
        Run([](Api::Session& session) {
            const std::vector<std::wstring> paths{L"C:\\one.txt", L"C:\\dir\\two.txt"};
            Check(session.CopyFiles(paths).has_value(), L"CopyFiles failed");

            const auto pasted = session.PasteFiles();
            Check(pasted.has_value(), L"PasteFiles failed");
            Check(pasted.value().size() == 2, L"the wrong number of paths came back");
            Check(pasted.value()[0] == L"C:\\one.txt", L"the first path came back different");
            Check(pasted.value()[1] == L"C:\\dir\\two.txt", L"the second path came back different");
        });
    }

    TEST_METHOD(Test_Dib_GoesInAndComesBack)
    {
        Run([](Api::Session& session) {
            const std::vector<BYTE> dib = MakeMinimalDib(2, 2, 32);
            Check(session.CopyDib(AsBytes(dib)).has_value(), L"CopyDib failed");

            const auto pasted = session.PasteDib();
            Check(pasted.has_value(), L"PasteDib failed");
            Check(pasted.value().size() == dib.size(), L"the image came back a different size");
            Check(::memcmp(pasted.value().data(), dib.data(), dib.size()) == 0,
                  L"the image came back different");
        });
    }

    TEST_METHOD(Test_CustomBytes_GoInAndComeBack)
    {
        Run([](Api::Session& session) {
            const std::vector<BYTE> raw{0x00, 0x01, 0x7f, 0x80, 0xff};
            Check(session.CopyCustom(L"NativeToolkit.Test", AsBytes(raw)).has_value(),
                  L"CopyCustom failed");

            const auto pasted = session.PasteCustom(L"NativeToolkit.Test");
            Check(pasted.has_value(), L"PasteCustom failed");
            Check(pasted.value().size() == raw.size(), L"the bytes came back a different size");
            Check(::memcmp(pasted.value().data(), raw.data(), raw.size()) == 0,
                  L"the bytes came back different");
        });
    }

    TEST_METHOD(Test_HasFormatAndClear)
    {
        Run([](Api::Session& session) {
            Check(session.CopyText(L"something").has_value(), L"CopyText failed");

            const auto has = session.HasFormat(L"CF_UNICODETEXT");
            Check(has.has_value() && has.value(), L"the text format was not reported");

            Check(session.Clear().has_value(), L"Clear failed");

            const auto after = session.HasFormat(L"CF_UNICODETEXT");
            Check(after.has_value() && !after.value(), L"Clear left the format behind");
        });
    }

    TEST_METHOD(Test_GetFormatsAndPreferredFormat_Answer)
    {
        // These two read the real clipboard, so only that they answer is
        // checked here; what they answer is the C ABI's own ground.
        Run([](Api::Session& session) {
            Check(session.GetFormats().has_value(), L"GetFormats failed");
            Check(session.GetPreferredFormat().has_value(), L"GetPreferredFormat failed");
        });
    }

    // --- Write options ------------------------------------------------------

    TEST_METHOD(Test_WriteOptions_PlaceTheMarkersTheOsReads)
    {
        Run([](Api::Session& session) {
            Api::WriteOptions options;
            options.excludeFromHistory = true;
            options.excludeFromRoaming = true;
            Check(session.CopyText(L"secret", options).has_value(), L"CopyText failed");

            const UINT history = ::RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
            const UINT roaming = ::RegisterClipboardFormatW(L"CanUploadToCloudClipboard");
            Check(ClipboardSessionForTest::Current()->Holds(history), L"the history marker was not placed");
            Check(ClipboardSessionForTest::Current()->Holds(roaming), L"the roaming marker was not placed");
        });
    }

    TEST_METHOD(Test_NoWriteOptions_PlaceNoMarkers)
    {
        Run([](Api::Session& session) {
            Check(session.CopyText(L"ordinary").has_value(), L"CopyText failed");

            const UINT history = ::RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
            const UINT roaming = ::RegisterClipboardFormatW(L"CanUploadToCloudClipboard");
            Check(!ClipboardSessionForTest::Current()->Holds(history), L"a marker was placed without being asked for");
            Check(!ClipboardSessionForTest::Current()->Holds(roaming), L"a marker was placed without being asked for");
        });
    }

    // --- Several formats at once (U-B) --------------------------------------

    TEST_METHOD(Test_CopyMultiple_PlacesEveryItem)
    {
        Run([](Api::Session& session) {
            const std::vector<Api::FormatPayload> items{
                Api::HtmlPayload{L"HTML Format", L"<i>text</i>"},
                Api::TextPayload{L"CF_UNICODETEXT", L"text"},
                Api::BytesPayload{L"NativeToolkit.Test", AsBytes({0x01, 0x02})},
            };
            Check(session.CopyMultiple(items).has_value(), L"CopyMultiple failed");

            const auto html = session.PasteHtml();
            Check(html.has_value() && html.value() == L"<i>text</i>", L"the HTML item was lost");

            const auto text = session.PasteText();
            Check(text.has_value() && text.value() == L"text", L"the text item was lost");

            const auto custom = session.PasteCustom(L"NativeToolkit.Test");
            Check(custom.has_value() && custom.value().size() == 2, L"the bytes item was lost");
        });
    }

    TEST_METHOD(Test_CopyMultiple_MatchesWhatTheJsonPathWrites)
    {
        // U-B. The rules about which payload a format may carry, and how each
        // is encoded, used to live in the JSON parser. This is the check that
        // the struct goes through the same ones: the same description, written
        // both ways, has to leave the same bytes on the clipboard.
        Run([](Api::Session& session) {
            const std::vector<Api::FormatPayload> items{
                Api::HtmlPayload{L"HTML Format", L"<i>text</i>"},
                Api::TextPayload{L"CF_UNICODETEXT", L"text"},
            };
            Check(session.CopyMultiple(items).has_value(), L"CopyMultiple failed");

            const UINT htmlFormat = ::RegisterClipboardFormatW(L"HTML Format");
            const std::vector<BYTE> fromStruct = ClipboardSessionForTest::Current()->BytesOf(htmlFormat);
            const std::vector<BYTE> textFromStruct = ClipboardSessionForTest::Current()->BytesOf(CF_UNICODETEXT);
            Check(!fromStruct.empty(), L"the struct path wrote no HTML");

            DWORD error = CLIPBOARD_ERROR_NONE;
            ClipboardManager::GetInstance().CopyMultipleFormats(
                LR"([{"format":"HTML Format","html":"<i>text</i>"},)"
                LR"({"format":"CF_UNICODETEXT","text":"text"}])",
                CLIPBOARD_WRITE_OPTION_NONE, &error);
            Check(error == CLIPBOARD_ERROR_NONE, L"the JSON path was refused");

            Check(ClipboardSessionForTest::Current()->BytesOf(htmlFormat) == fromStruct,
                  L"the two paths wrote different HTML bytes");
            Check(ClipboardSessionForTest::Current()->BytesOf(CF_UNICODETEXT) == textFromStruct,
                  L"the two paths wrote different text bytes");
        });
    }

    TEST_METHOD(Test_CopyMultiple_TheSameFormatTwice_IsRefusedBeforeAnythingIsPlaced)
    {
        Run([](Api::Session& session) {
            Check(session.CopyText(L"still here").has_value(), L"CopyText failed");

            const std::vector<Api::FormatPayload> items{
                Api::TextPayload{L"CF_UNICODETEXT", L"one"},
                Api::TextPayload{L"CF_UNICODETEXT", L"two"},
            };
            const auto result = session.CopyMultiple(items);

            Check(!result.has_value(), L"a duplicate format was accepted");
            Check(ErrorCode::InvalidParameter == result.error().code, L"not InvalidParameter");

            const auto text = session.PasteText();
            Check(text.has_value() && text.value() == L"still here",
                  L"the refused write emptied the clipboard anyway");
        });
    }

    TEST_METHOD(Test_CopyMultiple_APayloadTheFormatCannotCarry_IsRefused)
    {
        Run([](Api::Session& session) {
            // CF_BITMAP is a handle format; it cannot be written as bytes
            // (CLP-137).
            const std::vector<Api::FormatPayload> items{
                Api::BytesPayload{L"CF_BITMAP", AsBytes({0x01})},
            };
            const auto result = session.CopyMultiple(items);

            Check(!result.has_value(), L"a payload the format cannot carry was accepted");
            Check(ErrorCode::InvalidParameter == result.error().code, L"not InvalidParameter");
        });
    }

    TEST_METHOD(Test_CopyMultiple_BytesThatAreNotADib_AreRefused)
    {
        Run([](Api::Session& session) {
            const std::vector<Api::FormatPayload> items{
                Api::BytesPayload{L"CF_DIB", AsBytes({0x01, 0x02, 0x03})},
            };
            const auto result = session.CopyMultiple(items);

            Check(!result.has_value(), L"a malformed image was accepted");
            Check(ErrorCode::InvalidData == result.error().code, L"not InvalidData");
        });
    }

    // --- Borrowed strings (C-12) --------------------------------------------

    TEST_METHOD(Test_AViewIntoALargerString_IsReadToItsOwnLength)
    {
        // The view is not NUL terminated and there is more text after it; only
        // what the view covers may be written.
        Run([](Api::Session& session) {
            const std::wstring backing = L"prefix[middle]suffix";
            const std::wstring_view middle(backing.data() + 7, 6);
            Check(middle == L"middle", L"the test's own view is wrong");

            Check(session.CopyText(middle).has_value(), L"CopyText failed");

            const auto pasted = session.PasteText();
            Check(pasted.has_value(), L"PasteText failed");
            Check(pasted.value() == L"middle", L"the write ran past the end of the view");
        });
    }

    TEST_METHOD(Test_AViewWithAnEmbeddedNul_IsRefused)
    {
        // The clipboard formats underneath end at the first NUL, so the rest
        // could not be written; saying so beats writing a prefix.
        Run([](Api::Session& session) {
            const std::wstring backing(L"before\0after", 12);
            const std::wstring_view view(backing.data(), backing.size());

            const auto result = session.CopyText(view);

            Check(!result.has_value(), L"a string with an embedded NUL was accepted");
            Check(ErrorCode::InvalidParameter == result.error().code, L"not InvalidParameter");
        });
    }

    TEST_METHOD(Test_EveryBorrowedArgument_RefusesAnEmbeddedNul)
    {
        Run([](Api::Session& session) {
            const std::wstring backing(L"bad\0name", 8);
            const std::wstring_view view(backing.data(), backing.size());

            Check(!session.CopyText(view).has_value(), L"CopyText accepted it");
            Check(!session.CopyHtml(view, L"plain").has_value(), L"CopyHtml accepted a bad fragment");
            Check(!session.CopyHtml(L"<b>x</b>", view).has_value(), L"CopyHtml accepted a bad fallback");
            Check(!session.CopyCustom(view, {}).has_value(), L"CopyCustom accepted it");
            Check(!session.PasteCustom(view).has_value(), L"PasteCustom accepted it");
            Check(!session.HasFormat(view).has_value(), L"HasFormat accepted it");
        });
    }

    // --- A session that is not open -----------------------------------------

    TEST_METHOD(Test_EveryOperationOnAClosedSession_ReportsNotInitialized)
    {
        Run([](Api::Session& session) {
            Check(session.Close().has_value(), L"Close failed");

            Check(NotInitialized(session.CopyText(L"x")), L"CopyText");
            Check(NotInitialized(session.PasteText()), L"PasteText");
            Check(NotInitialized(session.CopyHtml(L"<b>x</b>", L"x")), L"CopyHtml");
            Check(NotInitialized(session.PasteHtml()), L"PasteHtml");
            Check(NotInitialized(session.CopyFiles(std::vector<std::wstring>{L"C:\\x"})), L"CopyFiles");
            Check(NotInitialized(session.PasteFiles()), L"PasteFiles");
            Check(NotInitialized(session.CopyDib({})), L"CopyDib");
            Check(NotInitialized(session.PasteDib()), L"PasteDib");
            Check(NotInitialized(session.CopyCustom(L"x", {})), L"CopyCustom");
            Check(NotInitialized(session.PasteCustom(L"x")), L"PasteCustom");
            Check(NotInitialized(session.CopyMultiple({})), L"CopyMultiple");
            Check(NotInitialized(session.HasFormat(L"x")), L"HasFormat");
            Check(NotInitialized(session.GetFormats()), L"GetFormats");
            Check(NotInitialized(session.GetPreferredFormat()), L"GetPreferredFormat");
            Check(NotInitialized(session.Clear()), L"Clear");
        });
    }

private:

    template <class T>
    static bool NotInitialized(const Api::Result<T>& result)
    {
        return !result.has_value() && ErrorCode::NotInitialized == result.error().code;
    }

    static void Run(const std::function<void(Api::Session&)>& body)
    {
        const std::wstring failure = ClipboardSessionForTest::Run(body);
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }
};

}  // namespace WindowsClipboardApiCoreTest
