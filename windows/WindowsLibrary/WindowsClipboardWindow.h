/**
 * @file WindowsClipboardWindow.h
 * @brief Creates/destroys the toolkit-owned dispatch window (dispatchHwnd).
 * @details
 *  A hidden top-level window (not HWND_MESSAGE - see design notes) with its
 *  own WndProc, used as: the SetClipboardData owner for delayed rendering,
 *  the AddClipboardFormatListener target, and the UI-thread dispatch target
 *  for history requests/cancel/drain messages. Routes messages to the
 *  ClipboardManager singleton.
 */
#pragma once

#include <windows.h>

namespace WindowsClipboardWindow
{
    // Must be called on the thread that will pump messages for the lifetime
    // of the manager (that thread becomes the owner UI thread).
    HWND Create();
    void Destroy(HWND hwnd);
}
