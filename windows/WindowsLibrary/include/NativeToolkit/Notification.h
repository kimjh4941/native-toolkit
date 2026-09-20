/**
 * @file Notification.h
 * @brief Toast notifications, their content and the values they carry back.
 * @details
 *  Part of the public C++ API added in stage 3 of the windows-architecture
 *  topic (design section 8). This header carries the content types; the
 *  Manager and Runtime that use them arrive with OP-07..OP-20.
 *
 *  The fields come from what the JSON payload of the C ABI actually accepts,
 *  listed in designs/2026-09-20-windows-architecture-c-abi-input-inventory.md
 *  section 1, and the names follow the JSON keys so the two can be compared.
 *  Two shapes there do not reduce to fixed fields and are kept open:
 *  a button's arguments are an arbitrary string map, and keys the parser does
 *  not know are accepted and ignored today, so unknownKeys carries them
 *  through instead of dropping them silently.
 *
 *  Keep this header ASCII only.
 */
#pragma once

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "NativeToolkit/BuildStamp.h"
#include "NativeToolkit/Error.h"

namespace NativeToolkit::Notification {

/// How the system treats the notification. JSON: scenario.
enum class Scenario {
    Default,      ///< No scenario; the plain toast.
    Reminder,     ///< "reminder"
    Alarm,        ///< "alarm"
    Urgent,       ///< "urgent"
    IncomingCall, ///< "incomingCall"
};

/// Which sound to play. JSON: audio.type.
enum class AudioKind {
    Event,  ///< "event", the default: a named system sound.
    Mute,   ///< "mute": no sound. The loop and event fields are then ignored.
    Uri,    ///< "uri": the sound at AudioSpec::uri.
};

/// How long the toast stays on screen. JSON: duration.
enum class Duration {
    Short,  ///< The default.
    Long,   ///< "long". Required before a looping sound is allowed.
};

/// How the app logo is cropped. JSON: appLogo.crop.
enum class LogoCrop {
    None,    ///< Anything other than "circle".
    Circle,  ///< "circle"
};

/// What the notification settings of the OS report. Matches getNotificationSetting.
enum class NotificationSetting {
    Enabled                = 0,
    DisabledForApplication = 1,
    DisabledForUser        = 2,
    DisabledByGroupPolicy  = 3,
    DisabledByManifest     = 4,
};

/// The version of the Windows App Runtime to bootstrap, as 0xMMMMmmmm.
struct RuntimeVersion {
    uint32_t majorMinor = 0;
};

/// Arbitrary key/value pairs, kept in order. Used for button arguments and activation values.
using ArgumentPairs = std::vector<std::pair<std::wstring, std::wstring>>;

/**
 * @brief A button on the toast. JSON: an entry of buttons.
 * @details args and invokeUri are mutually exclusive, per button - not for the
 *          notification as a whole.
 */
struct Button {
    std::wstring  label;      ///< JSON: label. Required.
    ArgumentPairs args;       ///< JSON: args. Any keys the caller likes.
    std::wstring  invokeUri;  ///< JSON: invokeUri.
};

/// A text field on the toast. JSON: an entry of textBoxes.
struct TextInput {
    std::wstring id;           ///< JSON: id. Required.
    std::wstring placeholder;  ///< JSON: placeholder.
    std::wstring title;        ///< JSON: title.
};

/// One choice of a selection field. JSON: an entry of comboBoxes[].items.
struct ComboItem {
    std::wstring id;     ///< JSON: id. Required.
    std::wstring label;  ///< JSON: label. Required.
};

/// A selection field on the toast. JSON: an entry of comboBoxes.
struct ComboInput {
    std::wstring           id;                ///< JSON: id. Required.
    std::wstring           title;             ///< JSON: title.
    std::wstring           defaultSelection;  ///< JSON: defaultSelection. Not checked against items.
    std::vector<ComboItem> items;
};

/// The app logo override. JSON: appLogo.
struct AppLogo {
    std::wstring uri;                  ///< JSON: appLogo.uri. Required once appLogo is given.
    LogoCrop     crop = LogoCrop::None;///< JSON: appLogo.crop.
};

/// The sound. JSON: audio.
struct AudioSpec {
    AudioKind    kind = AudioKind::Event;
    std::wstring eventName;   ///< JSON: audio.event, e.g. "reminder", "alarm", "loopingAlarm", "loopingCall".
    std::wstring uri;         ///< JSON: audio.uri. Required when kind is Uri.
    bool         loop = false;///< JSON: audio.loop. Requires Duration::Long.
};

/**
 * @brief The progress bar. JSON: progress.
 * @details valueStr and status are optional because the presence of the key,
 *          not its content, decides whether the bar binds that part at all.
 */
struct ProgressSpec {
    std::wstring                title;        ///< JSON: progress.title.
    double                      value = 0.0;  ///< JSON: progress.value. Not range checked.
    std::optional<std::wstring> valueStr;     ///< JSON: progress.valueStr.
    std::optional<std::wstring> status;       ///< JSON: progress.status.
};

/**
 * @brief Everything a toast can carry.
 * @details
 *  Schedule ignores expiration and progress, and an unpackaged app ignores
 *  expiresOnReboot; both are how the implementation behaves today and the C++
 *  API does not change it.
 */
struct NotificationContent {
    std::wstring                title;            ///< JSON: title. Shown first.
    std::wstring                body;             ///< JSON: body. Shown second.
    std::wstring                tag;              ///< JSON: tag.
    std::wstring                group;            ///< JSON: group.
    Scenario                    scenario = Scenario::Default;
    std::wstring                heroImage;        ///< JSON: heroImage.
    std::wstring                inlineImage;      ///< JSON: inlineImage.
    std::optional<AppLogo>      appLogo;          ///< JSON: appLogo.
    std::wstring                attribution;      ///< JSON: attribution.
    Duration                    duration = Duration::Short;
    std::optional<AudioSpec>    audio;            ///< JSON: audio. Absent leaves the sound to the OS.
    std::vector<Button>         buttons;          ///< At most five.
    std::vector<TextInput>      textInputs;       ///< JSON: textBoxes.
    std::vector<ComboInput>     comboInputs;      ///< JSON: comboBoxes.
    std::optional<ProgressSpec> progress;         ///< Ignored when scheduling.
    std::optional<std::chrono::system_clock::time_point> timestamp;   ///< JSON: timestamp, an absolute time.
    std::optional<std::chrono::seconds>                  expiration;  ///< JSON: expiration, relative to delivery.
    bool                        expiresOnReboot = false;              ///< Packaged apps only.
    ArgumentPairs               unknownKeys;      ///< Keys the parser does not know, kept rather than dropped.
};

/// What to change on a notification that is already showing a progress bar.
struct ProgressUpdate {
    std::wstring tag;
    std::wstring group;
    double       value = 0.0;
    std::wstring valueString;
    std::wstring status;
    uint32_t     sequenceNumber = 0;  ///< The caller owns this; the OS rejects stale ones.
};

/// A notification that is currently in the action centre.
struct NotificationRef {
    uint32_t     id = 0;
    std::wstring tag;
    std::wstring group;
};

/**
 * @brief What the user did, as it reaches the invoked handler.
 * @details
 *  values holds the merged dictionary the OS hands over: the arguments of the
 *  button that was pressed, whatever the platform added, and the contents of
 *  every text and selection field, keyed by their ids. A field overwrites an
 *  argument of the same name.
 */
struct ActivationArgs {
    ArgumentPairs values;
    std::wstring  rawArguments;  ///< The untouched argument string, for anything values cannot express.
};

}  // namespace NativeToolkit::Notification
