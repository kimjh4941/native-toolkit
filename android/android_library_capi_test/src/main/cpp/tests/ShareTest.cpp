// Share through the C ABI (C ABI design part 2, 6.4, 11.4, 12.1 the Share rows and 12.2): the
// entry and the completions (AP-19), the foreground, Direct Share, the selection events and their
// request IDs (AP-17), the chooser actions of each share (AP-7), and removing listeners (AP-11).
// The Sharesheet is pressed with UiAutomator; ShareTargetActivity ("NTK target") is the app picked.
#include <gtest/gtest.h>

#include <unistd.h>

#include <chrono>
#include <string>
#include <vector>

#include <NativeToolkitC/Share.h>

#include "../TestSupport.h"

using ntktest::Leaked;
using ntktest::Recorder;

namespace {

constexpr ntk_share_error kNone = NTK_SHARE_ERROR_NONE;
constexpr ntk_share_error kInvalid = NTK_SHARE_ERROR_INVALID_PARAMETER;
constexpr const char* kTarget = "NTK target";
constexpr auto kQuiet = std::chrono::seconds(3);

void OnDone(void* user_data, ntk_share_error error, uint32_t system_code) {
    static_cast<Recorder*>(user_data)->Add({"done", error, system_code});
}

void OnSelection(void* user_data, uint64_t request_id, ntk_string* package_name) {
    ntktest::Record record;
    record.what = "event";
    record.value = static_cast<int64_t>(request_id);
    record.detail = package_name == nullptr ? "<null>"
                                            : std::string(ntk_string_data(package_name), ntk_string_size(package_name));
    static_cast<Recorder*>(user_data)->Add(record);
    ntk_string_free(package_name);
}

void OnChooserAction(void* user_data, ntk_string* action_id) {
    ntktest::Record record;
    record.what = "event";
    record.detail = std::string(ntk_string_data(action_id), ntk_string_size(action_id));
    static_cast<Recorder*>(user_data)->Add(record);
    ntk_string_free(action_id);
}

ntk_share_text_content Text(const char* text) {
    ntk_share_text_content content{};
    content.struct_size = sizeof(content);
    content.text = text;
    return content;
}

// The completion of a recorder that saw exactly one opening.
int32_t DoneError(Recorder& recorder) {
    EXPECT_TRUE(recorder.WaitFor("done", 1, std::chrono::seconds(10)));
    for (const auto& record : recorder.Records()) {
        if (record.what == "done") return record.error;
    }
    return -1;
}

ntk_share_listener* AddSelection(Recorder& recorder) {
    ntk_share_listener* listener = nullptr;
    EXPECT_EQ(kNone, ntk_share_add_selection_listener(OnSelection, &recorder, Recorder::Release, &listener));
    return listener;
}

ntk_share_listener* AddChooser(Recorder& recorder) {
    ntk_share_listener* listener = nullptr;
    EXPECT_EQ(kNone, ntk_share_add_chooser_action_listener(OnChooserAction, &recorder, Recorder::Release, &listener));
    return listener;
}

// Opens a Sharesheet for selection and waits for its completion; returns the request ID.
uint64_t OpenForSelection(Recorder& done, const char* text) {
    ntk_share_text_content content = Text(text);
    uint64_t id = 0;
    EXPECT_EQ(kNone, ntk_share_text_for_selection(&content, OnDone, &done, Recorder::Release, &id));
    EXPECT_NE(0u, id);
    return id;
}

class Share : public testing::Test {
protected:
    void TearDown() override {
        // A Sharesheet left open would cover the next case.
        ntktest::UiBackToApp();
        ntktest::DrainMain();
    }
};

}  // namespace

// --- the entry (AP-19): returned, no completion, released here ---

