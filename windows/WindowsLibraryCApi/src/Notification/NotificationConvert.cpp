// The notification handles of the C ABI and the conversions to and from the
// C++ API (stage 5 design 8.4.2, 7.5.1, E-12).

#include "Notification/NotificationConvert.h"

#include <new>

#include "Common/Guard.h"
#include "Common/StructInput.h"
#include "Common/Utf8.h"

namespace NativeToolkitC::Detail::Notification {

namespace {

constexpr ntk_notification_error kOk = NTK_NOTIFICATION_ERROR_NONE;
constexpr ntk_notification_error kInvalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;

/// A string that may be NULL, which stands for "" (E-15).
bool PlainText(const char* text, std::wstring& out)
{
    if (!text) {
        out.clear();
        return true;
    }
    return Utf8ToWide(text, out);
}

template <class T>
ntk_notification_error ReadStruct(const T* in, T& out)
{
    switch (ReadInputStruct(in, out)) {
    case StructCheck::Ok:           return kOk;
    case StructCheck::NotSupported: return NTK_NOTIFICATION_ERROR_NOT_SUPPORTED;
    default:                        return kInvalid;
    }
}

}  // namespace

std::function<void(const Api::ActivationArgs&)> MakeHandler(ntk_notification_invoked_fn fn,
                                                             std::shared_ptr<ReleaseGuard> guard)
{
    if (!fn) return {};
    return [fn, guard = std::move(guard)](const Api::ActivationArgs& args) {
        // The delivery runs on an OS thread and has nowhere to send a failure:
        // an activation that cannot be converted is dropped.
        try {
            const auto activation = ToActivation(args);
            CallCaller([&] { fn(guard->UserData(), &activation); });
        } catch (...) {
        }
    };
}

ntk_notification_activation ToActivation(const Api::ActivationArgs& args)
{
    ntk_notification_activation activation;
    activation.raw = WideToUtf8(args.rawArguments);
    activation.values.reserve(args.values.size());
    for (const auto& [key, value] : args.values) {
        activation.values.emplace_back(WideToUtf8(key), WideToUtf8(value));
    }
    return activation;
}

ntk_notification_list* NewList(const std::vector<Api::NotificationRef>& refs)
{
    auto list = std::make_unique<ntk_notification_list>();
    list->entries.reserve(refs.size());
    for (const auto& ref : refs) {
        list->entries.push_back({ref.id, WideToUtf8(ref.tag), WideToUtf8(ref.group)});
    }
    return list.release();
}

ntk_notification_error ReadManagerOptions(const ntk_notification_manager_options* in,
                                          ntk_notification_manager_options& raw)
{
    const auto read = ReadStruct(in, raw);
    if (read != kOk) return read;
    if (raw.reserved0 != 0 || raw.reserved1 != 0) return kInvalid;
    return kOk;
}

ntk_notification_error ToManagerOptions(const ntk_notification_manager_options& raw,
                                        Api::ManagerOptions& out)
{
    out = Api::ManagerOptions{};
    out.isPackaged = raw.is_unpackaged == 0;
    if (!PlainText(raw.display_name, out.displayName)) return kInvalid;
    if (!PlainText(raw.icon_uri, out.iconUri)) return kInvalid;
    return kOk;
}

ntk_notification_error ToProgressUpdate(const ntk_notification_progress_update* in,
                                        Api::ProgressUpdate& out)
{
    out = Api::ProgressUpdate{};
    ntk_notification_progress_update update;
    const auto read = ReadStruct(in, update);
    if (read != kOk) return read;
    if (update.reserved0 != 0 || update.reserved1 != 0) return kInvalid;
    if (!PlainText(update.tag, out.tag)) return kInvalid;
    if (!PlainText(update.group, out.group)) return kInvalid;
    if (!PlainText(update.value_string, out.valueString)) return kInvalid;
    if (!PlainText(update.status, out.status)) return kInvalid;
    out.value = update.value;
    out.sequenceNumber = update.sequence_number;
    return kOk;
}

}  // namespace NativeToolkitC::Detail::Notification
