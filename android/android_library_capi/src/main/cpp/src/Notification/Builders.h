// The notification content and channel builders (C ABI design part 2, 6.3, AP-4). They hold C
// copies only - every setter copies its arguments deeply - and are turned into Kotlin values
// when an operation takes them (Notification.cpp). An unset optional is Kotlin's default.
#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "NativeToolkitC/Notification.h"

namespace nativetoolkit::notification {

struct ChannelData {
    std::string id;
    std::string name;
    int32_t importance = 3;
    std::optional<std::string> description;
    std::optional<bool> show_badge;
    std::optional<bool> enable_lights;
    std::optional<uint32_t> light_color;
    std::optional<bool> enable_vibration;
    std::optional<std::vector<int64_t>> vibration_pattern;
    std::optional<std::string> sound;
    std::optional<int32_t> lockscreen_visibility;
    std::optional<std::string> group_id;
    std::optional<std::string> group_name;
};

struct Progress {
    int32_t max = 0;
    int32_t current = 0;
    bool indeterminate = false;
};

struct Message {
    std::string text;
    int64_t timestamp_ms = 0;
    std::optional<std::string> sender;
};

struct ViewClick {
    std::string view_id_name;
    std::string action_id;
};

struct Action {
    std::string title;
    std::string action_id;
    std::optional<std::string> icon_name;
    bool launch_app = false;
    bool allow_generated_replies = false;
    int32_t semantic_action = 0;
    bool contextual = false;
    bool shows_user_interface = true;
};

enum class StyleKind { kDefault, kBigText, kInbox, kBigPicture, kMessaging, kCustomView };

// One style at a time: the last one set wins (part 2, 6.3).
struct Style {
    StyleKind kind = StyleKind::kDefault;
    // BigText, Inbox, BigPicture.
    std::string big_text;
    std::vector<std::string> lines;
    std::optional<std::string> summary_text;
    std::optional<std::string> big_content_title;
    // BigPicture.
    std::optional<std::string> picture_name;
    std::optional<std::string> picture_uri;
    std::optional<std::string> large_icon_name;
    bool hide_expanded_large_icon = false;
    // Messaging.
    std::string user_display_name;
    std::optional<std::string> conversation_title;
    std::optional<bool> group_conversation;
    std::vector<Message> messages;
    // Custom view.
    std::string layout_name;
    std::optional<std::string> big_layout_name;
    std::vector<ViewClick> view_clicks;
};

}  // namespace nativetoolkit::notification

struct ntk_notification_channel {
    nativetoolkit::notification::ChannelData data;
};

struct ntk_notification_content {
    int32_t id = 0;
    std::string title;
    std::string message;
    std::optional<std::string> tag;
    std::optional<nativetoolkit::notification::ChannelData> channel;
    std::optional<std::string> small_icon;
    std::optional<std::string> large_icon;
    std::optional<int32_t> priority;
    std::optional<bool> auto_cancel;
    std::optional<bool> ongoing;
    std::optional<std::string> sub_text;
    std::optional<bool> show_timestamp;
    std::optional<int64_t> timestamp;
    std::optional<std::string> sound;
    std::optional<std::string> category;
    std::optional<int32_t> visibility;
    std::optional<uint32_t> color;
    std::optional<int32_t> number;
    std::optional<std::string> ticker;
    std::optional<std::string> group;
    std::optional<bool> group_summary;
    std::optional<int32_t> group_alert_behavior;
    std::optional<std::string> sort_key;
    std::optional<bool> only_alert_once;
    std::optional<bool> local_only;
    std::optional<bool> silent;
    std::optional<bool> uses_chronometer;
    std::optional<int64_t> timeout_after;
    std::optional<nativetoolkit::notification::Progress> progress;
    nativetoolkit::notification::Style style;
    // The events (AP-18): the body tap opens the app and sends an event, the dismissal sends one.
    ntk_notification_tap tap = NTK_NOTIFICATION_TAP_OPEN_APP;
    std::vector<std::pair<std::string, std::string>> data;
    bool dismiss_event = true;
    bool full_screen = false;
    std::vector<nativetoolkit::notification::Action> actions;
};
