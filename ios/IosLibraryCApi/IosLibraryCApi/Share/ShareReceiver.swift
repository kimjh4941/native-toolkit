//
//  ShareReceiver.swift
//  IosLibraryCApi
//

import IosLibrary

/// What the function of Share.h does (part 2, 5.1, 6.4): the entry's checks and copies in `ShareMapping`, the
/// accepted request to the main thread, the manager with `.foreground` (P2-1), the result handle and the completion.
enum ShareReceiver {
    /// The call that shows the sheet. Tests replace it, so that nothing is shown (part 2, 12.1).
    struct Sharing: Sendable {
        var share: @MainActor @Sendable (ShareContent, @escaping @MainActor @Sendable (Result<ShareResult, ShareError>) -> Void) -> Void

        static let library = Sharing { content, completion in
            IosShareManager.shared.share(content: content, presenter: .foreground, completion: completion)
        }
    }

    @MainActor static var sharing = Sharing.library

    private static let none = ntk_share_error(NTK_SHARE_ERROR_NONE)
    private static let systemCode: UInt32 = 0

    @MainActor
    static func finish(_ registration: Registration<ntk_share_result_fn>, _ result: Result<ShareResult, ShareError>) {
        CApiLog.share.debug("[finish] id: \(registration.id, privacy: .public)")
        switch result {
        case .success(let value):
            let mapped = ShareMapping.result(of: value)
            registration.complete { callback, userData, _ in callback(userData, none, systemCode, ShareHandles.makeResult(mapped)) }
        case .failure(let failure):
            let error = ShareMapping.error(for: failure)
            CApiLog.share.error("[finish] error: \(error, privacy: .public)")
            registration.complete { callback, userData, _ in callback(userData, error, systemCode, nil) }
        }
    }

    /// OP-46. It cannot be cancelled (P1-24): the registration has no request box.
    static func share(_ request: UnsafePointer<ntk_share_request>?, _ callback: ntk_share_result_fn?,
                      _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_share_error {
        CApiLog.share.debug("[share] request: \(request == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        guard let callback else {
            CApiLog.share.error("[share] the callback is NULL")
            return Entry.reject(.invalidParameter, userData: userData, release: release)
        }
        do throws(ShareRejection) {
            let content = try ShareMapping.content(request)
            return Registry.accept(callback: callback, userData: userData, release: release,
                                   canceled: { callback, userData, _ in callback(userData, ntk_share_error(NTK_SHARE_ERROR_UNKNOWN), systemCode, nil) },
                                   start: { registration in
                                       CApiLog.share.debug("[start] id: \(registration.id, privacy: .public)")
                                       sharing.share(content) { finish(registration, $0) }
                                   })
        } catch {
            return Entry.reject(error.value, userData: userData, release: release)
        }
    }
}
