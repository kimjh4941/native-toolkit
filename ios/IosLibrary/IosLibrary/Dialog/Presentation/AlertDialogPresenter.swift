//
//  AlertDialogPresenter.swift
//  IosLibrary
//

import Foundation
import os
import UIKit

private let presenterLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "AlertDialogPresenter")
private let sessionLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "DialogSession")

/// What one `UIAlertController` looks like: built from a ``DialogRequest`` or from the arguments
/// of one of the dialog manager's `show...` methods.
@MainActor
struct AlertSpec {
    /// A button that closes the request with a ``DialogAnswer``.
    struct Button {
        let title: String?
        let style: UIAlertAction.Style
        let role: DialogAnswer.Button
    }

    /// A text field.
    struct Field {
        let placeholder: String?
        let isSecure: Bool
        let contentType: UITextContentType?
    }

    /// The buttons: the library's own (each answers the request), or the caller's
    /// `UIAlertAction`s as they are (`showDialog(...)`, which has no answer).
    enum Buttons {
        case library([Button])
        case custom([UIAlertAction])
    }

    /// The text fields: the library's own, or the caller's configuration closures.
    enum Fields {
        case library([Field])
        case custom([@MainActor @Sendable (UITextField) -> Void])
    }

    /// What the ``DialogAnswer/Button/primary`` button reports as input.
    enum Input {
        case none
        case text
        case login
    }

    /// The popover anchor the caller chose (`showDialog(...)`, `showActionSheet(...)`). Without
    /// one, the presentation procedure anchors an action sheet at the centre of the presenting
    /// view (P1-13).
    struct Anchor {
        var sourceView: UIView?
        var sourceRect: CGRect?
        var barButtonItem: UIBarButtonItem?
        var permittedArrowDirections: UIPopoverArrowDirection
    }

    var title: String?
    var message: String?
    var style: UIAlertController.Style
    var buttons: Buttons
    var fields: Fields
    var input: Input = .none
    /// When `true`, the ``DialogAnswer/Button/primary`` button is disabled until every field has text.
    var requiresInput = false
    var anchor: Anchor?
    var animated = true

    /// The spec of a request of the new API.
    init(request: DialogRequest) {
        switch request {
        case let .alert(title, message, buttonTitle):
            self.init(title: title, message: message, style: .alert,
                      buttons: .library([Button(title: buttonTitle, style: .default, role: .primary)]),
                      fields: .library([]))
        case let .confirm(title, message, confirmTitle, cancelTitle):
            self.init(title: title, message: message, style: .alert,
                      buttons: .library([Button(title: confirmTitle, style: .default, role: .primary),
                                         Button(title: cancelTitle, style: .cancel, role: .cancel)]),
                      fields: .library([]))
        case let .destructive(title, message, destructiveTitle, cancelTitle):
            self.init(title: title, message: message, style: .alert,
                      buttons: .library([Button(title: destructiveTitle, style: .destructive, role: .destructive),
                                         Button(title: cancelTitle, style: .cancel, role: .cancel)]),
                      fields: .library([]))
        case let .actionSheet(title, message, options, cancelTitle):
            let optionButtons = options.enumerated().map { Button(title: $0.element, style: .default, role: .option(index: $0.offset)) }
            self.init(title: title, message: message, style: .actionSheet,
                      buttons: .library(optionButtons + [Button(title: cancelTitle, style: .cancel, role: .cancel)]),
                      fields: .library([]))
        case let .textInput(title, message, placeholder, confirmTitle, cancelTitle, enableConfirmWhenEmpty):
            self.init(title: title, message: message, style: .alert,
                      buttons: .library([Button(title: confirmTitle, style: .default, role: .primary),
                                         Button(title: cancelTitle, style: .cancel, role: .cancel)]),
                      fields: .library([Field(placeholder: placeholder, isSecure: false, contentType: nil)]),
                      input: .text, requiresInput: !enableConfirmWhenEmpty)
        case let .login(title, message, usernamePlaceholder, passwordPlaceholder, loginTitle, cancelTitle, enableLoginWhenEmpty):
            self.init(title: title, message: message, style: .alert,
                      buttons: .library([Button(title: loginTitle, style: .default, role: .primary),
                                         Button(title: cancelTitle, style: .cancel, role: .cancel)]),
                      fields: .library([Field(placeholder: usernamePlaceholder, isSecure: false, contentType: .username),
                                        Field(placeholder: passwordPlaceholder, isSecure: true, contentType: .password)]),
                      input: .login, requiresInput: !enableLoginWhenEmpty)
        }
    }

