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
 *  The JSON path decides field by field on whether the key is present, and so
 *  does this one: the fields where an empty value differs from an absent one
 *  are optional in NotificationContent, and are read here with has_value
 *  rather than with empty. Section 1.10 of the input inventory lists the ten
 *  places that matters, and NotificationPayloadTest pins each of them.
 *
 *  The fields that are plain strings - the tag, the group, a combo box title
 *  and its default selection - were checked the same way and come out the same
 *  whether they are empty or absent, so skipping an empty one is faithful.
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
        // Which one is set decides, not whether it holds anything: an invoke
        // URI that is present and empty is a bad URI, and the App SDK says so.
        if (source.invokeUri.has_value()) {
            button.InvokeUri(winrt::Windows::Foundation::Uri{winrt::hstring{*source.invokeUri}});
        } else if (source.args.has_value()) {
            for (const auto& [key, value] : *source.args) {
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
        // Either one being present picks the three-argument overload, which
        // writes attributes the one-argument overload does not.
        if (!input.placeholder.has_value() && !input.title.has_value()) {
            builder.AddTextBox(winrt::hstring{input.id});
        } else {
            builder.AddTextBox(winrt::hstring{input.id},
                               winrt::hstring{input.placeholder.value_or(L"")},
                               winrt::hstring{input.title.value_or(L"")});
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
    if (content.heroImage.has_value()) {
        builder.SetHeroImage(Uri{winrt::hstring{*content.heroImage}});
    }
    if (content.inlineImage.has_value()) {
        builder.SetInlineImage(Uri{winrt::hstring{*content.inlineImage}});
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
        // Validation refused a Uri kind with no uri at all, so there is one
        // here; whether it parses is for the App SDK to say.
        builder.SetAudioUri(Uri{winrt::hstring{audio.uri.value_or(L"")}}, looping);
        return;
    }
    builder.SetAudioEvent(ToSoundEvent(audio.eventName), looping);
}

/// The progress bar, binding only the parts the caller provided.
inline void ApplyProgress(WinRtBuilder::AppNotificationBuilder& builder, const ProgressSpec& progress)
{
    WinRtBuilder::AppNotificationProgressBar bar;
    if (progress.title.has_value()) {
        bar.Title(winrt::hstring{*progress.title});
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

    if (content.title.has_value()) builder.AddText(winrt::hstring{*content.title});
    if (content.body.has_value())  builder.AddText(winrt::hstring{*content.body});
    if (!content.tag.empty())      builder.SetTag(winrt::hstring{content.tag});
    if (!content.group.empty())    builder.SetGroup(winrt::hstring{content.group});

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
    if (content.attribution.has_value()) {
        builder.SetAttributionText(winrt::hstring{*content.attribution});
    }
    if (content.timestamp.has_value()) {
        builder.SetTimeStamp(winrt::clock::from_sys(*content.timestamp));
    }
    return builder;
}

}  // namespace NativeToolkit::Notification::Data
