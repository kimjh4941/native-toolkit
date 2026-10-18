// The notification content and channel builders (C ABI design part 2, 6.3 and 12.1 ビルダー;
// AP-4, AP-8). The builders have no getters: what they hold is checked when an operation shows
// it (TB-6). Here: what they accept and reject.
#include <gtest/gtest.h>

#include <cstring>
#include <vector>

#include <NativeToolkitC/Notification.h>

namespace {

struct ContentGuard {
    ntk_notification_content* content = nullptr;
    ~ContentGuard() { ntk_notification_content_free(content); }
};

struct ChannelGuard {
    ntk_notification_channel* channel = nullptr;
    ~ChannelGuard() { ntk_notification_channel_free(channel); }
};

constexpr ntk_notification_error kNone = NTK_NOTIFICATION_ERROR_NONE;
constexpr ntk_notification_error kInvalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;

ntk_notification_action Action(const char* title, const char* action_id) {
    ntk_notification_action action{};
    action.struct_size = sizeof(action);
    action.title = title;
    action.action_id = action_id;
    return action;
}

class NotificationBuilder : public testing::Test {
protected:
    void SetUp() override { ASSERT_EQ(kNone, ntk_notification_content_create(1, "Title", "Message", &c.content)); }
    ContentGuard c;
};

}  // namespace

TEST(NotificationContent, CreateNeedsAnOutputAndTakesNullAsEmpty) {
    EXPECT_EQ(kInvalid, ntk_notification_content_create(1, "t", "m", nullptr));
    ContentGuard g;
    EXPECT_EQ(kNone, ntk_notification_content_create(-5, nullptr, nullptr, &g.content));
    EXPECT_NE(nullptr, g.content);
    auto* out = reinterpret_cast<ntk_notification_content*>(0x1);
    EXPECT_EQ(kInvalid, ntk_notification_content_create(1, "\xED\xA0\x80", "m", &out));
    EXPECT_EQ(nullptr, out);
    ntk_notification_content_free(nullptr);
}

TEST_F(NotificationBuilder, ANullContentIsRejectedBySetters) {
    EXPECT_EQ(kInvalid, ntk_notification_content_set_tag(nullptr, "t"));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_priority(nullptr, 0));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_auto_cancel(nullptr, 1));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_data(nullptr, "k", "v"));
}

TEST_F(NotificationBuilder, TextsMustBeStrictUtf8AndNullUnsets) {
    EXPECT_EQ(kInvalid, ntk_notification_content_set_tag(c.content, "\xC0\x80"));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_sub_text(c.content, "\xF4\x90\x80\x80"));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_small_icon(c.content, "\xED\xBF\xBF"));
    EXPECT_EQ(kNone, ntk_notification_content_set_tag(c.content, "a tag"));
    EXPECT_EQ(kNone, ntk_notification_content_set_tag(c.content, nullptr));
    EXPECT_EQ(kNone, ntk_notification_content_set_small_icon(c.content, "ic_launcher"));
    EXPECT_EQ(kNone, ntk_notification_content_set_sound(c.content, nullptr));
}

TEST_F(NotificationBuilder, NumbersOutOfRangeAreRejectedNotCorrected) {
    EXPECT_EQ(kInvalid, ntk_notification_content_set_priority(c.content, -3));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_priority(c.content, 3));
    EXPECT_EQ(kNone, ntk_notification_content_set_priority(c.content, -2));
    EXPECT_EQ(kNone, ntk_notification_content_set_priority(c.content, 2));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_visibility(c.content, -2));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_visibility(c.content, 2));
    EXPECT_EQ(kNone, ntk_notification_content_set_visibility(c.content, -1));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_group_alert_behavior(c.content, 3));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_group_alert_behavior(c.content, -1));
    EXPECT_EQ(kNone, ntk_notification_content_set_group_alert_behavior(c.content, 2));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_timestamp(c.content, -1));
    EXPECT_EQ(kNone, ntk_notification_content_set_timestamp(c.content, 0));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_timeout_after(c.content, -1));
    EXPECT_EQ(kNone, ntk_notification_content_set_number(c.content, -7));
    EXPECT_EQ(kNone, ntk_notification_content_set_color(c.content, 0xFF00FF00u));
}

TEST_F(NotificationBuilder, ProgressNeedsCurrentWithinMaxUnlessIndeterminate) {
    EXPECT_EQ(kNone, ntk_notification_content_set_progress(c.content, 100, 0, 0));
    EXPECT_EQ(kNone, ntk_notification_content_set_progress(c.content, 100, 100, 0));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_progress(c.content, 100, 101, 0));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_progress(c.content, 100, -1, 0));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_progress(c.content, -1, 0, 0));
    EXPECT_EQ(kNone, ntk_notification_content_set_progress(c.content, 0, 50, 1));
}

