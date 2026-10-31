// Hand-off 1 probe: the host app of the unit and UI tests. With "-handoff-scenario <name>" it calls the
// C ABI at launch and lists every completion and release in a label that the UI tests read.
import IosLibraryCApi
import UIKit

enum HostLog {
    static weak var label: UILabel?
    static var lines: [String] = []

    static func add(_ line: String) {
        lines.append(line)
        label?.text = lines.joined(separator: " | ")
        print("HANDOFF \(line)")
    }
}

private func tag(_ userData: UnsafeMutableRawPointer?) -> Int { Int(bitPattern: userData) }

let hostDialogDone: ntk_probe_dialog_done_fn = { userData, requestId, error, _, button in
    HostLog.add("dialog tag=\(tag(userData)) id=\(requestId) error=\(error) button=\(button) main=\(Thread.isMainThread ? 1 : 0)")
}
let hostShareDone: ntk_probe_share_done_fn = { userData, error, _, completed, activity in
    ntk_string_free(activity)
    HostLog.add("share tag=\(tag(userData)) error=\(error) completed=\(completed) main=\(Thread.isMainThread ? 1 : 0)")
}
let hostRelease: ntk_release_fn = { userData in
    HostLog.add("release tag=\(tag(userData)) main=\(Thread.isMainThread ? 1 : 0)")
}

@main
final class TestHostAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.accessibilityIdentifier = "results"
        label.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: root.view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: root.view.layoutMarginsGuide.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.bottomAnchor),
        ])
        HostLog.label = label
        window?.rootViewController = root
        window?.makeKeyAndVisible()

        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-handoff-scenario"), index + 1 < arguments.count else { return true }
        let state = UIApplication.shared.connectedScenes.first.map { "\($0.activationState.rawValue)" } ?? "none"
        HostLog.add("launch scene state=\(state)")
        switch arguments[index + 1] {
        case "dialog":   // called inside didFinishLaunching (the scene is not active yet)
            let error = ntk_probe_dialog_show_alert("Handoff", "Pick one", "Yes", "No", hostDialogDone,
                                                    UnsafeMutableRawPointer(bitPattern: 1), hostRelease, nil)
            HostLog.add("show returned \(error)")
        case "two":      // two alerts in the same main turn (P1-12)
            for tagValue in 1...2 {
                let error = ntk_probe_dialog_show_alert("Handoff \(tagValue)", nil, "Yes \(tagValue)", nil, hostDialogDone,
                                                        UnsafeMutableRawPointer(bitPattern: tagValue), hostRelease, nil)
                HostLog.add("show \(tagValue) returned \(error)")
            }
        case "share":
            let error = ntk_probe_share_text("Handoff text", hostShareDone, UnsafeMutableRawPointer(bitPattern: 3), hostRelease)
            HostLog.add("share returned \(error)")
        default:
            break
        }
        return true
    }
}
