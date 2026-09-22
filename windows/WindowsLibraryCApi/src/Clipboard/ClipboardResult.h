#pragma once
// How every clipboard function of the C ABI reports its result (stage 5
// design 7.3, 7.7). Shared by the three source files of the feature.

#include <cstdint>

#include "Clipboard/ClipboardConvert.h"
#include "Common/Guard.h"
#include "Common/LastError.h"

namespace NativeToolkitC::Detail::Clipboard {

constexpr ntk_clipboard_error kInvalid = NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;

inline ntk_clipboard_error Succeed() noexcept
{
    SetLastSystemCode(0);
    return NTK_CLIPBOARD_ERROR_NONE;
}

inline ntk_clipboard_error Fail(ntk_clipboard_error code, uint32_t systemCode = 0) noexcept
{
    SetLastSystemCode(systemCode);
    return code;
}

inline ntk_clipboard_error Fail(const Api::Error& error) noexcept
{
    // The C values are the C++ enumeration's (checked by T-11).
    return Fail(static_cast<ntk_clipboard_error>(error.code), error.systemCode);
}

inline ntk_clipboard_error Done(const Api::Result<void>& result) noexcept
{
    return result.has_value() ? Succeed() : Fail(result.error());
}

/// Everything runs inside this: no exception leaves the C ABI (7.7). The C++
/// API reports its own out-of-memory with the error value as the system code,
/// and so does this.
template <class F>
ntk_clipboard_error Run(F&& body) noexcept
{
    return Guarded<ntk_clipboard_error>(NTK_CLIPBOARD_ERROR_UNKNOWN, NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY,
                                        NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY, body);
}

/// An operation on the session: a NULL handle is refused, anything else is
/// the C++ API's to answer, closed or not.
template <class F>
ntk_clipboard_error WithSession(ntk_clipboard_session* session, F&& body) noexcept
{
    return Run([&]() -> ntk_clipboard_error {
        if (!session) return Fail(kInvalid);
        return body(session->session);
    });
}

}  // namespace NativeToolkitC::Detail::Clipboard