TEST_F(NotificationBuilder, AMessageOrAViewClickNeedsItsStyle) {
    EXPECT_EQ(kInvalid, ntk_notification_content_add_message(c.content, "hi", 0, nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_view_click(c.content, "button", "clicked"));
    ASSERT_EQ(kNone, ntk_notification_content_set_style_messaging(c.content, "Me", nullptr, -1));
    EXPECT_EQ(kNone, ntk_notification_content_add_message(c.content, "hi", 1000, nullptr));
    EXPECT_EQ(kNone, ntk_notification_content_add_message(c.content, "yo", 2000, "Them"));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_message(c.content, nullptr, 0, nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_message(c.content, "neg", -1, nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_view_click(c.content, "button", "clicked"));
    // The last style set wins: after another style, messages are no longer accepted.
    ASSERT_EQ(kNone, ntk_notification_content_set_style_custom_view(c.content, "notification_custom", nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_message(c.content, "late", 0, nullptr));
    EXPECT_EQ(kNone, ntk_notification_content_add_view_click(c.content, "button", "clicked"));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_view_click(c.content, nullptr, "clicked"));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_view_click(c.content, "button", nullptr));
    ASSERT_EQ(kNone, ntk_notification_content_set_style_big_text(c.content, "big", nullptr, nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_view_click(c.content, "button", "clicked"));
}

TEST_F(NotificationBuilder, StylesRejectWhatKotlinRequires) {
    EXPECT_EQ(kInvalid, ntk_notification_content_set_style_big_text(c.content, nullptr, "s", "t"));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_style_messaging(c.content, nullptr, nullptr, -1));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_style_messaging(c.content, "Me", nullptr, 2));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_style_big_picture(c.content, nullptr, nullptr, nullptr, nullptr,
                                                                       nullptr, 0));
    EXPECT_EQ(kNone, ntk_notification_content_set_style_big_picture(c.content, nullptr, "content://x/y", nullptr,
                                                                    nullptr, nullptr, 0));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_style_custom_view(c.content, nullptr, "big"));
    const char* lines[] = {"one", nullptr};
    EXPECT_EQ(kInvalid, ntk_notification_content_set_style_inbox(c.content, lines, 2, nullptr, nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_style_inbox(c.content, nullptr, 1, nullptr, nullptr));
    EXPECT_EQ(kNone, ntk_notification_content_set_style_inbox(c.content, lines, 1, nullptr, nullptr));
    EXPECT_EQ(kNone, ntk_notification_content_set_style_inbox(c.content, nullptr, 0, "summary", nullptr));
}

TEST_F(NotificationBuilder, TapDataAndEventFlags) {
    EXPECT_EQ(kNone, ntk_notification_content_set_tap(c.content, NTK_NOTIFICATION_TAP_EVENT_ONLY));
    EXPECT_EQ(kNone, ntk_notification_content_set_tap(c.content, NTK_NOTIFICATION_TAP_NONE));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_tap(c.content, 3));
    EXPECT_EQ(kInvalid, ntk_notification_content_set_tap(c.content, -1));
    EXPECT_EQ(kNone, ntk_notification_content_add_data(c.content, "k", "v"));
    EXPECT_EQ(kNone, ntk_notification_content_add_data(c.content, "k", "replaced"));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_data(c.content, nullptr, "v"));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_data(c.content, "k", nullptr));
    EXPECT_EQ(kNone, ntk_notification_content_set_dismiss_event(c.content, 0));
    EXPECT_EQ(kNone, ntk_notification_content_set_full_screen(c.content, 1));
}

