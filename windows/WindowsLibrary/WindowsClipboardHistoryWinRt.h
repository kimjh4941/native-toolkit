/**
 * @file WindowsClipboardHistoryWinRt.h
 * @brief WinRT (Windows.ApplicationModel.DataTransfer.Clipboard) implementation
 *        of IClipboardHistoryBackend.
 * @details
 *  Uses co_await. Only reached through the IClipboardHistoryBackend
 *  pointer created by MakeClipboardHistoryWinRtBackend().
 */
#pragma once

#include "WindowsClipboardHistoryBackend.h"
#include <memory>

// Factory: the concrete type and its WinRT dependencies stay out of every
// other header. Must be called on the owner UI thread (STA already verified
// by the Manager before this is constructed).
std::unique_ptr<IClipboardHistoryBackend> MakeClipboardHistoryWinRtBackend();
