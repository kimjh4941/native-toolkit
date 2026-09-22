/**
 * @file ClipboardCodes.h
 * @brief The error values, write flags and callback types the clipboard
 *        implementation uses internally.
 * @details
 *  They came from the header of the 1.x C ABI, which stage 5 of the
 *  windows-architecture topic removed together with that ABI (design 8.5).
 *  The values are the ones the C++ API's ClipboardError and the 2.x C ABI's
 *  NTK_CLIPBOARD_ERROR_* carry, and they stay exactly as they were:
 *  scripts/check_cpp_api_contract.py compares them one to one.
 *
 *  Not part of any public API.
 */
#pragma once

#include <windows.h>
#include <cstdint>

// ---------------------------------------------------------------------------
// Error values (0 = success)
// ---------------------------------------------------------------------------
#define CLIPBOARD_ERROR_NONE                     0
#define CLIPBOARD_ERROR_INVALID_PARAMETER        1
#define CLIPBOARD_ERROR_NOT_INITIALIZED          2
#define CLIPBOARD_ERROR_BUSY                     3
#define CLIPBOARD_ERROR_EMPTY                    4
#define CLIPBOARD_ERROR_FORMAT_UNAVAILABLE       5
#define CLIPBOARD_ERROR_INVALID_DATA             6
#define CLIPBOARD_ERROR_BUFFER_TOO_SMALL         7   // reserved: no public API returns it (E-10)
#define CLIPBOARD_ERROR_OUT_OF_MEMORY            8
#define CLIPBOARD_ERROR_ACCESS_DENIED            9
#define CLIPBOARD_ERROR_HISTORY_DISABLED         10
#define CLIPBOARD_ERROR_ITEM_DELETED             11
#define CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED  12
#define CLIPBOARD_ERROR_PARTIAL_STATE            13
#define CLIPBOARD_ERROR_WRONG_THREAD             14
#define CLIPBOARD_ERROR_CANCELED                 15
#define CLIPBOARD_ERROR_NOT_SUPPORTED            16
#define CLIPBOARD_ERROR_NOT_FOREGROUND           17
#define CLIPBOARD_ERROR_WRONG_APARTMENT          18
#define CLIPBOARD_ERROR_UNKNOWN                  19

// ---------------------------------------------------------------------------
// Write options (bit flags)
// ---------------------------------------------------------------------------
#define CLIPBOARD_WRITE_OPTION_NONE              0x00000000u
#define CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY   0x00000001u  // CanIncludeInClipboardHistory = 0
#define CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING   0x00000002u  // CanUploadToCloudClipboard = 0
#define CLIPBOARD_WRITE_OPTION_SENSITIVE         0x00000003u  // both of the above

// ---------------------------------------------------------------------------
// Callback types of the implementation
// ---------------------------------------------------------------------------
typedef void (*ClipboardChangedCallback)(void);
typedef void (*ClipboardHistoryChangedCallback)(void);
typedef void (*ClipboardFlagChangedCallback)(BOOL enabled);
typedef void (*ClipboardRequestCallback)(uint32_t requestId, DWORD error, const wchar_t* json);
typedef DWORD (*ClipboardRenderCallback)(const wchar_t* formatName,
                                         void* context,
                                         BYTE* buffer,
                                         DWORD buffer_size,
                                         DWORD* pRequiredSize);
