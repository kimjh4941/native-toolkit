// Hand-off 1 probe: receivers of ProbeDialog.h. IosDialogManager cannot hand back the presented
// alert, take a presenter or be cancelled, so the alert is built here (1b requirement, see the hand-off).
import Foundation
import UIKit

enum DialogOutcome: Sendable { case button(Int32), notForeground, showFailed, canceled, canceledBySystem }

/// Main-only presentation state of one alert.
@MainActor final class AlertSession {
    weak var alert: UIAlertController?
    var presentFinished = false
    var dismissWhenPresented = false
}

final class DialogRegistration: Registration, @unchecked Sendable {
    let callback: ntk_probe_dialog_done_fn
    let title: String?
    let message: String?
    let positive: String
    let negative: String?
    /// Weak: the box is kept by the queued start block, then by the alert's actions and watch.
    weak var box: RequestBox<DialogOutcome>?
    /// Main only.
    nonisolated(unsafe) var session: AlertSession?

    init(_ callback: @escaping ntk_probe_dialog_done_fn, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
         title: String?, message: String?, positive: String, negative: String?) {
        self.callback = callback
        self.title = title
        self.message = message
        self.positive = positive
        self.negative = negative
        super.init(id: Registry.nextId(), userData: userData, release: release)
    }

    func deliver(_ outcome: DialogOutcome) {
        let (error, button): (Int, Int32) = switch outcome {
        case .button(let index): (NTK_PROBE_DIALOG_ERROR_NONE, index)
        case .notForeground: (NTK_PROBE_DIALOG_ERROR_NOT_FOREGROUND, -1)
        case .showFailed: (NTK_PROBE_DIALOG_ERROR_SHOW_FAILED, -1)
        case .canceled: (NTK_PROBE_DIALOG_ERROR_CANCELED, -1)
        case .canceledBySystem: (NTK_PROBE_DIALOG_ERROR_CANCELED_BY_SYSTEM, -1)
        }
        CApiLog.dialog.debug("completion id=\(self.id, privacy: .public) error=\(error, privacy: .public) button=\(button, privacy: .public)")
        callback(userData, id, ntk_probe_dialog_error(error), 0, button)
    }
}

