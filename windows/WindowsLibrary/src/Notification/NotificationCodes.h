/**
 * @file NotificationCodes.h
 * @brief The error values and the callback type the notification
 *        implementation uses internally.
 * @details
 *  They came from the header of the 1.x C ABI, which stage 5 of the
 *  windows-architecture topic removed together with that ABI (design 8.5).
 *  The values are the ones the C++ API's NotificationError and the 2.x C
 *  ABI's NTK_NOTIFICATION_ERROR_* carry, and they stay exactly as they were:
 *  scripts/check_cpp_api_contract.py compares them one to one.
 *
 *  Not part of any public API.
 */
#pragma once

#define NOTIFICATION_SUCCESS                    0
#define NOTIFICATION_ERROR_NOT_INITIALIZED      1
#define NOTIFICATION_ERROR_DISABLED             2
#define NOTIFICATION_ERROR_INVALID_PAYLOAD      3  // reserved: no public API returns it (E-10)
#define NOTIFICATION_ERROR_PROGRESS_NOT_FOUND   4
#define NOTIFICATION_ERROR_HRESULT_FAILURE      5
#define NOTIFICATION_ERROR_BADGE_FAILED         6
#define NOTIFICATION_ERROR_INVALID_PARAMETER    7
#define NOTIFICATION_ERROR_NOT_SUPPORTED        8  // not available for this app type (e.g. unpackaged RemoveById/GetAll)

/// How the manager hands an activation on: the arguments as JSON.
typedef void (*NotificationInvokedCallback)(const wchar_t* argsJson);
