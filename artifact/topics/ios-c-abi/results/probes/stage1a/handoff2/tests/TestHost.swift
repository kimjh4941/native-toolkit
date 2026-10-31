// Hand-off 2 probe: the host app of the unit and UI tests. Without arguments it does nothing (unit
// tests). With "-handoff2" it plays a host app that uses the C ABI (like Unity's .mm plus C#):
//   -install will|did|none      call ntk_notification_install in willFinish / didFinish (default will)
//   -host none|forward|cyclic   the host's own UNUserNotificationCenter delegate (default none)
//   -listen-after <s>           register the C listener s seconds after launch (default 0; -1: never)
//   -schedule <id> <s> <title>  schedule a library notification through the C ABI
//   -schedule-host <id> <s> <title>  schedule a host notification (no library marker)
//   -arm-cold                   the next launch without arguments (a tap) replays "-handoff2"
// Every line goes to the "results" label (joined by " | ") and to the console as "HANDOFF2 ...".
import IosLibraryCApi
import UIKit
import UserNotifications

enum HostLog {
    static weak var label: UILabel?
    static var lines: [String] = []

    static func add(_ line: String) {
        lines.append(line)
        label?.text = lines.joined(separator: " | ")
        print("HANDOFF2 \(line)")
    }
}

private func take(_ handle: OpaquePointer?) -> String {
    guard let handle else { return "nil" }
    defer { ntk_string_free(handle) }
    return ntk_string_data(handle).map { String(cString: $0) } ?? "nil"
}

let hostEvent: ntk_probe_notification_event_fn = { _, kind, identifier, action, text, launch in
    HostLog.add("event kind=\(kind) id=\(take(identifier)) action=\(take(action)) text=\(take(text)) launch=\(launch) state=\(UIApplication.shared.applicationState.rawValue) main=\(Thread.isMainThread ? 1 : 0)")
}
let hostDone: ntk_probe_notification_done_fn = { userData, error, _, granted in
    HostLog.add("done tag=\(Int(bitPattern: userData)) error=\(error) granted=\(granted)")
}
let hostRelease: ntk_release_fn = { userData in HostLog.add("release tag=\(Int(bitPattern: userData))") }

/// The host's own delegate. `cyclic` forwards to the delegate it replaced (the library's proxy)
/// synchronously, which makes the cycle of part 1 5.12.5 when the library is installed again.
final class HostDelegate: NSObject, UNUserNotificationCenterDelegate {
    let mode: String
    weak var previous: (any UNUserNotificationCenterDelegate)?
    init(mode: String) { self.mode = mode }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        HostLog.add("host willPresent id=\(notification.request.identifier)")
        if mode == "cyclic", let previous {
            previous.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
        } else {
            completionHandler([.banner, .list])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        HostLog.add("host didReceive id=\(response.notification.request.identifier)")
        if mode == "cyclic", let previous {
            previous.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }
}

@main
final class TestHostAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var hostDelegate: HostDelegate?
    private var arguments: [String] = []

    private func value(_ name: String, _ fallback: String) -> String {
        guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return fallback }
        return arguments[i + 1]
    }

    private func install(_ point: String) {
        let error = ntk_notification_install()
        HostLog.add("install at=\(point) error=\(error) state=\(UIApplication.shared.applicationState.rawValue)")
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard
        if !arguments.contains("-handoff2"), let saved = defaults.stringArray(forKey: "handoff2.cold") {
            defaults.removeObject(forKey: "handoff2.cold")   // a launch from a notification tap
            arguments = saved
            HostLog.add("cold launch replaying \(saved.joined(separator: " "))")
        }
        guard arguments.contains("-handoff2") else { return true }
        if arguments.contains("-arm-cold") {
            var saved = Array(arguments.dropFirst()).filter { $0 != "-arm-cold" }
            for flag in ["-schedule", "-schedule-host"] {
                if let i = saved.firstIndex(of: flag) { saved.removeSubrange(i..<min(i + 4, saved.count)) }
            }
            defaults.set(saved, forKey: "handoff2.cold")
        }
        let host = value("-host", "none")
        if host == "forward" {
            hostDelegate = HostDelegate(mode: host)
            UNUserNotificationCenter.current().delegate = hostDelegate
        }
        if value("-install", "will") == "will" { install("will") }
        if host == "cyclic" {
            // The host replaces the library's delegate, keeps it as its previous one, and the library
            // is installed again: proxy -> host -> proxy.
            let delegate = HostDelegate(mode: host)
            delegate.previous = UNUserNotificationCenter.current().delegate
            hostDelegate = delegate
            UNUserNotificationCenter.current().delegate = delegate
            install("will-again")
        }
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        label.accessibilityIdentifier = "results"
        label.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: root.view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: root.view.layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.topAnchor),
        ])
        HostLog.label = label
        label.text = HostLog.lines.joined(separator: " | ")
        window?.rootViewController = root
        window?.makeKeyAndVisible()
        guard arguments.contains("-handoff2") else { return true }
        if value("-install", "will") == "did" { install("did") }

        if arguments.contains("-auth") {
            HostLog.add("permission returned \(ntk_probe_notification_request_permission(hostDone, UnsafeMutableRawPointer(bitPattern: 9), hostRelease))")
        }
        for (flag, marked) in [("-schedule", true), ("-schedule-host", false)] {
            guard let i = arguments.firstIndex(of: flag), i + 3 < arguments.count else { continue }
            let (id, seconds, title) = (arguments[i + 1], UInt32(arguments[i + 2]) ?? 3, arguments[i + 3])
            if marked {
                HostLog.add("schedule \(id) returned \(ntk_probe_notification_schedule_marked(seconds, id, title, hostDone, UnsafeMutableRawPointer(bitPattern: 1), hostRelease))")
            } else {
                let content = UNMutableNotificationContent()
                content.title = title
                content.userInfo = ["host": 1]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
                    DispatchQueue.main.async { HostLog.add("schedule-host \(id) error=\(error.map { "\($0)" } ?? "nil")") }
                }
            }
        }
        let after = Double(value("-listen-after", "0")) ?? 0
        if after >= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + after) {
                var listener: OpaquePointer?
                let error = ntk_probe_notification_add_listener(hostEvent, UnsafeMutableRawPointer(bitPattern: 2), hostRelease, &listener)
                HostLog.add("listener added error=\(error)")
            }
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard arguments.contains("-handoff2") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            var identifier: OpaquePointer?
            var action: OpaquePointer?
            let error = ntk_probe_notification_get_launch_response(&identifier, &action)
            HostLog.add("launch-response error=\(error) id=\(take(identifier)) action=\(take(action))")
        }
    }
}
