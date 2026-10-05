// The clipboard through the C ABI (C ABI design part 2, 6.1, 11.3 and 12.1; part 1, 5.8).
// The runner gives the test app the window focus, which reading and change events need.
#include <gtest/gtest.h>

#include <unistd.h>

#include <chrono>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include <NativeToolkitC/Clipboard.h>

#include "../TestSupport.h"

using ntktest::Recorder;

namespace {

std::string Str(const char* text, size_t size) {
    return text == nullptr ? std::string("<null>") : std::string(text, size);
}

std::string ItemText(const ntk_clipboard_content* content, size_t index) {
    size_t size = 0;
    const char* text = ntk_clipboard_content_item_text_at(content, index, &size);
    return Str(text, size);
}

struct ContentGuard {
    ntk_clipboard_content* content = nullptr;
    ~ContentGuard() { ntk_clipboard_content_free(content); }
};

struct DescriptionGuard {
    ntk_clipboard_description* description = nullptr;
    ~DescriptionGuard() { ntk_clipboard_description_free(description); }
};

ntk_clipboard_copy_options Options(const char* label, int32_t sensitive) {
    ntk_clipboard_copy_options options{};
    options.struct_size = sizeof(options);
    options.label = label;
    options.sensitive = sensitive;
    return options;
}

void ChangeCounter(void* user_data) {
    static_cast<Recorder*>(user_data)->Add({"change"});
}

class Clipboard : public testing::Test {
protected:
    void TearDown() override {
        ntk_clipboard_stop_observing();
        ntktest::DrainMain();
    }
};

}  // namespace

// --- the entry (12.1, 入口の検査) ---

TEST_F(Clipboard, NullAndInvalidUtf8AreRejectedAtTheEntry) {
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_text(nullptr, nullptr));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_text("\xED\xA0\x80", nullptr));      // surrogate
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_text("\xC0\x80", nullptr));          // overlong
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_text("\xF4\x90\x80\x80", nullptr));  // > U+10FFFF
    ntk_clipboard_copy_options bad_label = Options("\xED\xBF\xBF", 0);
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_text("ok", &bad_label));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_html(nullptr, "plain", nullptr));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_html("<b>x</b>", "\xC0\x80", nullptr));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_uri(nullptr, nullptr));
    const char* with_null[] = {"a", nullptr};
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_texts(with_null, 2, nullptr));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_texts(nullptr, 1, nullptr));
    const char* bad_item[] = {"a", "\xE3\x81"};
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_texts(bad_item, 2, nullptr));
    // No items is EMPTY_ITEMS, decided at the entry (part 2, AP-19).
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_EMPTY_ITEMS, ntk_clipboard_copy_texts(with_null, 0, nullptr));
}

TEST_F(Clipboard, TheOptionsFollowTheStructSizeRules) {
    ntk_clipboard_copy_options options = Options(nullptr, 0);
    options.struct_size = sizeof(options) - 8;
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_text("x", &options));
    options = Options(nullptr, 0);
    options.reserved0 = 1;
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_text("x", &options));
    options = Options(nullptr, 0);
    options.reserved1 = 1;
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_copy_text("x", &options));

    // A newer header's struct: accepted when its new part is zero, NOT_SUPPORTED otherwise.
    std::vector<unsigned char> newer(sizeof(ntk_clipboard_copy_options) + 8, 0);
    ntk_clipboard_copy_options base = Options(nullptr, 0);
    base.struct_size = static_cast<uint32_t>(newer.size());
    std::memcpy(newer.data(), &base, sizeof(base));
    auto* as_options = reinterpret_cast<const ntk_clipboard_copy_options*>(newer.data());
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_text("x", as_options));
    newer.back() = 1;
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_NOT_SUPPORTED, ntk_clipboard_copy_text("x", as_options));

    std::vector<unsigned char> huge(4096 + 8, 0);
    base.struct_size = static_cast<uint32_t>(huge.size());
    std::memcpy(huge.data(), &base, sizeof(base));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER,
              ntk_clipboard_copy_text("x", reinterpret_cast<const ntk_clipboard_copy_options*>(huge.data())));
}

TEST_F(Clipboard, OutputsAreClearedAndANullOutputIsRejected) {
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_read(nullptr));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_has_clip(nullptr));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, ntk_clipboard_get_description(nullptr));
    Recorder recorder;
    auto* listener = reinterpret_cast<ntk_clipboard_listener*>(0x1234);
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER,
              ntk_clipboard_add_change_listener(nullptr, &recorder, Recorder::Release, &listener));
    EXPECT_EQ(nullptr, listener);
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER,
              ntk_clipboard_add_change_listener(ChangeCounter, &recorder, Recorder::Release, nullptr));
    // Both releases ran on this thread before the calls returned (part 1, 1.3).
    ASSERT_EQ(2u, recorder.Count("release"));
    for (const auto& record : recorder.Records()) EXPECT_EQ(gettid(), record.thread);
}

// --- writes, reads and the output handles ---

