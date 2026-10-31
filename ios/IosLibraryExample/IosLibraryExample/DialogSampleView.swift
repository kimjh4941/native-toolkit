import IosLibrary
import os
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "DialogSampleView")

/// Single source of truth for the accessibility identifiers exposed by `DialogSampleView`.
///
/// A button's `<name>` is the lowerCamelCase of its title.
enum DialogSampleIdentifiers {

    static let result = "dialog.result"

    static func button(_ name: String) -> String { "dialog.button.\(name)" }

    enum ButtonName {
        static let showAlert = "showAlert"
        static let showConfirmDialog = "showConfirmDialog"
        static let showDestructiveDialog = "showDestructiveDialog"
        static let showActionSheet = "showActionSheet"
        static let showTextInputDialog = "showTextInputDialog"
        static let showLoginDialog = "showLoginDialog"
        // Swift API (2.0.0): `show(_:presenter:requestBox:completion:)` and its async form.
        static let showRequestAlert = "showRequestAlert"
        static let showRequestConfirm = "showRequestConfirm"
        static let showRequestDestructive = "showRequestDestructive"
        static let showRequestActionSheet = "showRequestActionSheet"
        static let showRequestTextInput = "showRequestTextInput"
        static let showRequestLogin = "showRequestLogin"
        static let showTwoInOneTurn = "showTwoInOneTurn"
        static let showThenCancel = "showThenCancel"
        static let showCoverThenCancel = "showCoverThenCancel"
        static let showThenDismissFromOutside = "showThenDismissFromOutside"
        static let showAfter3Seconds = "showAfter3Seconds"
    }

    /// The screen that `showCoverThenCancel` presents over its dialog.
    static let cover = "dialog.cover"
}

/// The screen presented over a dialog by `ShowCoverThenCancel`: a plain view with a label.
final class DialogCoverViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("[DialogCoverViewController.viewDidLoad]")
        view.backgroundColor = .systemYellow
        view.accessibilityIdentifier = DialogSampleIdentifiers.cover
        let label = UILabel()
        label.text = "Cover"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

/// What the sample saw at the moment it cancelled or dismissed a dialog of the Swift API section,
/// added to that request's result line (`shown=true`, `covered=true`). A UI test then reads it
/// from the result line instead of having to find the dialog before the timer ends it.
@MainActor
final class DialogMoment {
    var note = ""
}

struct DialogSampleView: View {

    private typealias ID = DialogSampleIdentifiers

    /// Which kind of report updated the result line.
    private enum ResultKind {
        /// The `completion` of the show call (the dialog was presented, or failed to be).
        case completion
        /// A button callback (`onButton`, `onConfirm`, `onCancel`, ...).
        case callback
    }

    @State private var resultText = "Result will be displayed here"
    /// Number of result updates per kind, exposed as the result line's `accessibilityValue` so a
    /// UI test can tell a new result from an identical old one and count each kind exactly.
    @State private var completionCount = 0
    @State private var callbackCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("IosDialogManager Example")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()

                Text(resultText)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(ID.result)
                    .accessibilityValue("completion=\(completionCount),callback=\(callbackCount)")

