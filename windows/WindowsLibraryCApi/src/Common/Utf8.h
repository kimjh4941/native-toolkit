#pragma once
// UTF-8 at the edge of the C ABI, UTF-16 inside (stage 5 design 7.6, E-16).

#include <string>
#include <string_view>

namespace NativeToolkitC::Detail {

/// Converts NUL-terminated UTF-8 to UTF-16. False when the text is not valid
/// UTF-8, which the caller reports as INVALID_PARAMETER. text must not be NULL.
bool Utf8ToWide(const char* text, std::wstring& out);

/// Converts UTF-16 to UTF-8. A surrogate without its pair cannot be spelled in
/// UTF-8 and becomes U+FFFD: text that came from another program is passed on
/// rather than failing the whole call. Throws std::bad_alloc.
std::string WideToUtf8(std::wstring_view text);

}  // namespace NativeToolkitC::Detail
