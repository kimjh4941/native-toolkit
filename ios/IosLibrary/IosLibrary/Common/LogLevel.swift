//
//  LogLevel.swift
//  IosLibrary
//

import os
import Synchronization

extension OSLogType {
    /// The level of the library's routine messages (the first line of every function): `.debug`.
    ///
    /// The library writes `logger.log(level: .libraryDebug, "...")` instead of `logger.debug`
    /// so that, in Debug builds only, the log test (UT-15) can raise these messages to `.info`
    /// while it runs: `OSLogStore` does not return `.debug` entries (MS-13), and the test reads
    /// the messages back to check that no secret value is in them. Release builds always use
    /// `.debug`, which the system does not keep.
    static var libraryDebug: OSLogType {
        #if DEBUG
        LibraryLogLevel.raisesDebugToInfo.load(ordering: .relaxed) ? .info : .debug
        #else
        .debug
        #endif
    }
}

#if DEBUG
/// The switch behind ``OSLogType/libraryDebug``. Debug builds only; set by the tests.
enum LibraryLogLevel {
    static let raisesDebugToInfo = Atomic<Bool>(false)
}
#endif
