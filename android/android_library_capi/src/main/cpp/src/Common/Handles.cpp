#include "Common/Handles.h"

#include <memory>

#include <new>

#include "Common/Export.h"
#include "Common/Log.h"

namespace nativetoolkit::handles {

ntk_string* MakeString(std::string_view text) {
    NTK_LOGD("[MakeString] length: %zu", text.size());
    try {
        return new ntk_string{std::string(text)};
    } catch (const std::bad_alloc&) {
        NTK_LOGE("[MakeString] out of memory, length: %zu", text.size());
        return nullptr;
    }
}

ntk_bytes* MakeBytes(const uint8_t* data, size_t size) {
    NTK_LOGD("[MakeBytes] data: %p, size: %zu", data, size);
    try {
        auto made = std::make_unique<ntk_bytes>();
        if (size > 0) made->bytes.assign(data, data + size);
        return made.release();
    } catch (const std::bad_alloc&) {
        NTK_LOGE("[MakeBytes] out of memory, size: %zu", size);
        return nullptr;
    }
}

ntk_string_list* MakeStringList(std::vector<std::string> items) {
    NTK_LOGD("[MakeStringList] count: %zu", items.size());
    try {
        return new ntk_string_list{std::move(items)};
    } catch (const std::bad_alloc&) {
        NTK_LOGE("[MakeStringList] out of memory");
        return nullptr;
    }
}

}  // namespace nativetoolkit::handles

// --- Common.h ----------------------------------------------------------------

NTK_EXPORT uint32_t NTK_CALL ntk_version(void) {
    NTK_LOGD("[ntk_version]");
    return NTK_VERSION;
}

// Always 0 on Android: failures come as exceptions, not numbers, and their detail goes to logcat
// (AC-10).
NTK_EXPORT uint32_t NTK_CALL ntk_last_system_code(void) {
    NTK_LOGD("[ntk_last_system_code]");
    return 0;
}

// Strings may be clipboard or dialog text: only lengths are logged (design 5.12).
NTK_EXPORT const char* NTK_CALL ntk_string_data(const ntk_string* s) {
    NTK_LOGD("[ntk_string_data] s: %p", s);
    return s == nullptr ? nullptr : s->text.c_str();
}

NTK_EXPORT size_t NTK_CALL ntk_string_size(const ntk_string* s) {
    NTK_LOGD("[ntk_string_size] s: %p", s);
    return s == nullptr ? 0 : s->text.size();
}

NTK_EXPORT void NTK_CALL ntk_string_free(ntk_string* s) {
    NTK_LOGD("[ntk_string_free] s: %p", s);
    delete s;
}

NTK_EXPORT const uint8_t* NTK_CALL ntk_bytes_data(const ntk_bytes* b) {
    NTK_LOGD("[ntk_bytes_data] b: %p", b);
    // Never NULL for a valid handle, even when there are no bytes (Common.h).
    static const uint8_t kEmpty = 0;
    if (b == nullptr) return nullptr;
    return b->bytes.empty() ? &kEmpty : b->bytes.data();
}

NTK_EXPORT size_t NTK_CALL ntk_bytes_size(const ntk_bytes* b) {
    NTK_LOGD("[ntk_bytes_size] b: %p", b);
    return b == nullptr ? 0 : b->bytes.size();
}

NTK_EXPORT void NTK_CALL ntk_bytes_free(ntk_bytes* b) {
    NTK_LOGD("[ntk_bytes_free] b: %p", b);
    delete b;
}

NTK_EXPORT size_t NTK_CALL ntk_string_list_count(const ntk_string_list* list) {
    NTK_LOGD("[ntk_string_list_count] list: %p", list);
    return list == nullptr ? 0 : list->items.size();
}

NTK_EXPORT const char* NTK_CALL ntk_string_list_at(const ntk_string_list* list, size_t index, size_t* out_size) {
    NTK_LOGD("[ntk_string_list_at] list: %p, index: %zu, out_size: %p", list, index, out_size);
    if (list == nullptr || index >= list->items.size()) {
        if (out_size != nullptr) *out_size = 0;
        return nullptr;
    }
    const std::string& item = list->items[index];
    if (out_size != nullptr) *out_size = item.size();
    return item.c_str();
}

NTK_EXPORT void NTK_CALL ntk_string_list_free(ntk_string_list* list) {
    NTK_LOGD("[ntk_string_list_free] list: %p", list);
    delete list;
}