TEST_F(Share, TheEntryChecksReturnAndReleaseOnTheCallingThread) {
    Recorder& recorder = Leaked<Recorder>();
    std::vector<uint8_t> png = ntktest::PngBytes();
    ntk_share_text_content content = Text("x");
    EXPECT_EQ(kInvalid, ntk_share_text(&content, nullptr, 0, nullptr, &recorder, Recorder::Release));
    EXPECT_EQ(kInvalid, ntk_share_text(nullptr, nullptr, 0, OnDone, &recorder, Recorder::Release));
    ntk_share_text_content small = content;
    small.struct_size = 8;
    EXPECT_EQ(kInvalid, ntk_share_text(&small, nullptr, 0, OnDone, &recorder, Recorder::Release));
    ntk_share_text_content bad = Text("\xC0\x80");
    EXPECT_EQ(kInvalid, ntk_share_text(&bad, nullptr, 0, OnDone, &recorder, Recorder::Release));
    ntk_share_text_content no_text = Text(nullptr);
    EXPECT_EQ(kInvalid, ntk_share_text(&no_text, nullptr, 0, OnDone, &recorder, Recorder::Release));
    ntk_share_text_content empty = Text("");
    EXPECT_EQ(NTK_SHARE_ERROR_EMPTY_CONTENT, ntk_share_text(&empty, nullptr, 0, OnDone, &recorder, Recorder::Release));
    EXPECT_EQ(NTK_SHARE_ERROR_EMPTY_CONTENT,
              ntk_share_text_for_selection(&empty, OnDone, &recorder, Recorder::Release, nullptr));
    EXPECT_EQ(kInvalid, ntk_share_text(&content, nullptr, 1, OnDone, &recorder, Recorder::Release));

    // Chooser actions: an empty or repeated ID, or no icon (6.4).
    ntk_share_chooser_action actions[2] = {{"a", "A", png.data(), png.size()}, {"a", "B", png.data(), png.size()}};
    EXPECT_EQ(NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION,
              ntk_share_text(&content, actions, 2, OnDone, &recorder, Recorder::Release));
    actions[1].id = "";
    EXPECT_EQ(NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION,
              ntk_share_text(&content, actions, 2, OnDone, &recorder, Recorder::Release));
    actions[1].id = nullptr;
    EXPECT_EQ(NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION,
              ntk_share_text(&content, actions, 2, OnDone, &recorder, Recorder::Release));
    actions[1].id = "b";
    actions[1].icon_size = 0;
    EXPECT_EQ(NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION,
              ntk_share_text(&content, actions, 2, OnDone, &recorder, Recorder::Release));
    actions[1].icon = nullptr;
    actions[1].icon_size = png.size();
    EXPECT_EQ(NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION,
              ntk_share_text(&content, actions, 2, OnDone, &recorder, Recorder::Release));

    // Files and IDs: none is the empty error, a NULL item is invalid.
    const char* paths[] = {"/a", nullptr};
    EXPECT_EQ(NTK_SHARE_ERROR_EMPTY_FILE_LIST, ntk_share_images(paths, 0, OnDone, &recorder, Recorder::Release));
    EXPECT_EQ(NTK_SHARE_ERROR_EMPTY_FILE_LIST, ntk_share_files(nullptr, 0, OnDone, &recorder, Recorder::Release));
    EXPECT_EQ(kInvalid, ntk_share_files(paths, 2, OnDone, &recorder, Recorder::Release));
    EXPECT_EQ(kInvalid, ntk_share_image(nullptr, nullptr, OnDone, &recorder, Recorder::Release));
    EXPECT_EQ(kInvalid, ntk_share_file("\xED\xA0\x80", OnDone, &recorder, Recorder::Release));
    EXPECT_EQ(NTK_SHARE_ERROR_EMPTY_ID_LIST, ntk_share_remove_direct_targets(paths, 0));
    EXPECT_EQ(kInvalid, ntk_share_remove_direct_targets(paths, 2));

    // Direct Share targets: NULL id or label is invalid, no icon is INVALID_ICON.
    ntk_share_direct_target target{};
    target.struct_size = sizeof(target);
    target.id = "t";
    target.label = "T";
    EXPECT_EQ(NTK_SHARE_ERROR_INVALID_ICON, ntk_share_register_direct_target(&target));
    target.icon = png.data();
    target.icon_size = png.size();
    target.label = nullptr;
    EXPECT_EQ(kInvalid, ntk_share_register_direct_target(&target));
    EXPECT_EQ(kInvalid, ntk_share_register_direct_target(nullptr));

    // Listeners.
    ntk_share_listener* listener = reinterpret_cast<ntk_share_listener*>(1);
    EXPECT_EQ(kInvalid, ntk_share_add_selection_listener(nullptr, &recorder, Recorder::Release, &listener));
    EXPECT_EQ(nullptr, listener);
    EXPECT_EQ(kInvalid, ntk_share_add_chooser_action_listener(OnChooserAction, &recorder, Recorder::Release, nullptr));
    ntk_share_listener_remove(nullptr);

    // 20 asynchronous calls above, each released once here and never completed.
    ntktest::DrainMain();
    EXPECT_EQ(20u, recorder.Count("release"));
    EXPECT_EQ(0u, recorder.Count("done"));
    for (const auto& record : recorder.Records()) EXPECT_EQ(gettid(), record.thread);
}

