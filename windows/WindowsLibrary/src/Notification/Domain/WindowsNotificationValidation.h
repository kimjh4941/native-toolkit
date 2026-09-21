/**
 * @file WindowsNotificationValidation.h
 * @brief Domain layer: the payload rules, checked on the struct instead of JSON.
 * @details
 *  Pure logic - no WinRT, no JSON - so the rules can be tested without the
 *  runtime. They are the same rules ValidatePayload and the sub-builders apply
 *  to the JSON payload today (NTF-34), moved here so that both the C++ API and
 *  the bridge answer identically:
 *
 *   - at most five buttons;
 *   - a looping sound needs Duration::Long;
 *   - a button carries arguments or an invoke URI, never both;
 *   - audio of kind Uri needs a URI;
 *   - a badge value below -6 is not a glyph.
 *
 *  Every failure is InvalidParameter, which is what the implementation returns
 *  today. InvalidPayload belongs to a JSON string that does not parse, and a
 *  struct cannot be in that state.
 */
#pragma once

#include <cstdint>

#include "NativeToolkit/Error.h"
#include "NativeToolkit/Notification.h"

namespace NativeToolkit::Notification::Domain {

/// The most buttons a toast accepts (NTF-34).
inline constexpr size_t kMaxButtons = 5;

/// The lowest badge value that still names a glyph; below this is not a badge at all.
inline constexpr int kLowestBadgeGlyph = -6;

/// Why a payload was rejected. Kept separate from the error so a caller can log it.
enum class ValidationFailure {
    None,
    TooManyButtons,
    LoopingAudioNeedsLongDuration,
    ButtonHasArgsAndInvokeUri,
    AudioUriMissing,
    BadgeValueOutOfRange,
};

/// The rule a payload broke, or None.
inline ValidationFailure FindFailure(const NotificationContent& content) noexcept
{
    if (content.audio.has_value()) {
        if (content.audio->loop && content.duration != Duration::Long) {
            return ValidationFailure::LoopingAudioNeedsLongDuration;
        }
        // No uri at all is this rule; a uri that is present and does not parse
        // is the App SDK's answer later, and a different one (1.10 of the
        // input inventory).
        if (content.audio->kind == AudioKind::Uri && !content.audio->uri.has_value()) {
            return ValidationFailure::AudioUriMissing;
        }
    }
    if (content.buttons.size() > kMaxButtons) {
        return ValidationFailure::TooManyButtons;
    }
    for (const auto& button : content.buttons) {
        // Giving both is the violation, whatever they hold: an empty args
        // object still counts as having given arguments.
        if (button.args.has_value() && button.invokeUri.has_value()) {
            return ValidationFailure::ButtonHasArgsAndInvokeUri;
        }
    }
    return ValidationFailure::None;
}

/// True when the payload breaks no rule.
inline bool IsValid(const NotificationContent& content) noexcept
{
    return FindFailure(content) == ValidationFailure::None;
}

/// The payload rules as a Result: success, or InvalidParameter.
inline Result<void> Validate(const NotificationContent& content)
{
    if (FindFailure(content) == ValidationFailure::None) {
        return {};
    }
    return Unexpected{Error{NotificationError::InvalidParameter, 0u}};
}

/// Whether a badge value names a count, a clear, or a glyph (NTF-65).
inline bool IsValidBadgeValue(int value) noexcept
{
    return value >= kLowestBadgeGlyph;
}

/// The badge rule as a Result.
inline Result<void> ValidateBadgeValue(int value)
{
    if (IsValidBadgeValue(value)) {
        return {};
    }
    return Unexpected{Error{NotificationError::InvalidParameter, 0u}};
}

}  // namespace NativeToolkit::Notification::Domain
