// The notification content builder of the C ABI, and the two operations that
// take content (OP-10, OP-11). Stage 5 design 8.4.2.
//
// The builder only records: it checks what the C ABI itself must (NULL,
// UTF-8, indexes and enum values) and leaves everything the C++ API checks to
// ntk_notification_show and ntk_notification_schedule. A setter that fails
// leaves the content as it was.

#include "NativeToolkitC/Notification.h"

#include <chrono>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>

#include "Common/Guard.h"
#include "Common/LastError.h"
#include "Common/Utf8.h"
#include "Notification/NotificationConvert.h"

using namespace NativeToolkitC::Detail;
using namespace NativeToolkitC::Detail::Notification;

namespace {

constexpr ntk_notification_error kOk = NTK_NOTIFICATION_ERROR_NONE;
constexpr ntk_notification_error kInvalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;

/// The widest time system_clock can hold, in milliseconds: its tick is 100 ns.
constexpr int64_t kMaxUnixMs = INT64_MAX / 10000;

ntk_notification_error Finish(ntk_notification_error code, uint32_t systemCode = 0) noexcept
{
    SetLastSystemCode(systemCode);
    return code;
}

/// Everything below runs inside this: no exception leaves the C ABI (7.7).
template <class F>
ntk_notification_error Run(F&& body) noexcept
{
    return Guarded<ntk_notification_error>(NTK_NOTIFICATION_ERROR_HRESULT_FAILURE,
                                           NTK_NOTIFICATION_ERROR_HRESULT_FAILURE,
                                           NTK_SYSTEM_CODE_E_OUTOFMEMORY, body);
}

/// A setter: a NULL content is refused, and body's answer is the result.
template <class F>
ntk_notification_error Edit(ntk_notification_content* content, F&& body) noexcept
{
    return Run([&]() -> ntk_notification_error {
        if (!content) return Finish(kInvalid);
        return Finish(body(content->content));
    });
}

/// A string that must be given.
bool Required(const char* text, std::wstring& out)
{
    return text && Utf8ToWide(text, out);
}

/// A string whose NULL is "" (E-15).
bool Plain(const char* text, std::wstring& out)
{
    if (!text) {
        out.clear();
        return true;
    }
    return Utf8ToWide(text, out);
}

/// A string whose NULL is absent and "" present and empty (7.6).
bool Optional(const char* text, std::optional<std::wstring>& out)
{
    if (!text) {
        out.reset();
        return true;
    }
    std::wstring wide;
    if (!Utf8ToWide(text, wide)) return false;
    out = std::move(wide);
    return true;
}

bool InRange(int32_t value, int32_t first, int32_t last) noexcept
{
    return value >= first && value <= last;
}

bool ToTime(int64_t unixMs, std::chrono::system_clock::time_point& out) noexcept
{
    if (unixMs > kMaxUnixMs || unixMs < -kMaxUnixMs) return false;
    out = std::chrono::system_clock::time_point(
        std::chrono::duration_cast<std::chrono::system_clock::duration>(std::chrono::milliseconds(unixMs)));
    return true;
}

/// Sets one optional string field; the field is left alone on failure.
ntk_notification_error SetOptional(std::optional<std::wstring>& field, const char* value)
{
    std::optional<std::wstring> converted;
    if (!Optional(value, converted)) return kInvalid;
    field = std::move(converted);
    return kOk;
}

ntk_notification_error SetPlain(std::wstring& field, const char* value)
{
    std::wstring converted;
    if (!Plain(value, converted)) return kInvalid;
    field = std::move(converted);
    return kOk;
}

}  // namespace

// =============================================================================
// The builder's handle
// =============================================================================

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_create(ntk_notification_content** out_content)
{
    return Run([&]() -> ntk_notification_error {
        if (!out_content) return Finish(kInvalid);
        *out_content = nullptr;
        *out_content = new ntk_notification_content();
        return Finish(kOk);
    });
}

extern "C" void NTK_CALL ntk_notification_content_free(ntk_notification_content* content)
{
    delete content;
}

