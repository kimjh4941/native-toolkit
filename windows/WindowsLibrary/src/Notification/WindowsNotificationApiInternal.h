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

#include <string>

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

    /**
     * @brief Delivers an activation as the OS would, on the calling thread.
     * @param argsJson The argument JSON the backend would have produced.
     */
    static void Activate(const std::wstring& argsJson);

    /**
     * @brief Runs hook in every delivery after the handler has been copied
     *        and before it is called; nullptr removes it.
     * @details The window a replacement or a Close can land in while a
     *          delivery is under way. A test blocks in hook to hold a
     *          delivery there (stage 5 design CT-18).
     */
    static void SetAfterHandlerCopy(void (*hook)()) noexcept;
};

}  // namespace NativeToolkit::Notification::Detail
