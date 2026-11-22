// Probe for macos-c-abi 0a and 1a-8 (run only inside the qualified macOS 15 VM).
// - 0a: a small AppKit app the spike UI test drives: notification authorization, banners,
//   actions (foreground / background / text input), scheduled delivery, cold start from a
//   notification click, NSSharingServicePicker (listed, never chosen), NSAlert with help,
//   NSOpenPanel / NSSavePanel (VM temp folder only), SwiftUI PasteButton, pasteboard read.
// - 1a-8: the notification delegate is installed in applicationWillFinishLaunching. Every
//   didReceive / didBecomeActive / willFinish / didFinish is logged with a timestamp and
//   NSApp.isActive so the launch-trigger rule (iOS P1-22) can be checked on macOS.
// Events go to ~/ntk/probe-events.log (one line each) and to the "lastEvent" label.
import AppKit
import SwiftUI
import UserNotifications

try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/ntk/paneltmp", withIntermediateDirectories: true)
let logPath = NSHomeDirectory() + "/ntk/probe-events.log"
if !FileManager.default.fileExists(atPath: logPath) { FileManager.default.createFile(atPath: logPath, contents: nil) }
let logHandle = FileHandle(forWritingAtPath: logPath)!
logHandle.seekToEndOfFile()
let pid = ProcessInfo.processInfo.processIdentifier
let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
var lastEventLabel: NSTextField?
var lastReceiveLabel: NSTextField?
var counters: [String: Int] = [:]

func log(_ s: String) {
    let active = Thread.isMainThread ? String(NSApp?.isActive ?? false) : "?"
    let line = "\(fmt.string(from: Date())) up=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime)) pid=\(pid) active=\(active) \(s)"
    logHandle.write((line + "\n").data(using: .utf8)!)
    if Thread.isMainThread { lastEventLabel?.stringValue = s } else { DispatchQueue.main.async { lastEventLabel?.stringValue = s } }
}
func first(_ key: String) -> Int { counters[key, default: 0] += 1; return counters[key]! }

log("main begin path=\(Bundle.main.bundlePath) args=\(CommandLine.arguments.dropFirst().joined(separator: " "))")

