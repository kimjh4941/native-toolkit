/**
 * @file Error.h
 * @brief Failure values and the Result type the C++ API returns.
 * @details
 *  Part of the public C++ API added in stage 3 of the windows-architecture
 *  topic (design section 7.2). Operations report failure by value, never by
 *  throwing: a failure that happens after a call has been entered - an OS or
 *  WinRT failure, an allocation inside the library - always comes back as a
 *  Failure. Building the arguments at the call site is ordinary C++ and can
 *  still throw std::bad_alloc.
 *
 *  Each feature binds Result to its own error enumeration, so
 *  Clipboard::Result and Dialog::Result are different types and the enum a
 *  failure carries is never erased to a number.
 *
 *  This is NOT std::expected and swapping it for std::expected is not
 *  mechanical. The differences are listed in section 7.2 of the design: errors
 *  are built through Unexpected rather than std::unexpected, value() has a
 *  precondition instead of throwing, and there is no state that holds neither
 *  a value nor an error.
 *
 *  Keep this header ASCII only.
 */
#pragma once

#include <cstdint>
#include <new>
#include <type_traits>
#include <utility>

#include "NativeToolkit/BuildStamp.h"

namespace NativeToolkit {

/**
 * @brief A failed operation: which case, plus the raw value the OS reported.
 * @tparam Code The feature's error enumeration.
 */
template <class Code>
struct Failure {
    Code     code{};           ///< The documented case.
    uint32_t systemCode = 0;   ///< GetLastError, an HRESULT or CommDlgExtendedError; 0 when there is none.
};

/**
 * @brief Wraps an error so that constructing a failed Result is explicit.
 * @details Mirrors the role of std::unexpected. Required even when T and E are
 *          the same type, which is why Result has no ambiguity there.
 */
template <class E>
struct Unexpected {
    E error;
};
template <class E> Unexpected(E) -> Unexpected<E>;

namespace detail {

/// Deletes the copy members when the alternatives cannot be copied, so that
/// Result<MoveOnly> reports as move only instead of failing when copied.
template <bool Copyable>
struct CopyControl {};

template <>
struct CopyControl<false> {
    CopyControl() = default;
    CopyControl(const CopyControl&) = delete;
    CopyControl& operator=(const CopyControl&) = delete;
    CopyControl(CopyControl&&) = default;
    CopyControl& operator=(CopyControl&&) = default;
};

}  // namespace detail

/**
 * @brief Either a value of type T or a failure of type E.
 * @details
 *  Copyable only when both T and E are; Result<Session> and Result<Manager>
 *  are therefore move only. Trivially destructible when both T and E are, so a
 *  Result of plain values costs nothing to destroy. value() and error() are
 *  unchecked: calling the wrong one is a precondition violation, asserted in
 *  debug builds, and never throws.
 */
template <class T, class E>
class Result : private detail::CopyControl<std::is_copy_constructible_v<T> && std::is_copy_constructible_v<E>> {
    static_assert(!std::is_reference_v<T>, "Result<T&> is not supported");

    static constexpr bool kTriviallyDestructible =
        std::is_trivially_destructible_v<T> && std::is_trivially_destructible_v<E>;

public:
    Result(T value) : hasValue_(true) { ::new (static_cast<void*>(&storage_.value)) T(std::move(value)); }
    Result(Unexpected<E> error) : hasValue_(false) { ::new (static_cast<void*>(&storage_.error)) E(std::move(error.error)); }

    Result(const Result& other)
        requires (std::is_copy_constructible_v<T> && std::is_copy_constructible_v<E>)
        : hasValue_(other.hasValue_)
    {
        if (hasValue_) ::new (static_cast<void*>(&storage_.value)) T(other.storage_.value);
        else           ::new (static_cast<void*>(&storage_.error)) E(other.storage_.error);
    }
    Result(Result&& other) noexcept(std::is_nothrow_move_constructible_v<T> && std::is_nothrow_move_constructible_v<E>)
        : hasValue_(other.hasValue_)
    {
        if (hasValue_) ::new (static_cast<void*>(&storage_.value)) T(std::move(other.storage_.value));
        else           ::new (static_cast<void*>(&storage_.error)) E(std::move(other.storage_.error));
    }
    Result& operator=(const Result& other)
        requires (std::is_copy_constructible_v<T> && std::is_copy_constructible_v<E>)
    {
        if (this != &other) { Destroy(); CopyFrom(other); }
        return *this;
    }
    Result& operator=(Result&& other) noexcept(std::is_nothrow_move_constructible_v<T> && std::is_nothrow_move_constructible_v<E>)
    {
        if (this != &other) { Destroy(); MoveFrom(std::move(other)); }
        return *this;
    }

    ~Result() requires kTriviallyDestructible = default;
    ~Result() { Destroy(); }

    bool     has_value() const noexcept { return hasValue_; }
    explicit operator bool() const noexcept { return hasValue_; }

    T&       value() & noexcept { return storage_.value; }
    const T& value() const& noexcept { return storage_.value; }
    T&&      value() && noexcept { return std::move(storage_.value); }

    /// Returns the value when there is one, otherwise the fallback. Requires a copyable T.
    T value_or(T fallback) const&
        requires std::is_copy_constructible_v<T>
    { return hasValue_ ? storage_.value : std::move(fallback); }

