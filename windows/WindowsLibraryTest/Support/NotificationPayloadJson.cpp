#include "pch.h"
#include "Support/NotificationPayloadJson.h"

#include <string>

using namespace winrt::Windows::Data::Json;
using namespace NativeToolkit::Notification;

namespace NotificationPayloadJson {

namespace {

/// The value of a key, when it is there at all. Absent and empty are different
/// things here; that is the whole point of this file.
std::optional<std::wstring> OptionalString(const JsonObject& json, const wchar_t* key)
{
    if (!json.HasKey(key)) {
        return std::nullopt;
    }
    return std::wstring{json.GetNamedString(key)};
}

/// The same, for a key whose emptiness makes no difference to the result.
std::wstring PlainString(const JsonObject& json, const wchar_t* key)
{
    return json.HasKey(key) ? std::wstring{json.GetNamedString(key)} : std::wstring{};
}

Scenario ReadScenario(const JsonObject& json)
{
    // Anything the four names do not cover is ignored without complaint, as it
    // always has been.
    if (!json.HasKey(L"scenario")) return Scenario::Default;
    const std::wstring value{json.GetNamedString(L"scenario")};
    if (value == L"reminder")     return Scenario::Reminder;
    if (value == L"alarm")        return Scenario::Alarm;
    if (value == L"urgent")       return Scenario::Urgent;
    if (value == L"incomingCall") return Scenario::IncomingCall;
    return Scenario::Default;
}

void ReadButtons(const JsonObject& json, NotificationContent& content)
{
    if (!json.HasKey(L"buttons")) return;
    for (const auto& entry : json.GetNamedArray(L"buttons")) {
        const auto object = entry.GetObject();
        Button button;
        // No label at all throws, which is what it has always done.
        button.label = std::wstring{object.GetNamedString(L"label")};

        // Presence, not content: giving both keys is the violation even when
        // the args object is empty.
        if (object.HasKey(L"args")) {
            ArgumentPairs pairs;
            for (const auto& [key, value] : object.GetNamedObject(L"args")) {
                pairs.emplace_back(std::wstring{key}, std::wstring{value.GetString()});
            }
            button.args = std::move(pairs);
        }
        button.invokeUri = OptionalString(object, L"invokeUri");

        content.buttons.push_back(std::move(button));
    }
}

void ReadTextInputs(const JsonObject& json, NotificationContent& content)
{
    if (!json.HasKey(L"textBoxes")) return;
    for (const auto& entry : json.GetNamedArray(L"textBoxes")) {
        const auto object = entry.GetObject();
        TextInput input;
        input.id          = std::wstring{object.GetNamedString(L"id")};
        input.placeholder = OptionalString(object, L"placeholder");
        input.title       = OptionalString(object, L"title");
        content.textInputs.push_back(std::move(input));
    }
}

void ReadComboInputs(const JsonObject& json, NotificationContent& content)
{
    if (!json.HasKey(L"comboBoxes")) return;
    for (const auto& entry : json.GetNamedArray(L"comboBoxes")) {
        const auto object = entry.GetObject();
        ComboInput combo;
        combo.id    = std::wstring{object.GetNamedString(L"id")};
        combo.title = PlainString(object, L"title");
        if (object.HasKey(L"items")) {
            for (const auto& item : object.GetNamedArray(L"items")) {
                const auto fields = item.GetObject();
                combo.items.push_back(ComboItem{std::wstring{fields.GetNamedString(L"id")},
                                                std::wstring{fields.GetNamedString(L"label")}});
            }
        }
        combo.defaultSelection = PlainString(object, L"defaultSelection");
        content.comboInputs.push_back(std::move(combo));
    }
}

void ReadAppLogo(const JsonObject& json, NotificationContent& content)
{
    if (!json.HasKey(L"appLogo")) return;
    const auto object = json.GetNamedObject(L"appLogo");
    AppLogo logo;
    // No uri throws, as it always has.
    logo.uri  = std::wstring{object.GetNamedString(L"uri")};
    logo.crop = (object.HasKey(L"crop") && object.GetNamedString(L"crop") == L"circle")
                    ? LogoCrop::Circle : LogoCrop::None;
    content.appLogo = std::move(logo);
}

void ReadAudio(const JsonObject& json, NotificationContent& content)
{
    if (!json.HasKey(L"audio")) return;
    const auto object = json.GetNamedObject(L"audio");

    AudioSpec audio;
    const std::wstring type = object.HasKey(L"type")
                                  ? std::wstring{object.GetNamedString(L"type")} : L"event";
    audio.kind = type == L"mute" ? AudioKind::Mute
               : type == L"uri"  ? AudioKind::Uri
                                 : AudioKind::Event;
    audio.loop      = object.HasKey(L"loop") && object.GetNamedBoolean(L"loop");
    audio.eventName = PlainString(object, L"event");
    // Absent is the rule that answers InvalidParameter; present and unusable is
    // the App SDK's answer, and a different one.
    audio.uri       = OptionalString(object, L"uri");
    content.audio   = std::move(audio);
}

void ReadProgress(const JsonObject& json, NotificationContent& content)
{
    if (!json.HasKey(L"progress")) return;
    const auto object = json.GetNamedObject(L"progress");

    ProgressSpec progress;
    progress.title    = OptionalString(object, L"title");
    progress.value    = object.HasKey(L"value") ? object.GetNamedNumber(L"value") : 0.0;
    progress.valueStr = OptionalString(object, L"valueStr");
    progress.status   = OptionalString(object, L"status");
    content.progress  = std::move(progress);
}

}  // namespace

void Read(const JsonObject& json, NotificationContent& content)
{
    content.title       = OptionalString(json, L"title");
    content.body        = OptionalString(json, L"body");
    content.tag         = PlainString(json, L"tag");
    content.group       = PlainString(json, L"group");
    content.scenario    = ReadScenario(json);
    content.duration    = (json.HasKey(L"duration") && json.GetNamedString(L"duration") == L"long")
                              ? Duration::Long : Duration::Short;
    content.heroImage   = OptionalString(json, L"heroImage");
    content.inlineImage = OptionalString(json, L"inlineImage");
    content.attribution = OptionalString(json, L"attribution");

    ReadButtons(json, content);
    ReadTextInputs(json, content);
    ReadComboInputs(json, content);
    ReadAppLogo(json, content);
    ReadAudio(json, content);
    ReadProgress(json, content);

    if (json.HasKey(L"timestamp")) {
        const auto seconds = static_cast<time_t>(json.GetNamedNumber(L"timestamp"));
        content.timestamp = std::chrono::system_clock::from_time_t(seconds);
    }
    if (json.HasKey(L"expiration")) {
        content.expiration =
            std::chrono::seconds{static_cast<int64_t>(json.GetNamedNumber(L"expiration"))};
    }
    content.expiresOnReboot =
        json.HasKey(L"expiresOnReboot") && json.GetNamedBoolean(L"expiresOnReboot");

    // A key the payload does not know is ignored, as the 1.x parser did (NTF-64).
}

}  // namespace NotificationPayloadJson
