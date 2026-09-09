/**
 * @file WindowsClipboardHistoryWinRt.h
 * @brief WinRT (Windows.ApplicationModel.DataTransfer.Clipboard) implementation
 *        of IClipboardHistoryBackend.
 * @details
 *  Requires C++20 (co_await) - compiled with a per-file LanguageStandard
 *  override; the rest of WindowsLibrary stays on C++17. Never included from
 *  a C++17 translation unit: only reached through the IClipboardHistoryBackend
 *  pointer created by MakeClipboardHistoryWinRtBackend().
 */
#pragma once

#include "WindowsClipboardHistoryBackend.h"
#include <memory>

// Factory: the concrete type and its WinRT dependencies stay out of every
// C++17 header. Must be called on the owner UI thread (STA already verified
// by the Manager before this is constructed).
std::unique_ptr<IClipboardHistoryBackend> MakeClipboardHistoryWinRtBackend();
