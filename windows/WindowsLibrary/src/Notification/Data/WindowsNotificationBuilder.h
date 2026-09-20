/**
 * @file WindowsNotificationBuilder.h
 * @brief Data layer: builds a toast from NotificationContent.
 * @details
 *  The counterpart of BuildFromJson, taking the struct of the C++ API instead
 *  of a JSON payload. Both have to produce the same toast, and
 *  NotificationBuilderTest asserts that by comparing the XML each one emits:
 *  a field that this file forgets shows up as a difference rather than as a
 *  capability that quietly disappears.
 *
 *  The rules are the ones the JSON path applies today, including the ones that
 *  look like mistakes and are kept on purpose:
 *
 *   - AudioKind::Mute returns before loop and the sound event are read, so
 *     those are discarded (NTF-15);
 *   - "alarm" and "loopingAlarm" both map to the Alarm sound event, so the
 *     distinction is lost in the OS, not here;
 *   - a progress bar binds its value string and status only when the caller
 *     provided them, because it is the presence of the key that decides.
 *
 *  The JSON path decides field by field on whether the key is present; a
 *  struct has no absent string, so here an empty string means the same thing.
 *  The one place that distinction is observable is a deliberately empty title
 *  or body, which the JSON path renders as an empty line and this one drops.
 *  Everything that carries a URI, an id or a label is unusable when empty, so
 *  the two agree. Fields where absence changes the toast - the sound, the app
 *  logo, the progress bar, the timestamp - are optional rather than empty.
 *
 *  Validation lives in Domain and runs before this is called.
 */
#pragma once

#include <winrt/Microsoft.Windows.AppNotifications.Builder.h>
#include <winrt/Windows.Foundation.h>

#include <chrono>

#include "NativeToolkit/Notification.h"