// --- opening: completed on main once the Sharesheet opened ---

TEST_F(Share, EveryOpeningCompletesNoneOnMainWhenTheSharesheetOpens) {
    std::string image = ntktest::MakeShareFile("ntk_share_1.png", true);
    std::string image2 = ntktest::MakeShareFile("ntk_share_2.png", true);
    std::string file = ntktest::MakeShareFile("ntk_share_1.txt", false);
    const char* images[] = {image.c_str(), image2.c_str()};
    const char* files[] = {file.c_str(), image.c_str()};
    ntk_share_text_content content = Text("Shared from C");
    content.subject = "Subject";
    content.preview_title = "Preview";
    auto open = [](auto&& call) {
        Recorder& recorder = Leaked<Recorder>();
        EXPECT_EQ(kNone, call(recorder));
        EXPECT_EQ(kNone, DoneError(recorder));
        EXPECT_TRUE(recorder.Records()[0].on_main);
        EXPECT_TRUE(ntktest::UiSharesheetShown());
        EXPECT_TRUE(ntktest::UiBackToApp());
        EXPECT_TRUE(recorder.WaitFor("release", 1));
    };
    open([&](Recorder& r) { return ntk_share_text(&content, nullptr, 0, OnDone, &r, Recorder::Release); });
    open([&](Recorder& r) { return ntk_share_image(image.c_str(), nullptr, OnDone, &r, Recorder::Release); });
    open([&](Recorder& r) { return ntk_share_images(images, 2, OnDone, &r, Recorder::Release); });
    open([&](Recorder& r) { return ntk_share_file(file.c_str(), OnDone, &r, Recorder::Release); });
    open([&](Recorder& r) { return ntk_share_files(files, 2, OnDone, &r, Recorder::Release); });
}

TEST_F(Share, FailuresFoundByKotlinComeInTheCompletion) {
    std::vector<uint8_t> png = ntktest::PngBytes();
    std::string image = ntktest::MakeShareFile("ntk_share_3.png", true);
    auto failed = [](auto&& call) {
        Recorder& recorder = Leaked<Recorder>();
        EXPECT_EQ(kNone, call(recorder));
        return DoneError(recorder);
    };
    ntk_share_text_content blank = Text("   ");  // blank, not empty: Kotlin's isBlank (AP-19)
    EXPECT_EQ(NTK_SHARE_ERROR_EMPTY_CONTENT,
              failed([&](Recorder& r) { return ntk_share_text(&blank, nullptr, 0, OnDone, &r, Recorder::Release); }));
    EXPECT_EQ(NTK_SHARE_ERROR_FILE_NOT_FOUND, failed([&](Recorder& r) {
                  return ntk_share_file("/data/local/tmp/ntk-none.txt", OnDone, &r, Recorder::Release);
              }));
    EXPECT_EQ(NTK_SHARE_ERROR_ILLEGAL_FILE_ACCESS, failed([&](Recorder& r) {
                  return ntk_share_file("/system/etc/hosts", OnDone, &r, Recorder::Release);
              }));
    EXPECT_EQ(NTK_SHARE_ERROR_INVALID_MIME_TYPE, failed([&](Recorder& r) {
                  return ntk_share_image(image.c_str(), " ", OnDone, &r, Recorder::Release);
              }));
    const uint8_t unreadable[] = {1, 2, 3};
    ntk_share_chooser_action action = {"bad", "Bad", unreadable, sizeof(unreadable)};
    ntk_share_text_content content = Text("x");
    EXPECT_EQ(NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION, failed([&](Recorder& r) {
                  return ntk_share_text(&content, &action, 1, OnDone, &r, Recorder::Release);
              }));
}

