// Notification events through the C ABI (C ABI design part 2, 12.1 the events and the default tap
// and dismissal, 12.2 the notification shade; AP-18, AP-21). Most events are raised by sending the
// shown notification's own PendingIntents (NotificationInspector.fire), which returns once the
// library's receiver has handled them; the shade case presses the notification itself.
#include <gtest/gtest.h>

#include <unistd.h>

#include <chrono>
#include <string>
#include <vector>

#include <NativeToolkitC/Notification.h>

#include "../TestSupport.h"

using ntktest::Leaked;
using ntktest::Recorder;

namespace {

constexpr ntk_notification_error kNone = NTK_NOTIFICATION_ERROR_NONE;
constexpr ntk_notification_error kInvalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;

std::string Text(const char* text, size_t size) { return text == nullptr ? "<null>" : std::string(text, size); }

// "kind:id:tag:action_id:key=value,..."
std::string Describe(const ntk_notification_interaction* event) {
    size_t size = 0;
    std::string out = std::to_string(ntk_notification_interaction_kind(event)) + ":" +
                      std::to_string(ntk_notification_interaction_notification_id(event)) + ":";
    const char* tag = ntk_notification_interaction_tag(event, &size);
    out += Text(tag, size) + ":";
    const char* action_id = ntk_notification_interaction_action_id(event, &size);
    out += Text(action_id, size) + ":";
    for (size_t i = 0; i < ntk_notification_interaction_data_count(event); ++i) {
        const char* key = ntk_notification_interaction_data_key_at(event, i, &size);
        out += (i == 0 ? "" : ",") + Text(key, size) + "=";
        const char* value = ntk_notification_interaction_data_value_at(event, i, &size);
        out += Text(value, size);
    }
    return out;
}

void OnInteraction(void* user_data, ntk_notification_interaction* event) {
    ntktest::Record record;
    record.what = "event";
    record.detail = Describe(event);
    static_cast<Recorder*>(user_data)->Add(record);
    ntk_notification_interaction_free(event);
}

void OnShown(void* user_data, ntk_notification_shown* event) {
    size_t tag_size = 0;
    size_t channel_size = 0;
    const char* tag = ntk_notification_shown_tag(event, &tag_size);
    const char* channel = ntk_notification_shown_channel_id(event, &channel_size);
    ntktest::Record record;
    record.what = "event";
    record.detail = std::to_string(ntk_notification_shown_notification_id(event)) + ":" + Text(tag, tag_size) + ":" +
                    Text(channel, channel_size);
    static_cast<Recorder*>(user_data)->Add(record);
    ntk_notification_shown_free(event);
}

std::vector<std::string> Events(Recorder& recorder) {
    std::vector<std::string> events;
    for (const auto& record : recorder.Records()) {
        if (record.what == "event") events.push_back(record.detail);
    }
    return events;
}

ntk_notification_listener* AddInteraction(Recorder& recorder) {
    ntk_notification_listener* listener = nullptr;
    EXPECT_EQ(kNone, ntk_notification_add_interaction_listener(OnInteraction, &recorder, Recorder::Release, &listener));
    return listener;
}

// Adds a listener, lets its insertion run (which adds the bridge's EventHub listener), then
// removes it: from here on the bridge, not EventHub, keeps the events (AP-21). Removing before
// the insertion would leave nothing inserted.
void UsedOnce(Recorder& recorder) {
    ntk_notification_listener* listener = AddInteraction(recorder);
    ntktest::DrainMain();
    ntk_notification_listener_remove(listener);
    ntktest::DrainMain();
}

// Shows notification id whose body tap only raises the event, with one data pair and one action.
void ShowEventOnly(int32_t id, const char* tag) {
    ntk_notification_content* content = nullptr;
    ASSERT_EQ(kNone, ntk_notification_content_create(id, "Event", "Only", &content));
    if (tag != nullptr) ASSERT_EQ(kNone, ntk_notification_content_set_tag(content, tag));
    ASSERT_EQ(kNone, ntk_notification_content_set_tap(content, NTK_NOTIFICATION_TAP_EVENT_ONLY));
    ASSERT_EQ(kNone, ntk_notification_content_add_data(content, "k", "v"));
    ntk_notification_action action{};
    action.struct_size = sizeof(action);
    action.title = "Act";
    action.action_id = "act-1";
    ASSERT_EQ(kNone, ntk_notification_content_add_action(content, &action));
    ASSERT_EQ(kNone, ntk_notification_show(content));
    ntk_notification_content_free(content);
    ASSERT_TRUE(ntktest::WaitShown(id, tag));
}

class NotificationEvent : public testing::Test {
protected:
    void SetUp() override { ntktest::GrantNotifications(); }
    void TearDown() override {
        ntktest::UiCloseShade();
        ntk_notification_remove_all();
        ntk_notification_cancel_all_scheduled();
        ntktest::DrainMain();
    }
};

}  // namespace

