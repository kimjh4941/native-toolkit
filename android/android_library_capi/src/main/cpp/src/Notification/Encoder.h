// The content and channel builders as bytes for the Kotlin side (NotificationBridge.Reader reads
// them in the same order). Little-endian numbers, UTF-8 strings with a 32-bit length, and a
// presence byte before every optional field. Internal to the AAR: both sides change together.
#pragma once

#include <cstdint>
#include <cstring>
#include <optional>
#include <string>
#include <vector>

#include "Notification/Builders.h"

namespace nativetoolkit::notification {

class Writer {
public:
    void I32(int32_t value) { Raw(&value, sizeof(value)); }
    void I64(int64_t value) { Raw(&value, sizeof(value)); }
    void Bool(bool value) { bytes_.push_back(value ? 1 : 0); }
    void Str(const std::string& value) {
        I32(static_cast<int32_t>(value.size()));
        bytes_.insert(bytes_.end(), value.begin(), value.end());
    }
    void OptStr(const std::optional<std::string>& value) {
        Bool(value.has_value());
        if (value) Str(*value);
    }
    void OptI32(const std::optional<int32_t>& value) {
        Bool(value.has_value());
        if (value) I32(*value);
    }
    void OptU32(const std::optional<uint32_t>& value) {
        Bool(value.has_value());
        if (value) I32(static_cast<int32_t>(*value));
    }
    void OptI64(const std::optional<int64_t>& value) {
        Bool(value.has_value());
        if (value) I64(*value);
    }
    void OptBool(const std::optional<bool>& value) {
        Bool(value.has_value());
        if (value) Bool(*value);
    }
    const std::vector<uint8_t>& Bytes() const { return bytes_; }

private:
    // Android is little-endian on every ABI this library builds (arm64-v8a, x86_64).
    void Raw(const void* data, size_t size) {
        const auto* p = static_cast<const uint8_t*>(data);
        bytes_.insert(bytes_.end(), p, p + size);
    }
    std::vector<uint8_t> bytes_;
};

inline void EncodeChannel(Writer& w, const ChannelData& c) {
    w.Str(c.id);
    w.Str(c.name);
    w.I32(c.importance);
    w.OptStr(c.description);
    w.OptBool(c.show_badge);
    w.OptBool(c.enable_lights);
    w.OptU32(c.light_color);
    w.OptBool(c.enable_vibration);
    w.Bool(c.vibration_pattern.has_value());
    if (c.vibration_pattern) {
        w.I32(static_cast<int32_t>(c.vibration_pattern->size()));
        for (int64_t value : *c.vibration_pattern) w.I64(value);
    }
    w.OptStr(c.sound);
    w.OptI32(c.lockscreen_visibility);
    w.OptStr(c.group_id);
    w.OptStr(c.group_name);
}

inline std::vector<uint8_t> EncodeChannel(const ChannelData& c) {
    Writer w;
    EncodeChannel(w, c);
    return w.Bytes();
}

inline std::vector<uint8_t> EncodeContent(const ntk_notification_content& c) {
    Writer w;
    w.I32(c.id);
    w.Str(c.title);
    w.Str(c.message);
    w.OptStr(c.tag);
    w.Bool(c.channel.has_value());
    if (c.channel) EncodeChannel(w, *c.channel);
    w.OptStr(c.small_icon);
    w.OptStr(c.large_icon);
    w.OptI32(c.priority);
    w.OptBool(c.auto_cancel);
    w.OptBool(c.ongoing);
    w.OptStr(c.sub_text);
    w.OptBool(c.show_timestamp);
    w.OptI64(c.timestamp);
    w.OptStr(c.sound);
    w.OptStr(c.category);
    w.OptI32(c.visibility);
    w.OptU32(c.color);
    w.OptI32(c.number);
    w.OptStr(c.ticker);
    w.OptStr(c.group);
    w.OptBool(c.group_summary);
    w.OptI32(c.group_alert_behavior);
    w.OptStr(c.sort_key);
    w.OptBool(c.only_alert_once);
    w.OptBool(c.local_only);
    w.OptBool(c.silent);
    w.OptBool(c.uses_chronometer);
    w.OptI64(c.timeout_after);
    w.Bool(c.progress.has_value());
    if (c.progress) {
        w.I32(c.progress->max);
        w.I32(c.progress->current);
        w.Bool(c.progress->indeterminate);
    }
    const Style& s = c.style;
    w.I32(static_cast<int32_t>(s.kind));
    switch (s.kind) {
        case StyleKind::kDefault:
            break;
        case StyleKind::kBigText:
            w.Str(s.big_text);
            w.OptStr(s.summary_text);
            w.OptStr(s.big_content_title);
            break;
        case StyleKind::kInbox:
            w.I32(static_cast<int32_t>(s.lines.size()));
            for (const std::string& line : s.lines) w.Str(line);
            w.OptStr(s.summary_text);
            w.OptStr(s.big_content_title);
            break;
        case StyleKind::kBigPicture:
            w.OptStr(s.picture_name);
            w.OptStr(s.picture_uri);
            w.OptStr(s.summary_text);
            w.OptStr(s.big_content_title);
            w.OptStr(s.large_icon_name);
            w.Bool(s.hide_expanded_large_icon);
            break;
        case StyleKind::kMessaging:
            w.Str(s.user_display_name);
            w.OptStr(s.conversation_title);
            w.OptBool(s.group_conversation);
            w.I32(static_cast<int32_t>(s.messages.size()));
            for (const Message& m : s.messages) {
                w.Str(m.text);
                w.I64(m.timestamp_ms);
                w.OptStr(m.sender);
            }
            break;
        case StyleKind::kCustomView:
            w.Str(s.layout_name);
            w.OptStr(s.big_layout_name);
            w.I32(static_cast<int32_t>(s.view_clicks.size()));
            for (const ViewClick& click : s.view_clicks) {
                w.Str(click.view_id_name);
                w.Str(click.action_id);
            }
            break;
    }
    w.I32(c.tap);
    w.I32(static_cast<int32_t>(c.data.size()));
    for (const auto& pair : c.data) {
        w.Str(pair.first);
        w.Str(pair.second);
    }
    w.Bool(c.dismiss_event);
    w.Bool(c.full_screen);
    w.I32(static_cast<int32_t>(c.actions.size()));
    for (const Action& a : c.actions) {
        w.Str(a.title);
        w.Str(a.action_id);
        w.OptStr(a.icon_name);
        w.Bool(a.launch_app);
        w.Bool(a.allow_generated_replies);
        w.I32(a.semantic_action);
        w.Bool(a.contextual);
        w.Bool(a.shows_user_interface);
    }
    return w.Bytes();
}

}  // namespace nativetoolkit::notification
