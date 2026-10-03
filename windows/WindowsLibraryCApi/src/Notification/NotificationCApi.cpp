// The notification functions of the C ABI: the runtime, the manager, the
// operations that take no content, and the two output handles (OP-07..OP-09,
// OP-12..OP-20). Each converts its input, calls the C++ API and hands the
// result back; the C++ API decides everything else.

#include "NativeToolkitC/Notification.h"

#include <atomic>
#include <memory>
#include <utility>

#include "Common/Guard.h"
#include "Common/Handles.h"
#include "Common/LastError.h"
#include "Common/Utf8.h"
#include "Notification/NotificationCApiInternal.h"
#include "Notification/NotificationConvert.h"
#include "Notification/NotificationRuntime.h"

using namespace NativeToolkitC::Detail;
using namespace NativeToolkitC::Detail::Notification;

namespace {

std::atomic<ManagerFactory> g_factory{nullptr};

ntk_notification_error Succeed() noexcept
{
    SetLastSystemCode(0);
    return NTK_NOTIFICATION_ERROR_NONE;
}

ntk_notification_error Fail(ntk_notification_error code, uint32_t systemCode = 0) noexcept
{
    SetLastSystemCode(systemCode);
    return code;
}

ntk_notification_error Fail(const Api::Error& error) noexcept
{
    // The C values are the C++ enumeration's (checked by T-11).
    return Fail(static_cast<ntk_notification_error>(error.code), error.systemCode);
}

ntk_notification_error Done(const Api::Result<void>& result) noexcept
{
    return result.has_value() ? Succeed() : Fail(result.error());
}

/// Everything below runs inside this: no exception leaves the C ABI (7.7).
template <class F>
ntk_notification_error Run(F&& body) noexcept
{
    return Guarded<ntk_notification_error>(NTK_NOTIFICATION_ERROR_HRESULT_FAILURE,
                                           NTK_NOTIFICATION_ERROR_HRESULT_FAILURE,
                                           NTK_SYSTEM_CODE_E_OUTOFMEMORY, body);
}

/// An operation on the manager: a NULL handle is refused, anything else is
/// the C++ API's to answer, closed or not.
template <class F>
ntk_notification_error WithManager(ntk_notification_manager* manager, F&& body) noexcept
{
    return Run([&]() -> ntk_notification_error {
        if (!manager) return Fail(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);
        return body(manager->manager);
    });
}

Api::Result<Api::Manager> CreateManager(const Api::ManagerOptions& options)
{
    const auto factory = g_factory.load();
    return factory ? factory(options) : Api::Manager::Create(options);
}

}  // namespace

namespace NativeToolkitC::Detail::Notification {

void SetManagerFactoryForTest(ManagerFactory factory) noexcept
{
    g_factory.store(factory);
}

}  // namespace NativeToolkitC::Detail::Notification

// =============================================================================
// Runtime (OP-07)
// =============================================================================

extern "C" ntk_notification_error NTK_CALL ntk_notification_runtime_initialize(
    uint32_t major_minor, ntk_notification_runtime** out_runtime)
{
    return Run([&]() -> ntk_notification_error {
        if (!out_runtime) return Fail(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);
        *out_runtime = nullptr;
        // Allocated first, so that a runtime once loaded always has a handle.
        auto runtime = std::make_unique<ntk_notification_runtime>();
        uint32_t systemCode = 0;
        const auto result = InitializeRuntime(major_minor, &systemCode);
        if (result != NTK_NOTIFICATION_ERROR_NONE) return Fail(result, systemCode);
        *out_runtime = runtime.release();
        return Succeed();
    });
}

extern "C" void NTK_CALL ntk_notification_runtime_free(ntk_notification_runtime* runtime)
{
    if (!runtime) return;
    delete runtime;
    ReleaseRuntime();
}

// =============================================================================
// Manager (OP-08, OP-09, E-12)
// =============================================================================

