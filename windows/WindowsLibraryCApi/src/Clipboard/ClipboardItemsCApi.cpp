// The multi-format builder of the C ABI and the write that takes it (OP-35).
// Stage 5 design 8.4.3: the three kinds map one to one onto the C++ payloads,
// and whether a format name suits its kind is for ntk_clipboard_copy_multiple
// to decide, as in C++. A call that fails leaves the builder as it was.

#include "NativeToolkitC/Clipboard.h"

#include <string>
#include <utility>
#include <vector>

#include "Clipboard/ClipboardConvert.h"
#include "Clipboard/ClipboardResult.h"

using namespace NativeToolkitC::Detail;
using namespace NativeToolkitC::Detail::Clipboard;

namespace {

/// Adds one payload: a NULL builder is refused, and body's answer is the result.
template <class F>
ntk_clipboard_error Add(ntk_clipboard_items* items, F&& body) noexcept
{
    return Run([&]() -> ntk_clipboard_error {
        if (!items) return Fail(kInvalid);
        Api::FormatPayload payload;
        if (!body(payload)) return Fail(kInvalid);
        items->items.push_back(std::move(payload));
        return Succeed();
    });
}

}  // namespace

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_items_create(ntk_clipboard_items** out_items)
{
    return Run([&]() -> ntk_clipboard_error {
        if (!out_items) return Fail(kInvalid);
        *out_items = nullptr;
        *out_items = new ntk_clipboard_items();
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_items_add_text(
    ntk_clipboard_items* items, const char* format_name, const char* text)
{
    return Add(items, [&](Api::FormatPayload& payload) {
        Api::TextPayload textPayload;
        if (!RequiredText(format_name, textPayload.formatName) || !RequiredText(text, textPayload.text)) return false;
        payload = std::move(textPayload);
        return true;
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_items_add_html(
    ntk_clipboard_items* items, const char* format_name, const char* html)
{
    return Add(items, [&](Api::FormatPayload& payload) {
        Api::HtmlPayload htmlPayload;
        if (!RequiredText(format_name, htmlPayload.formatName) || !RequiredText(html, htmlPayload.html)) return false;
        payload = std::move(htmlPayload);
        return true;
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_items_add_bytes(
    ntk_clipboard_items* items, const char* format_name, const uint8_t* data, size_t size)
{
    return Add(items, [&](Api::FormatPayload& payload) {
        Api::BytesPayload bytesPayload;
        if (!RequiredText(format_name, bytesPayload.formatName) || !ToBytes(data, size, bytesPayload.bytes)) return false;
        payload = std::move(bytesPayload);
        return true;
    });
}

extern "C" void NTK_CALL ntk_clipboard_items_free(ntk_clipboard_items* items)
{
    delete items;
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_copy_multiple(
    ntk_clipboard_session* session, const ntk_clipboard_items* items, uint32_t flags)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        Api::WriteOptions options;
        if (!items || ToWriteOptions(flags, options) != NTK_CLIPBOARD_ERROR_NONE) return Fail(kInvalid);
        return Done(s.CopyMultiple(items->items, options));
    });
}