    E&       error() & noexcept { return storage_.error; }
    const E& error() const& noexcept { return storage_.error; }
    E&&      error() && noexcept { return std::move(storage_.error); }

private:
    union Storage {
        Storage() {}
        ~Storage() requires kTriviallyDestructible = default;
        ~Storage() {}
        T value;
        E error;
    };

    void Destroy() noexcept
    {
        if constexpr (!kTriviallyDestructible) {
            if (hasValue_) storage_.value.~T();
            else           storage_.error.~E();
        }
    }
    void CopyFrom(const Result& other)
    {
        hasValue_ = other.hasValue_;
        if (hasValue_) ::new (static_cast<void*>(&storage_.value)) T(other.storage_.value);
        else           ::new (static_cast<void*>(&storage_.error)) E(other.storage_.error);
    }
    void MoveFrom(Result&& other)
    {
        hasValue_ = other.hasValue_;
        if (hasValue_) ::new (static_cast<void*>(&storage_.value)) T(std::move(other.storage_.value));
        else           ::new (static_cast<void*>(&storage_.error)) E(std::move(other.storage_.error));
    }

    Storage storage_;
    bool    hasValue_;
};

/// The same contract for operations that return no value.
template <class E>
class Result<void, E> {
public:
    Result() noexcept : error_{}, hasValue_(true) {}
    Result(Unexpected<E> error) : error_(std::move(error.error)), hasValue_(false) {}

    bool     has_value() const noexcept { return hasValue_; }
    explicit operator bool() const noexcept { return hasValue_; }

    E&       error() & noexcept { return error_; }
    const E& error() const& noexcept { return error_; }
    E&&      error() && noexcept { return std::move(error_); }

private:
    E    error_;
    bool hasValue_;
};

/// Errors of the Dialog feature. New in the C++ API: the C ABI passes raw OS values.
enum class DialogError : uint32_t {
    None             = 0,  ///< Success.
    InvalidParameter = 1,  ///< A null argument, or a zero-sized buffer on the C ABI.
    Canceled         = 2,  ///< The user dismissed the dialog.
    BufferTooSmall   = 3,  ///< Only reachable through the C ABI; the C++ API returns values.
    SystemError      = 4,  ///< GetLastError, CommDlgExtendedError or a failed HRESULT; see systemCode.
    Unknown          = 5,  ///< Anything the cases above do not cover.
};

/// Errors of the Notification feature. The values match NOTIFICATION_* of the C ABI.
enum class NotificationError : uint32_t {
    None             = 0,
    NotInitialized   = 1,  ///< Used before Create, or after Close.
    Disabled         = 2,  ///< Notifications are off for this app or user.
    InvalidPayload   = 3,  ///< The content failed validation.
    ProgressNotFound = 4,  ///< No notification to update, or a stale sequence number.
    HResultFailure   = 5,  ///< Registration, the shortcut, or the runtime bootstrap failed.
    BadgeFailed      = 6,
    InvalidParameter = 7,  ///< A bad argument, such as a badge value below -6.
    NotSupported     = 8,  ///< Not available for this app type, or a second manager.
};

/// Errors of the Clipboard feature. The values match CLIPBOARD_ERROR_* of the C ABI.
enum class ClipboardError : uint32_t {
    None                  = 0,
    InvalidParameter      = 1,   ///< Null or empty arguments, an embedded NUL, an unknown request id.
    NotInitialized        = 2,   ///< Used before Create, or after Close.
    Busy                  = 3,   ///< OpenClipboard kept failing, or Close still has work in flight.
    Empty                 = 4,
    FormatUnavailable     = 5,
    InvalidData           = 6,   ///< A payload failed its structural checks.
    BufferTooSmall        = 7,   ///< Only reachable through the C ABI.
    OutOfMemory           = 8,
    AccessDenied          = 9,
    HistoryDisabled       = 10,
    ItemDeleted           = 11,
    MonitorRegisterFailed = 12,  ///< A listener or event token could not be registered or revoked.
    PartialState          = 13,  ///< A placement failed and the rollback failed too.
    WrongThread           = 14,  ///< An owner-thread-only call from another thread.
    Canceled              = 15,  ///< Cancelled, or drained by Close.
    NotSupported          = 16,  ///< No Windows equivalent, or a second session.
    NotForeground         = 17,  ///< This process is not in the foreground; reported through the callback.
    WrongApartment        = 18,  ///< The calling thread is not an STA.
    Unknown               = 19,  ///< Anything else; the raw value is always logged.
};

}  // namespace NativeToolkit

namespace NativeToolkit::Dialog {
/// The feature's error cases, reachable without leaving this namespace.
using ErrorCode = NativeToolkit::DialogError;
using Error = Failure<DialogError>;
template <class T = void> using Result = NativeToolkit::Result<T, Error>;
}  // namespace NativeToolkit::Dialog

namespace NativeToolkit::Notification {
/// The feature's error cases, reachable without leaving this namespace.
using ErrorCode = NativeToolkit::NotificationError;
using Error = Failure<NotificationError>;
template <class T = void> using Result = NativeToolkit::Result<T, Error>;
}  // namespace NativeToolkit::Notification

namespace NativeToolkit::Clipboard {
/// The feature's error cases, reachable without leaving this namespace.
using ErrorCode = NativeToolkit::ClipboardError;
using Error = Failure<ClipboardError>;
template <class T = void> using Result = NativeToolkit::Result<T, Error>;
}  // namespace NativeToolkit::Clipboard
