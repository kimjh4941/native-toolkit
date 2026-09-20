/**
 * @file WindowsNotificationApiInternal.h
 * @brief Test seams for the notification C++ API.
 * @details
 *  Manager::Create registers this process with the OS, which a unit test host
 *  cannot do. These give a test the same Manager without that registration, so
 *  the fourteen operations can be driven against a mock backend exactly as the
 *  C ABI ones already are. Same idea, and same naming, as
 *  WindowsNotificationManager::SetBackendForTest.
 *
 *  Not part of the public API and not exported.
 */
#pragma once

#include "NativeToolkit/Notification.h"

namespace NativeToolkit::Notification::Detail {

/// Reaches the parts of Manager that only Create may otherwise touch.
class TestAccess {
public:
    /**
     * @brief A live Manager without the OS registration Create performs.
     * @details Marks the process as having a manager and installs the
     *          activation forwarder, so SetInvokedHandler and the operations
     *          behave as they would after a real Create. Closing or destroying
     *          it releases the process the same way.
     */
    static Manager MakeManager();
};

}  // namespace NativeToolkit::Notification::Detail
