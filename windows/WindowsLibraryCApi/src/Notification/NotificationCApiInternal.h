#pragma once
// Test seam for the notification part of the C ABI.
//
// ntk_notification_manager_create registers the process with the OS, which a
// unit test host cannot do. A test puts a factory in place of
// Manager::Create - typically one over Detail::TestAccess::MakeManager - so the
// C ABI around it runs as it would.

#include "NativeToolkit/Notification.h"

namespace NativeToolkitC::Detail::Notification {

using ManagerFactory = NativeToolkit::Notification::Result<NativeToolkit::Notification::Manager> (*)(
    const NativeToolkit::Notification::ManagerOptions& options);

/// Replaces Manager::Create; nullptr restores it.
void SetManagerFactoryForTest(ManagerFactory factory) noexcept;

}  // namespace NativeToolkitC::Detail::Notification
