/**
 * @file WindowsNotificationApi.cpp
 * @brief The C++ API of the Notification feature (OP-08..OP-20).
 * @details
 *  Thin over the existing manager: the content type goes straight to the Data
 *  layer, and the raw DWORD the manager reports becomes a typed failure. No
 *  notification logic lives here.
 *
 *  Two things about the shape are worth stating, because they are constraints
 *  of the platform rather than decisions of this API.
 *
 *  Windows registers one activation handler per process, so there is one set
 *  of notification state per process however this is written. Manager is the
 *  handle to that state: the first Create takes it and a second is told
 *  NotSupported, rather than silently replacing the first one's handler the
 *  way a second initNotificationManager does. Replacing the handler on purpose
 *  is what SetInvokedHandler is for (N-10).
 *
 *  The handler is held in this file rather than on the Manager because the
 *  callback the C ABI takes is a plain function pointer with nowhere to carry
 *  a std::function. There is at most one Manager, so one slot is enough. It is
 *  read under a lock: activations arrive on whichever thread the OS chooses.
 *
 *  Runtime is not here - it lives with the bootstrap call in
 *  Data/WindowsAppSdkBootstrap.cpp, so that the unit tests, which compile this
 *  file, keep their independence from Microsoft.WindowsAppRuntime.Bootstrap.dll.
 */
#include "pch.h"

#include <mutex>
#include <string>
#include <utility>

#include "Common/CommonInternal.h"
#include "NativeToolkit/Notification.h"
#include "Notification/Data/WindowsNotificationActivation.h"
#include "Notification/WindowsNotificationApiInternal.h"
#include "Notification/WindowsNotificationManagerInternal.h"

