/**
 * @file Types.h
 * @brief Value types shared by every feature of the C++ API.
 * @details
 *  Part of the public C++ API added in stage 3 of the windows-architecture
 *  topic. The public headers never include <windows.h>: a consumer that has
 *  not included it still gets a usable WindowHandle, and one that has gets the
 *  very same type as HWND.
 *
 *  Keep this header ASCII only. A non-ASCII byte forces every consumer to
 *  compile with /utf-8 or see warning C4819.
 */
#pragma once

#include <cstdint>

#include "NativeToolkit/BuildStamp.h"

/// Declared exactly as <windows.h> declares it, at global scope.
struct HWND__;

namespace NativeToolkit {

/**
 * @brief A window handle, with the same representation as HWND.
 * @details
 *  Interoperating with HWND assumes the STRICT handle model, which MSVC uses
 *  by default. Under NO_STRICT, HWND is a generic handle and does not convert
 *  implicitly to this type.
 */
using WindowHandle = ::HWND__*;

/**
 * @brief Per-write options accepted by every clipboard copy operation.
 * @details
 *  Mirrors the CLIPBOARD_WRITE_OPTION_* flags of the C ABI: excludeHistory is
 *  0x1, excludeRoaming is 0x2, and both together are what that ABI calls
 *  SENSITIVE. Placing the markers is not best effort - a failure rolls the
 *  whole write back.
 */
struct WriteOptions {
    bool excludeHistory = false;  ///< Keep the value out of the clipboard history (Win+V).
    bool excludeRoaming = false;  ///< Keep the value off the cloud clipboard.
};

}  // namespace NativeToolkit
