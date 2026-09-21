// The clipboard handles of the C ABI and the conversions to the C++ API
// (stage 5 design 7.5.2, 8.4.3).

#include "Clipboard/ClipboardConvert.h"

#include "Common/Guard.h"
#include "Common/StructInput.h"
#include "Common/Utf8.h"

namespace NativeToolkitC::Detail::Clipboard {

namespace {

constexpr ntk_clipboard_error kOk = NTK_CLIPBOARD_ERROR_NONE;
constexpr ntk_clipboard_error kInvalid = NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;

template <class T>
ntk_clipboard_error ReadStruct(const T* in, T& out)
{
    switch (ReadInputStruct(in, out)) {
    case StructCheck::Ok:           return kOk;
    case StructCheck::NotSupported: return NTK_CLIPBOARD_ERROR_NOT_SUPPORTED;
    default:                        return kInvalid;
    }
}

}  // namespace

ntk_clipboard_error ToWriteOptions(uint32_t flags, Api::WriteOptions& out) noexcept
{
    out = Api::WriteOptions{};
    if ((flags & ~static_cast<uint32_t>(NTK_CLIPBOARD_WRITE_SENSITIVE)) != 0) return kInvalid;
    out.excludeFromHistory = (flags & NTK_CLIPBOARD_WRITE_EXCLUDE_HISTORY) != 0;
    out.excludeFromRoaming = (flags & NTK_CLIPBOARD_WRITE_EXCLUDE_ROAMING) != 0;
    return kOk;
}

ntk_clipboard_error ToSessionOptions(const ntk_clipboard_session_options* in,
                                     const std::shared_ptr<CallbackGate>& gate, Api::SessionOptions& out)
{
    out = Api::SessionOptions{};
    if (!in) return kOk;
    ntk_clipboard_session_options options;
    const auto read = ReadStruct(in, options);
    if (read != kOk) return read;
    if (options.reserved0 != 0) return kInvalid;
    if (const auto fn = options.on_clipboard_changed) {
        void* const userData = options.user_data;
        out.onClipboardChanged = [gate, fn, userData] {
            gate->Run([&] { CallCaller([&] { fn(userData); }); });
        };
    }
    return kOk;
}

ntk_clipboard_error ToHistoryHandlers(const ntk_clipboard_history_handlers* in,
                                      const std::shared_ptr<CallbackGate>& gate, Api::HistoryHandlers& out)
{
    out = Api::HistoryHandlers{};
    if (!in) return kOk;
    ntk_clipboard_history_handlers handlers;
    const auto read = ReadStruct(in, handlers);
    if (read != kOk) return read;
    if (handlers.reserved0 != 0) return kInvalid;

    void* const userData = handlers.user_data;
    if (const auto fn = handlers.on_history_changed) {
        out.onHistoryChanged = [gate, fn, userData] {
            gate->Run([&] { CallCaller([&] { fn(userData); }); });
        };
    }
    if (const auto fn = handlers.on_history_enabled_changed) {
        out.onHistoryEnabledChanged = [gate, fn, userData](bool enabled) {
            gate->Run([&] { CallCaller([&] { fn(userData, enabled ? 1 : 0); }); });
        };
    }
    if (const auto fn = handlers.on_roaming_enabled_changed) {
        out.onRoamingEnabledChanged = [gate, fn, userData](bool enabled) {
            gate->Run([&] { CallCaller([&] { fn(userData, enabled ? 1 : 0); }); });
        };
    }
    return kOk;
}

bool RequiredText(const char* text, std::wstring& out)
{
    return text && Utf8ToWide(text, out);
}

bool ToBytes(const uint8_t* data, size_t size, std::vector<std::byte>& out)
{
    out.clear();
    if (size == 0) return true;
    if (!data) return false;
    const auto* first = reinterpret_cast<const std::byte*>(data);
    out.assign(first, first + size);
    return true;
}

bool ToPaths(const char* const* paths, size_t count, std::vector<std::wstring>& out)
{
    out.clear();
    if (count == 0) return true;
    if (!paths) return false;
    out.reserve(count);
    for (size_t i = 0; i < count; ++i) {
        std::wstring path;
        if (!RequiredText(paths[i], path)) return false;
        out.push_back(std::move(path));
    }
    return true;
}

}  // namespace NativeToolkitC::Detail::Clipboard