// =============================================================================
// Text and images
// =============================================================================

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_title(ntk_notification_content* content, const char* value)
{
    return Edit(content, [&](Api::NotificationContent& c) { return SetOptional(c.title, value); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_body(ntk_notification_content* content, const char* value)
{
    return Edit(content, [&](Api::NotificationContent& c) { return SetOptional(c.body, value); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_tag(ntk_notification_content* content, const char* value)
{
    return Edit(content, [&](Api::NotificationContent& c) { return SetPlain(c.tag, value); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_group(ntk_notification_content* content, const char* value)
{
    return Edit(content, [&](Api::NotificationContent& c) { return SetPlain(c.group, value); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_scenario(
    ntk_notification_content* content, ntk_notification_scenario value)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        if (!InRange(value, NTK_NOTIFICATION_SCENARIO_DEFAULT, NTK_NOTIFICATION_SCENARIO_INCOMING_CALL)) return kInvalid;
        // The C values are the C++ enumerations' declaration order (checked by T-11).
        c.scenario = static_cast<Api::Scenario>(value);
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_hero_image(ntk_notification_content* content, const char* value)
{
    return Edit(content, [&](Api::NotificationContent& c) { return SetOptional(c.heroImage, value); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_inline_image(ntk_notification_content* content, const char* value)
{
    return Edit(content, [&](Api::NotificationContent& c) { return SetOptional(c.inlineImage, value); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_app_logo(
    ntk_notification_content* content, const char* uri, ntk_notification_logo_crop crop)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        if (!InRange(crop, NTK_NOTIFICATION_LOGO_CROP_NONE, NTK_NOTIFICATION_LOGO_CROP_CIRCLE)) return kInvalid;
        if (!uri) {
            c.appLogo.reset();
            return kOk;
        }
        Api::AppLogo logo;
        if (!Utf8ToWide(uri, logo.uri)) return kInvalid;
        logo.crop = static_cast<Api::LogoCrop>(crop);
        c.appLogo = std::move(logo);
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_attribution(ntk_notification_content* content, const char* value)
{
    return Edit(content, [&](Api::NotificationContent& c) { return SetOptional(c.attribution, value); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_duration(
    ntk_notification_content* content, ntk_notification_duration value)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        if (!InRange(value, NTK_NOTIFICATION_DURATION_SHORT, NTK_NOTIFICATION_DURATION_LONG)) return kInvalid;
        c.duration = static_cast<Api::Duration>(value);
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_audio(
    ntk_notification_content* content, ntk_notification_audio_kind kind, const char* event_name,
    const char* uri, int32_t loop)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        if (!InRange(kind, NTK_NOTIFICATION_AUDIO_KIND_EVENT, NTK_NOTIFICATION_AUDIO_KIND_URI)) return kInvalid;
        Api::AudioSpec audio;
        audio.kind = static_cast<Api::AudioKind>(kind);
        if (!Plain(event_name, audio.eventName)) return kInvalid;
        if (!Optional(uri, audio.uri)) return kInvalid;
        audio.loop = loop != 0;
        c.audio = std::move(audio);
        return kOk;
    });
}

// =============================================================================
// Buttons and inputs
// =============================================================================

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_add_button(
    ntk_notification_content* content, const char* label, const char* invoke_uri,
    int32_t with_arguments, size_t* out_index)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        Api::Button button;
        if (!Required(label, button.label)) return kInvalid;
        if (!Optional(invoke_uri, button.invokeUri)) return kInvalid;
        if (with_arguments != 0) button.args.emplace();
        c.buttons.push_back(std::move(button));
        if (out_index) *out_index = c.buttons.size() - 1;
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_add_button_argument(
    ntk_notification_content* content, size_t button_index, const char* key, const char* value)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        if (button_index >= c.buttons.size()) return kInvalid;
        std::wstring wideKey, wideValue;
        if (!Required(key, wideKey) || !Plain(value, wideValue)) return kInvalid;
        auto& args = c.buttons[button_index].args;
        if (!args) args.emplace();
        args->emplace_back(std::move(wideKey), std::move(wideValue));
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_add_text_input(
    ntk_notification_content* content, const char* id, const char* placeholder, const char* title)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        Api::TextInput input;
        if (!Required(id, input.id)) return kInvalid;
        if (!Optional(placeholder, input.placeholder) || !Optional(title, input.title)) return kInvalid;
        c.textInputs.push_back(std::move(input));
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_add_combo(
    ntk_notification_content* content, const char* id, const char* title,
    const char* default_selection, size_t* out_index)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        Api::ComboInput combo;
        if (!Required(id, combo.id)) return kInvalid;
        if (!Plain(title, combo.title) || !Plain(default_selection, combo.defaultSelection)) return kInvalid;
        c.comboInputs.push_back(std::move(combo));
        if (out_index) *out_index = c.comboInputs.size() - 1;
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_add_combo_item(
    ntk_notification_content* content, size_t combo_index, const char* id, const char* label)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        if (combo_index >= c.comboInputs.size()) return kInvalid;
        Api::ComboItem item;
        if (!Required(id, item.id) || !Required(label, item.label)) return kInvalid;
        c.comboInputs[combo_index].items.push_back(std::move(item));
        return kOk;
    });
}

// =============================================================================
// Progress and time
// =============================================================================

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_progress(
    ntk_notification_content* content, const char* title, double value,
    const char* value_string, const char* status)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        Api::ProgressSpec progress;
        progress.value = value;
        if (!Optional(title, progress.title) || !Optional(value_string, progress.valueStr) ||
            !Optional(status, progress.status)) {
            return kInvalid;
        }
        c.progress = std::move(progress);
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_timestamp(
    ntk_notification_content* content, int64_t unix_ms)
{
    return Edit(content, [&](Api::NotificationContent& c) -> ntk_notification_error {
        std::chrono::system_clock::time_point when;
        if (!ToTime(unix_ms, when)) return kInvalid;
        c.timestamp = when;
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_expiration(
    ntk_notification_content* content, int64_t seconds)
{
    return Edit(content, [&](Api::NotificationContent& c) {
        c.expiration = std::chrono::seconds(seconds);
        return kOk;
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_content_set_expires_on_reboot(
    ntk_notification_content* content, int32_t value)
{
    return Edit(content, [&](Api::NotificationContent& c) {
        c.expiresOnReboot = value != 0;
        return kOk;
    });
}

// =============================================================================
// Showing it (OP-10, OP-11)
// =============================================================================

extern "C" ntk_notification_error NTK_CALL ntk_notification_show(
    ntk_notification_manager* manager, const ntk_notification_content* content)
{
    return Run([&]() -> ntk_notification_error {
        if (!manager || !content) return Finish(kInvalid);
        const auto result = manager->manager.Show(content->content);
        if (!result.has_value()) {
            return Finish(static_cast<ntk_notification_error>(result.error().code), result.error().systemCode);
        }
        return Finish(kOk);
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_schedule(
    ntk_notification_manager* manager, const ntk_notification_content* content, int64_t unix_ms)
{
    return Run([&]() -> ntk_notification_error {
        if (!manager || !content) return Finish(kInvalid);
        std::chrono::system_clock::time_point when;
        if (!ToTime(unix_ms, when)) return Finish(kInvalid);
        const auto result = manager->manager.Schedule(content->content, when);
        if (!result.has_value()) {
            return Finish(static_cast<ntk_notification_error>(result.error().code), result.error().systemCode);
        }
        return Finish(kOk);
    });
}
