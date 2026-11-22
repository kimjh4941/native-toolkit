/**
 * @file Notification.h
 * @brief macOS C ABI 1a-9 probe: the notification delegate installer (D-4). The name and the contract
 *        follow iOS (C ABI design part 1, 1.4); the macOS details are decided in part 1.
 */
#ifndef NATIVETOOLKITC_NOTIFICATION_H
#define NATIVETOOLKITC_NOTIFICATION_H

#if defined(__has_include) && __has_include(<NtkProbeMacCApi/NativeToolkitC/Common.h>)
#include <NtkProbeMacCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Same names and numbers as iOS / Android. */
typedef int32_t ntk_notification_error;
enum {
    NTK_NOTIFICATION_ERROR_NONE = 0,
    NTK_NOTIFICATION_ERROR_INVALID_PARAMETER = 1,
    NTK_NOTIFICATION_ERROR_NOT_INITIALIZED = 2,
    /** The process has no app bundle (a command-line tool): UNUserNotificationCenter is not touched. */
    NTK_NOTIFICATION_ERROR_NOT_SUPPORTED = 3,
    NTK_NOTIFICATION_ERROR_UNKNOWN = 4,
    NTK_NOTIFICATION_ERROR_PERMISSION_DENIED = 10,
    NTK_NOTIFICATION_ERROR_WRONG_THREAD = 16
};

/* Installs the library's UNUserNotificationCenter delegate before it returns, keeping the current one
   as the previous delegate (a minimal proxy forwards what is not the library's to it). Main thread only;
   synchronous. Meant to be called by the host's native code during launch (before
   applicationDidFinishLaunching returns), e.g. from an NSApplicationWillFinishLaunchingNotification
   observer registered in main() before PlayerMain, or in main() itself (NSApp does not exist yet; this
   probe never creates it). Off the main thread: WRONG_THREAD at once, nothing done. Without an app
   bundle: NOT_SUPPORTED, UNUserNotificationCenter.current() is not called. Calling it again is a no-op
   while the proxy is in place and re-installs it after someone replaced it. */
ntk_notification_error NTK_CALL ntk_notification_install(void);

#ifdef __cplusplus
}
#endif
#endif