namespace NativeToolkit::Notification::Data {

namespace WinRtBuilder = winrt::Microsoft::Windows::AppNotifications::Builder;

/// The sound event a name selects, as the JSON path maps them.
inline WinRtBuilder::AppNotificationSoundEvent ToSoundEvent(const std::wstring& name) noexcept
{
    if (name == L"reminder")     return WinRtBuilder::AppNotificationSoundEvent::Reminder;
    if (name == L"alarm")        return WinRtBuilder::AppNotificationSoundEvent::Alarm;
    if (name == L"loopingAlarm") return WinRtBuilder::AppNotificationSoundEvent::Alarm;
    if (name == L"loopingCall")  return WinRtBuilder::AppNotificationSoundEvent::Call;
    return WinRtBuilder::AppNotificationSoundEvent::Default;
}

/// The scenario, or nothing when the content asks for the plain toast.
inline void ApplyScenario(WinRtBuilder::AppNotificationBuilder& builder, Scenario scenario)
{
    using WinRtBuilder::AppNotificationScenario;
    switch (scenario) {
        case Scenario::Default:      break;
        case Scenario::Reminder:     builder.SetScenario(AppNotificationScenario::Reminder); break;
        case Scenario::Alarm:        builder.SetScenario(AppNotificationScenario::Alarm); break;
        case Scenario::Urgent:       builder.SetScenario(AppNotificationScenario::Urgent); break;
        case Scenario::IncomingCall: builder.SetScenario(AppNotificationScenario::IncomingCall); break;
    }
}

/// Buttons, each with its arguments or its invoke URI.
inline void ApplyButtons(WinRtBuilder::AppNotificationBuilder& builder,
                         const std::vector<Button>& buttons)
{
    for (const auto& source : buttons) {
        WinRtBuilder::AppNotificationButton button{winrt::hstring{source.label}};
        if (!source.invokeUri.empty()) {
            button.InvokeUri(winrt::Windows::Foundation::Uri{winrt::hstring{source.invokeUri}});
        } else {
            for (const auto& [key, value] : source.args) {
                button.AddArgument(winrt::hstring{key}, winrt::hstring{value});
            }
        }
        builder.AddButton(button);
    }
}

/// Text fields. With neither placeholder nor title the one-argument overload is used.
inline void ApplyTextInputs(WinRtBuilder::AppNotificationBuilder& builder,
                            const std::vector<TextInput>& inputs)
{
    for (const auto& input : inputs) {
        if (input.placeholder.empty() && input.title.empty()) {
            builder.AddTextBox(winrt::hstring{input.id});
        } else {
            builder.AddTextBox(winrt::hstring{input.id},
                               winrt::hstring{input.placeholder},
                               winrt::hstring{input.title});
        }
    }
}

/// Selection fields and their items.
inline void ApplyComboInputs(WinRtBuilder::AppNotificationBuilder& builder,
                             const std::vector<ComboInput>& inputs)
{
    for (const auto& input : inputs) {
        WinRtBuilder::AppNotificationComboBox combo{winrt::hstring{input.id}};
        if (!input.title.empty()) {
            combo.Title(winrt::hstring{input.title});
        }
        for (const auto& item : input.items) {
            combo.AddItem(winrt::hstring{item.id}, winrt::hstring{item.label});
        }
        if (!input.defaultSelection.empty()) {
            combo.SelectedItem(winrt::hstring{input.defaultSelection});
        }
        builder.AddComboBox(combo);
    }
}

/// The app logo override, the hero image and the inline image.
inline void ApplyImages(WinRtBuilder::AppNotificationBuilder& builder,
                        const NotificationContent& content)
{
    using winrt::Windows::Foundation::Uri;
    using WinRtBuilder::AppNotificationImageCrop;

    if (content.appLogo.has_value()) {
        const auto crop = content.appLogo->crop == LogoCrop::Circle ? AppNotificationImageCrop::Circle
                                                                   : AppNotificationImageCrop::Default;
        builder.SetAppLogoOverride(Uri{winrt::hstring{content.appLogo->uri}}, crop);
    }
    if (!content.heroImage.empty()) {
        builder.SetHeroImage(Uri{winrt::hstring{content.heroImage}});
    }
    if (!content.inlineImage.empty()) {
        builder.SetInlineImage(Uri{winrt::hstring{content.inlineImage}});
    }
}

/// The sound. Mute wins over everything else, as it does in the JSON path.
inline void ApplyAudio(WinRtBuilder::AppNotificationBuilder& builder, const AudioSpec& audio)
{
    using winrt::Windows::Foundation::Uri;
    using WinRtBuilder::AppNotificationAudioLooping;

    if (audio.kind == AudioKind::Mute) {
        builder.MuteAudio();
        return;
    }
    const auto looping = audio.loop ? AppNotificationAudioLooping::Loop
                                    : AppNotificationAudioLooping::None;
    if (audio.kind == AudioKind::Uri) {
        builder.SetAudioUri(Uri{winrt::hstring{audio.uri}}, looping);
        return;
    }
    builder.SetAudioEvent(ToSoundEvent(audio.eventName), looping);
}

/// The progress bar, binding only the parts the caller provided.
inline void ApplyProgress(WinRtBuilder::AppNotificationBuilder& builder, const ProgressSpec& progress)
{
    WinRtBuilder::AppNotificationProgressBar bar;
    if (!progress.title.empty()) {
        bar.Title(winrt::hstring{progress.title});
    }
    bar.BindValue();
    if (progress.valueStr.has_value()) {
        bar.BindValueStringOverride();
    }
    if (progress.status.has_value()) {
        bar.BindStatus();
    }
    builder.AddProgressBar(bar);
}

/**
 * @brief Builds the toast for a content value.
 * @details The order matches BuildFromJson: title first, then body, so the two
 *          lines of text land the same way round.
 */
inline WinRtBuilder::AppNotificationBuilder BuildFromContent(const NotificationContent& content)
{
    WinRtBuilder::AppNotificationBuilder builder;

    if (!content.title.empty()) builder.AddText(winrt::hstring{content.title});
    if (!content.body.empty())  builder.AddText(winrt::hstring{content.body});
    if (!content.tag.empty())   builder.SetTag(winrt::hstring{content.tag});
    if (!content.group.empty()) builder.SetGroup(winrt::hstring{content.group});

    ApplyScenario(builder, content.scenario);
    if (content.duration == Duration::Long) {
        builder.SetDuration(WinRtBuilder::AppNotificationDuration::Long);
    }

    ApplyButtons(builder, content.buttons);
    ApplyTextInputs(builder, content.textInputs);
    ApplyComboInputs(builder, content.comboInputs);
    ApplyImages(builder, content);
    if (content.audio.has_value()) {
        ApplyAudio(builder, *content.audio);
    }
    if (content.progress.has_value()) {
        ApplyProgress(builder, *content.progress);
    }
    if (!content.attribution.empty()) {
        builder.SetAttributionText(winrt::hstring{content.attribution});
    }
    if (content.timestamp.has_value()) {
        builder.SetTimeStamp(winrt::clock::from_sys(*content.timestamp));
    }
    return builder;
}

}  // namespace NativeToolkit::Notification::Data