final class Delegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate,
                      NSSharingServicePickerDelegate, NSAlertDelegate {
    var window: NSWindow!

    func applicationWillFinishLaunching(_ n: Notification) {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        let fg = UNNotificationAction(identifier: "FG", title: "Open FG", options: [.foreground])
        let bg = UNNotificationAction(identifier: "BG", title: "Mark BG", options: [])
        let txt = UNTextInputNotificationAction(identifier: "TXT", title: "Reply", options: [],
                                                textInputButtonTitle: "Send", textInputPlaceholder: "Type")
        c.setNotificationCategories([UNNotificationCategory(identifier: "PROBE", actions: [fg, bg, txt], intentIdentifiers: [])])
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            log("didBecomeActive #\(first("dba"))")
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: nil) { _ in
            log("didResignActive")
        }
        log("willFinishLaunching delegateInstalled keys=\(n.userInfo?.keys.map { "\($0)" } ?? [])")
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let keys = n.userInfo?.keys.map { "\($0)" } ?? []
        let isDefault = n.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool
        let un = n.userInfo?[NSApplication.launchUserNotificationUserInfoKey]
        log("didFinishLaunching keys=\(keys) launchIsDefault=\(String(describing: isDefault)) launchUserNotification=\(un != nil)")
        buildWindow()
        DispatchQueue.main.async { log("didFinishLaunching+mainAsync") }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    // MARK: notifications
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        log("willPresent id=\(n.request.identifier)")
        done([.banner, .list])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let text = (r as? UNTextInputNotificationResponse)?.userText
        log("didReceive #\(first("dr")) id=\(r.notification.request.identifier) action=\(r.actionIdentifier) text=\(text ?? "-") dbaSoFar=\(counters["dba", default: 0]) didFinishDone=\(window != nil)")
        lastReceiveLabel?.stringValue = "didReceive action=\(r.actionIdentifier) text=\(text ?? "-") first=\(counters["dr"]! == 1) dbaSoFar=\(counters["dba", default: 0])"
        DispatchQueue.main.async { log("didReceive+mainAsync") }
        done()
    }

    // MARK: actions
    @objc func reqAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, err in
            log("auth granted=\(ok) err=\(String(describing: err))")
        }
        log("auth requested")
    }
    @objc func authStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            log("authStatus=\(s.authorizationStatus.rawValue) alertStyle=\(s.alertStyle.rawValue)")
        }
    }
    func post(after seconds: TimeInterval, id: String) {
        let content = UNMutableNotificationContent()
        content.title = "NTK probe \(id)"
        content.body = "body \(id)"
        content.categoryIdentifier = "PROBE"
        let req = UNNotificationRequest(identifier: id, content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        UNUserNotificationCenter.current().add(req) { err in log("added id=\(id) after=\(seconds) err=\(String(describing: err))") }
    }
    @objc func post1() { post(after: 1, id: "n1-\(Int(Date().timeIntervalSince1970) % 100000)") }
    @objc func post10() { post(after: 10, id: "n10-\(Int(Date().timeIntervalSince1970) % 100000)") }
    @objc func post8() { post(after: 8, id: "n8-\(Int(Date().timeIntervalSince1970) % 100000)") }
    @objc func clearAll() {
        let c = UNUserNotificationCenter.current()
        c.removeAllDeliveredNotifications(); c.removeAllPendingNotificationRequests(); log("cleared")
    }
    @objc func showAlert() {
        let a = NSAlert()
        a.messageText = "Probe alert"
        a.informativeText = "informative"
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        a.showsHelp = true
        a.delegate = self
        let r = a.runModal()
        log("alert result=\(r.rawValue)")
    }
    func alertShowHelp(_ alert: NSAlert) -> Bool { log("alertShowHelp"); return true }
    @objc func openPanel() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/ntk/paneltmp")
        p.canChooseFiles = true
        let r = p.runModal()
        log("openPanel result=\(r.rawValue) urls=\(p.urls.map { $0.lastPathComponent })")
    }
    @objc func savePanel() {
        let p = NSSavePanel()
        p.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/ntk/paneltmp")
        p.nameFieldStringValue = "probe-save.txt"
        let r = p.runModal()
        if r == .OK, let u = p.url { try? "saved".write(to: u, atomically: true, encoding: .utf8) }
        log("savePanel result=\(r.rawValue) url=\(p.url?.path ?? "-")")
    }
    var shareButton: NSButton!
    @objc func share() {
        let picker = NSSharingServicePicker(items: ["ntk probe text"])
        picker.delegate = self
        picker.show(relativeTo: shareButton.bounds, of: shareButton, preferredEdge: .minY)
        log("share shown")
    }
    func sharingServicePicker(_ p: NSSharingServicePicker, sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        log("share proposed=[\(proposed.map { $0.title }.joined(separator: "|"))]")
        return proposed
    }
    func sharingServicePicker(_ p: NSSharingServicePicker, didChoose service: NSSharingService?) {
        log("share didChoose=\(service?.title ?? "nil")")
    }
    @objc func readPasteboard() {
        let s = NSPasteboard.general.string(forType: .string)
        log("pbRead=\(s ?? "nil")")
    }
    @objc func quit() { NSApp.terminate(nil) }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 360, height: 560),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "NTK probe 0a"
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        let label = NSTextField(labelWithString: "ready")
        label.setAccessibilityIdentifier("lastEvent")
        lastEventLabel = label
        stack.addArrangedSubview(label)
        let rlabel = NSTextField(labelWithString: "none")
        rlabel.setAccessibilityIdentifier("lastReceive")
        lastReceiveLabel = rlabel
        stack.addArrangedSubview(rlabel)
        let items: [(String, Selector)] = [
            ("reqAuth", #selector(reqAuth)), ("authStatus", #selector(authStatus)),
            ("post1", #selector(post1)), ("post8", #selector(post8)), ("post10", #selector(post10)),
            ("clearAll", #selector(clearAll)), ("alert", #selector(showAlert)),
            ("openPanel", #selector(openPanel)), ("savePanel", #selector(savePanel)),
            ("share", #selector(share)), ("readPasteboard", #selector(readPasteboard)), ("quit", #selector(quit)),
        ]
        for (title, sel) in items {
            let b = NSButton(title: title, target: self, action: sel)
            b.setAccessibilityIdentifier(title)
            stack.addArrangedSubview(b)
            if title == "share" { shareButton = b }
        }
        let paste = NSHostingView(rootView: PasteButton(payloadType: String.self) { strings in
            DispatchQueue.main.async { log("pasteButton=\(strings.joined(separator: ","))") }
        }.accessibilityIdentifier("pasteButton"))
        stack.addArrangedSubview(paste)
        stack.frame = NSRect(x: 16, y: 16, width: 328, height: 528)
        window.contentView = NSView()
        window.contentView!.addSubview(stack)
        window.makeKeyAndOrderFront(nil)
        log("window shown")
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
