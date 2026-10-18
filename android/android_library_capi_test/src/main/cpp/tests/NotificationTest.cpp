// Notification operations through the C ABI (C ABI design part 2, 6.3, 11.2 and 12.1: the
// mapping table, the foreground, progress, the prior checks with the permission granted, the
// default tap and dismissal, the zero-filled schedule). What the builders hold is read back from
// the notification the system shows. The cases without the permission are in the noStartup
// flavor, which never grants it (ManualInitTest).
#include <gtest/gtest.h>

#include <unistd.h>

#include <chrono>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

#include <NativeToolkitC/Notification.h>

#include "../TestSupport.h"

using ntktest::Leaked;
using ntktest::Recorder;

namespace {

constexpr ntk_notification_error kNone = NTK_NOTIFICATION_ERROR_NONE;
constexpr ntk_notification_error kInvalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;

struct Content {
    ntk_notification_content* content = nullptr;
    explicit Content(int32_t id, const char* title = "Title", const char* message = "Message") {
        EXPECT_EQ(kNone, ntk_notification_content_create(id, title, message, &content));
    }
    ~Content() { ntk_notification_content_free(content); }
};

int64_t NowMillis() {
    timespec now{};
    clock_gettime(CLOCK_REALTIME, &now);
    return static_cast<int64_t>(now.tv_sec) * 1000 + now.tv_nsec / 1000000;
}

ntk_notification_schedule_options Schedule(int64_t trigger) {
    ntk_notification_schedule_options schedule{};
    schedule.struct_size = sizeof(schedule);
    schedule.trigger_at_millis = trigger;
    return schedule;
}

std::string Field(int32_t id, const char* name, const char* tag = nullptr) {
    return ntktest::NotificationField(id, tag, name);
}

class Notification : public testing::Test {
protected:
    void SetUp() override { ntktest::GrantNotifications(); }
    void TearDown() override {
        ntk_notification_stop_progress();
        ntk_notification_remove_all();
        ntk_notification_cancel_all_scheduled();
        ntktest::DrainMain();
    }
};

void OnPermission(void* user_data, uint64_t, ntk_notification_error error, uint32_t system_code,
                  ntk_notification_permission_result result) {
    EXPECT_EQ(0u, system_code);  // 12.1: the completion's system_code is 0 (part 1, AC-10)
    static_cast<Recorder*>(user_data)->Add({"done", error, result});
}

void OnSettings(void* user_data, ntk_notification_error error, uint32_t system_code,
                ntk_notification_settings_result result) {
    EXPECT_EQ(0u, system_code);
    static_cast<Recorder*>(user_data)->Add({"done", error, result});
}

}  // namespace

// --- the entry ---

