// Hand-off 1 probe: receivers of ProbeShare.h. Calls IosLibrary's public IosShareManager (P1-2).
import Foundation
import IosLibrary
import UIKit

final class ShareRegistration: Registration, @unchecked Sendable {
    let callback: ntk_probe_share_done_fn
    let text: String

    init(_ callback: @escaping ntk_probe_share_done_fn, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?, text: String) {
        self.callback = callback
        self.text = text
        super.init(id: Registry.nextId(), userData: userData, release: release)
    }

    @MainActor func finish(_ error: Int, completed: Bool = false, activityType: String? = nil) {
        Registry.complete(self) { _ in   // Share cannot be cancelled, so `canceled` is never true
            CApiLog.share.debug("completion id=\(self.id, privacy: .public) error=\(error, privacy: .public) completed=\(completed, privacy: .public)")
            callback(userData, ntk_probe_share_error(error), 0, completed ? 1 : 0, activityType.map(Handle.makeString))
        }
    }
}

enum ShareReceiver {
    private static func reject(_ error: Int, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_probe_share_error {
        CApiLog.share.debug("rejected error=\(error, privacy: .public)")
        release?(userData)
        return ntk_probe_share_error(error)
    }

    static func shareText(_ text: UnsafePointer<CChar>?, _ callback: ntk_probe_share_done_fn?,
                          _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_probe_share_error {
        CApiLog.share.debug("share_text text=\(text != nil, privacy: .public)")
        guard let callback else { return reject(NTK_PROBE_SHARE_ERROR_INVALID_PARAMETER, userData, release) }
        let value: String
        switch CApiString.input(text) {
        case .absent, .invalid: return reject(NTK_PROBE_SHARE_ERROR_INVALID_PARAMETER, userData, release)
        case .value(let string): value = string
        }
        guard !value.isEmpty else { return reject(NTK_PROBE_SHARE_ERROR_EMPTY_CONTENT, userData, release) }
        let registration = ShareRegistration(callback, userData, release, text: value)
        Registry.insert(registration)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard registration.currentState == .active else { return }
                // P1-11 foreground first; IosShareManager then finds its own (foregroundActive) root.
                guard ForegroundPresenter.topViewController() != nil else {
                    registration.finish(NTK_PROBE_SHARE_ERROR_NOT_FOREGROUND)
                    return
                }
                Task { @MainActor in
                    do {
                        let result = try await IosShareManager.shared.share(content: ShareContent(items: [.text(registration.text)]))
                        registration.finish(NTK_PROBE_SHARE_ERROR_NONE, completed: result.completed, activityType: result.activityType)
                    } catch let error as ShareError {
                        if case .noRootViewController = error {
                            registration.finish(NTK_PROBE_SHARE_ERROR_NOT_FOREGROUND)
                        } else {
                            CApiLog.share.error("IosShareManager failed: \(String(describing: error), privacy: .private)")
                            registration.finish(NTK_PROBE_SHARE_ERROR_UNKNOWN)
                        }
                    } catch {
                        registration.finish(NTK_PROBE_SHARE_ERROR_UNKNOWN)
                    }
                }
            }
        }
        return ntk_probe_share_error(NTK_PROBE_SHARE_ERROR_NONE)
    }
}
