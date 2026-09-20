/**
 * @file WindowsClipboardApiInternal.h
 * @brief Test seams for the clipboard C++ API.
 * @details
 *  A process gets one clipboard session, and abandoning one is meant to be
 *  final. A test suite, though, runs many cases in one process and has to be
 *  able to put that state back. Same idea, and same naming, as
 *  ClipboardManager::SetHistoryBackendFactoryForTest.
 *
 *  Not part of the public API and not exported.
 */
#pragma once

#include "NativeToolkit/Clipboard.h"

namespace NativeToolkit::Clipboard::Detail {

/// Reaches the process-wide session state that nothing else may touch.
class ClipboardTestAccess {
public:
    /**
     * @brief Forgets that this process ever had a session.
     * @details Only undoes the bookkeeping this API keeps; whatever the
     *          manager underneath still holds is the test's own business.
     */
    static void ResetProcessState();

    /// Whether a session was destroyed without being closed.
    static bool IsAbandoned();
};

}  // namespace NativeToolkit::Clipboard::Detail
