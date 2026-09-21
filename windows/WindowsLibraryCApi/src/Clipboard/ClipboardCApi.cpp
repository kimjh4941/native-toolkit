// The clipboard session and the reads and writes of the C ABI (OP-21..OP-34,
// OP-36..OP-39). Each converts its input, calls the C++ API and hands the
// result back; the C++ API decides everything else, including which thread
// may call what.

#include "NativeToolkitC/Clipboard.h"

#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "Clipboard/ClipboardConvert.h"
#include "Common/Guard.h"
#include "Common/Handles.h"
#include "Common/LastError.h"
#include "Common/Utf8.h"

using namespace NativeToolkitC::Detail;
using namespace NativeToolkitC::Detail::Clipboard;

namespace {

constexpr ntk_clipboard_error kInvalid = NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;

ntk_clipboard_error Succeed() noexcept
{
    SetLastSystemCode(0);
    return NTK_CLIPBOARD_ERROR_NONE;
}

ntk_clipboard_error Fail(ntk_clipboard_error code, uint32_t systemCode = 0) noexcept
{
    SetLastSystemCode(systemCode);
    return code;
}

ntk_clipboard_error Fail(const Api::Error& error) noexcept
{
    // The C values are the C++ enumeration's (checked by T-11).
    return Fail(static_cast<ntk_clipboard_error>(error.code), error.systemCode);
}

ntk_clipboard_error Done(const Api::Result<void>& result) noexcept
{
    return result.has_value() ? Succeed() : Fail(result.error());
}

/// Everything below runs inside this: no exception leaves the C ABI (7.7).
/// The C++ API reports its own out-of-memory with the error value as the
/// system code, and so does this.
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

}  // namespace