namespace NativeToolkit::Notification {

namespace {

const wchar_t* TAG = L"NativeToolkit::Notification";

/// The handler the one Manager of this process installed.
std::mutex                                g_handlerMutex;
std::function<void(const ActivationArgs&)> g_handler;

/// True while a Manager exists. Guards the second Create (7.4.2).
bool g_managerLive = false;

/// The C callback the manager takes, which forwards to whatever handler is set.
void ForwardActivation(const wchar_t* argsJson)
{
    std::function<void(const ActivationArgs&)> handler;
    {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        handler = g_handler;
    }
    if (!handler) {
        DLog(TAG, L"[ForwardActivation] no handler installed; activation dropped");
        return;
    }
    handler(Data::ParseActivationJson(argsJson ? argsJson : L""));
}

/// What a closed or moved-from Manager gives every operation. It owns none of
/// the process's notification state, and asking the state directly would let a
/// moved-from handle act on whatever the live one owns.
Error Closed() noexcept
{
    return Error{ErrorCode::NotInitialized, NOTIFICATION_ERROR_NOT_INITIALIZED};
}

/// Nothing on success, or the case the manager reported.
Result<void> ToResult(DWORD error)
{
    if (error == NOTIFICATION_SUCCESS) {
        return {};
    }
    return Unexpected{Error{static_cast<ErrorCode>(error), error}};
}

/// A null pointer and an empty string mean the same thing to the C ABI.
const wchar_t* OrNull(const std::wstring& text) noexcept
{
    return text.empty() ? nullptr : text.c_str();
}

WindowsNotificationManager& Backing() noexcept
{
    return WindowsNotificationManager::GetInstance();
}

}  // namespace

// =============================================================================
// Lifetime (OP-08, OP-09, N-10)
// =============================================================================

Result<Manager> Manager::Create(const ManagerOptions& options)
{
    DFLog(TAG, L"[Manager::Create] isPackaged=%d, displayName=%ls",
          options.isPackaged, options.displayName.c_str());

    if (g_managerLive) {
        DLog(TAG, L"[Manager::Create] a manager already exists in this process");
        return Unexpected{Error{ErrorCode::NotSupported, 0}};
    }

    {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        g_handler = options.onInvoked;
    }

    DWORD error = NOTIFICATION_SUCCESS;
    Backing().Init(&ForwardActivation, options.isPackaged ? TRUE : FALSE,
                   OrNull(options.displayName), OrNull(options.iconUri), &error);
    if (error != NOTIFICATION_SUCCESS) {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        g_handler = nullptr;
        return Unexpected{Error{static_cast<ErrorCode>(error), error}};
    }

    Manager manager;
    manager.held_ = true;
    g_managerLive = true;
    return manager;
}

Manager::Manager(Manager&& other) noexcept : held_(other.held_)
{
    other.held_ = false;
}

Manager& Manager::operator=(Manager&& other) noexcept
{
    if (this != &other) {
        Close();
        held_ = other.held_;
        other.held_ = false;
    }
    return *this;
}

Manager::~Manager()
{
    Close();
}

void Manager::Close() noexcept
{
    if (!held_) {
        return;
    }
    DLog(TAG, L"[Manager::Close]");

    // Uninit revokes the registration before it drops the callback, which is
    // what closes the window where an activation could arrive with nothing to
    // receive it (NTF-40). Clearing the handler afterwards is safe for the
    // same reason.
    Backing().Uninit();
    {
        std::lock_guard<std::mutex> lock(g_handlerMutex);
        g_handler = nullptr;
    }
    g_managerLive = false;
    held_ = false;
}

void Manager::SetInvokedHandler(std::function<void(const ActivationArgs&)> handler)
{
    DLog(TAG, L"[Manager::SetInvokedHandler]");
    std::lock_guard<std::mutex> lock(g_handlerMutex);
    g_handler = std::move(handler);
}

// =============================================================================
// Delivery (OP-10..OP-13)
// =============================================================================

Result<void> Manager::Show(const NotificationContent& content)
{
    if (!held_) return Unexpected{Closed()};
    DWORD error = NOTIFICATION_SUCCESS;
    Backing().Show(content, &error);
    return ToResult(error);
}

Result<void> Manager::Schedule(const NotificationContent& content,
                               std::chrono::system_clock::time_point when)
{
    if (!held_) return Unexpected{Closed()};
    const auto milliseconds =
        std::chrono::duration_cast<std::chrono::milliseconds>(when.time_since_epoch()).count();

    DWORD error = NOTIFICATION_SUCCESS;
    Backing().Schedule(content, milliseconds, &error);
    return ToResult(error);
}

Result<void> Manager::CancelScheduled(const std::wstring& tag, const std::wstring& group)
{
    if (!held_) return Unexpected{Closed()};
    DWORD error = NOTIFICATION_SUCCESS;
    Backing().CancelScheduled(tag.c_str(), group.c_str(), &error);
    return ToResult(error);
}

Result<void> Manager::UpdateProgress(const ProgressUpdate& update)
{
    if (!held_) return Unexpected{Closed()};
    DWORD error = NOTIFICATION_SUCCESS;
    Backing().UpdateProgress(update.tag.c_str(), update.group.c_str(), update.value,
                             update.valueString.c_str(), update.status.c_str(),
                             update.sequenceNumber, &error);
    return ToResult(error);
}

// =============================================================================
// The action centre (OP-14..OP-18)
// =============================================================================

Result<void> Manager::SetBadge(int value)
{
    if (!held_) return Unexpected{Closed()};
    DWORD error = NOTIFICATION_SUCCESS;
    Backing().SetBadge(value, &error);
    return ToResult(error);
}

Result<void> Manager::RemoveById(uint32_t id)
{
    if (!held_) return Unexpected{Closed()};
    DWORD error = NOTIFICATION_SUCCESS;
    Backing().RemoveById(id, &error);
    return ToResult(error);
}

Result<void> Manager::RemoveByTag(const std::wstring& tag, const std::wstring& group)
{
    if (!held_) return Unexpected{Closed()};
    DWORD error = NOTIFICATION_SUCCESS;
    Backing().RemoveByTag(tag.c_str(), group.c_str(), &error);
    return ToResult(error);
}

Result<void> Manager::RemoveAll()
{
    if (!held_) return Unexpected{Closed()};
    DWORD error = NOTIFICATION_SUCCESS;
    Backing().RemoveAll(&error);
    return ToResult(error);
}

Result<std::vector<NotificationRef>> Manager::GetAll()
{
    if (!held_) return Unexpected{Closed()};
    // The manager writes a JSON array into a caller buffer and truncates
    // silently when it does not fit, so the size is chosen here and checked by
    // parsing: a truncated array has lost its closing bracket and cannot parse.
    // T-14 removes the buffer; until then, growing and retrying is what keeps a
    // long list from coming back quietly short.
    constexpr size_t kFirstBuffer = 16 * 1024;
    constexpr size_t kLargestBuffer = 1024 * 1024;

    using winrt::Windows::Data::Json::JsonArray;

    for (size_t size = kFirstBuffer; ; size *= 4) {
        std::wstring buffer(size, L'\0');
        DWORD error = NOTIFICATION_SUCCESS;
        Backing().GetAll(buffer.data(), static_cast<uint32_t>(buffer.size()), &error);
        if (error != NOTIFICATION_SUCCESS) {
            return Unexpected{Error{static_cast<ErrorCode>(error), error}};
        }

        JsonArray array{nullptr};
        if (!JsonArray::TryParse(winrt::hstring{buffer.c_str()}, array)) {
            if (size >= kLargestBuffer) {
                DFLog(TAG, L"[Manager::GetAll] the list did not parse at %zu characters", size);
                return Unexpected{Error{ErrorCode::HResultFailure, 0}};
            }
            continue;
        }

        std::vector<NotificationRef> notifications;
        notifications.reserve(array.Size());
        for (const auto& entry : array) {
            const auto object = entry.GetObject();
            NotificationRef ref;
            ref.id    = static_cast<uint32_t>(object.GetNamedNumber(L"id"));
            ref.tag   = std::wstring{object.GetNamedString(L"tag")};
            ref.group = std::wstring{object.GetNamedString(L"group")};
            notifications.push_back(std::move(ref));
        }
        return notifications;
    }
}

// =============================================================================
// Settings (OP-19, OP-20)
// =============================================================================

Result<NotificationSetting> Manager::GetSetting()
{
    if (!held_) return Unexpected{Closed()};
    // The C ABI packs "could not ask" into the same int as the answer, by
    // returning -1. Here the two are told apart.
    const int setting = Backing().GetSetting();
    if (setting < 0) {
        return Unexpected{Error{ErrorCode::HResultFailure, 0}};
    }
    return static_cast<NotificationSetting>(setting);
}

Result<void> Manager::OpenSettings()
{
    if (!held_) return Unexpected{Closed()};
    DWORD error = NOTIFICATION_SUCCESS;
    Backing().OpenSettings(&error);
    return ToResult(error);
}

// =============================================================================
// Test seam
// =============================================================================

namespace Detail {

Manager TestAccess::MakeManager()
{
    Backing().SetCallbackForTest(&ForwardActivation);
    Manager manager;
    manager.held_ = true;
    g_managerLive = true;
    return manager;
}

}  // namespace Detail

}  // namespace NativeToolkit::Notification
