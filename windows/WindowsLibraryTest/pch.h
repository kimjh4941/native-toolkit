#pragma once

// Windows types (BOOL/DWORD) used by the WindowsLibrary public headers — must precede winrt/base.h
#include <windows.h>

// CppUnitTestFramework
#include <CppUnitTest.h>

// WinRT base — required before WindowsNotificationManagerInternal.h
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Microsoft.Windows.AppNotifications.h>
#include <winrt/Microsoft.Windows.AppNotifications.Builder.h>
#include <winrt/Microsoft.Windows.AppLifecycle.h>
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.System.h>

#include <string>
#include <chrono>
