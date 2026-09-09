/**
 * @file WindowsClipboardFormats.h
 * @brief Pure-logic helpers for clipboard payload construction and validation.
 * @details
 *  No WinRT or live clipboard dependency: safe to unit test directly. Every
 *  function treats its input as untrusted (either about to be written to the
 *  clipboard, or read back from it) and never throws.
 */
#pragma once

#include <windows.h>
#include <cstdint>
#include <string>
#include <vector>

namespace ClipboardFormats
{
    enum class MultiFormatPayloadKind
    {
        Text,
        Html,
        Base64,
    };

    // ------------------------------------------------------------------
    // Checked arithmetic - used by every size computation on read and write
    // paths so an overflow becomes a validation failure instead of undefined
    // behavior or a truncated allocation.
    // ------------------------------------------------------------------
    bool CheckedAdd(size_t a, size_t b, size_t& out);
    bool CheckedMul(size_t a, size_t b, size_t& out);
    bool CheckedToInt(size_t v, int& out);
    bool CheckedToUInt(size_t v, UINT& out);

    // ------------------------------------------------------------------
    // CF_HTML ("HTML Format") - UTF-8 payload with a byte-offset header.
    // ------------------------------------------------------------------

    // Builds a full CF_HTML payload from a raw UTF-8 fragment. The fragment is
    // wrapped in <html><body><!--StartFragment-->...<!--EndFragment--></body></html>
    // and the header offsets are computed from fixed prefix lengths - never by
    // searching the body for the marker text, because the caller's fragment may
    // legitimately contain that text itself. Returns an empty string on overflow.
    std::string BuildCfHtml(const std::string& utf8Fragment);

    struct CfHtmlOffsets
    {
        size_t startHtml = 0;
        size_t endHtml = 0;
        size_t startFragment = 0;
        size_t endFragment = 0;
        bool   hasSelection = false;
        size_t startSelection = 0;
        size_t endSelection = 0;
    };

    // Parses a CF_HTML payload's header block and validates:
    //   - Version is "0.9" or "1.0"
    //   - StartFragment/EndFragment are mandatory, real numbers, ordered, in range
    //   - StartHTML/EndHTML are both -1 or both real numbers, and (when real) the
    //     numeric StartHTML must equal the end of the parsed header block
    //   - StartSelection/EndSelection, if present, are both present, ordered, and
    //     fall inside the fragment
    //   - no known header key is duplicated
    // Returns false and leaves *out unspecified on any violation.
    bool ParseCfHtmlHeader(const std::string& payload, CfHtmlOffsets& out);

    // ------------------------------------------------------------------
    // CF_HDROP / DROPFILES - double-NUL-terminated Unicode path list.
    // ------------------------------------------------------------------

    // Builds a DROPFILES block (fWide = TRUE) followed by the paths, each
    // NUL-terminated, with a trailing extra NUL. Returns false on empty input,
    // an empty path, or size overflow.
    bool BuildDropFiles(const std::vector<std::wstring>& paths, std::vector<BYTE>& out);

    // Validates that a DROPFILES block is well-formed: header fits, pFiles
    // points inside the block, and the path list is properly double-NUL
    // terminated within the given size.
    bool ValidateDropFiles(const BYTE* data, size_t totalBytes);

    // ------------------------------------------------------------------
    // CF_DIB - BITMAPINFOHEADER + optional palette/masks + pixel data.
    // ------------------------------------------------------------------

    // Validates biSize/biPlanes/biBitCount/biCompression, palette or
    // BI_BITFIELDS masks, and that header + palette + (stride * |height|) all
    // fit inside totalBytes without overflow.
    bool ValidateDib(const BYTE* data, size_t totalBytes);
    bool IsMultiFormatPayloadAllowed(const std::wstring& formatName, UINT format,
                                     MultiFormatPayloadKind payloadKind);

    // ------------------------------------------------------------------
    // CF_UNICODETEXT - NUL-terminated UTF-16 block.
    // ------------------------------------------------------------------

    // Validates that totalBytes is a nonzero multiple of sizeof(wchar_t) and
    // that a NUL terminator exists within the block. outChars receives the
    // string length in characters, excluding the terminator.
    bool ValidateUnicodeTextBlock(const BYTE* data, size_t totalBytes, size_t& outChars);

    // ------------------------------------------------------------------
    // UTF-8 / UTF-16 conversion (CF_HTML is UTF-8; everything else is UTF-16).
    // ------------------------------------------------------------------
    std::string WideToUtf8(const std::wstring& s);
    std::wstring Utf8ToWide(const std::string& s);

    // ------------------------------------------------------------------
    // Base64 (RFC 4648) - used for the "base64" payload kind in
    // copyMultipleFormats so arbitrary binary formats can be placed without
    // relying on text/html shape (M1, 2026-07-29 v2 review). Rejects
    // malformed input (wrong length, invalid characters, misplaced padding)
    // rather than silently truncating.
    // ------------------------------------------------------------------
    bool Base64Decode(const std::string& in, std::vector<BYTE>& out);
}
