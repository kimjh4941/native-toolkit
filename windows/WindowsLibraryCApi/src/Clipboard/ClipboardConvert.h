#pragma once
// The clipboard handles of the C ABI and the conversions to the C++ API
// (stage 5 design 7.5.2, 8.4.3). Separate from the exports so they can be
// tested on their own.

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "Common/CallbackGate.h"
#include "NativeToolkit/Clipboard.h"
#include "NativeToolkitC/Clipboard.h"

struct ntk_clipboard_session {
    ntk_clipboard_session(NativeToolkit::Clipboard::Session created,
                          std::shared_ptr<NativeToolkitC::Detail::CallbackGate> sessionGate) noexcept
        : session(std::move(created)), gate(std::move(sessionGate)) {}

    NativeToolkit::Clipboard::Session session;
    /// Every callback given to the C++ API runs through this gate, and holds a
    /// share of it: the C++ side may keep a callback after the handle is freed
    /// (an abandoned session), and must then find the gate shut (7.5.2).
    std::shared_ptr<NativeToolkitC::Detail::CallbackGate> gate;
};

namespace NativeToolkitC::Detail::Clipboard {

namespace Api = NativeToolkit::Clipboard;

/// The copy flags: NONE, or INVALID_PARAMETER for an unknown bit.
ntk_clipboard_error ToWriteOptions(uint32_t flags, Api::WriteOptions& out) noexcept;

/// Reads the session options (NULL is no listener): NONE, INVALID_PARAMETER
/// or NOT_SUPPORTED. The listener, if any, runs through gate.
ntk_clipboard_error ToSessionOptions(const ntk_clipboard_session_options* in,
                                     const std::shared_ptr<CallbackGate>& gate, Api::SessionOptions& out);

/// Reads the history handlers (NULL, or all three NULL, is none): NONE,
/// INVALID_PARAMETER or NOT_SUPPORTED. Each runs through gate.
ntk_clipboard_error ToHistoryHandlers(const ntk_clipboard_history_handlers* in,
                                      const std::shared_ptr<CallbackGate>& gate, Api::HistoryHandlers& out);

/// A required UTF-8 string: false for NULL or invalid UTF-8.
bool RequiredText(const char* text, std::wstring& out);

/// Bytes that may be NULL only when there are none: false otherwise.
bool ToBytes(const uint8_t* data, size_t size, std::vector<std::byte>& out);

/// Every path required: false for a NULL array with a count, a NULL entry or
/// invalid UTF-8.
bool ToPaths(const char* const* paths, size_t count, std::vector<std::wstring>& out);

}  // namespace NativeToolkitC::Detail::Clipboard