TEST_F(Share, FromTheBackEveryOpeningIsNotForeground) {
    std::string image = ntktest::MakeShareFile("ntk_share_4.png", true);
    const char* paths[] = {image.c_str()};
    ntk_share_text_content content = Text("x");
    ASSERT_TRUE(ntktest::UiHome());
    auto from_back = [](auto&& call) {
        Recorder& recorder = Leaked<Recorder>();
        EXPECT_EQ(kNone, call(recorder));
        return DoneError(recorder);
    };
    constexpr ntk_share_error kBack = NTK_SHARE_ERROR_NOT_FOREGROUND;
    EXPECT_EQ(kBack, from_back([&](Recorder& r) { return ntk_share_text(&content, nullptr, 0, OnDone, &r, Recorder::Release); }));
    EXPECT_EQ(kBack, from_back([&](Recorder& r) { return ntk_share_image(image.c_str(), nullptr, OnDone, &r, Recorder::Release); }));
    EXPECT_EQ(kBack, from_back([&](Recorder& r) { return ntk_share_images(paths, 1, OnDone, &r, Recorder::Release); }));
    EXPECT_EQ(kBack, from_back([&](Recorder& r) { return ntk_share_file(image.c_str(), OnDone, &r, Recorder::Release); }));
    EXPECT_EQ(kBack, from_back([&](Recorder& r) { return ntk_share_files(paths, 1, OnDone, &r, Recorder::Release); }));
    EXPECT_EQ(kBack, from_back([&](Recorder& r) {
                  return ntk_share_text_for_selection(&content, OnDone, &r, Recorder::Release, nullptr);
              }));
}

// --- Direct Share (synchronous) ---

TEST_F(Share, DirectShareTargetsAreRegisteredAndRemoved) {
    std::vector<uint8_t> png = ntktest::PngBytes();
    ntk_share_direct_target target{};
    target.struct_size = sizeof(target);
    target.id = "ntk-direct-1";
    target.label = "NTK direct";
    target.icon = png.data();
    target.icon_size = png.size();
    ASSERT_EQ(kNone, ntk_share_register_direct_target(&target));
    EXPECT_NE(std::string::npos, ntktest::DynamicShortcutIds().find("ntk-direct-1"));
    const uint8_t unreadable[] = {1, 2, 3};
    target.id = "ntk-direct-2";
    target.icon = unreadable;
    target.icon_size = sizeof(unreadable);
    EXPECT_EQ(NTK_SHARE_ERROR_INVALID_ICON, ntk_share_register_direct_target(&target));
    const char* ids[] = {"ntk-direct-1"};
    ASSERT_EQ(kNone, ntk_share_remove_direct_targets(ids, 1));
    EXPECT_EQ(std::string::npos, ntktest::DynamicShortcutIds().find("ntk-direct"));
}

// --- the selection events and their request IDs (AP-17, 12.2) ---

TEST_F(Share, ThePickedAppArrivesWithTheRequestId) {
    Recorder& events = Leaked<Recorder>();
    AddSelection(events);
    Recorder& done = Leaked<Recorder>();
    uint64_t id = OpenForSelection(done, "Pick me");
    ASSERT_EQ(kNone, DoneError(done));
    ASSERT_TRUE(ntktest::UiPick(kTarget));
    ASSERT_TRUE(events.WaitFor("event", 1, std::chrono::seconds(10)));
    EXPECT_EQ(static_cast<int64_t>(id), events.Records()[0].value);
    EXPECT_EQ(ntktest::TestPackage(), events.Records()[0].detail);
    EXPECT_TRUE(events.Records()[0].on_main);
}

