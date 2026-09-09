#include "pch.h"
#include "WindowsClipboardFormats.h"
#include <climits>
#include <cstdio>
#include <cstring>

namespace ClipboardFormats
{
    bool CheckedAdd(size_t a, size_t b, size_t& out)
    {
        if (a > SIZE_MAX - b) return false;
        out = a + b;
        return true;
    }

    bool CheckedMul(size_t a, size_t b, size_t& out)
    {
        if (a != 0 && b > SIZE_MAX / a) return false;
        out = a * b;
        return true;
    }

    bool CheckedToInt(size_t v, int& out)
    {
        if (v > static_cast<size_t>(INT_MAX)) return false;
        out = static_cast<int>(v);
        return true;
    }

    bool CheckedToUInt(size_t v, UINT& out)
    {
        if (v > static_cast<size_t>(UINT_MAX)) return false;
        out = static_cast<UINT>(v);
        return true;
    }

    // ------------------------------------------------------------------
    // CF_HTML
    // ------------------------------------------------------------------

    namespace
    {
        constexpr char kPrefix[] = "<html><body>";
        constexpr char kSuffix[] = "</body></html>";
        constexpr char kFragStart[] = "<!--StartFragment-->";
        constexpr char kFragEnd[] = "<!--EndFragment-->";
    }

    std::string BuildCfHtml(const std::string& utf8Fragment)
    {
        const std::string body = std::string(kPrefix) + kFragStart + utf8Fragment + kFragEnd + kSuffix;

        char header[160] = {};
        const int headerLen = ::sprintf_s(header, "Version:1.0\r\nStartHTML:%010d\r\nEndHTML:%010d\r\n"
                                          "StartFragment:%010d\r\nEndFragment:%010d\r\n", 0, 0, 0, 0);
        if (headerLen <= 0) return {};

        const size_t base = static_cast<size_t>(headerLen);
        size_t startFragSz = 0, endFragSz = 0, endHtmlSz = 0;

        // StartFragment = header + "<html><body>" + "<!--StartFragment-->"
        if (!CheckedAdd(base, sizeof(kPrefix) - 1, startFragSz)) return {};
        if (!CheckedAdd(startFragSz, sizeof(kFragStart) - 1, startFragSz)) return {};
        // EndFragment = StartFragment + fragment length
        if (!CheckedAdd(startFragSz, utf8Fragment.size(), endFragSz)) return {};
        if (!CheckedAdd(base, body.size(), endHtmlSz)) return {};

        int startHtml = 0, startFrag = 0, endFrag = 0, endHtml = 0;
        if (!CheckedToInt(base, startHtml)) return {};
        if (!CheckedToInt(startFragSz, startFrag)) return {};
        if (!CheckedToInt(endFragSz, endFrag)) return {};
        if (!CheckedToInt(endHtmlSz, endHtml)) return {};

        if (::sprintf_s(header, "Version:1.0\r\nStartHTML:%010d\r\nEndHTML:%010d\r\n"
                        "StartFragment:%010d\r\nEndFragment:%010d\r\n",
                        startHtml, endHtml, startFrag, endFrag) != headerLen)
        {
            return {};
        }
        return std::string(header) + body;
    }

    namespace
    {
        struct HeaderField
        {
            bool present = false;
            bool isMinusOne = false;
            size_t value = 0;
        };

        // Parses "<value>" for an already-identified key. The value must consume the
        // whole remainder of the line, so "-10" and "123x" are rejected. A key seen
        // twice is rejected by the caller (out.present already true).
        bool ParseHeaderValue(const std::string& value, HeaderField& out)
        {
            if (value.empty()) return false;
            if (out.present) return false; // duplicate key

            if (value == "-1") { out = { true, true, 0 }; return true; }

            size_t v = 0;
            for (const char c : value)
            {
                if (c < '0' || c > '9') return false;
                size_t scaled = 0;
                if (!CheckedMul(v, 10, scaled)) return false;
                if (!CheckedAdd(scaled, static_cast<size_t>(c - '0'), v)) return false;
            }
            out = { true, false, v };
            return true;
        }
    }