// =============================================================================
// Session (OP-21..OP-24)
// =============================================================================

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_session_create(
    const ntk_clipboard_session_options* options, ntk_clipboard_session** out_session)
{
    return Run([&]() -> ntk_clipboard_error {
        if (!out_session) return Fail(kInvalid);
        *out_session = nullptr;

        auto gate = std::make_shared<CallbackGate>();
        Api::SessionOptions converted;
        if (const auto e = ToSessionOptions(options, gate, converted); e != NTK_CLIPBOARD_ERROR_NONE) return Fail(e);

        auto created = Api::Session::Create(converted);
        if (!created.has_value()) return Fail(created.error());
        // Should this throw, the Session is destroyed unclosed and abandoned,
        // which is what a session nobody holds must become.
        *out_session = new ntk_clipboard_session(std::move(created.value()), std::move(gate));
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_session_close(ntk_clipboard_session* session)
{
    return WithSession(session, [](Api::Session& s) { return Done(s.Close()); });
}

extern "C" int32_t NTK_CALL ntk_clipboard_session_can_close(const ntk_clipboard_session* session)
{
    return !session || session->session.CanClose() ? 1 : 0;
}

extern "C" void NTK_CALL ntk_clipboard_session_free(ntk_clipboard_session* session)
{
    if (!session) return;
    // Callbacks stop first, and the ones running on other threads finish,
    // before the Session goes; an unclosed one is then abandoned (7.4).
    session->gate->Shut();
    delete session;
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_set_history_handlers(
    ntk_clipboard_session* session, const ntk_clipboard_history_handlers* handlers)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        Api::HistoryHandlers converted;
        if (const auto e = ToHistoryHandlers(handlers, session->gate, converted); e != NTK_CLIPBOARD_ERROR_NONE) return Fail(e);
        return Done(s.SetHistoryHandlers(std::move(converted)));
    });
}

// =============================================================================
// Read and write (OP-25..OP-34, OP-36..OP-39)
// =============================================================================

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_copy_text(
    ntk_clipboard_session* session, const char* text, uint32_t flags)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        Api::WriteOptions options;
        std::wstring wide;
        if (ToWriteOptions(flags, options) != NTK_CLIPBOARD_ERROR_NONE || !RequiredText(text, wide)) return Fail(kInvalid);
        return Done(s.CopyText(wide, options));
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_paste_text(
    ntk_clipboard_session* session, ntk_string** out_text)
{
    if (out_text) *out_text = nullptr;
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        if (!out_text) return Fail(kInvalid);
        const auto result = s.PasteText();
        if (!result.has_value()) return Fail(result.error());
        *out_text = NewString(result.value());
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_copy_html(
    ntk_clipboard_session* session, const char* fragment, const char* plain_text, uint32_t flags)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        Api::WriteOptions options;
        std::wstring wideFragment, widePlain;
        if (ToWriteOptions(flags, options) != NTK_CLIPBOARD_ERROR_NONE || !RequiredText(fragment, wideFragment) ||
            (plain_text && !Utf8ToWide(plain_text, widePlain))) {
            return Fail(kInvalid);
        }
        return Done(s.CopyHtml(wideFragment, widePlain, options));
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_paste_html(
    ntk_clipboard_session* session, ntk_string** out_html)
{
    if (out_html) *out_html = nullptr;
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        if (!out_html) return Fail(kInvalid);
        const auto result = s.PasteHtml();
        if (!result.has_value()) return Fail(result.error());
        *out_html = NewString(result.value());
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_copy_files(
    ntk_clipboard_session* session, const char* const* paths, size_t count, uint32_t flags)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        Api::WriteOptions options;
        std::vector<std::wstring> widePaths;
        if (ToWriteOptions(flags, options) != NTK_CLIPBOARD_ERROR_NONE || !ToPaths(paths, count, widePaths)) {
            return Fail(kInvalid);
        }
        return Done(s.CopyFiles(widePaths, options));
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_paste_files(
    ntk_clipboard_session* session, ntk_string_list** out_paths)
{
    if (out_paths) *out_paths = nullptr;
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        if (!out_paths) return Fail(kInvalid);
        const auto result = s.PasteFiles();
        if (!result.has_value()) return Fail(result.error());
        *out_paths = NewStringList(result.value());
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_copy_dib(
    ntk_clipboard_session* session, const uint8_t* dib, size_t size, uint32_t flags)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        Api::WriteOptions options;
        std::vector<std::byte> bytes;
        if (ToWriteOptions(flags, options) != NTK_CLIPBOARD_ERROR_NONE || !ToBytes(dib, size, bytes)) return Fail(kInvalid);
        return Done(s.CopyDib(bytes, options));
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_paste_dib(
    ntk_clipboard_session* session, ntk_bytes** out_dib)
{
    if (out_dib) *out_dib = nullptr;
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        if (!out_dib) return Fail(kInvalid);
        const auto result = s.PasteDib();
        if (!result.has_value()) return Fail(result.error());
        *out_dib = NewBytes(result.value().data(), result.value().size());
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_copy_custom(
    ntk_clipboard_session* session, const char* format_name, const uint8_t* data, size_t size,
    uint32_t flags)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        Api::WriteOptions options;
        std::wstring name;
        std::vector<std::byte> bytes;
        if (ToWriteOptions(flags, options) != NTK_CLIPBOARD_ERROR_NONE || !RequiredText(format_name, name) ||
            !ToBytes(data, size, bytes)) {
            return Fail(kInvalid);
        }
        return Done(s.CopyCustom(name, bytes, options));
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_paste_custom(
    ntk_clipboard_session* session, const char* format_name, ntk_bytes** out_data)
{
    if (out_data) *out_data = nullptr;
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        std::wstring name;
        if (!out_data || !RequiredText(format_name, name)) return Fail(kInvalid);
        const auto result = s.PasteCustom(name);
        if (!result.has_value()) return Fail(result.error());
        *out_data = NewBytes(result.value().data(), result.value().size());
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_has_format(
    ntk_clipboard_session* session, const char* format_name, int32_t* out_present)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        std::wstring name;
        if (!out_present || !RequiredText(format_name, name)) return Fail(kInvalid);
        const auto result = s.HasFormat(name);
        if (!result.has_value()) return Fail(result.error());
        *out_present = result.value() ? 1 : 0;
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_get_formats(
    ntk_clipboard_session* session, ntk_string_list** out_formats)
{
    if (out_formats) *out_formats = nullptr;
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        if (!out_formats) return Fail(kInvalid);
        const auto result = s.GetFormats();
        if (!result.has_value()) return Fail(result.error());
        *out_formats = NewStringList(result.value());
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_get_preferred_format(
    ntk_clipboard_session* session, ntk_string** out_format)
{
    if (out_format) *out_format = nullptr;
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        if (!out_format) return Fail(kInvalid);
        const auto result = s.GetPreferredFormat();
        if (!result.has_value()) return Fail(result.error());
        *out_format = NewString(result.value());
        return Succeed();
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_clear(ntk_clipboard_session* session)
{
    return WithSession(session, [](Api::Session& s) { return Done(s.Clear()); });
}
