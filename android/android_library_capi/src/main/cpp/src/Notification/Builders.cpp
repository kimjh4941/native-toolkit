#include "Notification/Builders.h"

#include <climits>
#include <memory>
#include <new>
#include <string_view>

#include "Common/Export.h"
#include "Common/Log.h"
#include "Common/StructSize.h"
#include "Common/Utf8.h"

namespace nativetoolkit::notification {
namespace {

// Every builder function: no C++ exception leaves it (part 1, 1.1).
template <class F>
ntk_notification_error Guard(const char* name, F&& body) noexcept {
    try {
        return body();
    } catch (const std::bad_alloc&) {
        NTK_LOGE("[%s] out of memory", name);
        return NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        NTK_LOGE("[%s] failed", name);
        return NTK_NOTIFICATION_ERROR_UNKNOWN;
    }
}

bool ValidText(const char* text) {
    size_t length = 0;
    return text == nullptr || (utf8::Length(text, &length) && utf8::IsStrict(std::string_view(text, length)));
}

// A string field: NULL unsets it (back to Kotlin's default), anything else must be strict UTF-8.
ntk_notification_error SetText(std::optional<std::string>& field, const char* value) {
    if (!ValidText(value)) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    if (value == nullptr) {
        field.reset();
    } else {
        field = std::string(value);
    }
    return NTK_NOTIFICATION_ERROR_NONE;
}

// A string that is required: present and strict UTF-8.
bool RequiredText(const char* text) {
    return text != nullptr && ValidText(text);
}

bool InRange(int64_t value, int64_t low, int64_t high) {
    return value >= low && value <= high;
}

ntk_notification_error Content(ntk_notification_content* content) {
    return content == nullptr ? NTK_NOTIFICATION_ERROR_INVALID_PARAMETER : NTK_NOTIFICATION_ERROR_NONE;
}

// The semantic actions Android defines up to API 31 (Notification.Action.SEMANTIC_ACTION_*).
constexpr int32_t kLastSemanticAction = 12;

}  // namespace
}  // namespace nativetoolkit::notification

namespace notification = nativetoolkit::notification;
using notification::Guard;

#define NTK_CONTENT_GUARD(content)                                                         \
    if (ntk_notification_error invalid = notification::Content(content); invalid != NTK_NOTIFICATION_ERROR_NONE) \
        return invalid