    bool ParseCfHtmlHeader(const std::string& payload, CfHtmlOffsets& out)
    {
        if (payload.compare(0, 8, "Version:") != 0) return false;

        HeaderField version, startHtml, endHtml, startFrag, endFrag, startSel, endSel;
        bool versionPresent = false;
        size_t pos = 0;
        size_t scanLimit = payload.size();
        size_t headerEnd = 0;

        while (pos < scanLimit)
        {
            size_t eol = payload.find_first_of("\r\n", pos);
            if (eol == std::string::npos || eol > scanLimit) eol = scanLimit;
            const std::string line = payload.substr(pos, eol - pos);

            const size_t colon = line.find(':');
            if (colon == std::string::npos) break; // end of the header block
            const std::string key = line.substr(0, colon);
            const std::string value = line.substr(colon + 1);

            if (key == "Version")
            {
                if (versionPresent) return false;
                if (value != "1.0" && value != "0.9") return false;
                versionPresent = true;
            }
            else if (key == "StartHTML")
            {
                if (!ParseHeaderValue(value, startHtml)) return false;
                if (!startHtml.isMinusOne)
                {
                    if (startHtml.value > payload.size()) return false;
                    scanLimit = startHtml.value;
                }
            }
            else if (key == "EndHTML")        { if (!ParseHeaderValue(value, endHtml))   return false; }
            else if (key == "StartFragment")  { if (!ParseHeaderValue(value, startFrag)) return false; }
            else if (key == "EndFragment")    { if (!ParseHeaderValue(value, endFrag))   return false; }
            else if (key == "StartSelection") { if (!ParseHeaderValue(value, startSel))  return false; }
            else if (key == "EndSelection")   { if (!ParseHeaderValue(value, endSel))    return false; }
            // unknown key: ignored by design (the format is extensible)

            pos = eol;
            while (pos < scanLimit && (payload[pos] == '\r' || payload[pos] == '\n')) ++pos;
            headerEnd = pos;
        }

        if (!versionPresent) return false;
        if (!startFrag.present || startFrag.isMinusOne) return false;
        if (!endFrag.present || endFrag.isMinusOne) return false;
        if (!startHtml.present || !endHtml.present) return false;

        const size_t size = payload.size();
        out.startFragment = startFrag.value;
        out.endFragment = endFrag.value;
        if (out.startFragment > out.endFragment || out.endFragment > size) return false;

        if (startHtml.isMinusOne != endHtml.isMinusOne) return false;
        if (!startHtml.isMinusOne)
        {
            out.startHtml = startHtml.value;
            out.endHtml = endHtml.value;
            if (out.startHtml != headerEnd) return false;
            if (out.startHtml > out.startFragment) return false;
            if (out.endFragment > out.endHtml) return false;
            if (out.endHtml > size) return false;
        }

        out.hasSelection = false;
        if (startSel.present != endSel.present) return false;
        if (startSel.present)
        {
            if (startSel.isMinusOne || endSel.isMinusOne) return false;
            if (startSel.value > endSel.value) return false;
            if (startSel.value < out.startFragment || endSel.value > out.endFragment) return false;
            out.startSelection = startSel.value;
            out.endSelection = endSel.value;
            out.hasSelection = true;
        }
        return true;
    }

    // ------------------------------------------------------------------
    // CF_HDROP / DROPFILES
    // ------------------------------------------------------------------

    bool BuildDropFiles(const std::vector<std::wstring>& paths, std::vector<BYTE>& out)
    {
        if (paths.empty()) return false;

        size_t chars = 1; // trailing extra NUL terminates the list
        for (const auto& p : paths)
        {
            if (p.empty()) return false;
            size_t withNul = 0;
            if (!CheckedAdd(p.size(), 1, withNul)) return false;
            if (!CheckedAdd(chars, withNul, chars)) return false;
        }

        size_t bytes = 0;
        if (!CheckedMul(chars, sizeof(wchar_t), bytes)) return false;
        if (!CheckedAdd(bytes, sizeof(DROPFILES), bytes)) return false;

        out.assign(bytes, 0);
        auto* df = reinterpret_cast<DROPFILES*>(out.data());
        df->pFiles = sizeof(DROPFILES);
        df->fWide = TRUE;

        auto* dst = reinterpret_cast<wchar_t*>(out.data() + sizeof(DROPFILES));
        size_t remain = chars;
        for (const auto& p : paths)
        {
            wcscpy_s(dst, remain, p.c_str());
            dst += p.size() + 1;
            remain -= p.size() + 1;
        }
        *dst = L'\0';
        return true;
    }