// --- the entry and the readers ---

TEST_F(NotificationEvent, AddRejectsInvalidArgumentsAndReleasesHere) {
    Recorder& recorder = Leaked<Recorder>();
    ntk_notification_listener* listener = reinterpret_cast<ntk_notification_listener*>(1);
    EXPECT_EQ(kInvalid, ntk_notification_add_interaction_listener(nullptr, &recorder, Recorder::Release, &listener));
    EXPECT_EQ(nullptr, listener);
    EXPECT_EQ(kInvalid, ntk_notification_add_shown_listener(OnShown, &recorder, Recorder::Release, nullptr));
    ASSERT_EQ(2u, recorder.Count("release"));
    for (const auto& record : recorder.Records()) EXPECT_EQ(gettid(), record.thread);
    ntk_notification_listener_remove(nullptr);
}

TEST_F(NotificationEvent, ReadersOfNullAndOfAnEventWithoutTagOrData) {
    size_t size = 9;
    EXPECT_EQ(0, ntk_notification_interaction_kind(nullptr));
    EXPECT_EQ(0, ntk_notification_interaction_notification_id(nullptr));
    EXPECT_EQ(nullptr, ntk_notification_interaction_tag(nullptr, &size));
    EXPECT_EQ(0u, size);
    EXPECT_EQ(0u, ntk_notification_interaction_data_count(nullptr));
    EXPECT_EQ(nullptr, ntk_notification_interaction_data_value_at(nullptr, 0, nullptr));
    ntk_notification_interaction_free(nullptr);
    EXPECT_EQ(0, ntk_notification_shown_notification_id(nullptr));
    size = 9;
    EXPECT_EQ(nullptr, ntk_notification_shown_channel_id(nullptr, &size));
    EXPECT_EQ(0u, size);
    ntk_notification_shown_free(nullptr);

    // A plain notification: no tag, no data, no action id; out of range reads NULL with size 0.
    Recorder& recorder = Leaked<Recorder>();
    AddInteraction(recorder);
    ntk_notification_content* content = nullptr;
    ASSERT_EQ(kNone, ntk_notification_content_create(702, "Plain", "Event", &content));
    ASSERT_EQ(kNone, ntk_notification_content_set_tap(content, NTK_NOTIFICATION_TAP_EVENT_ONLY));
    ASSERT_EQ(kNone, ntk_notification_show(content));
    ntk_notification_content_free(content);
    ASSERT_TRUE(ntktest::WaitShown(702, nullptr));
    ASSERT_TRUE(ntktest::FireIntent(702, nullptr, "content"));
    ASSERT_TRUE(recorder.WaitFor("event", 1));
    EXPECT_EQ("0:702:<null>:<null>:", Events(recorder)[0]);
}

// --- delivery (12.1 the events) ---

TEST_F(NotificationEvent, EveryListenerGetsTheEventOnMainUntilRemoved) {
    ShowEventOnly(701, "t");
    Recorder& first = Leaked<Recorder>();
    Recorder& second = Leaked<Recorder>();
    ntk_notification_listener* removed = AddInteraction(first);
    AddInteraction(second);
    ntktest::DrainMain();

    ASSERT_TRUE(ntktest::FireIntent(701, "t", "content"));
    ASSERT_TRUE(ntktest::FireIntent(701, "t", "action:0"));
    ASSERT_TRUE(first.WaitFor("event", 2));
    ASSERT_TRUE(second.WaitFor("event", 2));
    std::vector<std::string> expected = {"0:701:t:<null>:k=v", "1:701:t:act-1:k=v"};
    EXPECT_EQ(expected, Events(first));
    EXPECT_EQ(expected, Events(second));
    for (const auto& record : first.Records()) EXPECT_TRUE(record.on_main);

    // Removed: no more events, and its release runs once.
    ntk_notification_listener_remove(removed);
    ntktest::DrainMain();
    EXPECT_EQ(1u, first.Count("release"));
    ASSERT_TRUE(ntktest::FireIntent(701, "t", "delete"));
    ASSERT_TRUE(second.WaitFor("event", 3));
    EXPECT_EQ("2:701:t:<null>:k=v", Events(second)[2]);
    ntktest::DrainMain();
    EXPECT_EQ(2u, Events(first).size());
}