                // ShowAlert
                Button(action: {
                    IosDialogManager.shared.showAlert(
                        title: "Hello from iOS",
                        message: "This is a native iOS dialog!",
                        buttonText: "OK",
                        onButton: { buttonText, isSuccess, errorMessage in
                            logger.debug("[showAlert][onButton] buttonText: \(buttonText ?? "nil", privacy: .private), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .callback, isSuccess: isSuccess, result: "[showAlert][onButton] buttonText: " + (buttonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            logger.debug("[showAlert][completion] isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .completion, isSuccess: isSuccess, result: "[showAlert][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowAlert")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showAlert))

                // ShowConfirmDialog
                Button(action: {
                    IosDialogManager.shared.showConfirmDialog(
                        title: "Confirm Action",
                        message: "Are you sure you want to proceed?",
                        confirmTitle: "Yes",
                        cancelTitle: "No",
                        onConfirm: { confirmButtonText, isSuccess, errorMessage in
                            logger.debug("[showConfirmDialog][onConfirm] confirmButtonText: \(confirmButtonText ?? "nil", privacy: .private), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .callback, isSuccess: isSuccess, result: "[showConfirmDialog][onConfirm] confirmButtonText: " + (confirmButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { cancelButtonText, isSuccess, errorMessage in
                            logger.debug("[showConfirmDialog][onCancel] cancelButtonText: \(cancelButtonText ?? "nil", privacy: .private), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .callback, isSuccess: isSuccess, result: "[showConfirmDialog][onCancel] cancelButtonText: " + (cancelButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            logger.debug("[showConfirmDialog][completion] isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .completion, isSuccess: isSuccess, result: "[showConfirmDialog][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowConfirmDialog")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showConfirmDialog))

                // ShowDestructiveDialog
                Button(action: {
                    IosDialogManager.shared.showDestructiveDialog(
                        title: "Delete File",
                        message: "This action cannot be undone. Are you sure?",
                        destructiveTitle: "Delete",
                        cancelTitle: "Cancel",
                        onDestructive: { destructiveButtonText, isSuccess, errorMessage in
                            logger.debug("[showDestructiveDialog][onDestructive] destructiveButtonText: \(destructiveButtonText ?? "nil", privacy: .private), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .callback, isSuccess: isSuccess, result: "[showDestructiveDialog][onDestructive] destructiveButtonText: " + (destructiveButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { cancelButtonText, isSuccess, errorMessage in
                            logger.debug("[showDestructiveDialog][onCancel] cancelButtonText: \(cancelButtonText ?? "nil", privacy: .private), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .callback, isSuccess: isSuccess, result: "[showDestructiveDialog][onCancel] cancelButtonText: " + (cancelButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            logger.debug("[showDestructiveDialog][completion] isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .completion, isSuccess: isSuccess, result: "[showDestructiveDialog][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowDestructiveDialog")
                        .buttonStyle(backgroundColor: .red)
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showDestructiveDialog))

                // ShowActionSheet
                Button(action: {
                    if let rootVC = IosDialogManager.shared.getRootViewController() {
                        IosDialogManager.shared.showActionSheet(
                            title: "Please select",
                            message: "Please choose an option",
                            options: ["Camera", "Photo Library", "Documents"],
                            cancelTitle: "Cancel",
                            sourceView: rootVC.view,
                            // A point at the centre: with the whole view as the anchor (nil), the
                            // iPad popover had no room and showed no options (1b D23).
                            sourceRect: CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0),
                            animated: true,
                            onAction: { action, isSuccess, errorMessage in
                                logger.debug("[showActionSheet][onAction] action: \(action ?? "nil", privacy: .private), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                                updateResult(kind: .callback, isSuccess: isSuccess, result: "[showActionSheet][onAction] action: " + (action ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                            },
                            completion: { isSuccess, errorMessage in
                                logger.debug("[showActionSheet][completion] isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                                updateResult(kind: .completion, isSuccess: isSuccess, result: "[showActionSheet][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                            }
                        )
                    }
                }) {
                    Text("ShowActionSheet")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showActionSheet))

                // ShowTextInputDialog
                Button(action: {
                    IosDialogManager.shared.showTextInputDialog(
                        title: "Enter Name",
                        message: "Please enter your name",
                        placeholder: "Your name here",
                        confirmTitle: "OK",
                        cancelTitle: "Cancel",
                        enableConfirmWhenEmpty: false,
                        onConfirm: { confirmButtonText, inputText, isSuccess, errorMessage in
                            logger.debug("[showTextInputDialog][onConfirm] confirmButtonText: \(confirmButtonText ?? "nil", privacy: .private), inputTextLength: \(inputText?.utf8.count ?? 0, privacy: .public), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .callback, isSuccess: isSuccess, result: "[showTextInputDialog][onConfirm] confirmButtonText: " + (confirmButtonText ?? "nil") + ", inputText: " + (inputText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { cancelButtonText, isSuccess, errorMessage in
                            logger.debug("[showTextInputDialog][onCancel] cancelButtonText: \(cancelButtonText ?? "nil", privacy: .private), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .callback, isSuccess: isSuccess, result: "[showTextInputDialog][onCancel] cancelButtonText: " + (cancelButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            logger.debug("[showTextInputDialog][completion] isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .completion, isSuccess: isSuccess, result: "[showTextInputDialog][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowTextInputDialog")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showTextInputDialog))

                // ShowLoginDialog
                Button(action: {
                    IosDialogManager.shared.showLoginDialog(
                        title: "Login Required",
                        message: "Please enter your credentials",
                        usernamePlaceholder: "Username",
                        passwordPlaceholder: "Password",
                        loginTitle: "Login",
                        cancelTitle: "Cancel",
                        enableLoginWhenEmpty: false,
                        onLogin: { loginButtonText, username, password, isSuccess, errorMessage in
                            logger.debug("[showLoginDialog][onLogin] loginButtonText: \(loginButtonText ?? "nil", privacy: .private), usernameLength: \(username?.utf8.count ?? 0, privacy: .public), passwordLength: \(password?.utf8.count ?? 0, privacy: .public), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .callback, isSuccess: isSuccess, result: "[showLoginDialog][onLogin] loginButtonText: " + (loginButtonText ?? "nil") + ", username: " + (username ?? "nil") + ", password: " + (password.map { "<length=\($0.utf8.count)>" } ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { cancelButtonText, isSuccess, errorMessage in
                            logger.debug("[showLoginDialog][onCancel] cancelButtonText: \(cancelButtonText ?? "nil", privacy: .private), isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .callback, isSuccess: isSuccess, result: "[showLoginDialog][onCancel] cancelButtonText: " + (cancelButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            logger.debug("[showLoginDialog][completion] isSuccess: \(isSuccess, privacy: .public), errorMessage: \(errorMessage ?? "nil", privacy: .private)")
                            updateResult(kind: .completion, isSuccess: isSuccess, result: "[showLoginDialog][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowLoginDialog")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showLoginDialog))

                // MARK: Swift API (2.0.0)

                Text("Swift API (2.0.0)")
                    .font(.headline)

                requestButton("ShowRequestAlert", ID.ButtonName.showRequestAlert,
                              .alert(title: "Request Alert", message: "Shown by show(_:presenter:)"))
                requestButton("ShowRequestConfirm", ID.ButtonName.showRequestConfirm,
                              .confirm(title: "Request Confirm", message: "Proceed?", confirmTitle: "Yes", cancelTitle: "No"))
                requestButton("ShowRequestDestructive", ID.ButtonName.showRequestDestructive,
                              .destructive(title: "Request Delete", message: "This cannot be undone."))
                requestButton("ShowRequestActionSheet", ID.ButtonName.showRequestActionSheet,
                              .actionSheet(title: "Request Sheet", message: "Choose a color", options: ["Red", "Green", "Blue"]))
                requestButton("ShowRequestTextInput", ID.ButtonName.showRequestTextInput,
                              .textInput(title: "Request Name", message: "Enter your name", placeholder: "Your name here",
                                         enableConfirmWhenEmpty: false))
                requestButton("ShowRequestLogin", ID.ButtonName.showRequestLogin,
                              .login(title: "Request Login", message: "Enter your credentials", enableLoginWhenEmpty: false))

                // Two requests in the same turn of the main queue (P1-12): the second waits for the
                // first's presentation and is shown over it.
                Button(action: {
                    logger.debug("[showTwoInOneTurn]")
                    for (title, button) in [("First", "First OK"), ("Second", "Second OK")] {
                        IosDialogManager.shared.show(.alert(title: title, message: nil, buttonTitle: button),
                                                     presenter: .foreground) { result in
                            report("alert", result)
                        }
                    }
                }) {
                    Text("ShowTwoInOneTurn").buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showTwoInOneTurn))

                // Cancelled 3 seconds after the tap (P1-24). The result line says whether the dialog
                // was shown when it was cancelled (`shown=true`).
                Button(action: {
                    logger.debug("[showThenCancel]")
                    let moment = DialogMoment()
                    let box = IosDialogManager.shared.show(.alert(title: "Cancel Me", message: "Cancelled after 3 seconds"),
                                                           presenter: .foreground) { result in
                        report("alert", result, note: moment.note)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        moment.note = "shown=\(Self.isDialogShown())"
                        IosDialogManager.shared.cancel(box)
                    }
                }) {
                    Text("ShowThenCancel").buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showThenCancel))

                // Shown, covered by another screen after 1 second, cancelled after 2 seconds; the
                // cover closes itself 3 seconds later (P1-24: a covered dialog stays). The result
                // line says whether the cover was over the dialog when it was cancelled
                // (`covered=true`).
                Button(action: {
                    logger.debug("[showCoverThenCancel]")
                    let moment = DialogMoment()
                    let box = IosDialogManager.shared.show(.confirm(title: "Covered", message: "Covered, then cancelled",
                                                                    confirmTitle: "Yes", cancelTitle: "No"),
                                                           presenter: .foreground) { result in
                        report("confirm", result, note: moment.note)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        let cover = DialogCoverViewController()
                        IosDialogManager.shared.foregroundViewController()?.present(cover, animated: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            let covered = cover.presentingViewController is UIAlertController
                                && IosDialogManager.shared.foregroundViewController() === cover
                            moment.note = "covered=\(covered)"
                            IosDialogManager.shared.cancel(box)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                cover.presentingViewController?.dismiss(animated: true)
                            }
                        }
                    }
                }) {
                    Text("ShowCoverThenCancel").buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showCoverThenCancel))

                // Dismissed by the sample from outside the library 3 seconds after the tap (the
                // release watch: dismissedBySystem). The result line says whether the dialog was
                // shown when it was dismissed (`shown=true`).
                Button(action: {
                    logger.debug("[showThenDismissFromOutside]")
                    let moment = DialogMoment()
                    IosDialogManager.shared.show(.alert(title: "Dismissed From Outside", message: "Dismissed after 3 seconds"),
                                                 presenter: .foreground) { result in
                        report("alert", result, note: moment.note)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        moment.note = "shown=\(Self.isDialogShown())"
                        let top = IosDialogManager.shared.foregroundViewController()
                        top?.presentingViewController?.dismiss(animated: true)
                    }
                }) {
                    Text("ShowThenDismissFromOutside").buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showThenDismissFromOutside))

                #if DEBUG
                // Test only: shown 3 seconds later, so that a UI test can move the app to the
                // background (notForeground) or pull Control Center over it (foregroundInactive).
                Button(action: {
                    logger.debug("[showAfter3Seconds]")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        // The scene's state when the request is made, in the result line, so that the
                        // UI test can tell that it reached the state it wanted (MS-02).
                        let state = Self.sceneState()
                        IosDialogManager.shared.show(.alert(title: "Delayed", message: "Shown 3 seconds later"),
                                                     presenter: .foreground) { result in
                            report("alert@\(state)", result)
                        }
                    }
                }) {
                    Text("ShowAfter3Seconds").buttonStyle()
                }
                .accessibilityIdentifier(ID.button(ID.ButtonName.showAfter3Seconds))
                #endif

                Spacer()
            }
            .padding()
        }
    }

    /// A button of the Swift API section that shows `request` with the `async` form.
    private func requestButton(_ title: String, _ name: String, _ request: DialogRequest) -> some View {
        Button(action: {
            logger.debug("[\(name, privacy: .public)]")
            let kind = Self.kind(of: request)
            Task {
                do {
                    let answer = try await IosDialogManager.shared.show(request, presenter: .foreground)
                    report(kind, .success(answer))
                } catch let error as DialogError {
                    report(kind, .failure(error))
                } catch {
                    updateResult(kind: .callback, isSuccess: false, result: "[show.\(kind)] failure \(error)")
                }
            }
        }) {
            Text(title).buttonStyle()
        }
        .accessibilityIdentifier(ID.button(name))
    }

    /// Writes a result of the Swift API to the result line (counted as a callback):
    /// `[show.<kind>] success button=<button> title=<title> input=<lengths>` or
    /// `[show.<kind>] failure <case>`, followed by ` <note>` when `note` is not empty. The input
    /// shows only lengths (`DialogInput.description`).
    private func report(_ kind: String, _ result: Result<DialogAnswer, DialogError>, note: String = "") {
        let suffix = note.isEmpty ? "" : " \(note)"
        switch result {
        case .success(let answer):
            logger.debug("[show.\(kind, privacy: .public)] success button: \(Self.name(of: answer.button), privacy: .public), input: \(answer.input?.description ?? "nil", privacy: .public), note: \(note, privacy: .public)")
            updateResult(kind: .callback, isSuccess: true,
                         result: "[show.\(kind)] success button=\(Self.name(of: answer.button)) title=\(answer.title ?? "nil") input=\(answer.input?.description ?? "nil")\(suffix)")
        case .failure(let error):
            logger.debug("[show.\(kind, privacy: .public)] failure: \(String(describing: error), privacy: .public), note: \(note, privacy: .public)")
            updateResult(kind: .callback, isSuccess: false, result: "[show.\(kind)] failure \(error)\(suffix)")
        }
    }

    /// Whether the view controller in the foreground is an alert (a dialog of the library is shown).
    private static func isDialogShown() -> Bool {
        IosDialogManager.shared.foregroundViewController() is UIAlertController
    }

    /// The activation state of the sample's window scenes (`foregroundActive`, ...).
    private static func sceneState() -> String {
        let states = UIApplication.shared.connectedScenes.map { scene -> String in
            switch scene.activationState {
            case .foregroundActive: return "foregroundActive"
            case .foregroundInactive: return "foregroundInactive"
            case .background: return "background"
            case .unattached: return "unattached"
            @unknown default: return "unknown"
            }
        }
        return states.sorted().joined(separator: ",")
    }

    private static func kind(of request: DialogRequest) -> String {
        switch request {
        case .alert: return "alert"
        case .confirm: return "confirm"
        case .destructive: return "destructive"
        case .actionSheet: return "actionSheet"
        case .textInput: return "textInput"
        case .login: return "login"
        @unknown default: return "unknown"
        }
    }

    private static func name(of button: DialogAnswer.Button) -> String {
        switch button {
        case .primary: return "primary"
        case .cancel: return "cancel"
        case .destructive: return "destructive"
        case .option(let index): return "option(\(index))"
        @unknown default: return "unknown"
        }
    }

    private func updateResult(kind: ResultKind, isSuccess: Bool, result: String?) {
        DispatchQueue.main.async {
            switch kind {
            case .completion:
                completionCount += 1
            case .callback:
                callbackCount += 1
            }
            if isSuccess {
                resultText = "✅ \nResult: \(result ?? "nil")"
            } else {
                resultText = "❌ \nResult: \(result ?? "nil")"
            }
        }
    }
}

#Preview {
    DialogSampleView()
}
