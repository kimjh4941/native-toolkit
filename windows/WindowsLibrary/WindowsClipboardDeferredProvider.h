/**
 * @file WindowsClipboardDeferredProvider.h
 * @brief Adapts the public two-phase render callback to an HGLOBAL renderer.
 */
#pragma once

#include "WindowsClipboardCore.h"
#include "WindowsClipboardManager.h"
#include <string>

DeferredClipboard::Renderer MakeDeferredRenderer(ClipboardRenderCallback provider,
                                                  void* context,
                                                  std::wstring formatName);
