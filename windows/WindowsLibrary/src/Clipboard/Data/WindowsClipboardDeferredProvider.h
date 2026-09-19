/**
 * @file WindowsClipboardDeferredProvider.h
 * @brief Adapts the public two-phase render callback to an HGLOBAL renderer.
 */
#pragma once

#include "Clipboard/Data/WindowsClipboardCore.h"
#include "Clipboard/WindowsClipboardManager.h"
#include <string>

DeferredClipboard::Renderer MakeDeferredRenderer(ClipboardRenderCallback provider,
                                                  void* context,
                                                  std::wstring formatName);
