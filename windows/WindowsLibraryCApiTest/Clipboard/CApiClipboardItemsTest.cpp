#include "pch.h"

#include "NativeToolkitC/Clipboard.h"

#include "Clipboard/CApiClipboardHarness.h"
#include "Clipboard/ClipboardConvert.h"

#include <cstring>
#include <string>
#include <variant>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace CApiClipboardHarness;

// ============================================================================
// The multi-format builder and ntk_clipboard_copy_multiple (stage 5 design,
// T-08, CT-10): the builder hands the C++ API the payloads in the order they
// were added, a refused add changes nothing, and a multi-format write reads
// back through the C ABI.
// ============================================================================

namespace CApiClipboardItemsTest
{

namespace
{
    namespace Api = NativeToolkit::Clipboard;

    void Ok(ntk_clipboard_error result, const wchar_t* what)
    {
        Check(result == NTK_CLIPBOARD_ERROR_NONE, what);
    }

    void AssertPassed(const std::wstring& failure)
    {
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }

    std::string Read(const ntk_string* s)
    {
        return std::string(ntk_string_data(s), ntk_string_size(s));
    }

    ntk_clipboard_items* NewItems()
    {
        ntk_clipboard_items* items = nullptr;
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_items_create(&items));
        return items;
    }

    const char* const kBad = "\xFF";   // not UTF-8
}