TEST_F(Share, ACanceledWaitGetsNoPick) {
    Recorder& events = Leaked<Recorder>();
    AddSelection(events);
    Recorder& done = Leaked<Recorder>();
    uint64_t id = OpenForSelection(done, "Cancel me");
    ASSERT_EQ(kNone, DoneError(done));
    EXPECT_EQ(kNone, ntk_share_cancel_selection(id));
    ntktest::DrainMain();
    ASSERT_TRUE(ntktest::UiPick(kTarget));
    EXPECT_FALSE(events.WaitFor("event", 1, kQuiet));
}

TEST_F(Share, ANotForegroundRequestLeavesTheEarlierWait) {
    Recorder& events = Leaked<Recorder>();
    AddSelection(events);
    Recorder& first = Leaked<Recorder>();
    uint64_t id = OpenForSelection(first, "Earlier");
    ASSERT_EQ(kNone, DoneError(first));
    ASSERT_TRUE(ntktest::UiSharesheetShown());
    // The Sharesheet is a sheet over the app, which stays started, so the app is still in the
    // foreground (part 1, 5.8). Finishing the app's Activity leaves the Sharesheet (a task of
    // its own) and takes the app out of the foreground: the next request is NOT_FOREGROUND and
    // has no token, so canceling it changes nothing.
    ASSERT_TRUE(ntktest::UiFinishForeground());
    Recorder& second = Leaked<Recorder>();
    uint64_t later = OpenForSelection(second, "Later");
    ASSERT_EQ(NTK_SHARE_ERROR_NOT_FOREGROUND, DoneError(second));
    EXPECT_EQ(kNone, ntk_share_cancel_selection(later));
    ntktest::DrainMain();
    ASSERT_TRUE(ntktest::UiPick(kTarget));
    ASSERT_TRUE(events.WaitFor("event", 1, std::chrono::seconds(10)));
    EXPECT_EQ(static_cast<int64_t>(id), events.Records()[0].value);
}

TEST_F(Share, ABlankTextLeavesTheEarlierWait) {
    // Both run on main back to back, before the Sharesheet covers the app: the blank one fails in
    // Kotlin before its token, so the earlier wait stays (AP-17).
    Recorder& events = Leaked<Recorder>();
    AddSelection(events);
    Recorder& first = Leaked<Recorder>();
    Recorder& second = Leaked<Recorder>();
    ntktest::HoldMain();
    uint64_t id = OpenForSelection(first, "Earlier");
    OpenForSelection(second, "   ");
    ntktest::UnholdMain();
    ASSERT_EQ(kNone, DoneError(first));
    ASSERT_EQ(NTK_SHARE_ERROR_EMPTY_CONTENT, DoneError(second));
    ASSERT_TRUE(ntktest::UiPick(kTarget));
    ASSERT_TRUE(events.WaitFor("event", 1, std::chrono::seconds(10)));
    EXPECT_EQ(static_cast<int64_t>(id), events.Records()[0].value);
}

TEST_F(Share, ALaterOpeningReplacesTheWait) {
    Recorder& events = Leaked<Recorder>();
    AddSelection(events);
    Recorder& first = Leaked<Recorder>();
    Recorder& second = Leaked<Recorder>();
    ntktest::HoldMain();
    OpenForSelection(first, "Earlier");
    uint64_t later = OpenForSelection(second, "Later");
    ntktest::UnholdMain();
    ASSERT_EQ(kNone, DoneError(first));
    ASSERT_EQ(kNone, DoneError(second));
    // Android may show either Sharesheet (the second start can bring the first one back). A pick
    // in the earlier one is not delivered; one in the later one carries the later ID.
    ASSERT_TRUE(ntktest::UiPick(kTarget));
    events.WaitFor("event", 1, std::chrono::seconds(5));
    EXPECT_LE(events.Count("event"), 1u);
    for (const auto& record : events.Records()) {
        if (record.what == "event") EXPECT_EQ(static_cast<int64_t>(later), record.value);
    }
}