extern "C" ntk_notification_error NTK_CALL ntk_notification_manager_create(
    const ntk_notification_manager_options* options, ntk_notification_manager** out_manager)
{
    return Run([&]() -> ntk_notification_error {
        if (out_manager) *out_manager = nullptr;

        // The release is taken before anything can fail, so that every path
        // below lets go of it: on failure the guard's last share goes when
        // this returns, on the calling thread (7.5.1).
        ntk_notification_manager_options raw{};
        const auto read = ReadManagerOptions(options, raw);
        const auto guard = NewGuard(raw.release, raw.user_data);
        if (read != NTK_NOTIFICATION_ERROR_NONE) return Fail(read);
        if (!out_manager) return Fail(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);

        Api::ManagerOptions converted;
        if (const auto e = ToManagerOptions(raw, converted); e != NTK_NOTIFICATION_ERROR_NONE) return Fail(e);
        converted.onInvoked = MakeHandler(raw.on_invoked, guard);

        auto created = CreateManager(converted);
        if (!created.has_value()) return Fail(created.error());
        // Should this throw, the Manager closes on the way out.
        *out_manager = new ntk_notification_manager(std::move(created.value()), guard);
        ManagerOpened();
        return Succeed();
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_manager_set_invoked_handler(
    ntk_notification_manager* manager, ntk_notification_invoked_fn on_invoked, void* user_data,
    ntk_release_fn release)
{
    return Run([&]() -> ntk_notification_error {
        const auto guard = NewGuard(release, user_data);
        if (!manager) return Fail(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);

        // The previous share is let go after both locks, the C++ one inside
        // SetInvokedHandler and this handle's (E-12).
        std::shared_ptr<ReleaseGuard> previous;
        {
            std::lock_guard<std::mutex> lock(manager->mutex);
            if (!manager->open) return Fail(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED);
            manager->manager.SetInvokedHandler(MakeHandler(on_invoked, guard));
            previous = std::exchange(manager->guard, guard);
        }
        previous.reset();
        return Succeed();
    });
}

extern "C" void NTK_CALL ntk_notification_manager_close(ntk_notification_manager* manager)
{
    if (!manager) return;
    std::shared_ptr<ReleaseGuard> previous;
    {
        std::lock_guard<std::mutex> lock(manager->mutex);
        if (!manager->open) return;
        manager->manager.Close();
        manager->open = false;
        previous = std::move(manager->guard);
    }
    ManagerClosed();
    previous.reset();
}

extern "C" void NTK_CALL ntk_notification_manager_free(ntk_notification_manager* manager)
{
    if (!manager) return;
    ntk_notification_manager_close(manager);
    delete manager;
}

// =============================================================================
// Operations (OP-12..OP-20). OP-10 and OP-11 take content; see
// NotificationContentCApi.cpp.
// =============================================================================

extern "C" ntk_notification_error NTK_CALL ntk_notification_cancel_scheduled(
    ntk_notification_manager* manager, const char* tag, const char* group)
{
    return WithManager(manager, [&](Api::Manager& m) -> ntk_notification_error {
        std::wstring wideTag, wideGroup;
        if ((tag && !Utf8ToWide(tag, wideTag)) || (group && !Utf8ToWide(group, wideGroup))) {
            return Fail(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);
        }
        return Done(m.CancelScheduled(wideTag, wideGroup));
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_update_progress(
    ntk_notification_manager* manager, const ntk_notification_progress_update* update)
{
    return WithManager(manager, [&](Api::Manager& m) -> ntk_notification_error {
        Api::ProgressUpdate converted;
        if (const auto e = ToProgressUpdate(update, converted); e != NTK_NOTIFICATION_ERROR_NONE) return Fail(e);
        return Done(m.UpdateProgress(converted));
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_set_badge(
    ntk_notification_manager* manager, int32_t value)
{
    return WithManager(manager, [&](Api::Manager& m) { return Done(m.SetBadge(value)); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_remove_by_id(
    ntk_notification_manager* manager, uint32_t id)
{
    return WithManager(manager, [&](Api::Manager& m) { return Done(m.RemoveById(id)); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_remove_by_tag(
    ntk_notification_manager* manager, const char* tag, const char* group)
{
    return WithManager(manager, [&](Api::Manager& m) -> ntk_notification_error {
        std::wstring wideTag, wideGroup;
        if ((tag && !Utf8ToWide(tag, wideTag)) || (group && !Utf8ToWide(group, wideGroup))) {
            return Fail(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);
        }
        return Done(m.RemoveByTag(wideTag, wideGroup));
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_remove_all(ntk_notification_manager* manager)
{
    return WithManager(manager, [&](Api::Manager& m) { return Done(m.RemoveAll()); });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_get_all(
    ntk_notification_manager* manager, ntk_notification_list** out_list)
{
    if (out_list) *out_list = nullptr;
    return WithManager(manager, [&](Api::Manager& m) -> ntk_notification_error {
        if (!out_list) return Fail(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);
        const auto result = m.GetAll();
        if (!result.has_value()) return Fail(result.error());
        *out_list = NewList(result.value());
        return Succeed();
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_get_setting(
    ntk_notification_manager* manager, ntk_notification_setting* out_setting)
{
    return WithManager(manager, [&](Api::Manager& m) -> ntk_notification_error {
        if (!out_setting) return Fail(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);
        const auto result = m.GetSetting();
        if (!result.has_value()) return Fail(result.error());
        *out_setting = static_cast<ntk_notification_setting>(result.value());
        return Succeed();
    });
}

extern "C" ntk_notification_error NTK_CALL ntk_notification_open_settings(ntk_notification_manager* manager)
{
    return WithManager(manager, [&](Api::Manager& m) { return Done(m.OpenSettings()); });
}

// =============================================================================
// List (the output of OP-18)
// =============================================================================

namespace {

const ntk_notification_list::Entry* EntryAt(const ntk_notification_list* list, size_t index) noexcept
{
    return list && index < list->entries.size() ? &list->entries[index] : nullptr;
}

}  // namespace

extern "C" size_t NTK_CALL ntk_notification_list_count(const ntk_notification_list* list)
{
    return list ? list->entries.size() : 0;
}

extern "C" uint32_t NTK_CALL ntk_notification_list_id_at(const ntk_notification_list* list, size_t index)
{
    const auto* entry = EntryAt(list, index);
    return entry ? entry->id : 0;
}

extern "C" const char* NTK_CALL ntk_notification_list_tag_at(
    const ntk_notification_list* list, size_t index, size_t* out_size)
{
    const auto* entry = EntryAt(list, index);
    if (!entry) {
        if (out_size) *out_size = 0;
        return nullptr;
    }
    return Borrow(entry->tag, out_size);
}

extern "C" const char* NTK_CALL ntk_notification_list_group_at(
    const ntk_notification_list* list, size_t index, size_t* out_size)
{
    const auto* entry = EntryAt(list, index);
    if (!entry) {
        if (out_size) *out_size = 0;
        return nullptr;
    }
    return Borrow(entry->group, out_size);
}

extern "C" void NTK_CALL ntk_notification_list_free(ntk_notification_list* list)
{
    delete list;
}

// =============================================================================
// Activation (the argument of ntk_notification_invoked_fn)
// =============================================================================

extern "C" const char* NTK_CALL ntk_notification_activation_raw_arguments(
    const ntk_notification_activation* activation, size_t* out_size)
{
    if (!activation) {
        if (out_size) *out_size = 0;
        return nullptr;
    }
    return Borrow(activation->raw, out_size);
}

extern "C" size_t NTK_CALL ntk_notification_activation_value_count(
    const ntk_notification_activation* activation)
{
    return activation ? activation->values.size() : 0;
}

extern "C" const char* NTK_CALL ntk_notification_activation_key_at(
    const ntk_notification_activation* activation, size_t index, size_t* out_size)
{
    if (!activation || index >= activation->values.size()) {
        if (out_size) *out_size = 0;
        return nullptr;
    }
    return Borrow(activation->values[index].first, out_size);
}

extern "C" const char* NTK_CALL ntk_notification_activation_value_at(
    const ntk_notification_activation* activation, size_t index, size_t* out_size)
{
    if (!activation || index >= activation->values.size()) {
        if (out_size) *out_size = 0;
        return nullptr;
    }
    return Borrow(activation->values[index].second, out_size);
}
