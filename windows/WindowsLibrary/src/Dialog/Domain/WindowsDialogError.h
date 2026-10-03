/**
 * @file WindowsDialogError.h
 * @brief Domain layer: turns what the dialogs report into DialogError.
 * @details
 *  Pure logic over numbers - no Win32 call, no COM - so it can be tested
 *  without showing a dialog. The C ABI has no error space of its own: it
 *  passes GetLastError, CommDlgExtendedError or an HRESULT straight through
 *  and marks a cancellation with -1 (see DLG-08 of the stage 3 design). The
 *  C++ API keeps those raw values in Failure::systemCode and classifies them
 *  into the cases a caller can act on.
 */
#pragma once

#include <cstdint>

#include "NativeToolkit/Error.h"

namespace NativeToolkit::Dialog::Domain {

/// The outcome of a dialog, as the C++ API reports it.
using ClassifiedOutcome = Failure<DialogError>;

/// What the C ABI writes to *pError when the user dismissed a dialog (DLG-01).
inline constexpr uint32_t kCanceledSentinel = 0xFFFFFFFFu;

/**
 * @brief Classifies a raw dialog outcome.
 * @param succeeded Whether the dialog reported success.
 * @param rawError  The value the C ABI would have written to *pError.
 * @return The case, with the raw value kept for the caller.
 * @details
 *  A cancelled dialog is not a failure of the call, but it is not a value
 *  either, so it becomes Canceled. Anything else that failed with a raw value
 *  is a SystemError; a failure with no raw value at all is Unknown, since
 *  there is nothing to report back.
 */
inline Failure<DialogError> Classify(bool succeeded, uint32_t rawError) noexcept
{
    if (rawError == kCanceledSentinel) {
        return Failure<DialogError>{DialogError::Canceled, 0u};
    }
    if (succeeded) {
        return Failure<DialogError>{DialogError::None, 0u};
    }
    if (rawError != 0u) {
        return Failure<DialogError>{DialogError::SystemError, rawError};
    }
    return Failure<DialogError>{DialogError::Unknown, 0u};
}

/// True when Classify would call this outcome a success.
inline bool Succeeded(const Failure<DialogError>& failure) noexcept
{
    return failure.code == DialogError::None;
}

}  // namespace NativeToolkit::Dialog::Domain