TEST_F(NotificationEvent, EventsBeforeTheFirstListenerArriveInItsInsertion) {
    // No C registration yet: the events wait in EventHub, then come with the insertion message.
    ShowEventOnly(703, nullptr);
    ASSERT_TRUE(ntktest::FireIntent(703, nullptr, "content"));
    ASSERT_TRUE(ntktest::FireIntent(703, nullptr, "delete"));
    Recorder& recorder = Leaked<Recorder>();
    AddInteraction(recorder);
    ntktest::RunOnMain([&recorder] { recorder.Add({"marker"}); });
    std::vector<std::string> order;
    for (const auto& record : recorder.Records()) order.push_back(record.what + " " + record.detail);
    std::vector<std::string> expected = {"event 0:703:<null>:<null>:k=v", "event 2:703:<null>:<null>:k=v", "marker "};
    EXPECT_EQ(expected, order);
}

TEST_F(NotificationEvent, AnEventWithNoActiveListenerWaitsForTheNext) {
    // After the first registration the bridge keeps them (AP-21), not EventHub.
    Recorder& first = Leaked<Recorder>();
    UsedOnce(first);
    ShowEventOnly(704, nullptr);
    ASSERT_TRUE(ntktest::FireIntent(704, nullptr, "content"));
    Recorder& second = Leaked<Recorder>();
    AddInteraction(second);
    ntktest::DrainMain();
    EXPECT_EQ(std::vector<std::string>{"0:704:<null>:<null>:k=v"}, Events(second));
    EXPECT_TRUE(Events(first).empty());
}

namespace {

// Removes its own registration on its first event and adds another (part 2, Y-X2).
struct Switcher {
    Recorder first;
    Recorder second;
    ntk_notification_listener* self = nullptr;
    ntk_notification_listener* next = nullptr;
};

void SwitchOnFirst(void* user_data, ntk_notification_interaction* event) {
    auto* switcher = static_cast<Switcher*>(user_data);
    OnInteraction(&switcher->first, event);
    if (switcher->next != nullptr) return;
    ntk_notification_listener_remove(switcher->self);
    ntk_notification_add_interaction_listener(OnInteraction, &switcher->second, Recorder::Release, &switcher->next);
}

}  // namespace

TEST_F(NotificationEvent, RemovingAndAddingInTheCallbackKeepsTheRest) {
    ShowEventOnly(705, nullptr);
    ASSERT_TRUE(ntktest::FireIntent(705, nullptr, "content"));
    ASSERT_TRUE(ntktest::FireIntent(705, nullptr, "delete"));
    ASSERT_TRUE(ntktest::FireIntent(705, nullptr, "action:0"));
    Switcher& switcher = Leaked<Switcher>();
    // The handle must be stored before the insertion runs the callback.
    ntktest::HoldMain();
    EXPECT_EQ(kNone, ntk_notification_add_interaction_listener(SwitchOnFirst, &switcher, nullptr, &switcher.self));
    ntktest::UnholdMain();
    ASSERT_TRUE(switcher.second.WaitFor("event", 2));
    ntktest::DrainMain();
    EXPECT_EQ(std::vector<std::string>{"0:705:<null>:<null>:k=v"}, Events(switcher.first));
    std::vector<std::string> rest = {"2:705:<null>:<null>:k=v", "1:705:<null>:act-1:k=v"};
    EXPECT_EQ(rest, Events(switcher.second));
}

