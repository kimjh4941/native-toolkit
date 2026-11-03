//
//  ClipboardReceiver.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary

/// What the functions of Clipboard.h do. They come with TB-3 and TB-4; this is what the shared parts take
/// from Clipboard.
enum ClipboardReceiver {
    /// A load closes its box through the manager, from any thread (part 2, 5.3; OP-12, P2-12).
    static let loadCancelKind = CancellableKind(name: "clipboardLoad") { IosClipboardManager.cancelLoad($0) }

    /// The result of a `.file` load: `IosLibrary` gives away the file and its parent folder (part 2, 5.3).
    /// The path may name what the user copied, so it is not logged.
    @MainActor
    static func loadedFile(at url: URL) -> OwnedResult {
        CApiLog.clipboard.debug("[loadedFile] url: provided")
        return OwnedResult {
            do {
                try FileManager.default.removeItem(at: url.deletingLastPathComponent())
            } catch {
                let failure = error as NSError
                CApiLog.clipboard.error("[loadedFile] not deleted: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")
            }
        }
    }
}