TEST_F(Clipboard, TextRoundTripsWithItsLabel) {
    const char* text = "A\xC3\xA9\xF0\x9F\x98\x80 text";
    ntk_clipboard_copy_options options = Options("my label", 1);
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_text(text, &options));
    int32_t has_clip = -1;
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_has_clip(&has_clip));
    EXPECT_EQ(1, has_clip);

    ContentGuard read;
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_read(&read.content));
    ASSERT_NE(nullptr, read.content) << "no clip read: does the test app have the window focus?";
    ASSERT_EQ(1u, ntk_clipboard_content_item_count(read.content));
    EXPECT_EQ(std::string(text), ItemText(read.content, 0));
    size_t size = 0;
    EXPECT_EQ("my label", Str(ntk_clipboard_content_label(read.content, &size), size));
    bool plain = false;
    for (size_t i = 0; i < ntk_clipboard_content_mime_type_count(read.content); ++i) {
        plain = plain || Str(ntk_clipboard_content_mime_type_at(read.content, i, &size), size) == "text/plain";
    }
    EXPECT_TRUE(plain);
    // Out of range and absent fields read as NULL with size 0.
    size = 99;
    EXPECT_EQ(nullptr, ntk_clipboard_content_item_text_at(read.content, 1, &size));
    EXPECT_EQ(0u, size);
    EXPECT_EQ(nullptr, ntk_clipboard_content_mime_type_at(read.content, 99, nullptr));
    EXPECT_EQ(nullptr, ntk_clipboard_content_item_html_at(read.content, 0, &size));

    DescriptionGuard description;
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_get_description(&description.description));
    ASSERT_NE(nullptr, description.description);
    EXPECT_EQ("my label", Str(ntk_clipboard_description_label(description.description, &size), size));
    EXPECT_GE(ntk_clipboard_description_mime_type_count(description.description), 1u);
    EXPECT_EQ(0, ntk_clipboard_description_is_styled_text(description.description));
}

TEST_F(Clipboard, HtmlUriAndSeveralTextsRoundTrip) {
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_html("<b>bold</b>", nullptr, nullptr));
    {
        ContentGuard read;
        ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_read(&read.content));
        ASSERT_NE(nullptr, read.content);
        size_t size = 0;
        EXPECT_EQ("<b>bold</b>", Str(ntk_clipboard_content_item_html_at(read.content, 0, &size), size));
    }
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_uri("content://com.jonghyunkim.capitest/item/1", nullptr));
    {
        ContentGuard read;
        ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_read(&read.content));
        ASSERT_NE(nullptr, read.content);
        size_t size = 0;
        EXPECT_EQ("content://com.jonghyunkim.capitest/item/1",
                  Str(ntk_clipboard_content_item_uri_at(read.content, 0, &size), size));
    }
    const char* texts[] = {"one", "two", "\xE4\xB8\x89"};
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_texts(texts, 3, nullptr));
    {
        ContentGuard read;
        ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_read(&read.content));
        ASSERT_NE(nullptr, read.content);
        ASSERT_EQ(3u, ntk_clipboard_content_item_count(read.content));
        EXPECT_EQ("one", ItemText(read.content, 0));
        EXPECT_EQ("\xE4\xB8\x89", ItemText(read.content, 2));
    }
}

TEST_F(Clipboard, KotlinFailuresMapToTheTable) {
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_EMPTY_CONTENT, ntk_clipboard_copy_html("   ", "plain", nullptr));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_URI, ntk_clipboard_copy_uri("", nullptr));
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_INVALID_URI, ntk_clipboard_copy_uri("https://example.com/", nullptr));
}

TEST_F(Clipboard, ClearLeavesNothingToRead) {
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_text("to clear", nullptr));
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_clear());
    int32_t has_clip = -1;
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_has_clip(&has_clip));
    EXPECT_EQ(0, has_clip);
    auto* content = reinterpret_cast<ntk_clipboard_content*>(0x1);
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_read(&content));
    EXPECT_EQ(nullptr, content);
    auto* description = reinterpret_cast<ntk_clipboard_description*>(0x1);
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_get_description(&description));
    EXPECT_EQ(nullptr, description);
}

TEST_F(Clipboard, WhatCCannotHoldIsReadAsTheReplacementCharacter) {
    // An unpaired surrogate and U+0000 put from Kotlin read as U+FFFD (part 1, AC-19).
    ntktest::SetClipboardText(std::u16string(u"a") + char16_t(0xD800) + u"b" + char16_t(0) + u"c");
    ContentGuard read;
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_read(&read.content));
    ASSERT_NE(nullptr, read.content);
    size_t size = 0;
    const char* text = ntk_clipboard_content_item_text_at(read.content, 0, &size);
    EXPECT_EQ(std::string("a\xEF\xBF\xBD" "b\xEF\xBF\xBD" "c"), Str(text, size));
    EXPECT_EQ(std::strlen(text), size);  // no NUL inside
}

