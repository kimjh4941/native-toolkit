#ifndef PCH_H
#define PCH_H

#include "targetver.h"

// Win32 — must precede winrt/base.h. Not WIN32_LEAN_AND_MEAN: the dialogs need
// the common dialog and COM declarations that the full windows.h brings in.
#include <windows.h>

// WinRT base
#include <winrt/base.h>

// Windows.Foundation — required for IAsyncOperation::get() / Uri
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>

// Windows App SDK — Notification
#include <winrt/Microsoft.Windows.AppNotifications.h>
#include <winrt/Microsoft.Windows.AppNotifications.Builder.h>
#include <winrt/Microsoft.Windows.AppLifecycle.h>

// Windows.UI.Notifications — Schedule / Badge
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.Data.Xml.Dom.h>

// JSON parsing / building
#include <winrt/Windows.Data.Json.h>

// Launcher — open the system notification settings page
#include <winrt/Windows.System.h>

// Clipboard (history). Only WindowsClipboardHistoryWinRt.cpp co_awaits
// Clipboard::GetHistoryItemsAsync().
#include <winrt/Windows.ApplicationModel.DataTransfer.h>

// NOTE: WinAppSDK Bootstrap/Deployment headers (MddBootstrap.h,
// winrt/Microsoft.Windows.ApplicationModel.WindowsAppRuntime.h) are intentionally
// NOT included here. They are used only by WindowsAppSdkBootstrap.cpp so the unit
// test (which compiles WindowsNotificationManager.cpp) does not take a hard
// dependency on Microsoft.WindowsAppRuntime.Bootstrap.dll.

// C++ standard
#include <string>
#include <chrono>

#endif // PCH_H
