#ifndef PCH_H
#define PCH_H

#include "framework.h"          // MFC (afxwin.h, afxext.h etc.) must come first

// WinRT base — must follow MFC headers
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

// NOTE: WinAppSDK Bootstrap/Deployment headers (MddBootstrap.h,
// winrt/Microsoft.Windows.ApplicationModel.WindowsAppRuntime.h) are intentionally
// NOT included here. They are used only by WindowsAppSdkBootstrap.cpp so the unit
// test (which compiles WindowsNotificationManager.cpp) does not take a hard
// dependency on Microsoft.WindowsAppRuntime.Bootstrap.dll.

// C++ standard
#include <string>
#include <chrono>

#endif // PCH_H
