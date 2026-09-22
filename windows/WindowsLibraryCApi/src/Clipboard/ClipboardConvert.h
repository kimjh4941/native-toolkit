#pragma once
// The clipboard handles of the C ABI and the conversions to the C++ API
// (stage 5 design 7.5.2, 8.4.3). Separate from the exports so they can be
// tested on their own.

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "Common/CallbackGate.h"
#include "Common/ReleaseGuard.h"
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

    /// The release guards of the reservations the C++ API may still hold.
    /// Weak: the C++ API's copies of a provider are what keep a guard alive,
    /// so a reservation that ends there (a new one, a write, another program,
    /// recovery) releases when its last copy goes. Close and free end the rest
    /// here, because neither drops the copies (7.5.3).
    std::mutex                                                          guardsMutex;
    std::vector<std::weak_ptr<NativeToolkitC::Detail::ReleaseGuard>>  guards;

    /// Calls every release that has not run yet, outside the lock: a release
    /// may be the last thing a caller does with its session.
    void FireGuards() noexcept
    {
        std::vector<std::weak_ptr<NativeToolkitC::Detail::ReleaseGuard>> taken;
        {
            std::lock_guard<std::mutex> lock(guardsMutex);
            taken.swap(guards);
        }
        for (auto& weak : taken) {
            if (auto guard = weak.lock()) guard->Fire();
        }
    }
};

/// Where a provider puts the bytes of the format it was asked for.
struct ntk_clipboard_render_target {
    std::vector<std::byte> bytes;
    bool set = false;
};

/// The multi-format builder.
struct ntk_clipboard_items {
    std::vector<NativeToolkit::Clipboard::FormatPayload> items;
};

/// The items a history listing handed back, already in UTF-8.
struct ntk_clipboard_history {
    struct Item {
        std::string                id;
        bool                       hasText = false;
        std::string                text;
        std::vector<std::string>   contentTypes;
        int64_t                    unixMs = 0;
    };
    std::vector<Item> items;
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

/// An array of required strings (paths, format names): false for a NULL
/// array with a count, a NULL entry or invalid UTF-8.
bool ToStrings(const char* const* strings, size_t count, std::vector<std::wstring>& out);

/// A WinRT timestamp (100 ns ticks since 1601-01-01 UTC) as milliseconds
/// since 1970-01-01 UTC, rounded down. 0, which the C++ API uses for a time it
/// could not read, stays 0 rather than becoming a date in 1601 (8.4.3, E-14).
int64_t TicksToUnixMs(int64_t ticks) noexcept;

/// The history handle for a listing. Throws std::bad_alloc.
ntk_clipboard_history ToHistory(const std::vector<Api::HistoryItem>& items);

/// The provider handed to the C++ API for one reservation. It calls fn
/// through gate, and never after the reservation's release has run.
Api::RenderProvider MakeRenderProvider(ntk_clipboard_render_fn fn, std::shared_ptr<ReleaseGuard> guard,
                                       std::shared_ptr<CallbackGate> gate);

}  // namespace NativeToolkitC::Detail::Clipboard