// --- the content builder ---------------------------------------------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_create(int32_t id, const char* title,
                                                                        const char* message,
                                                                        ntk_notification_content** out_content) {
    NTK_LOGD("[ntk_notification_content_create] id: %d, title: %p, message: %p", id, title, message);
    if (out_content == nullptr) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    *out_content = nullptr;
    if (!notification::ValidText(title) || !notification::ValidText(message)) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    return Guard("ntk_notification_content_create", [&] {
        auto content = std::make_unique<ntk_notification_content>();
        content->id = id;
        // A NULL title or message is "" (part 2, 6.3).
        content->title = title == nullptr ? "" : title;
        content->message = message == nullptr ? "" : message;
        *out_content = content.release();
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT void NTK_CALL ntk_notification_content_free(ntk_notification_content* content) {
    NTK_LOGD("[ntk_notification_content_free] content: %p", static_cast<void*>(content));
    delete content;
}

#define NTK_TEXT_SETTER(function, field)                                                                    \
    NTK_EXPORT ntk_notification_error NTK_CALL function(ntk_notification_content* content, const char* value) { \
        NTK_LOGD("[" #function "] content: %p, value: %p", static_cast<void*>(content), value);              \
        NTK_CONTENT_GUARD(content);                                                                         \
        return Guard(#function, [&] { return notification::SetText(content->field, value); });              \
    }

NTK_TEXT_SETTER(ntk_notification_content_set_tag, tag)
NTK_TEXT_SETTER(ntk_notification_content_set_small_icon, small_icon)
NTK_TEXT_SETTER(ntk_notification_content_set_large_icon, large_icon)
NTK_TEXT_SETTER(ntk_notification_content_set_sub_text, sub_text)
NTK_TEXT_SETTER(ntk_notification_content_set_sound, sound)
NTK_TEXT_SETTER(ntk_notification_content_set_category, category)
NTK_TEXT_SETTER(ntk_notification_content_set_ticker, ticker)
NTK_TEXT_SETTER(ntk_notification_content_set_group, group)
NTK_TEXT_SETTER(ntk_notification_content_set_sort_key, sort_key)

#define NTK_BOOL_SETTER(function, field)                                                                  \
    NTK_EXPORT ntk_notification_error NTK_CALL function(ntk_notification_content* content, int32_t value) { \
        NTK_LOGD("[" #function "] content: %p, value: %d", static_cast<void*>(content), value);            \
        NTK_CONTENT_GUARD(content);                                                                       \
        content->field = value != 0;                                                                      \
        return NTK_NOTIFICATION_ERROR_NONE;                                                               \
    }

NTK_BOOL_SETTER(ntk_notification_content_set_auto_cancel, auto_cancel)
NTK_BOOL_SETTER(ntk_notification_content_set_ongoing, ongoing)
NTK_BOOL_SETTER(ntk_notification_content_set_show_timestamp, show_timestamp)
NTK_BOOL_SETTER(ntk_notification_content_set_group_summary, group_summary)
NTK_BOOL_SETTER(ntk_notification_content_set_only_alert_once, only_alert_once)
NTK_BOOL_SETTER(ntk_notification_content_set_local_only, local_only)
NTK_BOOL_SETTER(ntk_notification_content_set_silent, silent)
NTK_BOOL_SETTER(ntk_notification_content_set_uses_chronometer, uses_chronometer)

// Numbers are checked at the entry, never corrected (AP-8).
#define NTK_RANGE_SETTER(function, field, type, low, high)                                               \
    NTK_EXPORT ntk_notification_error NTK_CALL function(ntk_notification_content* content, type value) { \
        NTK_LOGD("[" #function "] content: %p, value: %lld", static_cast<void*>(content),                  \
                 static_cast<long long>(value));                                                         \
        NTK_CONTENT_GUARD(content);                                                                      \
        if (!notification::InRange(value, low, high)) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;  \
        content->field = value;                                                                          \
        return NTK_NOTIFICATION_ERROR_NONE;                                                              \
    }

NTK_RANGE_SETTER(ntk_notification_content_set_priority, priority, int32_t, -2, 2)
NTK_RANGE_SETTER(ntk_notification_content_set_visibility, visibility, int32_t, -1, 1)
NTK_RANGE_SETTER(ntk_notification_content_set_group_alert_behavior, group_alert_behavior, int32_t, 0, 2)
NTK_RANGE_SETTER(ntk_notification_content_set_number, number, int32_t, INT32_MIN, INT32_MAX)
NTK_RANGE_SETTER(ntk_notification_content_set_timestamp, timestamp, int64_t, 0, INT64_MAX)
NTK_RANGE_SETTER(ntk_notification_content_set_timeout_after, timeout_after, int64_t, 0, INT64_MAX)

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_color(ntk_notification_content* content,
                                                                           uint32_t argb) {
    NTK_LOGD("[ntk_notification_content_set_color] content: %p, argb: %08x", static_cast<void*>(content), argb);
    NTK_CONTENT_GUARD(content);
    content->color = argb;
    return NTK_NOTIFICATION_ERROR_NONE;
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_channel(ntk_notification_content* content,
                                                                             const ntk_notification_channel* channel) {
    NTK_LOGD("[ntk_notification_content_set_channel] content: %p, channel: %p", static_cast<void*>(content),
             static_cast<const void*>(channel));
    NTK_CONTENT_GUARD(content);
    return Guard("ntk_notification_content_set_channel", [&] {
        // A copy: changing or freeing the channel builder later does not change the content.
        if (channel == nullptr) {
            content->channel.reset();
        } else {
            content->channel = channel->data;
        }
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_progress(ntk_notification_content* content,
                                                                              int32_t max, int32_t current,
                                                                              int32_t indeterminate) {
    NTK_LOGD("[ntk_notification_content_set_progress] content: %p, max: %d, current: %d, indeterminate: %d",
             static_cast<void*>(content), max, current, indeterminate);
    NTK_CONTENT_GUARD(content);
    // 0 <= current <= max, unless indeterminate (part 2, 6.3).
    if (indeterminate == 0 && !(current >= 0 && current <= max)) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    content->progress = notification::Progress{max, current, indeterminate != 0};
    return NTK_NOTIFICATION_ERROR_NONE;
}

// --- styles: the last one set wins ---------------------------------------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_style_big_text(ntk_notification_content* content,
                                                                                    const char* big_text,
                                                                                    const char* summary_text,
                                                                                    const char* big_content_title) {
    NTK_LOGD("[ntk_notification_content_set_style_big_text] content: %p", static_cast<void*>(content));
    NTK_CONTENT_GUARD(content);
    if (!notification::RequiredText(big_text) || !notification::ValidText(summary_text) ||
        !notification::ValidText(big_content_title)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_content_set_style_big_text", [&] {
        notification::Style style;
        style.kind = notification::StyleKind::kBigText;
        style.big_text = big_text;
        notification::SetText(style.summary_text, summary_text);
        notification::SetText(style.big_content_title, big_content_title);
        content->style = std::move(style);
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_style_inbox(ntk_notification_content* content,
                                                                                 const char* const* lines,
                                                                                 size_t line_count,
                                                                                 const char* summary_text,
                                                                                 const char* big_content_title) {
    NTK_LOGD("[ntk_notification_content_set_style_inbox] content: %p, line_count: %zu", static_cast<void*>(content),
             line_count);
    NTK_CONTENT_GUARD(content);
    if ((lines == nullptr && line_count > 0) || line_count > static_cast<size_t>(INT32_MAX) ||
        !notification::ValidText(summary_text) || !notification::ValidText(big_content_title)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    for (size_t i = 0; i < line_count; ++i) {
        if (!notification::RequiredText(lines[i])) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_content_set_style_inbox", [&] {
        notification::Style style;
        style.kind = notification::StyleKind::kInbox;
        for (size_t i = 0; i < line_count; ++i) style.lines.emplace_back(lines[i]);
        notification::SetText(style.summary_text, summary_text);
        notification::SetText(style.big_content_title, big_content_title);
        content->style = std::move(style);
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_style_big_picture(
    ntk_notification_content* content, const char* picture_name, const char* picture_uri, const char* summary_text,
    const char* big_content_title, const char* large_icon_name, int32_t hide_expanded_large_icon) {
    NTK_LOGD("[ntk_notification_content_set_style_big_picture] content: %p, hide_expanded_large_icon: %d",
             static_cast<void*>(content), hide_expanded_large_icon);
    NTK_CONTENT_GUARD(content);
    // A picture is needed: a name, a URI, or both (then the name wins when shown).
    if ((picture_name == nullptr && picture_uri == nullptr) || !notification::ValidText(picture_name) ||
        !notification::ValidText(picture_uri) || !notification::ValidText(summary_text) ||
        !notification::ValidText(big_content_title) || !notification::ValidText(large_icon_name)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_content_set_style_big_picture", [&] {
        notification::Style style;
        style.kind = notification::StyleKind::kBigPicture;
        notification::SetText(style.picture_name, picture_name);
        notification::SetText(style.picture_uri, picture_uri);
        notification::SetText(style.summary_text, summary_text);
        notification::SetText(style.big_content_title, big_content_title);
        notification::SetText(style.large_icon_name, large_icon_name);
        style.hide_expanded_large_icon = hide_expanded_large_icon != 0;
        content->style = std::move(style);
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_style_messaging(ntk_notification_content* content,
                                                                                     const char* user_display_name,
                                                                                     const char* conversation_title,
                                                                                     int32_t group_conversation) {
    NTK_LOGD("[ntk_notification_content_set_style_messaging] content: %p, group_conversation: %d",
             static_cast<void*>(content), group_conversation);
    NTK_CONTENT_GUARD(content);
    if (!notification::RequiredText(user_display_name) || !notification::ValidText(conversation_title) ||
        !notification::InRange(group_conversation, -1, 1)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_content_set_style_messaging", [&] {
        notification::Style style;
        style.kind = notification::StyleKind::kMessaging;
        style.user_display_name = user_display_name;
        notification::SetText(style.conversation_title, conversation_title);
        if (group_conversation >= 0) style.group_conversation = group_conversation == 1;
        content->style = std::move(style);
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_add_message(ntk_notification_content* content,
                                                                             const char* text, int64_t timestamp_ms,
                                                                             const char* sender_name) {
    // The message text may be private: not logged.
    NTK_LOGD("[ntk_notification_content_add_message] content: %p, timestamp_ms: %lld", static_cast<void*>(content),
             static_cast<long long>(timestamp_ms));
    NTK_CONTENT_GUARD(content);
    // Only on a messaging style (part 2, 6.3).
    if (content->style.kind != notification::StyleKind::kMessaging || !notification::RequiredText(text) ||
        timestamp_ms < 0 || !notification::ValidText(sender_name)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_content_add_message", [&] {
        notification::Message message;
        message.text = text;
        message.timestamp_ms = timestamp_ms;
        notification::SetText(message.sender, sender_name);
        content->style.messages.push_back(std::move(message));
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_style_custom_view(ntk_notification_content* content,
                                                                                       const char* layout_name,
                                                                                       const char* big_layout_name) {
    NTK_LOGD("[ntk_notification_content_set_style_custom_view] content: %p", static_cast<void*>(content));
    NTK_CONTENT_GUARD(content);
    if (!notification::RequiredText(layout_name) || !notification::ValidText(big_layout_name)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_content_set_style_custom_view", [&] {
        notification::Style style;
        style.kind = notification::StyleKind::kCustomView;
        style.layout_name = layout_name;
        notification::SetText(style.big_layout_name, big_layout_name);
        content->style = std::move(style);
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_add_view_click(ntk_notification_content* content,
                                                                                const char* view_id_name,
                                                                                const char* action_id) {
    NTK_LOGD("[ntk_notification_content_add_view_click] content: %p", static_cast<void*>(content));
    NTK_CONTENT_GUARD(content);
    // Only on a custom view style (part 2, 6.3).
    if (content->style.kind != notification::StyleKind::kCustomView || !notification::RequiredText(view_id_name) ||
        !notification::RequiredText(action_id)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_content_add_view_click", [&] {
        content->style.view_clicks.push_back({view_id_name, action_id});
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

// --- events (AP-18) --------------------------------------------------------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_tap(ntk_notification_content* content,
                                                                         ntk_notification_tap mode) {
    NTK_LOGD("[ntk_notification_content_set_tap] content: %p, mode: %d", static_cast<void*>(content), mode);
    NTK_CONTENT_GUARD(content);
    if (!notification::InRange(mode, NTK_NOTIFICATION_TAP_OPEN_APP, NTK_NOTIFICATION_TAP_NONE)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    content->tap = mode;
    return NTK_NOTIFICATION_ERROR_NONE;
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_add_data(ntk_notification_content* content,
                                                                          const char* key, const char* value) {
    // The value is the app's data: only its presence is logged.
    NTK_LOGD("[ntk_notification_content_add_data] content: %p, key: %s, value: %s", static_cast<void*>(content),
             key == nullptr ? "(null)" : key, value == nullptr ? "(null)" : "<redacted>");
    NTK_CONTENT_GUARD(content);
    if (!notification::RequiredText(key) || !notification::RequiredText(value)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_content_add_data", [&] {
        // A key added again replaces its value, as in a map.
        for (auto& pair : content->data) {
            if (pair.first == key) {
                pair.second = value;
                return NTK_NOTIFICATION_ERROR_NONE;
            }
        }
        content->data.emplace_back(key, value);
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_dismiss_event(ntk_notification_content* content,
                                                                                   int32_t enabled) {
    NTK_LOGD("[ntk_notification_content_set_dismiss_event] content: %p, enabled: %d", static_cast<void*>(content), enabled);
    NTK_CONTENT_GUARD(content);
    content->dismiss_event = enabled != 0;
    return NTK_NOTIFICATION_ERROR_NONE;
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_set_full_screen(ntk_notification_content* content,
                                                                                 int32_t enabled) {
    NTK_LOGD("[ntk_notification_content_set_full_screen] content: %p, enabled: %d", static_cast<void*>(content), enabled);
    NTK_CONTENT_GUARD(content);
    content->full_screen = enabled != 0;
    return NTK_NOTIFICATION_ERROR_NONE;
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_content_add_action(ntk_notification_content* content,
                                                                            const ntk_notification_action* action) {
    NTK_LOGD("[ntk_notification_content_add_action] content: %p, action: %p", static_cast<void*>(content),
             static_cast<const void*>(action));
    NTK_CONTENT_GUARD(content);
    ntk_notification_action read{};
    if (int32_t error = nativetoolkit::structs::Read(action, &read, false); error != nativetoolkit::kErrorNone) {
        return error;
    }
    if (read.reserved1 != 0 || !notification::RequiredText(read.title) || !notification::RequiredText(read.action_id) ||
        !notification::ValidText(read.icon_name) ||
        !notification::InRange(read.semantic_action, 0, notification::kLastSemanticAction)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_content_add_action", [&] {
        notification::Action copy;
        copy.title = read.title;
        copy.action_id = read.action_id;
        notification::SetText(copy.icon_name, read.icon_name);
        copy.launch_app = read.launch_app != 0;
        copy.allow_generated_replies = read.allow_generated_replies != 0;
        copy.semantic_action = read.semantic_action;
        copy.contextual = read.contextual != 0;
        // no_user_interface is the inverted name of Kotlin's showsUserInterface (true by default; E-9).
        copy.shows_user_interface = read.no_user_interface == 0;
        content->actions.push_back(std::move(copy));
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

// --- the channel builder ---------------------------------------------------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_create(const char* id, const char* name,
                                                                        int32_t importance,
                                                                        ntk_notification_channel** out_channel) {
    NTK_LOGD("[ntk_notification_channel_create] id: %s, importance: %d", id == nullptr ? "(null)" : id, importance);
    if (out_channel == nullptr) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    *out_channel = nullptr;
    // An id is needed and cannot be empty; importance 0 to 4 (5 would be lowered to 3: AP-8).
    if (!notification::RequiredText(id) || id[0] == '\0' || !notification::RequiredText(name) ||
        !notification::InRange(importance, 0, 4)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_channel_create", [&] {
        auto channel = std::make_unique<ntk_notification_channel>();
        channel->data.id = id;
        channel->data.name = name;
        channel->data.importance = importance;
        *out_channel = channel.release();
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT void NTK_CALL ntk_notification_channel_free(ntk_notification_channel* channel) {
    NTK_LOGD("[ntk_notification_channel_free] channel: %p", static_cast<void*>(channel));
    delete channel;
}

#define NTK_CHANNEL_GUARD(channel) \
    if ((channel) == nullptr) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_set_description(ntk_notification_channel* channel,
                                                                                 const char* value) {
    NTK_LOGD("[ntk_notification_channel_set_description] channel: %p", static_cast<void*>(channel));
    NTK_CHANNEL_GUARD(channel);
    return Guard("ntk_notification_channel_set_description",
                 [&] { return notification::SetText(channel->data.description, value); });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_set_show_badge(ntk_notification_channel* channel,
                                                                                int32_t value) {
    NTK_LOGD("[ntk_notification_channel_set_show_badge] channel: %p, value: %d", static_cast<void*>(channel), value);
    NTK_CHANNEL_GUARD(channel);
    channel->data.show_badge = value != 0;
    return NTK_NOTIFICATION_ERROR_NONE;
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_set_enable_lights(ntk_notification_channel* channel,
                                                                                   int32_t value) {
    NTK_LOGD("[ntk_notification_channel_set_enable_lights] channel: %p, value: %d", static_cast<void*>(channel), value);
    NTK_CHANNEL_GUARD(channel);
    channel->data.enable_lights = value != 0;
    return NTK_NOTIFICATION_ERROR_NONE;
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_set_light_color(ntk_notification_channel* channel,
                                                                                 uint32_t argb) {
    NTK_LOGD("[ntk_notification_channel_set_light_color] channel: %p, argb: %08x", static_cast<void*>(channel), argb);
    NTK_CHANNEL_GUARD(channel);
    channel->data.light_color = argb;
    return NTK_NOTIFICATION_ERROR_NONE;
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_set_enable_vibration(ntk_notification_channel* channel,
                                                                                      int32_t value) {
    NTK_LOGD("[ntk_notification_channel_set_enable_vibration] channel: %p, value: %d", static_cast<void*>(channel), value);
    NTK_CHANNEL_GUARD(channel);
    channel->data.enable_vibration = value != 0;
    return NTK_NOTIFICATION_ERROR_NONE;
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_set_vibration_pattern(ntk_notification_channel* channel,
                                                                                       const int64_t* pattern,
                                                                                       size_t count) {
    NTK_LOGD("[ntk_notification_channel_set_vibration_pattern] channel: %p, count: %zu", static_cast<void*>(channel), count);
    NTK_CHANNEL_GUARD(channel);
    // No pattern (count 0) unsets it; a pattern has no negative duration.
    if ((pattern == nullptr && count > 0) || count > static_cast<size_t>(INT32_MAX)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    for (size_t i = 0; i < count; ++i) {
        if (pattern[i] < 0) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_channel_set_vibration_pattern", [&] {
        if (count == 0) {
            channel->data.vibration_pattern.reset();
        } else {
            channel->data.vibration_pattern = std::vector<int64_t>(pattern, pattern + count);
        }
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_set_sound(ntk_notification_channel* channel,
                                                                           const char* uri) {
    NTK_LOGD("[ntk_notification_channel_set_sound] channel: %p, uri: %p", static_cast<void*>(channel), uri);
    NTK_CHANNEL_GUARD(channel);
    return Guard("ntk_notification_channel_set_sound", [&] { return notification::SetText(channel->data.sound, uri); });
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_set_lockscreen_visibility(
    ntk_notification_channel* channel, int32_t value) {
    NTK_LOGD("[ntk_notification_channel_set_lockscreen_visibility] channel: %p, value: %d", static_cast<void*>(channel),
             value);
    NTK_CHANNEL_GUARD(channel);
    if (!notification::InRange(value, -1, 1)) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    channel->data.lockscreen_visibility = value;
    return NTK_NOTIFICATION_ERROR_NONE;
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_channel_set_group(ntk_notification_channel* channel,
                                                                           const char* group_id,
                                                                           const char* group_name) {
    NTK_LOGD("[ntk_notification_channel_set_group] channel: %p, group_id: %p", static_cast<void*>(channel), group_id);
    NTK_CHANNEL_GUARD(channel);
    // A NULL id unsets the group; a group with an id needs a name to be created with.
    if (!notification::ValidText(group_id) || !notification::ValidText(group_name) ||
        (group_id != nullptr && group_name == nullptr)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    return Guard("ntk_notification_channel_set_group", [&] {
        notification::SetText(channel->data.group_id, group_id);
        notification::SetText(channel->data.group_name, group_id == nullptr ? nullptr : group_name);
        return NTK_NOTIFICATION_ERROR_NONE;
    });
}
