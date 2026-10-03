// UTF-8 at the edge of the C ABI (stage 5 design 7.6).

#include "Common/Utf8.h"

#include <windows.h>

#include <climits>
#include <new>

namespace NativeToolkitC::Detail {

bool Utf8ToWide(const char* text, std::wstring& out)
{
    out.clear();
    const size_t length = std::char_traits<char>::length(text);
    if (length == 0) return true;
    if (length > static_cast<size_t>(INT_MAX)) return false;

    // MB_ERR_INVALID_CHARS: a malformed sequence fails the conversion rather
    // than being replaced, so bad input is reported instead of passed on.
    const int needed = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text,
                                             static_cast<int>(length), nullptr, 0);
    if (needed <= 0) return false;
    out.resize(static_cast<size_t>(needed));
    return ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, static_cast<int>(length),
                                 out.data(), needed) == needed;
}

std::string WideToUtf8(std::wstring_view text)
{
    if (text.empty()) return {};
    if (text.size() > static_cast<size_t>(INT_MAX)) throw std::bad_alloc();

    // No WC_ERR_INVALID_CHARS: an unpaired surrogate becomes U+FFFD (E-16).
    const int needed = ::WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                                             nullptr, 0, nullptr, nullptr);
    if (needed <= 0) throw std::bad_alloc();
    std::string out(static_cast<size_t>(needed), '\0');
    ::WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                          out.data(), needed, nullptr, nullptr);
    return out;
}

}  // namespace NativeToolkitC::Detail