    bool ValidateDropFiles(const BYTE* data, size_t totalBytes)
    {
        if (!data || totalBytes < sizeof(DROPFILES)) return false;

        const auto* df = reinterpret_cast<const DROPFILES*>(data);
        if (df->pFiles != sizeof(DROPFILES)) return false;
        if (!df->fWide) return false; // only Unicode paths are accepted

        if (totalBytes < sizeof(DROPFILES) + sizeof(wchar_t) * 2) return false;
        if ((totalBytes - sizeof(DROPFILES)) % sizeof(wchar_t) != 0) return false;

        const auto* p = reinterpret_cast<const wchar_t*>(data + sizeof(DROPFILES));
        const size_t maxChars = (totalBytes - sizeof(DROPFILES)) / sizeof(wchar_t);

        // Must end with a double NUL (an empty string) somewhere inside the block.
        size_t i = 0;
        bool sawPath = false;
        while (i < maxChars)
        {
            size_t len = 0;
            while (i + len < maxChars && p[i + len] != L'\0') ++len;
            if (i + len >= maxChars) return false; // unterminated
            if (len == 0) return sawPath;           // empty string: end of list
            sawPath = true;
            i += len + 1;
        }
        return false; // ran out of buffer without the terminating empty string
    }

    // ------------------------------------------------------------------
    // CF_DIB
    // ------------------------------------------------------------------

    bool ValidateDib(const BYTE* data, size_t totalBytes)
    {
        if (!data || totalBytes < sizeof(BITMAPINFOHEADER)) return false;

        const auto* header = reinterpret_cast<const BITMAPINFOHEADER*>(data);
        if (header->biSize < sizeof(BITMAPINFOHEADER) || static_cast<size_t>(header->biSize) > totalBytes)
        {
            return false;
        }
        if (header->biPlanes != 1) return false;
        if (header->biWidth <= 0 || header->biHeight == 0) return false;

        switch (header->biBitCount)
        {
        case 1: case 4: case 8: case 16: case 24: case 32: break;
        default: return false;
        }

        switch (header->biCompression)
        {
        case BI_RGB:
        case BI_BITFIELDS:
        case BI_RLE8:
        case BI_RLE4:
            break;
        default:
            return false;
        }
        if (header->biCompression == BI_RLE8 && header->biBitCount != 8) return false;
        if (header->biCompression == BI_RLE4 && header->biBitCount != 4) return false;
        if (header->biCompression == BI_BITFIELDS &&
            header->biBitCount != 16 && header->biBitCount != 32)
        {
            return false;
        }

        size_t offset = static_cast<size_t>(header->biSize);

        // BI_BITFIELDS on a BITMAPINFOHEADER (not V4/V5) appends three DWORD masks.
        if (header->biCompression == BI_BITFIELDS && header->biSize == sizeof(BITMAPINFOHEADER))
        {
            size_t masks = 0;
            if (!CheckedMul(sizeof(DWORD), 3, masks)) return false;
            if (!CheckedAdd(offset, masks, offset)) return false;
            if (offset > totalBytes) return false;
        }

        // Palette entries for <= 8bpp (only meaningful for uncompressed/RLE formats).
        if (header->biBitCount <= 8)
        {
            const DWORD maxColors = 1u << header->biBitCount;
            const DWORD colorsUsed = header->biClrUsed != 0 ? header->biClrUsed : maxColors;
            if (colorsUsed > maxColors) return false;

            size_t paletteBytes = 0;
            if (!CheckedMul(static_cast<size_t>(colorsUsed), sizeof(RGBQUAD), paletteBytes)) return false;
            if (!CheckedAdd(offset, paletteBytes, offset)) return false;
            if (offset > totalBytes) return false;
        }

        // RLE DIBs must be bottom-up, use the matching bit depth, declare a
        // bounded compressed payload, and terminate with the end-of-bitmap
        // escape. This rejects truncated streams without attempting to decode
        // every run here.
        if (header->biCompression == BI_RLE8 || header->biCompression == BI_RLE4)
        {
            if (header->biHeight < 0 || header->biSizeImage < 2) return false;
            size_t end = 0;
            if (!CheckedAdd(offset, static_cast<size_t>(header->biSizeImage), end) || end > totalBytes)
            {
                return false;
            }
            return data[end - 2] == 0 && data[end - 1] == 1;
        }

        const int64_t signedHeight = static_cast<int64_t>(header->biHeight);
        const uint64_t absHeight = signedHeight < 0
            ? static_cast<uint64_t>(-signedHeight)
            : static_cast<uint64_t>(signedHeight);
        if (absHeight == 0 || absHeight > SIZE_MAX) return false;

        size_t rowBits = 0;
        if (!CheckedMul(static_cast<size_t>(header->biWidth), static_cast<size_t>(header->biBitCount), rowBits))
        {
            return false;
        }
        size_t stride = 0;
        if (!CheckedAdd(rowBits, 31, stride)) return false;
        stride = (stride / 32) * 4;

        size_t pixelBytes = 0;
        if (!CheckedMul(stride, static_cast<size_t>(absHeight), pixelBytes)) return false;

        size_t required = 0;
        if (!CheckedAdd(offset, pixelBytes, required)) return false;
        return required <= totalBytes;
    }

