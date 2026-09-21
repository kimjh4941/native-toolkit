#pragma once
// The three output handles of Common.h, and how the rest of the C ABI makes
// them. Every string a handle holds is already UTF-8, so reading one is a
// pointer and a length, with nothing converted on the way out.

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "NativeToolkitC/Common.h"

struct ntk_string {
    std::string text;
};

struct ntk_bytes {
    std::vector<uint8_t> data;
};

struct ntk_string_list {
    std::vector<std::string> items;
};

namespace NativeToolkitC::Detail {

/// A new string handle holding text as UTF-8. Throws std::bad_alloc.
ntk_string* NewString(std::wstring_view text);

/// A new bytes handle holding a copy of the range. Throws std::bad_alloc.
ntk_bytes* NewBytes(const void* data, size_t size);

/// A new list handle holding every item as UTF-8. Throws std::bad_alloc.
ntk_string_list* NewStringList(const std::vector<std::wstring>& items);

/// The pointer a reading function hands out for a string it owns, with its
/// length written to outSize when the caller asked for it.
const char* Borrow(const std::string& text, size_t* outSize) noexcept;

}  // namespace NativeToolkitC::Detail