TEST_F(Clipboard, ReadersOfANullHandleGiveNothing) {
    size_t size = 99;
    EXPECT_EQ(nullptr, ntk_clipboard_content_label(nullptr, &size));
    EXPECT_EQ(0u, size);
    EXPECT_EQ(0u, ntk_clipboard_content_item_count(nullptr));
    EXPECT_EQ(nullptr, ntk_clipboard_content_item_coerced_text_at(nullptr, 0, nullptr));
    EXPECT_EQ(0u, ntk_clipboard_description_mime_type_count(nullptr));
    EXPECT_EQ(-1, ntk_clipboard_description_classification_status(nullptr));
    ntk_clipboard_content_free(nullptr);
    ntk_clipboard_description_free(nullptr);
    ntk_clipboard_listener_remove(nullptr);
}

// --- observing and events (OP-09 to OP-12) ---

// One copy may be reported more than once: from Android 12 the system reports the clip again
// when it has classified the text. So the cases count "at least one" for a copy, and "no more"
// once a listener is removed or observing stopped, after the late reports have settled.
void Settle() {
    std::this_thread::sleep_for(std::chrono::milliseconds(700));
    ntktest::DrainMain();
}

TEST_F(Clipboard, EveryListenerGetsAChangeUntilItIsRemoved) {
    Recorder first;
    Recorder second;
    ntk_clipboard_listener* a = nullptr;
    ntk_clipboard_listener* b = nullptr;
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_start_observing());
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_add_change_listener(ChangeCounter, &first, Recorder::Release, &a));
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_add_change_listener(ChangeCounter, &second, Recorder::Release, &b));
    ASSERT_NE(nullptr, a);
    ntktest::DrainMain();

    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_text("change 1", nullptr));
    ASSERT_TRUE(first.WaitFor("change", 1));
    ASSERT_TRUE(second.WaitFor("change", 1));
    EXPECT_TRUE(first.Records()[0].on_main);

    // Removing a listener does not stop observing (part 2, AP-11): the other still gets changes.
    ntk_clipboard_listener_remove(a);
    ASSERT_TRUE(first.WaitFor("release", 1));
    Settle();
    size_t first_changes = first.Count("change");
    size_t second_changes = second.Count("change");
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_text("change 2", nullptr));
    ASSERT_TRUE(second.WaitFor("change", second_changes + 1));
    Settle();
    EXPECT_EQ(first_changes, first.Count("change"));
    EXPECT_EQ(1u, first.Count("release"));
    EXPECT_EQ("release", first.Records().back().what);
    EXPECT_TRUE(first.Records().back().on_main);
    ntk_clipboard_listener_remove(b);
    ASSERT_TRUE(second.WaitFor("release", 1));
}

TEST_F(Clipboard, AUriCopyReachesEachListenerExactlyOnce) {
    // A URI clip is not classified, so the system reports it once: each registration gets it
    // once, however many registrations there are (part 2, AP-21: one EventHub listener for all).
    Recorder first;
    Recorder second;
    Recorder third;
    ntk_clipboard_listener* listeners[3] = {};
    Recorder* recorders[3] = {&first, &second, &third};
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_start_observing());
    for (int i = 0; i < 3; ++i) {
        ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE,
                  ntk_clipboard_add_change_listener(ChangeCounter, recorders[i], Recorder::Release, &listeners[i]));
    }
    ntktest::DrainMain();
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_uri("content://com.jonghyunkim.capitest/once", nullptr));
    for (Recorder* recorder : recorders) ASSERT_TRUE(recorder->WaitFor("change", 1));
    Settle();
    for (Recorder* recorder : recorders) EXPECT_EQ(1u, recorder->Count("change"));
    for (int i = 0; i < 3; ++i) {
        ntk_clipboard_listener_remove(listeners[i]);
        ASSERT_TRUE(recorders[i]->WaitFor("release", 1));
    }
}

TEST_F(Clipboard, StoppingObservingStopsTheChangesAndStartingTwiceIsAccepted) {
    Recorder recorder;
    ntk_clipboard_listener* listener = nullptr;
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_start_observing());
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_start_observing());
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE,
              ntk_clipboard_add_change_listener(ChangeCounter, &recorder, Recorder::Release, &listener));
    ntktest::DrainMain();
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_text("seen", nullptr));
    ASSERT_TRUE(recorder.WaitFor("change", 1));

    // One stop is enough even after two starts.
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_stop_observing());
    Settle();
    size_t changes = recorder.Count("change");
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_text("unseen", nullptr));
    Settle();
    EXPECT_EQ(changes, recorder.Count("change"));
    ntk_clipboard_listener_remove(listener);
    ASSERT_TRUE(recorder.WaitFor("release", 1));
}

TEST_F(Clipboard, AListenerAloneDoesNotStartObserving) {
    Recorder recorder;
    ntk_clipboard_listener* listener = nullptr;
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE,
              ntk_clipboard_add_change_listener(ChangeCounter, &recorder, Recorder::Release, &listener));
    ntktest::DrainMain();
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, ntk_clipboard_copy_text("not observed", nullptr));
    Settle();
    EXPECT_EQ(0u, recorder.Count("change"));
    ntk_clipboard_listener_remove(listener);
    ASSERT_TRUE(recorder.WaitFor("release", 1));
}