TEST_F(NotificationEvent, AtMost32AreKeptAndTheOldestIsDropped) {
    Recorder& first = Leaked<Recorder>();
    UsedOnce(first);
    ShowEventOnly(706, nullptr);
    // The 33rd drops the dismissal, which came first.
    ASSERT_TRUE(ntktest::FireIntent(706, nullptr, "delete"));
    for (int i = 0; i < 32; ++i) ASSERT_TRUE(ntktest::FireIntent(706, nullptr, "content"));
    Recorder& second = Leaked<Recorder>();
    AddInteraction(second);
    ntktest::DrainMain();
    std::vector<std::string> events = Events(second);
    EXPECT_EQ(32u, events.size());
    for (const auto& event : events) EXPECT_EQ("0:706:<null>:<null>:k=v", event);
}

TEST_F(NotificationEvent, AShownEventReachesTheListener) {
    ntktest::AllowExactAlarms();
    Recorder& recorder = Leaked<Recorder>();
    ntk_notification_listener* listener = nullptr;
    ASSERT_EQ(kNone, ntk_notification_add_shown_listener(OnShown, &recorder, Recorder::Release, &listener));
    ntk_notification_content* content = nullptr;
    ASSERT_EQ(kNone, ntk_notification_content_create(707, "Scheduled", "Shown", &content));
    ASSERT_EQ(kNone, ntk_notification_content_set_tag(content, "s"));
    ntk_notification_schedule_options schedule{};
    schedule.struct_size = sizeof(schedule);
    schedule.trigger_at_millis =
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch())
            .count() +
        2000;
    ASSERT_EQ(kNone, ntk_notification_schedule(content, &schedule));
    ntk_notification_content_free(content);
    ASSERT_TRUE(recorder.WaitFor("event", 1, std::chrono::seconds(30)));
    EXPECT_EQ(std::vector<std::string>{"707:s:default_channel"}, Events(recorder));
    EXPECT_TRUE(recorder.Records()[0].on_main);
}

// --- the default tap and dismissal (AP-18), pressed in the shade (12.2) ---

TEST_F(NotificationEvent, TheDefaultTapOpensTheAppAndTheSwipeDismisses) {
    Recorder& recorder = Leaked<Recorder>();
    AddInteraction(recorder);
    ntk_notification_content* content = nullptr;
    ASSERT_EQ(kNone, ntk_notification_content_create(708, "Shade tap 708", "Nothing set", &content));
    ASSERT_EQ(kNone, ntk_notification_show(content));
    ntk_notification_content_free(content);
    ASSERT_TRUE(ntktest::WaitShown(708, nullptr));
    ASSERT_TRUE(ntktest::UiHome());
    ASSERT_TRUE(ntktest::UiOpenShade("Shade tap 708"));
    ASSERT_TRUE(ntktest::UiClick("Shade tap 708"));
    ASSERT_TRUE(recorder.WaitFor("event", 1, std::chrono::seconds(10)));
    EXPECT_EQ("0:708:<null>:<null>:", Events(recorder)[0]);
    // The app, sent to the back above, is opened like the launcher does: its task comes to the
    // front (FocusActivity of this run), or LaunchTargetActivity starts when there is none.
    EXPECT_NE("", ntktest::UiForegroundActivity());

    ASSERT_EQ(kNone, ntk_notification_content_create(709, "Shade swipe 709", "Nothing set", &content));
    ASSERT_EQ(kNone, ntk_notification_show(content));
    ntk_notification_content_free(content);
    ASSERT_TRUE(ntktest::WaitShown(709, nullptr));
    ASSERT_TRUE(ntktest::UiOpenShade("Shade swipe 709"));
    ASSERT_TRUE(ntktest::UiSwipeAway("Shade swipe 709"));
    ASSERT_TRUE(recorder.WaitFor("event", 2, std::chrono::seconds(10)));
    EXPECT_EQ("2:709:<null>:<null>:", Events(recorder)[1]);
}

TEST_F(NotificationEvent, AnEventOnlyTapOpensNothing) {
    Recorder& recorder = Leaked<Recorder>();
    AddInteraction(recorder);
    ShowEventOnly(710, nullptr);
    int32_t before = ntktest::ActivitiesCreated();
    ASSERT_TRUE(ntktest::FireIntent(710, nullptr, "content"));
    ASSERT_TRUE(recorder.WaitFor("event", 1));
    EXPECT_TRUE(ntktest::UiStaysAway("ntk capi launch target", 2000));
    EXPECT_EQ(before, ntktest::ActivitiesCreated());
}
