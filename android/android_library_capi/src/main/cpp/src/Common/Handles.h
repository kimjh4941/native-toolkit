// The output handles of Common.h, made by the features (C ABI design part 1, 5.7: C heap, no JNI
// references). Each maker returns nullptr when it runs out of memory.
#pragma once

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
    std::vector<uint8_t> bytes;
};

struct ntk_string_list {
    std::vector<std::string> items;
};

namespace nativetoolkit::handles {

ntk_string* MakeString(std::string_view text);
ntk_bytes* MakeBytes(const uint8_t* data, size_t size);
ntk_string_list* MakeStringList(std::vector<std::string> items);

}  // namespace nativetoolkit::handles