    bool IsMultiFormatPayloadAllowed(const std::wstring& formatName, UINT format,
                                     MultiFormatPayloadKind payloadKind)
    {
        if (format == 0 || format == CF_BITMAP) return false;
        if (format == CF_UNICODETEXT || format == CF_TEXT)
        {
            return payloadKind == MultiFormatPayloadKind::Text;
        }
        if (formatName == L"HTML Format")
        {
            return payloadKind == MultiFormatPayloadKind::Html;
        }
        if (format == CF_HDROP || format == CF_DIB || format == CF_DIBV5)
        {
            return payloadKind == MultiFormatPayloadKind::Base64;
        }
        // Registered/custom formats use the generic binary representation.
        return payloadKind == MultiFormatPayloadKind::Base64;
    }

    // ------------------------------------------------------------------
    // CF_UNICODETEXT
    // ------------------------------------------------------------------

    bool ValidateUnicodeTextBlock(const BYTE* data, size_t totalBytes, size_t& outChars)
    {
        if (!data || totalBytes < sizeof(wchar_t)) return false;
        if (totalBytes % sizeof(wchar_t) != 0) return false;

        const auto* src = reinterpret_cast<const wchar_t*>(data);
        const size_t maxChars = totalBytes / sizeof(wchar_t);
        const size_t len = ::wcsnlen(src, maxChars);
        if (len == maxChars) return false; // no NUL inside the block

        outChars = len;
        return true;
    }

    // ------------------------------------------------------------------
    // UTF-8 / UTF-16 conversion
    // ------------------------------------------------------------------

    std::string WideToUtf8(const std::wstring& s)
    {
        if (s.empty()) return {};
        const int len = ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                                              nullptr, 0, nullptr, nullptr);
        if (len <= 0) return {};
        std::string out(static_cast<size_t>(len), '\0');
        ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), out.data(), len, nullptr, nullptr);
        return out;
    }

    std::wstring Utf8ToWide(const std::string& s)
    {
        if (s.empty()) return {};
        const int len = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
        if (len <= 0) return {};
        std::wstring out(static_cast<size_t>(len), L'\0');
        ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), out.data(), len);
        return out;
    }

    namespace
    {
        int DecodeBase64Char(unsigned char c)
        {
            if (c >= 'A' && c <= 'Z') return c - 'A';
            if (c >= 'a' && c <= 'z') return c - 'a' + 26;
            if (c >= '0' && c <= '9') return c - '0' + 52;
            if (c == '+') return 62;
            if (c == '/') return 63;
            return -1;
        }
    }

    bool Base64Decode(const std::string& in, std::vector<BYTE>& out)
    {
        out.clear();

        std::string s;
        s.reserve(in.size());
        for (char c : in)
        {
            if (c == '\r' || c == '\n' || c == ' ' || c == '\t') continue;
            s.push_back(c);
        }
        if (s.empty() || s.size() % 4 != 0) return false;

        // At most the last two characters may be '=' padding.
        for (size_t i = 0; i + 2 < s.size(); ++i)
        {
            if (s[i] == '=') return false;
        }

        for (size_t i = 0; i < s.size(); i += 4)
        {
            const bool pad2 = (s[i + 2] == '=');
            const bool pad3 = (s[i + 3] == '=');
            if (pad2 && !pad3) return false;     // "X=Y=" style is not valid
            if ((pad2 || pad3) && i + 4 != s.size()) return false; // padding only at the very end

            const int c0 = DecodeBase64Char(static_cast<unsigned char>(s[i]));
            const int c1 = DecodeBase64Char(static_cast<unsigned char>(s[i + 1]));
            if (c0 < 0 || c1 < 0) return false; // the first two chars can never be padding
            out.push_back(static_cast<BYTE>((c0 << 2) | (c1 >> 4)));

            if (pad2) break; // "XY==" -> one output byte from this (final) quantum

            const int c2 = DecodeBase64Char(static_cast<unsigned char>(s[i + 2]));
            if (c2 < 0) return false;
            out.push_back(static_cast<BYTE>(((c1 & 0xF) << 4) | (c2 >> 2)));

            if (pad3) break; // "XYZ=" -> two output bytes from this (final) quantum

            const int c3 = DecodeBase64Char(static_cast<unsigned char>(s[i + 3]));
            if (c3 < 0) return false;
            out.push_back(static_cast<BYTE>(((c2 & 0x3) << 6) | c3));
        }
        return !out.empty();
    }
}
