#include "pch.h"
#include <shlobj.h> // DROPFILES
#include "../WindowsLibrary/WindowsClipboardFormats.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace ClipboardFormats;

namespace WindowsClipboardFormatsTest
{

namespace
{
    std::vector<BYTE> MakeMinimalDib(LONG width, LONG height, WORD bitCount)
    {
        BITMAPINFOHEADER hdr{};
        hdr.biSize = sizeof(BITMAPINFOHEADER);
        hdr.biWidth = width;
        hdr.biHeight = height;
        hdr.biPlanes = 1;
        hdr.biBitCount = bitCount;
        hdr.biCompression = BI_RGB;

        const size_t stride = ((static_cast<size_t>(width) * bitCount + 31) / 32) * 4;
        std::vector<BYTE> out(sizeof(BITMAPINFOHEADER) + stride * static_cast<size_t>(height), 0);
        memcpy(out.data(), &hdr, sizeof(hdr));
        return out;
    }

    std::vector<BYTE> MakeMinimalRleDib(LONG width, LONG height, WORD bitCount, DWORD compression)
    {
        BITMAPINFOHEADER hdr{};
        hdr.biSize = sizeof(BITMAPINFOHEADER);
        hdr.biWidth = width;
        hdr.biHeight = height;
        hdr.biPlanes = 1;
        hdr.biBitCount = bitCount;
        hdr.biCompression = compression;
        hdr.biSizeImage = 2;

        const size_t paletteEntries = static_cast<size_t>(1) << bitCount;
        std::vector<BYTE> out(sizeof(BITMAPINFOHEADER) + paletteEntries * sizeof(RGBQUAD) + 2, 0);
        memcpy(out.data(), &hdr, sizeof(hdr));
        out[out.size() - 2] = 0;
        out[out.size() - 1] = 1; // end-of-bitmap escape
        return out;
    }
}

TEST_CLASS(ClipboardFormatsTest)
{
public:
    // ---------------- Checked arithmetic ----------------

    TEST_METHOD(Test_CheckedAdd_Overflow_ReturnsFalse)
    {
        size_t out = 0;
        Assert::IsFalse(CheckedAdd(SIZE_MAX, 1, out));
        Assert::IsTrue(CheckedAdd(SIZE_MAX - 1, 1, out));
        Assert::AreEqual(SIZE_MAX, out);
    }

    TEST_METHOD(Test_CheckedMul_Overflow_ReturnsFalse)
    {
        size_t out = 0;
        Assert::IsFalse(CheckedMul(SIZE_MAX, 2, out));
        Assert::IsTrue(CheckedMul(0, SIZE_MAX, out));
        Assert::AreEqual(static_cast<size_t>(0), out);
    }

    TEST_METHOD(Test_CheckedToInt_OutOfRange_ReturnsFalse)
    {
        int out = 0;
        Assert::IsFalse(CheckedToInt(static_cast<size_t>(INT_MAX) + 1, out));
        Assert::IsTrue(CheckedToInt(static_cast<size_t>(INT_MAX), out));
        Assert::AreEqual(INT_MAX, out);
    }

    TEST_METHOD(Test_CheckedToUInt_OutOfRange_ReturnsFalse)
    {
        UINT out = 0;
        Assert::IsFalse(CheckedToUInt(static_cast<size_t>(UINT_MAX) + 1, out));
        Assert::IsTrue(CheckedToUInt(static_cast<size_t>(UINT_MAX), out));
    }

    // ---------------- CF_HTML ----------------

    TEST_METHOD(Test_BuildCfHtml_And_ParseCfHtmlHeader_RoundTrips)
    {
        const std::string fragment = "<b>hello</b>";
        const std::string payload = BuildCfHtml(fragment);
        Assert::IsFalse(payload.empty());

        CfHtmlOffsets off{};
        Assert::IsTrue(ParseCfHtmlHeader(payload, off));
        const std::string roundTrip = payload.substr(off.startFragment, off.endFragment - off.startFragment);
        Assert::AreEqual(fragment, roundTrip);
    }

    TEST_METHOD(Test_BuildCfHtml_FragmentContainsMarkerText_DoesNotTruncate)
    {
        const std::string fragment = "before <!--EndFragment--> after";
        const std::string payload = BuildCfHtml(fragment);
        Assert::IsFalse(payload.empty());

        CfHtmlOffsets off{};
        Assert::IsTrue(ParseCfHtmlHeader(payload, off));
        const std::string roundTrip = payload.substr(off.startFragment, off.endFragment - off.startFragment);
        Assert::AreEqual(fragment, roundTrip);
    }

    TEST_METHOD(Test_ParseCfHtmlHeader_MissingRequiredKey_ReturnsFalse)
    {
        const std::string payload =
            "Version:1.0\r\nStartHTML:0000000023\r\nEndHTML:0000000100\r\n"
            "StartFragment:0000000023\r\n"; // EndFragment missing
        CfHtmlOffsets off{};
        Assert::IsFalse(ParseCfHtmlHeader(payload, off));
    }

    TEST_METHOD(Test_ParseCfHtmlHeader_DuplicateKnownKey_ReturnsFalse)
    {
        std::string payload = BuildCfHtml("x");
        // Duplicate the Version: line.
        payload = "Version:1.0\r\n" + payload;
        CfHtmlOffsets off{};
        Assert::IsFalse(ParseCfHtmlHeader(payload, off));
    }

    TEST_METHOD(Test_ParseCfHtmlHeader_InvalidNumericValue_ReturnsFalse)
    {
        const std::string bad1 =
            "Version:1.0\r\nStartHTML:-10\r\nEndHTML:0000000100\r\n"
            "StartFragment:0000000023\r\nEndFragment:0000000050\r\n<html></html>";
        CfHtmlOffsets off1{};
        Assert::IsFalse(ParseCfHtmlHeader(bad1, off1));

        const std::string bad2 =
            "Version:1.0\r\nStartHTML:0000000023\r\nEndHTML:0000000100\r\n"
            "StartFragment:123x\r\nEndFragment:0000000050\r\n<html></html>";
        CfHtmlOffsets off2{};
        Assert::IsFalse(ParseCfHtmlHeader(bad2, off2));
    }

    TEST_METHOD(Test_ParseCfHtmlHeader_UnknownOrEmptyVersion_ReturnsFalse)
    {
        const std::string empty =
            "Version:\r\nStartHTML:0000000023\r\nEndHTML:0000000100\r\n"
            "StartFragment:0000000023\r\nEndFragment:0000000050\r\n";
        CfHtmlOffsets off1{};
        Assert::IsFalse(ParseCfHtmlHeader(empty, off1));

        const std::string unknown =
            "Version:2.0\r\nStartHTML:0000000023\r\nEndHTML:0000000100\r\n"
            "StartFragment:0000000023\r\nEndFragment:0000000050\r\n";
        CfHtmlOffsets off2{};
        Assert::IsFalse(ParseCfHtmlHeader(unknown, off2));
    }

    TEST_METHOD(Test_ParseCfHtmlHeader_StartHtmlInsideHeader_ReturnsFalse)
    {
        // StartHTML points inside the header block itself (reordered/forged input).
        const std::string bad =
            "Version:1.0\r\nStartHTML:0000000005\r\nEndHTML:0000000100\r\n"
            "StartFragment:0000000023\r\nEndFragment:0000000050\r\n<html></html>";
        CfHtmlOffsets off{};
        Assert::IsFalse(ParseCfHtmlHeader(bad, off));
    }

    TEST_METHOD(Test_ParseCfHtmlHeader_KnownKeyOutsideHeaderRange_IsIgnored)
    {
        // "Version:" appears again inside the HTML body - must not be re-parsed as a header line.
        const std::string payload = BuildCfHtml("Version:9.9 in the body");
        CfHtmlOffsets off{};
        Assert::IsTrue(ParseCfHtmlHeader(payload, off));
    }

    TEST_METHOD(Test_ParseCfHtmlHeader_Selection_OnlyOneSide_ReturnsFalse)
    {
        const std::string bad =
            "Version:1.0\r\nStartHTML:0000000023\r\nEndHTML:0000000100\r\n"
            "StartFragment:0000000023\r\nEndFragment:0000000050\r\nStartSelection:0000000030\r\n";
        CfHtmlOffsets off{};
        Assert::IsFalse(ParseCfHtmlHeader(bad, off));
    }

    // ---------------- CF_HDROP / DROPFILES ----------------

    TEST_METHOD(Test_BuildDropFiles_And_ValidateDropFiles_RoundTrips)
    {
        std::vector<std::wstring> paths{ L"C:\\a.txt", L"C:\\b.txt" };
        std::vector<BYTE> block;
        Assert::IsTrue(BuildDropFiles(paths, block));
        Assert::IsTrue(ValidateDropFiles(block.data(), block.size()));
    }

    TEST_METHOD(Test_BuildDropFiles_EmptyList_ReturnsFalse)
    {
        std::vector<std::wstring> paths;
        std::vector<BYTE> block;
        Assert::IsFalse(BuildDropFiles(paths, block));
    }

    TEST_METHOD(Test_ValidateDropFiles_TruncatedBuffer_ReturnsFalse)
    {
        std::vector<std::wstring> paths{ L"C:\\a.txt" };
        std::vector<BYTE> block;
        Assert::IsTrue(BuildDropFiles(paths, block));
        block.resize(block.size() - 4); // cut off the terminator
        Assert::IsFalse(ValidateDropFiles(block.data(), block.size()));
    }

    TEST_METHOD(Test_ValidateDropFiles_WrongPFilesOffset_ReturnsFalse)
    {
        std::vector<std::wstring> paths{ L"C:\\a.txt" };
        std::vector<BYTE> block;
        Assert::IsTrue(BuildDropFiles(paths, block));
        auto* df = reinterpret_cast<DROPFILES*>(block.data());
        df->pFiles = 9999; // out-of-range
        Assert::IsFalse(ValidateDropFiles(block.data(), block.size()));
    }

    // ---------------- CF_DIB ----------------

    TEST_METHOD(Test_ValidateDib_WellFormed_ReturnsTrue)
    {
        auto dib = MakeMinimalDib(4, 4, 24);
        Assert::IsTrue(ValidateDib(dib.data(), dib.size()));
    }

    TEST_METHOD(Test_ValidateDib_BadBitCount_ReturnsFalse)
    {
        auto dib = MakeMinimalDib(4, 4, 24);
        auto* hdr = reinterpret_cast<BITMAPINFOHEADER*>(dib.data());
        hdr->biBitCount = 7; // not a valid bit count
        Assert::IsFalse(ValidateDib(dib.data(), dib.size()));
    }

    TEST_METHOD(Test_ValidateDib_TruncatedPixelData_ReturnsFalse)
    {
        auto dib = MakeMinimalDib(4, 4, 24);
        dib.resize(dib.size() - 1);
        Assert::IsFalse(ValidateDib(dib.data(), dib.size()));
    }

    TEST_METHOD(Test_ValidateDib_BadPlanes_ReturnsFalse)
    {
        auto dib = MakeMinimalDib(4, 4, 24);
        auto* hdr = reinterpret_cast<BITMAPINFOHEADER*>(dib.data());
        hdr->biPlanes = 2;
        Assert::IsFalse(ValidateDib(dib.data(), dib.size()));
    }

    TEST_METHOD(Test_ValidateDib_ZeroWidth_ReturnsFalse)
    {
        auto dib = MakeMinimalDib(4, 4, 24);
        reinterpret_cast<BITMAPINFOHEADER*>(dib.data())->biWidth = 0;
        Assert::IsFalse(ValidateDib(dib.data(), dib.size()));
    }

    TEST_METHOD(Test_ValidateDib_RleBitDepthMismatch_ReturnsFalse)
    {
        auto rle8With4Bpp = MakeMinimalRleDib(4, 4, 4, BI_RLE8);
        auto rle4With8Bpp = MakeMinimalRleDib(4, 4, 8, BI_RLE4);
        Assert::IsFalse(ValidateDib(rle8With4Bpp.data(), rle8With4Bpp.size()));
        Assert::IsFalse(ValidateDib(rle4With8Bpp.data(), rle4With8Bpp.size()));
    }

    TEST_METHOD(Test_ValidateDib_TruncatedRlePayload_ReturnsFalse)
    {
        auto dib = MakeMinimalRleDib(4, 4, 8, BI_RLE8);
        reinterpret_cast<BITMAPINFOHEADER*>(dib.data())->biSizeImage = 8;
        Assert::IsFalse(ValidateDib(dib.data(), dib.size()));
    }

    TEST_METHOD(Test_ValidateDib_RleWithoutEndMarker_ReturnsFalse)
    {
        auto dib = MakeMinimalRleDib(4, 4, 4, BI_RLE4);
        dib.back() = 0;
        Assert::IsFalse(ValidateDib(dib.data(), dib.size()));
    }

    TEST_METHOD(Test_ValidateDib_WellFormedRle_ReturnsTrue)
    {
        auto dib = MakeMinimalRleDib(4, 4, 8, BI_RLE8);
        Assert::IsTrue(ValidateDib(dib.data(), dib.size()));
    }

    // ---------------- copyMultipleFormats payload rules ----------------

    TEST_METHOD(Test_MultiFormatPayloadRules_StandardFormatsAcceptOnlyTheirRepresentation)
    {
        Assert::IsTrue(IsMultiFormatPayloadAllowed(L"CF_UNICODETEXT", CF_UNICODETEXT,
                                                   MultiFormatPayloadKind::Text));
        Assert::IsFalse(IsMultiFormatPayloadAllowed(L"CF_UNICODETEXT", CF_UNICODETEXT,
                                                    MultiFormatPayloadKind::Html));
        Assert::IsTrue(IsMultiFormatPayloadAllowed(L"CF_TEXT", CF_TEXT,
                                                   MultiFormatPayloadKind::Text));
        Assert::IsTrue(IsMultiFormatPayloadAllowed(L"HTML Format", 0xC123,
                                                   MultiFormatPayloadKind::Html));
        Assert::IsFalse(IsMultiFormatPayloadAllowed(L"HTML Format", 0xC123,
                                                    MultiFormatPayloadKind::Text));
        Assert::IsTrue(IsMultiFormatPayloadAllowed(L"CF_DIB", CF_DIB,
                                                   MultiFormatPayloadKind::Base64));
        Assert::IsFalse(IsMultiFormatPayloadAllowed(L"CF_HDROP", CF_HDROP,
                                                    MultiFormatPayloadKind::Text));
    }

    TEST_METHOD(Test_MultiFormatPayloadRules_BitmapRejectedAndCustomRequiresBase64)
    {
        Assert::IsFalse(IsMultiFormatPayloadAllowed(L"CF_BITMAP", CF_BITMAP,
                                                    MultiFormatPayloadKind::Base64));
        Assert::IsTrue(IsMultiFormatPayloadAllowed(L"Custom.Format", 0xC123,
                                                   MultiFormatPayloadKind::Base64));
        Assert::IsFalse(IsMultiFormatPayloadAllowed(L"Custom.Format", 0xC123,
                                                    MultiFormatPayloadKind::Text));
    }

    // ---------------- CF_UNICODETEXT ----------------

    TEST_METHOD(Test_ValidateUnicodeTextBlock_NoTerminator_ReturnsFalse)
    {
        std::wstring text = L"hello";
        std::vector<BYTE> block(reinterpret_cast<const BYTE*>(text.data()),
                                reinterpret_cast<const BYTE*>(text.data()) + text.size() * sizeof(wchar_t));
        size_t chars = 0;
        Assert::IsFalse(ValidateUnicodeTextBlock(block.data(), block.size(), chars));
    }

    TEST_METHOD(Test_ValidateUnicodeTextBlock_NotMultipleOfWcharSize_ReturnsFalse)
    {
        std::vector<BYTE> block(3, 0);
        size_t chars = 0;
        Assert::IsFalse(ValidateUnicodeTextBlock(block.data(), block.size(), chars));
    }

    TEST_METHOD(Test_ValidateUnicodeTextBlock_WellFormed_ReturnsTrue)
    {
        std::wstring text = L"hi";
        std::vector<BYTE> block(reinterpret_cast<const BYTE*>(text.c_str()),
                                reinterpret_cast<const BYTE*>(text.c_str()) + (text.size() + 1) * sizeof(wchar_t));
        size_t chars = 0;
        Assert::IsTrue(ValidateUnicodeTextBlock(block.data(), block.size(), chars));
        Assert::AreEqual(static_cast<size_t>(2), chars);
    }

    // ---------------- UTF-8 / UTF-16 ----------------

    TEST_METHOD(Test_WideToUtf8_Utf8ToWide_RoundTrips)
    {
        // Built from explicit code points (rather than a literal) so this source
        // file itself stays pure ASCII regardless of compiler source-charset flags.
        const std::wstring original = L"hello " + std::wstring(1, static_cast<wchar_t>(0x65e5))
                                                 + std::wstring(1, static_cast<wchar_t>(0x672c))
                                                 + std::wstring(1, static_cast<wchar_t>(0x8a9e));
        const std::string utf8 = WideToUtf8(original);
        const std::wstring back = Utf8ToWide(utf8);
        Assert::IsTrue(original == back);
    }

    // ---------------- Base64 (M1, 2026-07-29 v2 review) ----------------

    TEST_METHOD(Test_Base64Decode_NoPadding_RoundTrips)
    {
        // "Man" -> "TWFu" (classic RFC 4648 example, 3 bytes / no padding)
        std::vector<BYTE> out;
        Assert::IsTrue(Base64Decode("TWFu", out));
        const std::vector<BYTE> expected{ 'M', 'a', 'n' };
        Assert::IsTrue(out == expected);
    }

    TEST_METHOD(Test_Base64Decode_OnePad_RoundTrips)
    {
        // "Ma" -> "TWE=" (2 bytes / one '=' pad)
        std::vector<BYTE> out;
        Assert::IsTrue(Base64Decode("TWE=", out));
        const std::vector<BYTE> expected{ 'M', 'a' };
        Assert::IsTrue(out == expected);
    }

    TEST_METHOD(Test_Base64Decode_TwoPad_RoundTrips)
    {
        // "M" -> "TQ==" (1 byte / two '=' pad)
        std::vector<BYTE> out;
        Assert::IsTrue(Base64Decode("TQ==", out));
        const std::vector<BYTE> expected{ 'M' };
        Assert::IsTrue(out == expected);
    }

    TEST_METHOD(Test_Base64Decode_WrongLength_ReturnsFalse)
    {
        std::vector<BYTE> out;
        Assert::IsFalse(Base64Decode("TWF", out)); // not a multiple of 4
    }

    TEST_METHOD(Test_Base64Decode_InvalidCharacter_ReturnsFalse)
    {
        std::vector<BYTE> out;
        Assert::IsFalse(Base64Decode("T!Fu", out));
    }

    TEST_METHOD(Test_Base64Decode_PaddingInWrongPosition_ReturnsFalse)
    {
        std::vector<BYTE> out;
        Assert::IsFalse(Base64Decode("T=Fu", out));  // '=' in position 1
        Assert::IsFalse(Base64Decode("TW=u", out));  // '=' in position 2 without position 3 also padded
        Assert::IsFalse(Base64Decode("TWFu====", out)); // padding not confined to the final quantum
    }

    TEST_METHOD(Test_Base64Decode_EmptyInput_ReturnsFalse)
    {
        std::vector<BYTE> out;
        Assert::IsFalse(Base64Decode("", out));
    }
};

} // namespace WindowsClipboardFormatsTest