TEST_F(Notification, InvalidArgumentsAreRejectedAtTheEntry) {
    EXPECT_EQ(kInvalid, ntk_notification_show(nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_update(nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_start_progress(nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_create_channel(nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_delete_channel(nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_remove(1, "\xC0\x80"));
    EXPECT_EQ(kInvalid, ntk_notification_has_permission(nullptr));
    int32_t value = 7;
    EXPECT_EQ(kInvalid, ntk_notification_is_scheduled(1, nullptr, nullptr));
    EXPECT_EQ(kInvalid, ntk_notification_is_scheduled(1, "\xED\xA0\x80", &value));
    EXPECT_EQ(0, value);

    Content c(201);
    EXPECT_EQ(kInvalid, ntk_notification_schedule(c.content, nullptr));
    ntk_notification_schedule_options schedule = Schedule(0);
    EXPECT_EQ(kInvalid, ntk_notification_schedule(c.content, &schedule));
    schedule = Schedule(NowMillis() + 60000);
    schedule.alarm_type = 2;  // ELAPSED_REALTIME: not Unix time (AP-22)
    EXPECT_EQ(kInvalid, ntk_notification_schedule(c.content, &schedule));
    schedule.alarm_type = 0;
    schedule.reserved0 = 1;
    EXPECT_EQ(kInvalid, ntk_notification_schedule(c.content, &schedule));
    schedule.reserved0 = 0;
    std::vector<unsigned char> newer(sizeof(schedule) + 8, 0);
    schedule.struct_size = static_cast<uint32_t>(newer.size());
    std::memcpy(newer.data(), &schedule, sizeof(schedule));
    newer.back() = 1;
    EXPECT_EQ(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED,
              ntk_notification_schedule(c.content, reinterpret_cast<ntk_notification_schedule_options*>(newer.data())));

    Recorder& recorder = Leaked<Recorder>();
    EXPECT_EQ(kInvalid, ntk_notification_open_settings_async(3, OnSettings, &recorder, Recorder::Release));
    EXPECT_EQ(kInvalid, ntk_notification_request_permission(nullptr, &recorder, Recorder::Release, nullptr));
    ASSERT_EQ(2u, recorder.Count("release"));
    for (const auto& record : recorder.Records()) EXPECT_EQ(gettid(), record.thread);
}

// --- show: what the builder holds reaches the notification ---

TEST_F(Notification, AZeroConfiguredContentGetsTheDefaultsAndTheEvents) {
    Content c(202, "Defaults", "Nothing set");
    ASSERT_EQ(kNone, ntk_notification_show(c.content));
    ASSERT_TRUE(ntktest::WaitShown(202, nullptr));
    EXPECT_EQ("Defaults", Field(202, "title"));
    EXPECT_EQ("Nothing set", Field(202, "text"));
    EXPECT_EQ("default_channel", Field(202, "channel"));
    EXPECT_EQ("true", Field(202, "autoCancel"));
    // AP-18: the body tap and the dismissal are there unless turned off.
    EXPECT_EQ("true", Field(202, "contentIntent"));
    EXPECT_EQ("true", Field(202, "deleteIntent"));
    EXPECT_EQ("false", Field(202, "fullScreenIntent"));
}

TEST_F(Notification, TheContentAndItsChannelReachTheNotification) {
    ntk_notification_channel* channel = nullptr;
    ASSERT_EQ(kNone, ntk_notification_channel_create("ntk_test_channel", "Test channel", 4, &channel));
    ASSERT_EQ(kNone, ntk_notification_channel_set_description(channel, "Made by the C ABI tests"));
    ASSERT_EQ(kNone, ntk_notification_channel_set_show_badge(channel, 0));
    Content c(203, "Everything", "Set");
    ASSERT_EQ(kNone, ntk_notification_content_set_channel(c.content, channel));
    // The content has its own copy: freeing the builder changes nothing.
    ntk_notification_channel_free(channel);
    ASSERT_EQ(kNone, ntk_notification_content_set_tag(c.content, "tag-203"));
    ASSERT_EQ(kNone, ntk_notification_content_set_small_icon(c.content, "ntk_test_icon"));
    ASSERT_EQ(kNone, ntk_notification_content_set_sub_text(c.content, "sub"));
    ASSERT_EQ(kNone, ntk_notification_content_set_category(c.content, "msg"));
    ASSERT_EQ(kNone, ntk_notification_content_set_number(c.content, 7));
    ASSERT_EQ(kNone, ntk_notification_content_set_color(c.content, 0xFF336699u));
    ASSERT_EQ(kNone, ntk_notification_content_set_group(c.content, "group-1"));
    ASSERT_EQ(kNone, ntk_notification_content_set_sort_key(c.content, "b"));
    ASSERT_EQ(kNone, ntk_notification_content_set_visibility(c.content, -1));
    ASSERT_EQ(kNone, ntk_notification_content_set_auto_cancel(c.content, 0));
    ASSERT_EQ(kNone, ntk_notification_content_set_ongoing(c.content, 1));
    ASSERT_EQ(kNone, ntk_notification_content_set_timeout_after(c.content, 60000));
    ASSERT_EQ(kNone, ntk_notification_show(c.content));
    ASSERT_TRUE(ntktest::WaitShown(203, "tag-203"));
    EXPECT_EQ("ntk_test_channel", Field(203, "channel", "tag-203"));
    EXPECT_EQ(ntktest::ResourceId("ntk_test_icon", "drawable"), Field(203, "smallIcon", "tag-203"));
    EXPECT_EQ("sub", Field(203, "subText", "tag-203"));
    EXPECT_EQ("msg", Field(203, "category", "tag-203"));
    EXPECT_EQ("7", Field(203, "number", "tag-203"));
    EXPECT_EQ("ff336699", Field(203, "color", "tag-203"));
    EXPECT_EQ("group-1", Field(203, "group", "tag-203"));
    EXPECT_EQ("b", Field(203, "sortKey", "tag-203"));
    EXPECT_EQ("-1", Field(203, "visibility", "tag-203"));
    EXPECT_EQ("false", Field(203, "autoCancel", "tag-203"));
    EXPECT_EQ("true", Field(203, "ongoing", "tag-203"));
    EXPECT_EQ("60000", Field(203, "timeoutAfter", "tag-203"));
    EXPECT_EQ("4", ntktest::ChannelField("ntk_test_channel", "importance"));
    EXPECT_EQ("Made by the C ABI tests", ntktest::ChannelField("ntk_test_channel", "description"));
    EXPECT_EQ("false", ntktest::ChannelField("ntk_test_channel", "showBadge"));
}

TEST_F(Notification, TheRemainingContentSettersReachTheNotification) {
    Content c(208);
    ASSERT_EQ(kNone, ntk_notification_content_set_large_icon(c.content, "ntk_test_icon"));
    ASSERT_EQ(kNone, ntk_notification_content_set_show_timestamp(c.content, 0));
    ASSERT_EQ(kNone, ntk_notification_content_set_ticker(c.content, "tick"));
    ASSERT_EQ(kNone, ntk_notification_content_set_group(c.content, "group-2"));
    ASSERT_EQ(kNone, ntk_notification_content_set_group_summary(c.content, 1));
    ASSERT_EQ(kNone, ntk_notification_content_set_only_alert_once(c.content, 1));
    ASSERT_EQ(kNone, ntk_notification_content_set_local_only(c.content, 1));
    ASSERT_EQ(kNone, ntk_notification_content_set_uses_chronometer(c.content, 1));
    ASSERT_EQ(kNone, ntk_notification_show(c.content));
    ASSERT_TRUE(ntktest::WaitShown(208, nullptr));
    EXPECT_EQ("true", Field(208, "largeIcon"));
    EXPECT_EQ("false", Field(208, "showWhen"));
    EXPECT_EQ("tick", Field(208, "ticker"));
    EXPECT_EQ("true", Field(208, "groupSummary"));
    EXPECT_EQ("true", Field(208, "onlyAlertOnce"));
    EXPECT_EQ("true", Field(208, "localOnly"));
    EXPECT_EQ("true", Field(208, "usesChronometer"));

    // AndroidX makes a silent notification that is not a summary alert only through its summary.
    // (Its "silent" group is not checked: Android 16 regroups groups without a summary.)
    Content silent(209);
    ASSERT_EQ(kNone, ntk_notification_content_set_silent(silent.content, 1));
    ASSERT_EQ(kNone, ntk_notification_show(silent.content));
    ASSERT_TRUE(ntktest::WaitShown(209, nullptr));
    EXPECT_EQ("1", Field(209, "groupAlertBehavior"));  // GROUP_ALERT_SUMMARY; the default is ALL (0)
}

TEST_F(Notification, TheChannelAlertSettersReachTheChannel) {
    // A new ID: Android keeps a channel's lights, vibration and sound from its first creation. Lights and
    // vibration are on by Kotlin's default, so turning them off shows that the values arrive.
    ntk_notification_channel* channel = nullptr;
    ASSERT_EQ(kNone, ntk_notification_channel_create("ntk_test_alerting", "Alerting", 3, &channel));
    ASSERT_EQ(kNone, ntk_notification_channel_set_enable_lights(channel, 0));
    ASSERT_EQ(kNone, ntk_notification_channel_set_light_color(channel, 0xFF00FF00u));
    ASSERT_EQ(kNone, ntk_notification_channel_set_enable_vibration(channel, 0));
    ASSERT_EQ(kNone, ntk_notification_channel_set_sound(channel, "content://settings/system/notification_sound"));
    ASSERT_EQ(kNone, ntk_notification_create_channel(channel));
    ntk_notification_channel_free(channel);
    EXPECT_EQ("false", ntktest::ChannelField("ntk_test_alerting", "lights"));
    EXPECT_EQ("ff00ff00", ntktest::ChannelField("ntk_test_alerting", "lightColor"));
    EXPECT_EQ("false", ntktest::ChannelField("ntk_test_alerting", "vibrates"));
    EXPECT_EQ("content://settings/system/notification_sound", ntktest::ChannelField("ntk_test_alerting", "sound"));
}

TEST_F(Notification, TheTapAndDismissEventsCanBeTurnedOff) {
    Content none(204);
    ASSERT_EQ(kNone, ntk_notification_content_set_tap(none.content, NTK_NOTIFICATION_TAP_NONE));
    ASSERT_EQ(kNone, ntk_notification_content_set_dismiss_event(none.content, 0));
    ASSERT_EQ(kNone, ntk_notification_show(none.content));
    ASSERT_TRUE(ntktest::WaitShown(204, nullptr));
    EXPECT_EQ("false", Field(204, "contentIntent"));
    EXPECT_EQ("false", Field(204, "deleteIntent"));
    Content event_only(205);
    ASSERT_EQ(kNone, ntk_notification_content_set_tap(event_only.content, NTK_NOTIFICATION_TAP_EVENT_ONLY));
    ASSERT_EQ(kNone, ntk_notification_content_set_full_screen(event_only.content, 1));
    ASSERT_EQ(kNone, ntk_notification_show(event_only.content));
    ASSERT_TRUE(ntktest::WaitShown(205, nullptr));
    EXPECT_EQ("true", Field(205, "contentIntent"));
}

TEST_F(Notification, StylesReachTheNotification) {
    Content big(206);
    ASSERT_EQ(kNone, ntk_notification_content_set_style_big_text(big.content, "A long text", nullptr, nullptr));
    ASSERT_EQ(kNone, ntk_notification_show(big.content));
    ASSERT_TRUE(ntktest::WaitShown(206, nullptr));
    EXPECT_EQ("BigTextStyle", Field(206, "template"));
    EXPECT_EQ("A long text", Field(206, "bigText"));

    Content inbox(207);
    const char* lines[] = {"one", "two"};
    ASSERT_EQ(kNone, ntk_notification_content_set_style_inbox(inbox.content, lines, 2, nullptr, nullptr));
    ASSERT_EQ(kNone, ntk_notification_show(inbox.content));
    ASSERT_TRUE(ntktest::WaitShown(207, nullptr));
    EXPECT_EQ("InboxStyle", Field(207, "template"));
    EXPECT_EQ("one|two", Field(207, "lines"));

    Content messaging(208);
    ASSERT_EQ(kNone, ntk_notification_content_set_style_messaging(messaging.content, "Me", "Chat", 1));
    ASSERT_EQ(kNone, ntk_notification_content_add_message(messaging.content, "hello", 1000, "Them"));
    ASSERT_EQ(kNone, ntk_notification_content_add_message(messaging.content, "hi", 2000, nullptr));
    ASSERT_EQ(kNone, ntk_notification_show(messaging.content));
    ASSERT_TRUE(ntktest::WaitShown(208, nullptr));
    EXPECT_EQ("MessagingStyle", Field(208, "template"));
    EXPECT_EQ("2", Field(208, "messages"));

    Content picture(209);
    ASSERT_EQ(kNone, ntk_notification_content_set_style_big_picture(picture.content, "ntk_test_icon", nullptr, nullptr,
                                                                    nullptr, nullptr, 0));
    ASSERT_EQ(kNone, ntk_notification_show(picture.content));
    ASSERT_TRUE(ntktest::WaitShown(209, nullptr));
    EXPECT_EQ("BigPictureStyle", Field(209, "template"));

    Content custom(210);
    ASSERT_EQ(kNone, ntk_notification_content_set_style_custom_view(custom.content, "ntk_test_custom", nullptr));
    ASSERT_EQ(kNone, ntk_notification_content_add_view_click(custom.content, "ntk_test_button", "pressed"));
    ASSERT_EQ(kNone, ntk_notification_show(custom.content));
    ASSERT_TRUE(ntktest::WaitShown(210, nullptr));
    EXPECT_EQ("DecoratedCustomViewStyle", Field(210, "template"));
    EXPECT_EQ("true", Field(210, "customView"));
}

TEST_F(Notification, ActionsReachTheNotification) {
    Content c(211);
    ntk_notification_action reply{};
    reply.struct_size = sizeof(reply);
    reply.title = "Reply";
    reply.action_id = "reply";
    reply.icon_name = "ntk_test_icon";
    ntk_notification_action open = reply;
    open.title = "Open";
    open.action_id = "open";
    open.icon_name = nullptr;
    open.launch_app = 1;
    ASSERT_EQ(kNone, ntk_notification_content_add_action(c.content, &reply));
    ASSERT_EQ(kNone, ntk_notification_content_add_action(c.content, &open));
    ASSERT_EQ(kNone, ntk_notification_show(c.content));
    ASSERT_TRUE(ntktest::WaitShown(211, nullptr));
    EXPECT_EQ("Reply|Open", Field(211, "actions"));
    EXPECT_EQ(ntktest::ResourceId("ntk_test_icon", "drawable"), Field(211, "actionIcon"));
}

TEST_F(Notification, NamesThatDoNotResolveAreResourceNotFound) {
    // AP-8: no default icon, no dropped picture or click: the name is reported.
    Content icon(212);
    ASSERT_EQ(kNone, ntk_notification_content_set_small_icon(icon.content, "ntk_no_such_icon"));
    EXPECT_EQ(NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND, ntk_notification_show(icon.content));
    Content picture(213);
    ASSERT_EQ(kNone, ntk_notification_content_set_style_big_picture(picture.content, "ntk_no_such_picture", nullptr,
                                                                    nullptr, nullptr, nullptr, 0));
    EXPECT_EQ(NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND, ntk_notification_show(picture.content));
    Content layout(214);
    ASSERT_EQ(kNone, ntk_notification_content_set_style_custom_view(layout.content, "ntk_no_such_layout", nullptr));
    EXPECT_EQ(NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND, ntk_notification_show(layout.content));
    Content view(215);
    ASSERT_EQ(kNone, ntk_notification_content_set_style_custom_view(view.content, "ntk_test_custom", nullptr));
    ASSERT_EQ(kNone, ntk_notification_content_add_view_click(view.content, "ntk_no_such_view", "x"));
    EXPECT_EQ(NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND, ntk_notification_show(view.content));
    Content action(216);
    ntk_notification_action a{};
    a.struct_size = sizeof(a);
    a.title = "A";
    a.action_id = "a";
    a.icon_name = "ntk_no_such_icon";
    ASSERT_EQ(kNone, ntk_notification_content_add_action(action.content, &a));
    EXPECT_EQ(NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND, ntk_notification_show(action.content));
    // None of them was shown.
    for (int32_t id = 212; id <= 216; ++id) EXPECT_EQ("<null>", Field(id, "title"));
}

TEST_F(Notification, UpdateAndRemove) {
    Content c(217, "Before", "m");
    ASSERT_EQ(kNone, ntk_notification_content_set_tag(c.content, "t"));
    ASSERT_EQ(kNone, ntk_notification_show(c.content));
    ASSERT_TRUE(ntktest::WaitShown(217, "t"));
    Content changed(217, "After", "m");
    ASSERT_EQ(kNone, ntk_notification_content_set_tag(changed.content, "t"));
    ASSERT_EQ(kNone, ntk_notification_update(changed.content));
    for (int i = 0; i < 50 && Field(217, "title", "t") != "After"; ++i) usleep(100000);
    EXPECT_EQ("After", Field(217, "title", "t"));
    ASSERT_EQ(kNone, ntk_notification_remove(217, "t"));
    EXPECT_TRUE(ntktest::WaitGone(217, "t"));
    Content other(218);
    ASSERT_EQ(kNone, ntk_notification_show(other.content));
    ASSERT_TRUE(ntktest::WaitShown(218, nullptr));
    ASSERT_EQ(kNone, ntk_notification_remove_all());
    EXPECT_TRUE(ntktest::WaitGone(218, nullptr));
}

TEST_F(Notification, ChannelsAreCreatedAndDeleted) {
    ntk_notification_channel* channel = nullptr;
    ASSERT_EQ(kNone, ntk_notification_channel_create("ntk_test_delete", "To delete", 2, &channel));
    const int64_t pattern[] = {0, 100, 50, 100};
    ASSERT_EQ(kNone, ntk_notification_channel_set_vibration_pattern(channel, pattern, 4));
    ASSERT_EQ(kNone, ntk_notification_channel_set_lockscreen_visibility(channel, 0));
    ASSERT_EQ(kNone, ntk_notification_create_channel(channel));
    ntk_notification_channel_free(channel);
    EXPECT_EQ("2", ntktest::ChannelField("ntk_test_delete", "importance"));
    EXPECT_EQ("0,100,50,100", ntktest::ChannelField("ntk_test_delete", "vibration"));
    // The lockscreen visibility is passed on, but the system keeps its own for an app's channel
    // (it reads VISIBILITY_NO_OVERRIDE back), so it is not checked here.
    ASSERT_EQ(kNone, ntk_notification_delete_channel("ntk_test_delete"));
    EXPECT_EQ("<null>", ntktest::ChannelField("ntk_test_delete", "importance"));
}

// --- schedules ---

TEST_F(Notification, AnInexactFutureScheduleIsKeptUntilCanceled) {
    Content c(219, "Later", "m");
    ntk_notification_schedule_options schedule = Schedule(NowMillis() + 600000);
    schedule.inexact = 1;
    ASSERT_EQ(kNone, ntk_notification_schedule(c.content, &schedule));
    int32_t scheduled = 0;
    ASSERT_EQ(kNone, ntk_notification_is_scheduled(219, nullptr, &scheduled));
    EXPECT_EQ(1, scheduled);
    ASSERT_EQ(kNone, ntk_notification_cancel_scheduled(219, nullptr));
    ASSERT_EQ(kNone, ntk_notification_is_scheduled(219, nullptr, &scheduled));
    EXPECT_EQ(0, scheduled);
}

TEST_F(Notification, APastScheduleIsShownAtOnce) {
    Content c(220, "Past", "m");
    ntk_notification_schedule_options schedule = Schedule(NowMillis() - 1000);
    ASSERT_EQ(kNone, ntk_notification_schedule(c.content, &schedule));
    EXPECT_TRUE(ntktest::WaitShown(220, nullptr));
}

TEST_F(Notification, AFutureExactScheduleNeedsExactAlarms) {
    // A fresh install has no exact alarm permission (API 34 and later); the case grants it after
    // checking the refusal, and only this case grants it.
    Content c(221, "Exact", "m");
    ntk_notification_schedule_options schedule = Schedule(NowMillis() + 600000);
    int32_t allowed = -1;
    ASSERT_EQ(kNone, ntk_notification_can_schedule_exact_alarms(&allowed));
    if (allowed == 0) {
        EXPECT_EQ(NTK_NOTIFICATION_ERROR_EXACT_ALARM_NOT_ALLOWED, ntk_notification_schedule(c.content, &schedule));
        ntk_notification_schedule_options inexact = schedule;
        inexact.inexact = 1;
        EXPECT_EQ(kNone, ntk_notification_schedule(c.content, &inexact));
        ntktest::AllowExactAlarms();
    }
    ASSERT_EQ(kNone, ntk_notification_can_schedule_exact_alarms(&allowed));
    EXPECT_EQ(1, allowed);
    EXPECT_EQ(kNone, ntk_notification_schedule(c.content, &schedule));
}

// --- progress (AP-9, AP-14) ---

TEST_F(Notification, ProgressIsCorrectedForTheForegroundService) {
    Content c(222, "Working", "m");
    EXPECT_EQ(kInvalid, ntk_notification_start_progress(c.content));  // no progress set
    ASSERT_EQ(kNone, ntk_notification_content_set_progress(c.content, 100, 40, 0));
    // The user's values are overridden while running (AP-9).
    ASSERT_EQ(kNone, ntk_notification_content_set_ongoing(c.content, 0));
    ASSERT_EQ(kNone, ntk_notification_content_set_auto_cancel(c.content, 1));
    ASSERT_EQ(kNone, ntk_notification_start_progress(c.content));
    // The system may hold a foreground service's notification back for up to 10 seconds.
    ASSERT_TRUE(ntktest::WaitShown(222, nullptr, 15000));
    EXPECT_EQ("40/100", Field(222, "progress"));
    EXPECT_EQ("true", Field(222, "ongoing"));
    EXPECT_EQ("false", Field(222, "autoCancel"));
    EXPECT_EQ("true", Field(222, "onlyAlertOnce"));
    ASSERT_EQ(kNone, ntk_notification_content_set_progress(c.content, 100, 70, 0));
    ASSERT_EQ(kNone, ntk_notification_update_progress(c.content));
    for (int i = 0; i < 50 && Field(222, "progress") != "70/100"; ++i) usleep(100000);
    EXPECT_EQ("70/100", Field(222, "progress"));
    ASSERT_EQ(kNone, ntk_notification_complete_progress(c.content));
    for (int i = 0; i < 50 && Field(222, "progress") != "100/100"; ++i) usleep(100000);
    EXPECT_EQ("100/100", Field(222, "progress"));
    EXPECT_EQ("false", Field(222, "ongoing"));
    EXPECT_EQ("true", Field(222, "autoCancel"));
}

// SERVICE_START_NOT_ALLOWED from the back cannot be caused here: an instrumented process may
// start foreground services from the background. The mapping is a JVM test
// (NotificationBridgeTest); the end-to-end case runs in the smoke app (TB-10).

// --- queries, settings, the permission ---

TEST_F(Notification, QueriesWithThePermissionGranted) {
    int32_t value = -1;
    ASSERT_EQ(kNone, ntk_notification_has_permission(&value));
    EXPECT_EQ(1, value);
    ASSERT_EQ(kNone, ntk_notification_are_enabled(&value));
    EXPECT_EQ(1, value);
}

TEST_F(Notification, ARequestWithThePermissionGrantedCompletesGranted) {
    Recorder& recorder = Leaked<Recorder>();
    uint64_t id = 0;
    ASSERT_EQ(kNone, ntk_notification_request_permission(OnPermission, &recorder, Recorder::Release, &id));
    EXPECT_NE(0u, id);
    ASSERT_TRUE(recorder.WaitFor("release", 1));
    std::vector<ntktest::Record> records = recorder.Records();
    ASSERT_EQ(2u, records.size());
    EXPECT_EQ(kNone, records[0].error);
    EXPECT_EQ(NTK_NOTIFICATION_PERMISSION_RESULT_GRANTED, records[0].value);
    EXPECT_TRUE(records[0].on_main);
}

TEST_F(Notification, SettingsOpenFromTheForegroundOnly) {
    Recorder& recorder = Leaked<Recorder>();
    ASSERT_EQ(kNone, ntk_notification_open_settings_async(NTK_NOTIFICATION_SETTINGS_TARGET_APP_DETAILS, OnSettings,
                                                          &recorder, Recorder::Release));
    ASSERT_TRUE(recorder.WaitFor("release", 1));
    std::vector<ntktest::Record> records = recorder.Records();
    ASSERT_EQ(2u, records.size());
    EXPECT_EQ(kNone, records[0].error);
    EXPECT_TRUE(records[0].value == NTK_NOTIFICATION_SETTINGS_RESULT_OPENED ||
                records[0].value == NTK_NOTIFICATION_SETTINGS_RESULT_OPENED_FALLBACK);

    ASSERT_TRUE(ntktest::UiHome());
    Recorder& back = Leaked<Recorder>();
    ASSERT_EQ(kNone, ntk_notification_open_settings_async(NTK_NOTIFICATION_SETTINGS_TARGET_NOTIFICATIONS, OnSettings,
                                                          &back, Recorder::Release));
    ASSERT_TRUE(back.WaitFor("release", 1));
    EXPECT_EQ(NTK_NOTIFICATION_ERROR_NOT_FOREGROUND, back.Records()[0].error);
}