    init(title: String?, message: String?, style: UIAlertController.Style, buttons: Buttons, fields: Fields,
         input: Input = .none, requiresInput: Bool = false, anchor: Anchor? = nil, animated: Bool = true) {
        self.title = title
        self.message = message
        self.style = style
        self.buttons = buttons
        self.fields = fields
        self.input = input
        self.requiresInput = requiresInput
        self.anchor = anchor
        self.animated = animated
    }

    /// Everything but the texts, for the log (`.public`): the style, the number of buttons and
    /// fields, the input, whether input is required, the anchor and `animated`. The texts (title,
    /// message, button titles, placeholders) are user values and are left out.
    var logSummary: String {
        let buttonSummary: String
        switch buttons {
        case .library(let list): buttonSummary = "library(\(list.count))"
        case .custom(let list): buttonSummary = "custom(\(list.count))"
        }
        let fieldSummary: String
        switch fields {
        case .library(let list): fieldSummary = "library(\(list.count))"
        case .custom(let list): fieldSummary = "custom(\(list.count))"
        }
        let anchorSummary = anchor.map { anchor in
            "sourceView: \(anchor.sourceView != nil ? "provided" : "nil"), sourceRect: \(anchor.sourceRect != nil ? "provided" : "nil"), "
                + "barButtonItem: \(anchor.barButtonItem != nil ? "provided" : "nil"), "
                + "permittedArrowDirections: \(anchor.permittedArrowDirections.rawValue)"
        } ?? "nil"
        return "style: \(String(describing: style)), buttons: \(buttonSummary), fields: \(fieldSummary), input: \(input), "
            + "requiresInput: \(requiresInput), anchor: \(anchorSummary), animated: \(animated)"
    }
}

/// How a request of one of the dialog manager's `show...` methods went, for its callbacks.
enum LegacyDialogEvent {
    /// `present`'s completion came: `completion(true, nil)`.
    case presented
    /// The dialog could not be presented: `completion(false, <message>)`.
    case failed(DialogError)
    /// A button was pressed: the button callback.
    case answered(DialogAnswer)
}

/// The presentation core of the dialog manager: the ``DialogPresenting`` port of the new API, and
/// the entry of the `show...` methods that came before it (S-P5).
protocol DialogPresentationCore: DialogPresenting {
    /// Presents `spec` from the current search (`.firstActiveScene`), as the `show...` methods
    /// always did, and reports the events of the request to `report` (main thread, after the
    /// call). A dialog dismissed from outside reports nothing (its methods have no such result).
    @MainActor
    func presentLegacy(_ spec: AlertSpec, report: @escaping @MainActor @Sendable (LegacyDialogEvent) -> Void)
}

/// The state of one presented dialog: the weakly held alert, the text-field observers and the
/// cancellation that waits for `present`'s completion.
///
/// Nothing here holds the alert strongly, and the alert's handlers and observers capture it
/// weakly, so the alert is freed once UIKit lets it go (README 1.4: the retain cycle and the
/// observers that were never removed).
@MainActor
final class DialogSession {
    let box: RequestBox
    weak var alert: UIAlertController?
    /// The handler of each library button, in the order of the spec's buttons. The same closures
    /// are the `UIAlertAction` handlers; the unit tests call them in place of a tap.
    private(set) var actionHandlers: [@MainActor (UIAlertAction) -> Void] = []
    private(set) var actions: [UIAlertAction] = []
    private(set) var observers: [any NSObjectProtocol] = []
    /// Whether `present`'s completion came.
    private(set) var isPresented = false
    /// A cancellation that came while the dialog was being presented: dismiss in `present`'s
    /// completion (part 1, 5.13.1, R4-2).
    private var dismissWhenPresented = false
    /// Whether the session ended (the box closed and the observers were removed).
    private(set) var isFinished = false

