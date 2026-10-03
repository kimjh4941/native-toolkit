// The output handles of Common.h (stage 5 design 7.4).

#include "Common/Handles.h"

#include "Common/Utf8.h"

namespace NativeToolkitC::Detail {

ntk_string* NewString(std::wstring_view text)
{
    auto* handle = new ntk_string;
    try {
        handle->text = WideToUtf8(text);
    } catch (...) {
        delete handle;
        throw;
    }
    return handle;
}

ntk_bytes* NewBytes(const void* data, size_t size)
{
    auto* handle = new ntk_bytes;
    try {
        const auto* begin = static_cast<const uint8_t*>(data);
        handle->data.assign(begin, begin + size);
    } catch (...) {
        delete handle;
        throw;
    }
    return handle;
}

ntk_string_list* NewStringList(const std::vector<std::wstring>& items)
{
    auto* handle = new ntk_string_list;
    try {
        handle->items.reserve(items.size());
        for (const auto& item : items) handle->items.push_back(WideToUtf8(item));
    } catch (...) {
        delete handle;
        throw;
    }
    return handle;
}

const char* Borrow(const std::string& text, size_t* outSize) noexcept
{
    if (outSize) *outSize = text.size();
    return text.c_str();
}

}  // namespace NativeToolkitC::Detail

using NativeToolkitC::Detail::Borrow;

// --- ntk_string --------------------------------------------------------------

extern "C" const char* NTK_CALL ntk_string_data(const ntk_string* s)
{
    return s ? s->text.c_str() : nullptr;
}

extern "C" size_t NTK_CALL ntk_string_size(const ntk_string* s)
{
    return s ? s->text.size() : 0;
}

extern "C" void NTK_CALL ntk_string_free(ntk_string* s)
{
    delete s;
}

// --- ntk_bytes ---------------------------------------------------------------

extern "C" const uint8_t* NTK_CALL ntk_bytes_data(const ntk_bytes* b)
{
    if (!b) return nullptr;
    // A vector with nothing in it may have no storage at all; the contract is
    // a non-NULL pointer for every valid handle, so point at something that
    // lives as long as the program.
    static const uint8_t kEmpty = 0;
    return b->data.empty() ? &kEmpty : b->data.data();
}

extern "C" size_t NTK_CALL ntk_bytes_size(const ntk_bytes* b)
{
    return b ? b->data.size() : 0;
}

extern "C" void NTK_CALL ntk_bytes_free(ntk_bytes* b)
{
    delete b;
}

// --- ntk_string_list ---------------------------------------------------------

extern "C" size_t NTK_CALL ntk_string_list_count(const ntk_string_list* list)
{
    return list ? list->items.size() : 0;
}

extern "C" const char* NTK_CALL ntk_string_list_at(const ntk_string_list* list, size_t index, size_t* out_size)
{
    if (!list || index >= list->items.size()) {
        if (out_size) *out_size = 0;
        return nullptr;
    }
    return Borrow(list->items[index], out_size);
}

extern "C" void NTK_CALL ntk_string_list_free(ntk_string_list* list)
{
    delete list;
}