TEST_F(NotificationBuilder, AnActionFollowsTheStructSizeRules) {
    ntk_notification_action action = Action("Reply", "reply");
    EXPECT_EQ(kNone, ntk_notification_content_add_action(c.content, &action));
    EXPECT_EQ(kInvalid, ntk_notification_content_add_action(c.content, nullptr));
    ntk_notification_action bad = action;
    bad.struct_size = 8;
    EXPECT_EQ(kInvalid, ntk_notification_content_add_action(c.content, &bad));
    bad = action;
    bad.reserved0 = 1;
    EXPECT_EQ(kInvalid, ntk_notification_content_add_action(c.content, &bad));
    bad = action;
    bad.reserved1 = 1;
    EXPECT_EQ(kInvalid, ntk_notification_content_add_action(c.content, &bad));
    bad = Action(nullptr, "id");
    EXPECT_EQ(kInvalid, ntk_notification_content_add_action(c.content, &bad));
    bad = Action("t", nullptr);
    EXPECT_EQ(kInvalid, ntk_notification_content_add_action(c.content, &bad));
    bad = Action("t", "\xC0\x80");
    EXPECT_EQ(kInvalid, ntk_notification_content_add_action(c.content, &bad));
    bad = action;
    bad.semantic_action = 13;
    EXPECT_EQ(kInvalid, ntk_notification_content_add_action(c.content, &bad));
    bad.semantic_action = 12;
    EXPECT_EQ(kNone, ntk_notification_content_add_action(c.content, &bad));

    std::vector<unsigned char> newer(sizeof(ntk_notification_action) + 8, 0);
    action.struct_size = static_cast<uint32_t>(newer.size());
    std::memcpy(newer.data(), &action, sizeof(action));
    auto* as_action = reinterpret_cast<const ntk_notification_action*>(newer.data());
    EXPECT_EQ(kNone, ntk_notification_content_add_action(c.content, as_action));
    newer.back() = 1;
    EXPECT_EQ(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, ntk_notification_content_add_action(c.content, as_action));
}

TEST(NotificationChannel, CreateChecksTheIdNameAndImportance) {
    ChannelGuard g;
    EXPECT_EQ(kInvalid, ntk_notification_channel_create("id", "Name", 3, nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_channel_create(nullptr, "Name", 3, &g.channel));
    EXPECT_EQ(nullptr, g.channel);
    EXPECT_EQ(kInvalid, ntk_notification_channel_create("", "Name", 3, &g.channel));
    EXPECT_EQ(kInvalid, ntk_notification_channel_create("id", nullptr, 3, &g.channel));
    // 5 would be lowered to 3 by Kotlin, so it is rejected (AP-8).
    EXPECT_EQ(kInvalid, ntk_notification_channel_create("id", "Name", 5, &g.channel));
    EXPECT_EQ(kInvalid, ntk_notification_channel_create("id", "Name", -1, &g.channel));
    EXPECT_EQ(kNone, ntk_notification_channel_create("id", "Name", 4, &g.channel));
    EXPECT_NE(nullptr, g.channel);
    ntk_notification_channel_free(nullptr);
}

TEST(NotificationChannel, SettersCheckTheirValues) {
    ChannelGuard g;
    ASSERT_EQ(kNone, ntk_notification_channel_create("id", "Name", 0, &g.channel));
    EXPECT_EQ(kInvalid, ntk_notification_channel_set_lockscreen_visibility(g.channel, 2));
    EXPECT_EQ(kInvalid, ntk_notification_channel_set_lockscreen_visibility(g.channel, -2));
    EXPECT_EQ(kNone, ntk_notification_channel_set_lockscreen_visibility(g.channel, -1));
    const int64_t pattern[] = {0, 100, 50};
    const int64_t negative[] = {0, -1};
    EXPECT_EQ(kNone, ntk_notification_channel_set_vibration_pattern(g.channel, pattern, 3));
    EXPECT_EQ(kInvalid, ntk_notification_channel_set_vibration_pattern(g.channel, negative, 2));
    EXPECT_EQ(kInvalid, ntk_notification_channel_set_vibration_pattern(g.channel, nullptr, 1));
    EXPECT_EQ(kNone, ntk_notification_channel_set_vibration_pattern(g.channel, nullptr, 0));
    EXPECT_EQ(kInvalid, ntk_notification_channel_set_group(g.channel, "group", nullptr));
    EXPECT_EQ(kNone, ntk_notification_channel_set_group(g.channel, "group", "Group"));
    EXPECT_EQ(kNone, ntk_notification_channel_set_group(g.channel, nullptr, nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_channel_set_description(g.channel, "\xED\xA0\x80"));
    EXPECT_EQ(kInvalid, ntk_notification_channel_set_show_badge(nullptr, 1));
}

TEST_F(NotificationBuilder, TheChannelIsCopiedSoItsBuilderCanBeFreed) {
    ntk_notification_channel* channel = nullptr;
    ASSERT_EQ(kNone, ntk_notification_channel_create("copied", "Copied", 3, &channel));
    ASSERT_EQ(kNone, ntk_notification_content_set_channel(c.content, channel));
    ntk_notification_channel_free(channel);
    // The content still holds its own copy; setting another channel or none works.
    EXPECT_EQ(kNone, ntk_notification_content_set_channel(c.content, nullptr));
}