    init(box: RequestBox) {
        sessionLogger.log(level: .libraryDebug, "[init]")
        self.box = box
    }

    func addAction(_ action: UIAlertAction, handler: @escaping @MainActor (UIAlertAction) -> Void) {
        sessionLogger.log(level: .libraryDebug, "[addAction] count: \(self.actions.count, privacy: .public)")
        actions.append(action)
        actionHandlers.append(handler)
    }

    func addObserver(_ token: any NSObjectProtocol) {
        sessionLogger.log(level: .libraryDebug, "[addObserver] count: \(self.observers.count, privacy: .public)")
        if isFinished {
            // The box closed while the alert was being built: never keep an observer.
            NotificationCenter.default.removeObserver(token)
            return
        }
        observers.append(token)
    }

    /// `present`'s completion came.
    func didPresent() {
        sessionLogger.log(level: .libraryDebug, "[didPresent] dismissWhenPresented: \(self.dismissWhenPresented, privacy: .public)")
        isPresented = true
        if dismissWhenPresented {
            dismissWhenPresented = false
            dismissForCancellation()
        }
    }

    /// The box closed: remove the observers, and close the dialog when the request was cancelled.
    func finish(_ outcome: RequestBoxOutcome) {
        sessionLogger.log(level: .libraryDebug, "[finish] outcome: \(outcome.logName, privacy: .public), observers: \(self.observers.count, privacy: .public)")
        isFinished = true
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers = []
        if case .canceled = outcome {
            dismissForCancellation()
        }
    }

    /// Closes the dialog for `cancel(_:)`, unless another view controller is presented over it
    /// (then it stays, and its buttons hit the closed box: P1-24).
    private func dismissForCancellation() {
        sessionLogger.log(level: .libraryDebug, "[dismissForCancellation] isPresented: \(self.isPresented, privacy: .public)")
        guard let alert else {
            sessionLogger.log(level: .libraryDebug, "[dismissForCancellation] the dialog is already gone")
            return
        }
        guard isPresented else {
            // Being presented (or not yet): wait for present's completion. MS-01 saw iOS 26.2 and
            // 18.3 take a dismiss during the presentation and close after it, but R4-2 expects
            // UIKit versions that ignore it; waiting gives the same result on both.
            dismissWhenPresented = true
            return
        }
        guard alert.presentingViewController != nil, !alert.isBeingDismissed else {
            sessionLogger.log(level: .libraryDebug, "[dismissForCancellation] the dialog is not presented any more")
            return
        }
        guard alert.presentedViewController == nil else {
            sessionLogger.info("[dismissForCancellation] another view controller is presented over the dialog; it stays")
            return
        }
        alert.dismiss(animated: true)
    }
}

/// Presents dialogs as `UIAlertController`s through ``PresentationProcedure`` (the ``DialogPresenting``
/// port of the library, and the core of the dialog manager's `show...` methods).
///
/// Every request gets its own alert and its own ``DialogSession``. The request ends when its box
/// closes: a button, `cancel(_:)`, a failure of the presentation procedure, or the release watch.
struct AlertDialogPresenter<Environment: PresentationEnvironment>: DialogPresentationCore where Environment.Node == UIViewController {
    private let makeEnvironment: @MainActor @Sendable () -> Environment
    /// Sees each session once its alert is built (unit tests only).
    private let observeSession: (@MainActor @Sendable (DialogSession) -> Void)?

    init(makeEnvironment: @escaping @MainActor @Sendable () -> Environment,
         observeSession: (@MainActor @Sendable (DialogSession) -> Void)? = nil) {
        presenterLogger.log(level: .libraryDebug, "[init] observeSession: \(observeSession != nil ? "provided" : "nil", privacy: .public)")
        self.makeEnvironment = makeEnvironment
        self.observeSession = observeSession
    }