TEST_F(Share, APickOfAShareKotlinOpenedIsNotDelivered) {
    Recorder& events = Leaked<Recorder>();
    AddSelection(events);
    ntktest::DrainMain();
    ntktest::ShareFromKotlin("From Kotlin");
    ASSERT_TRUE(ntktest::UiPick(kTarget));
    EXPECT_FALSE(events.WaitFor("event", 1, kQuiet));
}

// --- chooser actions (AP-7) and removing listeners (AP-11) ---

TEST_F(Share, ChooserActionsReachTheListenerAndEndWithTheNextShare) {
    std::vector<uint8_t> png = ntktest::PngBytes();
    Recorder& events = Leaked<Recorder>();
    AddChooser(events);
    ntk_share_text_content content = Text("With an action");
    ntk_share_chooser_action action = {"act-a", "NTK action A", png.data(), png.size()};
    Recorder& done = Leaked<Recorder>();
    ASSERT_EQ(kNone, ntk_share_text(&content, &action, 1, OnDone, &done, Recorder::Release));
    ASSERT_EQ(kNone, DoneError(done));
    ASSERT_TRUE(ntktest::UiPick("NTK action A"));
    ASSERT_TRUE(events.WaitFor("event", 1, std::chrono::seconds(10)));
    EXPECT_EQ("act-a", events.Records()[0].detail);
    ASSERT_TRUE(ntktest::UiBackToApp());

    // A share with actions, then one without, back to back: the first Sharesheet's action no
    // longer reaches C once the second share replaced the actions (AP-7).
    ntk_share_chooser_action stale = {"act-b", "NTK action B", png.data(), png.size()};
    Recorder& first = Leaked<Recorder>();
    Recorder& second = Leaked<Recorder>();
    ntktest::HoldMain();
    ASSERT_EQ(kNone, ntk_share_text(&content, &stale, 1, OnDone, &first, Recorder::Release));
    ASSERT_EQ(kNone, ntk_share_text(&content, nullptr, 0, OnDone, &second, Recorder::Release));
    ntktest::UnholdMain();
    ASSERT_EQ(kNone, DoneError(first));
    ASSERT_EQ(kNone, DoneError(second));
    ASSERT_TRUE(ntktest::UiPick("NTK action B"));
    EXPECT_FALSE(events.WaitFor("event", 2, kQuiet));
}

TEST_F(Share, RemovingAListenerKeepsTheWaitAndTheActions) {
    // The selection wait stays when its listener goes; a new listener gets the pick.
    Recorder& removed = Leaked<Recorder>();
    ntk_share_listener* listener = AddSelection(removed);
    Recorder& done = Leaked<Recorder>();
    uint64_t id = OpenForSelection(done, "Keep waiting");
    ASSERT_EQ(kNone, DoneError(done));
    ntk_share_listener_remove(listener);
    Recorder& events = Leaked<Recorder>();
    AddSelection(events);
    ntktest::DrainMain();
    ASSERT_TRUE(ntktest::UiPick(kTarget));
    ASSERT_TRUE(events.WaitFor("event", 1, std::chrono::seconds(10)));
    EXPECT_EQ(static_cast<int64_t>(id), events.Records()[0].value);
    EXPECT_EQ(0u, removed.Count("event"));
    ASSERT_TRUE(ntktest::UiBackToApp());

    // The action stays pressable when the chooser listener goes; it just reaches no one.
    std::vector<uint8_t> png = ntktest::PngBytes();
    Recorder& chooser = Leaked<Recorder>();
    ntk_share_listener* chooser_listener = AddChooser(chooser);
    ntk_share_text_content content = Text("Action without a listener");
    ntk_share_chooser_action action = {"act-c", "NTK action C", png.data(), png.size()};
    Recorder& opened = Leaked<Recorder>();
    ASSERT_EQ(kNone, ntk_share_text(&content, &action, 1, OnDone, &opened, Recorder::Release));
    ASSERT_EQ(kNone, DoneError(opened));
    ntk_share_listener_remove(chooser_listener);
    ntktest::DrainMain();
    ASSERT_TRUE(ntktest::UiPick("NTK action C"));
    EXPECT_FALSE(chooser.WaitFor("event", 1, kQuiet));
    EXPECT_EQ(1u, chooser.Count("release"));
}