enum DialogReceiver {
    private static func reject(_ error: Int, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_probe_dialog_error {
        CApiLog.dialog.debug("rejected error=\(error, privacy: .public)")
        release?(userData)
        return ntk_probe_dialog_error(error)
    }

    static func showAlert(_ title: UnsafePointer<CChar>?, _ message: UnsafePointer<CChar>?,
                          _ positiveText: UnsafePointer<CChar>?, _ negativeText: UnsafePointer<CChar>?,
                          _ callback: ntk_probe_dialog_done_fn?, _ userData: UnsafeMutableRawPointer?,
                          _ release: ntk_release_fn?, _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_dialog_error {
        CApiLog.dialog.debug("show_alert title=\(title != nil, privacy: .public) message=\(message != nil, privacy: .public) positive=\(positiveText != nil, privacy: .public) negative=\(negativeText != nil, privacy: .public)")
        guard let callback else { return reject(NTK_PROBE_DIALOG_ERROR_INVALID_PARAMETER, userData, release) }
        // Deep copies before anything is queued (5.7 step 3).
        var texts: [String?] = []
        for pointer in [title, message, positiveText, negativeText] {
            switch CApiString.input(pointer) {
            case .invalid: return reject(NTK_PROBE_DIALOG_ERROR_INVALID_PARAMETER, userData, release)
            case .absent: texts.append(nil)
            case .value(let value): texts.append(value)
            }
        }
        let registration = DialogRegistration(callback, userData, release, title: texts[0], message: texts[1],
                                              positive: texts[2] ?? "OK", negative: texts[3])
        let box = RequestBox<DialogOutcome> { outcome in
            MainActor.assumeIsolated {
                if case .canceled = outcome { closeAfterCancel(registration) }
                Registry.complete(registration) { canceled in registration.deliver(canceled ? .canceled : outcome) }
                registration.session = nil
            }
        }
        registration.box = box
        Registry.insert(registration)
        outRequestId?.pointee = registration.id
        DispatchQueue.main.async {
            MainActor.assumeIsolated { start(registration, box) }
        }
        return ntk_probe_dialog_error(NTK_PROBE_DIALOG_ERROR_NONE)
    }

    @MainActor private static func start(_ registration: DialogRegistration, _ box: RequestBox<DialogOutcome>) {
        guard registration.currentState == .active, !box.isClosed else { return }
        ForegroundPresenter.show(
            isOpen: { !box.isClosed },
            notForeground: { box.close(.notForeground) },
            failed: { box.close(.showFailed) },
            present: { top in present(registration, box, on: top) })
    }

    @MainActor private static func present(_ registration: DialogRegistration, _ box: RequestBox<DialogOutcome>, on top: UIViewController) {
        let alert = UIAlertController(title: registration.title, message: registration.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: registration.positive, style: .default) { _ in
            box.close(.button(Int32(NTK_PROBE_DIALOG_BUTTON_POSITIVE)))
        })
        if let negative = registration.negative {
            alert.addAction(UIAlertAction(title: negative, style: .cancel) { _ in
                box.close(.button(Int32(NTK_PROBE_DIALOG_BUTTON_NEGATIVE)))
            })
        }
        let watch = ReleaseWatch { presented in box.close(presented ? .canceledBySystem : .showFailed) }
        watch.attach(to: alert)
        let session = AlertSession()
        session.alert = alert
        registration.session = session
        ForegroundPresenter.anchorCenter(alert, on: top)
        top.present(alert, animated: true) {
            watch.presented.store(true, ordering: .releasing)
            session.presentFinished = true
            if session.dismissWhenPresented, alert.presentedViewController == nil { alert.dismiss(animated: true) }
        }
    }

    static func cancel(_ requestId: UInt64) -> ntk_probe_dialog_error {
        CApiLog.dialog.debug("cancel id=\(requestId, privacy: .public)")
        guard let registration = Registry.requestCancel(requestId, where: { $0 is DialogRegistration }) as? DialogRegistration else {
            return ntk_probe_dialog_error(NTK_PROBE_DIALOG_ERROR_NONE)
        }
        // Closing the box queues closeAfterCancel and the CANCELED completion on main (box onClose);
        // the "remove" row then only releases if the completion has not done it.
        registration.box?.close(.canceled)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { Registry.remove(registration) { registration.deliver(.canceled) } }
        }
        return ntk_probe_dialog_error(NTK_PROBE_DIALOG_ERROR_NONE)
    }

    /// Closes the alert unless something else is presented on top of it (P1-24). While the alert is
    /// still being presented, it is closed in the present completion. A view controller on top that is
    /// itself being dismissed (for example another cancelled alert) is not an overlay: the alert is
    /// closed after that transition, checked once more.
    @MainActor private static func closeAfterCancel(_ registration: DialogRegistration) {
        guard let session = registration.session, let alert = session.alert else { return }
        closeAlert(alert, session, retried: false)
    }

    @MainActor private static func closeAlert(_ alert: UIAlertController, _ session: AlertSession, retried: Bool) {
        guard session.presentFinished else { session.dismissWhenPresented = true; return }
        guard !alert.isBeingDismissed, alert.presentingViewController != nil else { return }
        guard let overlay = alert.presentedViewController else { alert.dismiss(animated: true); return }
        guard overlay.isBeingDismissed, !retried, let coordinator = overlay.transitionCoordinator else { return }
        coordinator.animate(alongsideTransition: nil) { _ in
            DispatchQueue.main.async { [weak alert] in
                MainActor.assumeIsolated { if let alert { closeAlert(alert, session, retried: true) } }
            }
        }
    }
}