    func present(_ request: DialogRequest, presenter: PresenterSelection, box: RequestBox,
                 completion: @escaping @MainActor @Sendable (Result<DialogAnswer, DialogError>) -> Void) {
        presenterLogger.log(level: .libraryDebug, "[present] request: \(request.kindName, privacy: .public), title: \(request.logTitle ?? "nil", privacy: .private), message: \(request.logMessage ?? "nil", privacy: .private), presenter: \(presenter.logName, privacy: .public), box closed: \(box.isClosed, privacy: .public), completion: provided")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.run(AlertSpec(request: request), presenter: presenter, box: box, onInvalid: {
                    completion(.failure(.invalidRequest))
                }, onPresented: {}, deliver: { outcome in
                    completion(Self.result(of: outcome))
                })
            }
        }
    }

    @MainActor
    func presentLegacy(_ spec: AlertSpec, report: @escaping @MainActor @Sendable (LegacyDialogEvent) -> Void) {
        presenterLogger.log(level: .libraryDebug, "[presentLegacy] title: \(spec.title ?? "nil", privacy: .private), message: \(spec.message ?? "nil", privacy: .private), \(spec.logSummary, privacy: .public), report: provided")
        let box = RequestBox()
        run(spec, presenter: .firstActiveScene, box: box, onInvalid: {
            // A new box is never attached elsewhere.
            presenterLogger.fault("[presentLegacy] a new box was already attached")
        }, onPresented: {
            switch box.outcome {
            case .notForeground?, .presentationFailed?:
                // The supplement already failed the request (UIKit declined it).
                presenterLogger.error("[presentLegacy] present's completion came after the request failed")
            default:
                report(.presented)
            }
        }, deliver: { outcome in
            switch outcome {
            case .completed(let value):
                if let answer = value as? DialogAnswer {
                    report(.answered(answer))
                }
            case .notForeground:
                report(.failed(.notForeground))
            case .presentationFailed:
                report(.failed(.presentationFailed))
            case .canceled, .dismissedBySystem:
                // No result of the `show...` methods stands for these (S-P5).
                presenterLogger.log(level: .libraryDebug, "[presentLegacy] ended without an answer: \(outcome.logName, privacy: .public)")
            }
        })
    }

    /// The box's outcome as the result of the new API.
    static func result(of outcome: RequestBoxOutcome) -> Result<DialogAnswer, DialogError> {
        presenterLogger.log(level: .libraryDebug, "[result] outcome: \(outcome.logName, privacy: .public)")
        switch outcome {
        case .completed(let value):
            guard let answer = value as? DialogAnswer else {
                presenterLogger.fault("[result] the box was completed with another type")
                return .failure(.presentationFailed)
            }
            return .success(answer)
        case .canceled: return .failure(.canceled)
        case .notForeground: return .failure(.notForeground)
        case .presentationFailed: return .failure(.presentationFailed)
        case .dismissedBySystem: return .failure(.dismissedBySystem)
        }
    }

    /// Ties the request to `box`, builds the alert and presents it.
    @MainActor
    private func run(_ spec: AlertSpec, presenter: PresenterSelection, box: RequestBox,
                     onInvalid: @MainActor () -> Void,
                     onPresented: @escaping @MainActor () -> Void,
                     deliver: @escaping @MainActor @Sendable (RequestBoxOutcome) -> Void) {
        presenterLogger.log(level: .libraryDebug, "[run] presenter: \(presenter.logName, privacy: .public), box closed: \(box.isClosed, privacy: .public)")
        let session = DialogSession(box: box)
        // The close handler holds the session (never the alert), so the alert, its release
        // watch and the box do not keep one another alive.
        let attached = box.attach { outcome in
            presenterLogger.log(level: .libraryDebug, "[run] closed: \(outcome.logName, privacy: .public)")
            session.finish(outcome)
            deliver(outcome)
        }
        guard attached else {
            onInvalid()
            return
        }
        guard !box.isClosed else {
            // Cancelled before it started: the attach delivers the outcome; nothing is shown.
            presenterLogger.log(level: .libraryDebug, "[run] the box is already closed")
            return
        }
        let alert = Self.makeAlert(spec, session: session)
        session.alert = alert
        observeSession?(session)
        PresentationProcedure.present(alert, presenter: presenter, box: box, firstActiveScenePolicy: .presentAnyway,
                                      environment: makeEnvironment(), animated: spec.animated) {
            session.didPresent()
            onPresented()
        }
    }

    /// Builds the alert of `spec`. Handlers and observers capture the alert, its primary action
    /// and its fields weakly.
    @MainActor
    static func makeAlert(_ spec: AlertSpec, session: DialogSession) -> UIAlertController {
        presenterLogger.log(level: .libraryDebug, "[makeAlert] title: \(spec.title ?? "nil", privacy: .private), message: \(spec.message ?? "nil", privacy: .private), style: \(String(describing: spec.style), privacy: .public), requiresInput: \(spec.requiresInput, privacy: .public)")
        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: spec.style)
        let box = session.box
        var primary: UIAlertAction?

        switch spec.buttons {
        case .library(let buttons):
            for button in buttons {
                let role = button.role
                let title = button.title
                let input = role == .primary ? spec.input : .none
                let handler: @MainActor (UIAlertAction) -> Void = { [weak alert] _ in
                    let answer = DialogAnswer(button: role, title: title, input: Self.input(input, of: alert))
                    presenterLogger.log(level: .libraryDebug, "[button] button: \(role.logName, privacy: .public), input: \(answer.input?.description ?? "nil", privacy: .public)")
                    box.close(.completed(answer))
                }
                let action = UIAlertAction(title: title, style: button.style, handler: handler)
                if role == .primary {
                    primary = action
                }
                session.addAction(action, handler: handler)
                alert.addAction(action)
            }
        case .custom(let actions):
            for action in actions {
                alert.addAction(action)
            }
            if actions.isEmpty {
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            }
        }

        switch spec.fields {
        case .library(let fields):
            if spec.requiresInput {
                primary?.isEnabled = false
            }
            for field in fields {
                alert.addTextField { [weak alert, weak primary] textField in
                    textField.placeholder = field.placeholder
                    textField.isSecureTextEntry = field.isSecure
                    if let contentType = field.contentType {
                        textField.textContentType = contentType
                    }
                    guard spec.requiresInput else { return }
                    let token = NotificationCenter.default.addObserver(
                        forName: UITextField.textDidChangeNotification,
                        object: textField,
                        queue: .main
                    ) { [weak alert, weak primary] _ in
                        // `queue: .main`: the block runs on the main thread.
                        MainActor.assumeIsolated {
                            primary?.isEnabled = Self.everyFieldHasText(alert)
                        }
                    }
                    session.addObserver(token)
                }
            }
        case .custom(let configurations):
            if spec.style == .alert {
                for configuration in configurations {
                    alert.addTextField(configurationHandler: configuration)
                }
            }
        }

        if let anchor = spec.anchor, let popover = alert.popoverPresentationController {
            if let sourceView = anchor.sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = anchor.sourceRect ?? sourceView.bounds
            } else if let barButtonItem = anchor.barButtonItem {
                popover.barButtonItem = barButtonItem
            }
            // Without a source view or a bar button item, the procedure anchors at the centre of
            // the presenting view (as these methods always did).
            popover.permittedArrowDirections = anchor.permittedArrowDirections
        }
        return alert
    }

    /// What the primary button of `alert` reports.
    @MainActor
    private static func input(_ input: AlertSpec.Input, of alert: UIAlertController?) -> DialogInput? {
        let fields = alert?.textFields ?? []
        switch input {
        case .none:
            return nil
        case .text:
            return .text(fields.first?.text ?? "")
        case .login:
            return .login(username: fields.count > 0 ? fields[0].text ?? "" : "",
                          password: fields.count > 1 ? fields[1].text ?? "" : "")
        }
    }

    @MainActor
    private static func everyFieldHasText(_ alert: UIAlertController?) -> Bool {
        let fields = alert?.textFields ?? []
        return !fields.isEmpty && fields.allSatisfy { !($0.text?.isEmpty ?? true) }
    }
}
