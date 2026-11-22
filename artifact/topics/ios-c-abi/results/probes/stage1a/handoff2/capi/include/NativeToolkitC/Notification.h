/**
 * @file Notification.h
 * @brief Stage 1a hand-off 2 probe: the notification delegate installer of C ABI design part 1, 1.4.
 *        The name and contract are the decided ones; the rest of the real Notification.h comes in part 2.
 */
#ifndef NATIVETOOLKITC_NOTIFICATION_H
#define NATIVETOOLKITC_NOTIFICATION_H

#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Same names and numbers as Android's ntk_notification_error; 16 is iOS only (P1-7). 9 and 11 to 15
   are not used by this probe. */
typedef int32_t ntk_notification_error;
enum {
    NTK_NOTIFICATION_ERROR_NONE = 0,
    NTK_NOTIFICATION_ERROR_INVALID_PARAMETER = 1,
    NTK_NOTIFICATION_ERROR_NOT_INITIALIZED = 2,
    NTK_NOTIFICATION_ERROR_NOT_SUPPORTED = 3,
    NTK_NOTIFICATION_ERROR_UNKNOWN = 4,
    NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY = 5,
    NTK_NOTIFICATION_ERROR_CANCELED = 6,
    NTK_NOTIFICATION_ERROR_CANCELED_BY_SYSTEM = 7,
    NTK_NOTIFICATION_ERROR_NOT_FOREGROUND = 8,
    NTK_NOTIFICATION_ERROR_PERMISSION_DENIED = 10,
    NTK_NOTIFICATION_ERROR_WRONG_THREAD = 16
};

/* Installs the library's UNUserNotificationCenter delegate, keeping the current one as the
   previous delegate. Main thread only; synchronous; never waits. Call it before
   application(_:didFinishLaunchingWithOptions:) returns (or inside scene(_:willConnectTo:options:)).
   Off the main thread it returns NTK_NOTIFICATION_ERROR_WRONG_THREAD at once and does nothing.
   Calling it again is a no-op while the library's delegate is in place, and re-installs it (with the
   replacing delegate as the new previous one) after someone replaced it. Returns NONE or WRONG_THREAD. */
ntk_notification_error NTK_CALL ntk_notification_install(void);

#ifdef __cplusplus
}
#endif
#endif
