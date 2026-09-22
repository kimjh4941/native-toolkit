/**
 * @file ClipboardPayloadJson.h
 * @brief Test helper: reads the 1.x C ABI's clipboard payloads into the C++
 *        API's values.
 * @details
 *  The JSON belonged to the 1.x C ABI, which stage 5 removed (design 8.5). The
 *  reader stays for the tests only, where a payload is a short way to write
 *  down a set of values; nothing in the library reads JSON from a caller any
 *  more.
 */
#pragma once

#include <string>
#include <vector>

#include "NativeToolkit/Clipboard.h"

namespace ClipboardPayloadJson {

/**
 * @brief Reads a JSON array of strings.
 * @return False when it is not an array of strings.
 * @throws std::bad_alloc, which is not a malformed input and has always
 *         reached the caller as OUT_OF_MEMORY rather than as a bad payload.
 */
bool ReadStringArray(const wchar_t* json, std::vector<std::wstring>& out);

/**
 * @brief Reads the items of a multi-format write.
 * @return False when the payload is malformed, an item names no payload, or
 *         names more than one. Which payload an item carries is decided by
 *         which key is present, and the variant then carries that choice
 *         rather than leaving it to be guessed from what the value holds.
 * @throws std::bad_alloc, for the same reason as above.
 */
bool ReadFormatItems(const wchar_t* json,
                     std::vector<NativeToolkit::Clipboard::FormatPayload>& out);

/// A JSON array of strings, which is how the C ABI carries a list back.
std::wstring WriteStringArray(const std::vector<std::wstring>& values);

}  // namespace ClipboardPayloadJson