TEST_CLASS(CApiClipboardItemsTest)
{
public:
    TEST_METHOD(Test_Builder_KeepsThePayloadsInOrder)
    {
        auto* items = NewItems();
        const uint8_t bytes[] = {1, 2, 3};
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_items_add_html(items, "HTML Format", "<b>x</b>"));
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_items_add_text(items, "CF_UNICODETEXT", "caf\xC3\xA9"));
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_items_add_bytes(items, "NativeToolkit.Bin", bytes, 3));
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_items_add_bytes(items, "NativeToolkit.Empty", nullptr, 0));

        Assert::AreEqual(size_t{4}, items->items.size());
        const auto& html = std::get<Api::HtmlPayload>(items->items[0]);
        Assert::AreEqual(std::wstring(L"HTML Format"), html.formatName);
        Assert::AreEqual(std::wstring(L"<b>x</b>"), html.html);
        const auto& text = std::get<Api::TextPayload>(items->items[1]);
        Assert::AreEqual(std::wstring(L"caf") + wchar_t(0x00E9), text.text);
        const auto& bin = std::get<Api::BytesPayload>(items->items[2]);
        Assert::AreEqual(size_t{3}, bin.bytes.size());
        Assert::IsTrue(bin.bytes[2] == std::byte{3});
        Assert::IsTrue(std::get<Api::BytesPayload>(items->items[3]).bytes.empty());
        ntk_clipboard_items_free(items);
    }

    TEST_METHOD(Test_Builder_RefusedAdd_ChangesNothing)
    {
        auto* items = NewItems();
        Assert::AreEqual<int32_t>(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_items_add_text(items, "CF_UNICODETEXT", "kept"));
        const uint8_t bytes[] = {1};
        const int32_t invalid = NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;

        Assert::AreEqual(invalid, ntk_clipboard_items_add_text(items, nullptr, "x"));
        Assert::AreEqual(invalid, ntk_clipboard_items_add_text(items, "CF_UNICODETEXT", nullptr));
        Assert::AreEqual(invalid, ntk_clipboard_items_add_text(items, kBad, "x"));
        Assert::AreEqual(invalid, ntk_clipboard_items_add_html(items, "HTML Format", nullptr));
        Assert::AreEqual(invalid, ntk_clipboard_items_add_html(items, "HTML Format", kBad));
        Assert::AreEqual(invalid, ntk_clipboard_items_add_bytes(items, nullptr, bytes, 1));
        Assert::AreEqual(invalid, ntk_clipboard_items_add_bytes(items, "Fmt", nullptr, 1));
        Assert::AreEqual(size_t{1}, items->items.size());

        Assert::AreEqual(invalid, ntk_clipboard_items_create(nullptr));
        Assert::AreEqual(invalid, ntk_clipboard_items_add_text(nullptr, "CF_UNICODETEXT", "x"));
        Assert::AreEqual(invalid, ntk_clipboard_items_add_html(nullptr, "HTML Format", "x"));
        Assert::AreEqual(invalid, ntk_clipboard_items_add_bytes(nullptr, "Fmt", bytes, 1));
        ntk_clipboard_items_free(items);
        ntk_clipboard_items_free(nullptr);
    }

    TEST_METHOD(Test_CopyMultiple_RoundTripsEveryKind)
    {
        AssertPassed(RunOnOwner([] {
            ntk_clipboard_session* session = nullptr;
            Ok(ntk_clipboard_session_create(nullptr, &session), L"create");
            ntk_clipboard_items* items = nullptr;
            Ok(ntk_clipboard_items_create(&items), L"items");
            const uint8_t bytes[] = {0, 9, 250};
            Ok(ntk_clipboard_items_add_html(items, "HTML Format", "<b>caf\xC3\xA9</b>"), L"add html");
            Ok(ntk_clipboard_items_add_text(items, "CF_UNICODETEXT", "caf\xC3\xA9 \xF0\x9F\x98\x80"), L"add text");
            Ok(ntk_clipboard_items_add_bytes(items, "NativeToolkit.CApiItems", bytes, sizeof(bytes)), L"add bytes");
            Ok(ntk_clipboard_copy_multiple(session, items, NTK_CLIPBOARD_WRITE_DEFAULT), L"copy_multiple");
            ntk_clipboard_items_free(items);

            ntk_string* html = nullptr;
            Ok(ntk_clipboard_paste_html(session, &html), L"paste html");
            Check(Read(html) == "<b>caf\xC3\xA9</b>", L"the HTML changed on the way");
            ntk_string_free(html);
            ntk_string* text = nullptr;
            Ok(ntk_clipboard_paste_text(session, &text), L"paste text");
            Check(Read(text) == "caf\xC3\xA9 \xF0\x9F\x98\x80", L"the text changed on the way");
            ntk_string_free(text);
            ntk_bytes* data = nullptr;
            Ok(ntk_clipboard_paste_custom(session, "NativeToolkit.CApiItems", &data), L"paste bytes");
            Check(ntk_bytes_size(data) == sizeof(bytes) && std::memcmp(ntk_bytes_data(data), bytes, sizeof(bytes)) == 0,
                  L"the bytes changed on the way");
            ntk_bytes_free(data);

            Ok(ntk_clipboard_session_close(session), L"close");
            ntk_clipboard_session_free(session);
        }));
    }

    TEST_METHOD(Test_CopyMultiple_WhatTheCppApiRefuses_ComesBack)
    {
        AssertPassed(RunOnOwner([] {
            ntk_clipboard_session* session = nullptr;
            Ok(ntk_clipboard_session_create(nullptr, &session), L"create");

            ntk_clipboard_items* twice = nullptr;
            Ok(ntk_clipboard_items_create(&twice), L"items");
            Ok(ntk_clipboard_items_add_text(twice, "CF_UNICODETEXT", "one"), L"one");
            Ok(ntk_clipboard_items_add_text(twice, "CF_UNICODETEXT", "two"), L"two");
            Check(ntk_clipboard_copy_multiple(session, twice, 0) == NTK_CLIPBOARD_ERROR_INVALID_PARAMETER,
                  L"the same format twice should be refused");
            ntk_clipboard_items_free(twice);

            ntk_clipboard_items* empty = nullptr;
            Ok(ntk_clipboard_items_create(&empty), L"empty items");
            Check(ntk_clipboard_copy_multiple(session, empty, 0) != NTK_CLIPBOARD_ERROR_NONE,
                  L"nothing to write should be refused");
            Check(ntk_clipboard_copy_multiple(session, empty, 4) == NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, L"flag 4");
            Check(ntk_clipboard_copy_multiple(session, nullptr, 0) == NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, L"NULL items");
            Check(ntk_clipboard_copy_multiple(nullptr, empty, 0) == NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, L"NULL session");
            ntk_clipboard_items_free(empty);

            Check(Current()->FormatCount() == 0, L"a refused write reached the clipboard");
            Ok(ntk_clipboard_session_close(session), L"close");
            ntk_clipboard_session_free(session);
        }));
    }
};

}  // namespace CApiClipboardItemsTest
