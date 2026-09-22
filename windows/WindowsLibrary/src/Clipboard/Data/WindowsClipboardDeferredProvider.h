/**
 * @file WindowsClipboardDeferredProvider.h
 * @brief Adapts the public two-phase render callback to an HGLOBAL renderer.
 */
#pragma once

#include "Clipboard/Data/WindowsClipboardCore.h"
#include "Clipboard/ClipboardCodes.h"
#include "NativeToolkit/Clipboard.h"
#include <string>

/// The C ABI's provider: asked for a size, then asked to fill a buffer.
DeferredClipboard::Renderer MakeDeferredRenderer(ClipboardRenderCallback provider,
                                                  void* context,
                                                  std::wstring formatName);

/**
 * @brief The C++ API's provider: asked once, and it brings its own storage.
 * @details
 *  The two-phase call stays in the version above, where it has to: a C caller
 *  has nowhere to put the bytes until it is told how big a buffer to use. A
 *  provider that returns a vector has already answered both questions, so
 *  asking twice would only give it a chance to answer differently (N-2).
 *
 *  A provider that fails, or throws, renders the format as nothing. By the
 *  time this runs the reservation is long made and an application is waiting
 *  mid-paste, so there is no one left to hand an error to (N-3).
 */
DeferredClipboard::Renderer MakeDeferredRenderer(NativeToolkit::Clipboard::RenderProvider provider,
                                                  std::wstring formatName);
