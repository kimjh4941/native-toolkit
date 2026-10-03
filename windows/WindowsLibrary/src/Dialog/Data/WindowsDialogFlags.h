/**
 * @file WindowsDialogFlags.h
 * @brief Data layer: the Win32 flag words of the dialogs.
 * @details
 *  This is where the MB_* and ID* constants live, because they are the Win32
 *  API and the Domain layer must not depend on it. What is only about shapes
 *  of data - the filter block, the packed multi-select buffers - stays in
 *  Domain, where it needs no windows.h at all.
 */
#pragma once

#include <windows.h>

#include "NativeToolkit/Dialog.h"

namespace NativeToolkit::Dialog::Data {

/// The MessageBoxW uType for a request.
inline UINT ToMessageBoxType(const AlertRequest& request) noexcept
{
    UINT type = 0;
    switch (request.buttons) {
        case AlertButtons::Ok:                type |= MB_OK; break;
        case AlertButtons::OkCancel:          type |= MB_OKCANCEL; break;
        case AlertButtons::YesNo:             type |= MB_YESNO; break;
        case AlertButtons::YesNoCancel:       type |= MB_YESNOCANCEL; break;
        case AlertButtons::RetryCancel:       type |= MB_RETRYCANCEL; break;
        case AlertButtons::AbortRetryIgnore:  type |= MB_ABORTRETRYIGNORE; break;
        case AlertButtons::CancelTryContinue: type |= MB_CANCELTRYCONTINUE; break;
    }
    switch (request.icon) {
        case AlertIcon::None:        break;
        case AlertIcon::Information: type |= MB_ICONINFORMATION; break;
        case AlertIcon::Warning:     type |= MB_ICONWARNING; break;
        case AlertIcon::Error:       type |= MB_ICONERROR; break;
        case AlertIcon::Question:    type |= MB_ICONQUESTION; break;
    }
    switch (request.defaultButton) {
        case AlertDefaultButton::First:  type |= MB_DEFBUTTON1; break;
        case AlertDefaultButton::Second: type |= MB_DEFBUTTON2; break;
        case AlertDefaultButton::Third:  type |= MB_DEFBUTTON3; break;
        case AlertDefaultButton::Fourth: type |= MB_DEFBUTTON4; break;
    }
    if (request.topMost)        type |= MB_TOPMOST;
    if (request.showHelpButton) type |= MB_HELP;
    return type;
}

/// The button id MessageBoxW returned, as the public enumeration.
inline AlertResult FromMessageBoxResult(int id) noexcept
{
    switch (id) {
        case IDOK:       return AlertResult::Ok;
        case IDCANCEL:   return AlertResult::Cancel;
        case IDYES:      return AlertResult::Yes;
        case IDNO:       return AlertResult::No;
        case IDRETRY:    return AlertResult::Retry;
        case IDABORT:    return AlertResult::Abort;
        case IDIGNORE:   return AlertResult::Ignore;
        case IDTRYAGAIN: return AlertResult::TryAgain;
        case IDCONTINUE: return AlertResult::Continue;
        case IDCLOSE:    return AlertResult::Close;
        case IDHELP:     return AlertResult::Help;
        default:         return AlertResult::Cancel;
    }
}

}  // namespace NativeToolkit::Dialog::Data
