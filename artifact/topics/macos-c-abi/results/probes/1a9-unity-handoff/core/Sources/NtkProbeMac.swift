// macOS C ABI 1a-9 probe: NtkProbeMac, the stand-in for MacLibrary (the Swift API). It holds what the
// decisions put in MacLibrary: the dialog shown the D-8 A' way, the share picker shown from a main-queue
// block (D-6, 1a-7), and the notification delegate proxy with the launch record (D-4). The C ABI
// (NtkProbeMacCApi) only receives the C calls and calls these. Not the product.
import AppKit
import os
import UserNotifications

let probeLog = Logger(subsystem: "com.jonghyunkim.nativetoolkit.probe1a9", category: "Core")

public enum NtkProbeCore {
    public static let version = "1.0.0"

    /// NSApp without creating it (NSApplication.shared would create an NSApplication before Unity's
    /// PlayerApplication, the NSPrincipalClass, gets the chance).
    public static var appIfExists: NSApplication? { NSApp }

    /// The path of the image that holds the given address (dladdr).
    public static func imagePath(of address: UnsafeRawPointer) -> String {
        var info = Dl_info()
        guard dladdr(address, &info) != 0, let name = info.dli_fname else { return "?" }
        return String(cString: name)
    }

    /// The path this framework was loaded from (redacted, see displayPath).
    public static var imagePath: String { displayPath(imagePath(of: #dsohandle)) }

    /// A path fit for logs on the user's Mac (device-testing.md: no home path, no user name):
    /// - inside or at an app bundle: from "<name>.app" on (".../Foo.app/Contents/X" -> "Foo.app/Contents/X")
    /// - inside a framework outside an app: ".../<name>.framework/..." ("…/" in front)
    /// - under the user's real home (getpwuid, not NSHomeDirectory/HOME, which point into the container
    ///   under the sandbox): "~/..."
    /// - anything else: "…/<last component>"
    public static func displayPath(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let app = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            return parts[app...].joined(separator: "/")
        }
        if let framework = parts.firstIndex(where: { $0.hasSuffix(".framework") }) {
            return "…/" + parts[framework...].joined(separator: "/")
        }
        if let home = realHome, path == home || path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return "…/" + (parts.last ?? "")
    }

    /// The login user's home folder from the user database (the same with and without the sandbox).
    static var realHome: String? {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return nil }
        return String(cString: dir)
    }

    /// Module and symbol of the callers above this frame (no addresses, no paths), for the record.
    public static func callerSymbols(_ count: Int = 12) -> String {
        Thread.callStackSymbols.dropFirst(2).prefix(count).map { line -> String in
            // "3   Unity NativeToolkit   0x00000001 symbol + 123": the module may contain spaces, so
            // split at the address token.
            let words = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let address = words.firstIndex(where: { $0.hasPrefix("0x") }), address >= 2 else { return "?" }
            let module = words[1..<address].joined(separator: " ")
            let symbol = words[(address + 1)...].prefix { $0 != "+" }.joined(separator: " ")
            return "\(module):\(symbol)"
    }.joined(separator: " < ")
    }

    /// True when the main bundle is an app bundle with an identifier. A command-line process is not,
    /// and UNUserNotificationCenter.current() raises an Objective-C exception there.
    public static var hasAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}

/// The ordered record of this process (install calls, launch notifications, delegate calls), with the
/// milliseconds since the first record. Read by ntk_probe_notification_describe.
public enum NtkProbeRecord {
    private static let lock = NSLock()
    private static var start: TimeInterval?
    private static var lines: [String] = []
    private static let limit = 200

    public static func mark(_ text: String) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if start == nil { start = now }
        let ms = Int(((now - (start ?? now)) * 1000).rounded())
        lines.append("+\(ms)ms \(text)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        lock.unlock()
        probeLog.notice("\(text, privacy: .public)")
    }

    public static var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: " | ")
    }
}

// MARK: - Dialog (D-8 A')

public enum NtkProbeDialog {
    public enum Outcome { case button(Int32), canceled, showFailed }

    /// How runModal is entered. runLoopBlock is A' (the decided recommendation); mainQueue is A (today's
    /// MacDialogManager: runModal inside a DispatchQueue.main.async block), kept only as the control of
    /// the Unity check (M-8), where the main queue is expected to stop while the alert is open (1a-6).
    public enum Entry { case runLoopBlock, mainQueue }

    /// A': queues a run-loop block on the main run loop in the common modes and returns. The block runs
    /// NSAlert.runModal(); since it is not inside a main-queue (GCD) block, the main queue keeps draining
    /// while the alert is open (1a-6). The completion is called on main after runModal returned.
    public static func enqueueAlert(title: String, message: String?, positive: String, negative: String?,
                                    autoCloseMs: UInt32, entry: Entry = .runLoopBlock,
                                    completion: @escaping (Outcome) -> Void) {
        let body = {
            MainActor.assumeIsolated {
                completion(run(title: title, message: message, positive: positive, negative: negative,
                               autoCloseMs: autoCloseMs, entry: entry))
            }
        }
        switch entry {
        case .runLoopBlock:
            let main = CFRunLoopGetMain()
            CFRunLoopPerformBlock(main, CFRunLoopMode.commonModes.rawValue, body)
            CFRunLoopWakeUp(main)
        case .mainQueue:
            DispatchQueue.main.async(execute: body)
        }
    }

    @MainActor private static func run(title: String, message: String?, positive: String, negative: String?,
                                       autoCloseMs: UInt32, entry: Entry) -> Outcome {
        guard let app = NtkProbeCore.appIfExists else { return .showFailed }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message ?? ""
        alert.addButton(withTitle: positive)
        if let negative { alert.addButton(withTitle: negative) }
        var timer: Timer?
        if autoCloseMs > 0 {
            // The common modes include the modal panel mode, so the timer fires while runModal runs.
            let closer = Timer(timeInterval: Double(autoCloseMs) / 1000, repeats: false) { _ in
                MainActor.assumeIsolated {
                    // Close only our alert, never a modal window of the host.
                    let ours = app.modalWindow === alert.window
                    NtkProbeRecord.mark("dialog auto-close ours=\(ours)")
                    if ours { app.abortModal() }
                }
            }
            RunLoop.main.add(closer, forMode: .common)
            timer = closer
        }
        // What the block runs inside (to tell Unity's frame loop from the modal loop when the frames stop).
        let mode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain()).map { $0.rawValue as String } ?? "nil"
        NtkProbeRecord.mark("dialog runModal enter entry=\(entry == .runLoopBlock ? "A'" : "A") mode=\(mode) fullScreen=\(isFullScreen(app)) stack=\(NtkProbeCore.callerSymbols())")
        let response = alert.runModal()
        timer?.invalidate()
        NtkProbeRecord.mark("dialog runModal return response=\(response.rawValue)")
        switch response {
        case .alertFirstButtonReturn: return .button(0)
        case .alertSecondButtonReturn: return .button(1)
        default: return .canceled
        }
    }

    @MainActor static func isFullScreen(_ app: NSApplication) -> Bool {
        guard let window = app.keyWindow ?? app.mainWindow else { return false }
        return window.styleMask.contains(.fullScreen)
    }
}

// MARK: - Share (D-6, 1a-7)

public enum NtkProbeShare {
    public enum Outcome { case notForeground, closed, chosen(String) }

    /// The boxes of the open pickers. A box holds its picker strongly until didChoose (the 1a-7 probe
    /// held the picker in its delayed close; AppKit's own retention while shown is not relied on).
    @MainActor private static var live: [ObjectIdentifier: PickerBox] = [:]

    /// Queues on the main queue and shows the picker at the centre of the key (or main) window's content
    /// view. The completion comes from didChoose, on main.
    public static func enqueue(text: String, autoCloseMs: UInt32, completion: @escaping (Outcome) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { show(text: text, autoCloseMs: autoCloseMs, completion: completion) }
        }
    }

    @MainActor private static func show(text: String, autoCloseMs: UInt32, completion: @escaping (Outcome) -> Void) {
        guard let app = NtkProbeCore.appIfExists, let window = app.keyWindow ?? app.mainWindow, let view = window.contentView else {
            NtkProbeRecord.mark("share no window active=\(NtkProbeCore.appIfExists?.isActive ?? false)")
            completion(.notForeground)
            return
        }
        let picker = NSSharingServicePicker(items: [text])
        let box = PickerBox(picker, completion)
        picker.delegate = box
        let key = ObjectIdentifier(box)
        box.onDone = { live[key] = nil }
        live[key] = box
        let rect = NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        NtkProbeRecord.mark("share show event=\(NSApp.currentEvent.map { String($0.type.rawValue) } ?? "nil") key=\(window.isKeyWindow) active=\(app.isActive) fullScreen=\(window.styleMask.contains(.fullScreen))")
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        if autoCloseMs > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(autoCloseMs))) {
                MainActor.assumeIsolated { box.closeIfOpen() }
            }
        }
    }

    private final class PickerBox: NSObject, NSSharingServicePickerDelegate {
        private var picker: NSSharingServicePicker?
        private var completion: ((Outcome) -> Void)?
        var onDone: (() -> Void)?

        init(_ picker: NSSharingServicePicker, _ completion: @escaping (Outcome) -> Void) {
            self.picker = picker
            self.completion = completion
        }

        @MainActor func closeIfOpen() {
            NtkProbeRecord.mark("share auto-close open=\(picker != nil)")
            picker?.close()
        }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            NtkProbeRecord.mark("share didChoose chosen=\(service != nil)")
            guard let completion else { return }
            self.completion = nil
            completion(service.map { .chosen($0.title) } ?? .closed)
            // Let go of the picker (and the box) only after AppKit's call has returned: this method is
            // called by the picker itself.
            DispatchQueue.main.async {
                self.picker = nil
                self.onDone?()
            }
        }
    }
}

// MARK: - Notification (D-4)

public struct NtkProbeNotificationEvent {
    public enum Kind { case response, settings }
    public let kind: Kind
    public let identifier: String?
    public let action: String?
    public let userText: String?
    public var isLaunchResponse = false
}

/// The launch record: the first didReceive of the process is the launch response when it comes before
/// the first NSApplicationDidBecomeActive and the library handled it. This is iOS's original P1-22 rule,
/// without iOS's later narrowing (H2-1: only a response that brings the app to the foreground, judged
/// in main-queue order); for a click on the body (M-7) both give the same result. The macOS definition
/// is decided in D-7 with the 1a-8 material.
enum NtkProbeLaunch {
    private static let lock = NSLock()
    private static var started = false
    private static var firstDidReceiveSeen = false
    private static var becameActive = false
    private static var launch: NtkProbeNotificationEvent?
    private static var observers: [NSObjectProtocol] = []

    /// Called on main by ntk_probe_notification_install_at (forms 1 and 3) or by the first install
    /// (form 2); in every form of unity/Main.cpp inside main(), before PlayerMain. queue nil: the observers run synchronously when posted.
    /// "Active" is only the NSApplicationDidBecomeActive notification: NSApp.isActive is already true at
    /// willFinishLaunching (1a-8, working notes 5.1), so it is recorded but not used.
    static func start() {
        lock.lock()
        let first = !started
        started = true
        lock.unlock()
        guard first else { return }
        NtkProbeRecord.mark("recording starts nsapp=\(NtkProbeCore.appIfExists != nil) isActive=\(NtkProbeCore.appIfExists?.isActive ?? false)")
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.willFinishLaunchingNotification, object: nil, queue: nil) { _ in
            NtkProbeRecord.mark("willFinishLaunching isActive=\(NtkProbeCore.appIfExists?.isActive ?? false)")
        })
        observers.append(center.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: nil) { note in
            let fromNotification = note.userInfo?[NSApplication.launchUserNotificationUserInfoKey] != nil
            NtkProbeRecord.mark("didFinishLaunching launchUserNotificationKey=\(fromNotification)")
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            NtkProbeRecord.mark("didBecomeActive")
            setActive()
        })
    }

    private static func setActive() {
        lock.lock()
        becameActive = true
        lock.unlock()
    }

    static func noteDidReceive(handledByLibrary: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !firstDidReceiveSeen else { return false }
        firstDidReceiveSeen = true
        return handledByLibrary && !becameActive
    }

    static func set(_ event: NtkProbeNotificationEvent) {
        lock.lock()
        launch = event
        lock.unlock()
    }

    static var current: NtkProbeNotificationEvent? {
        lock.lock()
        defer { lock.unlock() }
        return launch
    }
}

/// Calls the wrapped completion at most once from any thread (iOS part 1 5.12.4).
final class CompletionOnce<Value> {
    private let lock = NSLock()
    private var called = false
    private let completion: (Value) -> Void

    init(_ completion: @escaping (Value) -> Void) { self.completion = completion }

    func call(_ value: Value) {
        lock.lock()
        let first = !called
        called = true
        lock.unlock()
        guard first else {
            NtkProbeRecord.mark("completion called again; dropped")
            return
        }
        completion(value)
    }
}

/// Main-only: hands events to the listener, keeping up to 32 while there is none.
@MainActor public final class NtkProbeNotificationHub {
    public static let shared = NtkProbeNotificationHub()
    private var listener: ((NtkProbeNotificationEvent) -> Void)?
    private var held: [NtkProbeNotificationEvent] = []

    /// Set once by the C ABI; the events held so far are handed to it here.
    public func setListener(_ body: @escaping (NtkProbeNotificationEvent) -> Void) {
        listener = body
        let pending = held
        held = []
        pending.forEach(body)
    }

    func deliver(_ event: NtkProbeNotificationEvent) {
        guard let listener else {
            held.append(event)
            if held.count > 32 { held.removeFirst(held.count - 32) }
            return
        }
        listener(event)
    }
}

public final class NtkProbeNotificationProxy: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NtkProbeNotificationProxy()
    /// The userInfo key of every notification the library makes (value 1). Same as iOS.
    public static let markerKey = "com.jonghyunkim.nativetoolkit"

    public enum InstallResult { case installed, wrongThread, notSupported }

    private static let lock = NSLock()
    private static var installedFlag = false
    private weak var previousDelegate: UNUserNotificationCenterDelegate?
    private var forwarding = Set<String>()

    public static var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return installedFlag
    }

    /// Main only. Never creates NSApp. Never touches UNUserNotificationCenter without an app bundle.
    public static func install() -> InstallResult {
        let onMain = pthread_main_np() != 0
        let hasApp = NtkProbeCore.appIfExists != nil
        guard onMain else {
            NtkProbeRecord.mark("install main=0 -> WRONG_THREAD")
            return .wrongThread
        }
        guard NtkProbeCore.hasAppBundle else {
            NtkProbeRecord.mark("install main=1 nsapp=\(hasApp ? 1 : 0) bundle=0 -> NOT_SUPPORTED")
            return .notSupported
        }
        MainActor.assumeIsolated { shared.installOnMain(hasApp: hasApp) }
        return .installed
    }

    @MainActor private func installOnMain(hasApp: Bool) {
        let center = UNUserNotificationCenter.current()
        let current = center.delegate
        let active = NtkProbeCore.appIfExists?.isActive ?? false
        if (current as AnyObject?) === self {
            NtkProbeRecord.mark("install main=1 nsapp=\(hasApp ? 1 : 0) active=\(active ? 1 : 0) -> already installed")
            return
        }
        Self.lock.lock()
        previousDelegate = current
        Self.installedFlag = true
        Self.lock.unlock()
        center.delegate = self
        NtkProbeLaunch.start()
        NtkProbeRecord.mark("install main=1 nsapp=\(hasApp ? 1 : 0) app-class=\(NtkProbeCore.appIfExists.map { String(describing: type(of: $0)) } ?? "nil") active=\(active ? 1 : 0) previous=\(Self.className(current)) -> installed")
    }

    static func className(_ object: AnyObject?) -> String {
        object.map { String(describing: type(of: $0)) } ?? "nil"
    }

    /// "delegate=<class> previous=<class>" (reads the center only with an app bundle).
    public static var delegateSummary: String {
        guard NtkProbeCore.hasAppBundle else { return "delegate=(no app bundle)" }
        let current = UNUserNotificationCenter.current().delegate
        return "delegate=\(className(current)) previous=\(className(shared.previousDelegate))"
    }

    // MARK: router

    private func isLibrary(_ notification: UNNotification) -> Bool {
        notification.request.content.userInfo[Self.markerKey] != nil
    }

    private func previous(_ selector: Selector) -> UNUserNotificationCenterDelegate? {
        Self.lock.lock()
        let previous = previousDelegate
        Self.lock.unlock()
        guard let previous, previous.responds(to: selector) else { return nil }
        return previous
    }

    /// False when the same call is already being forwarded (a synchronous cycle, P1-21).
    private func enter(_ key: String) -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return forwarding.insert(key).inserted
    }

    private func leave(_ key: String) {
        Self.lock.lock()
        forwarding.remove(key)
        Self.lock.unlock()
    }

    /// The cycle key of iOS's NotificationDelegateRouter: method, identifier, date and action.
    private func key(_ method: String, _ notification: UNNotification?, _ action: String? = nil) -> String {
        guard let notification else { return method + "|nil" }
        return "\(method)|\(notification.request.identifier)|\(notification.date.timeIntervalSince1970)|\(action ?? "")"
    }

    // The three methods follow iOS's NotificationDelegateRouter (IosLibrary): the system completion is
    // wrapped in CompletionOnce (a previous delegate that calls it twice reaches the system once), a
    // nil openSettingsFor is not the library's and is forwarded, and every forwarded call is guarded
    // against a synchronous cycle. The forwarding with a real host delegate is not part of the 1a-9
    // checks (D-7 is not decided by them).

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let library = isLibrary(notification)
        NtkProbeRecord.mark("willPresent id=\(notification.request.identifier) library=\(library)")
        let once = CompletionOnce(completionHandler)
        let selector = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))
        if !library, let previous = previous(selector) {
            let key = key("wp", notification)
            if enter(key) {
                defer { leave(key) }
                previous.userNotificationCenter?(center, willPresent: notification) { options in once.call(options) }
                return
            }
            NtkProbeRecord.mark("willPresent came back while forwarding: unclaimed")
        }
        once.call([.banner, .list, .sound])
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        let library = isLibrary(response.notification)
        let id = response.notification.request.identifier
        NtkProbeRecord.mark("didReceive id=\(id) action=\(response.actionIdentifier) library=\(library) main=\(pthread_main_np()) active=\(NtkProbeCore.appIfExists?.isActive ?? false)")
        let once = CompletionOnce<Void> { _ in completionHandler() }
        var event = NtkProbeNotificationEvent(kind: .response, identifier: id, action: response.actionIdentifier,
                                              userText: (response as? UNTextInputNotificationResponse)?.userText)
        let selector = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))
        var mayBeLaunch = true
        if !library, let previous = previous(selector) {
            let key = key("dr", response.notification, response.actionIdentifier)
            if enter(key) {
                defer { leave(key) }
                _ = NtkProbeLaunch.noteDidReceive(handledByLibrary: false)   // uses up the first place
                previous.userNotificationCenter?(center, didReceive: response) { once.call(()) }
                return
            }
            NtkProbeRecord.mark("didReceive came back while forwarding: unclaimed")
            mayBeLaunch = false   // the outer call was forwarded
        }
        let launch = NtkProbeLaunch.noteDidReceive(handledByLibrary: true)
        event.isLaunchResponse = mayBeLaunch && launch
        if event.isLaunchResponse { NtkProbeLaunch.set(event) }
        let value = event
        DispatchQueue.main.async {
            MainActor.assumeIsolated { NtkProbeNotificationHub.shared.deliver(value) }
            once.call(())
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        NtkProbeRecord.mark("openSettingsFor id=\(notification?.request.identifier ?? "nil")")
        let selector = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:))
        // nil is not the library's notification (iOS part 1 R-13).
        if notification.map(isLibrary) != true, let previous = previous(selector) {
            let key = key("os", notification)
            if enter(key) {
                defer { leave(key) }
                previous.userNotificationCenter?(center, openSettingsFor: notification)
                return
            }
            NtkProbeRecord.mark("openSettingsFor came back while forwarding: unclaimed")
        }
        let event = NtkProbeNotificationEvent(kind: .settings, identifier: notification?.request.identifier, action: nil, userText: nil)
        DispatchQueue.main.async { MainActor.assumeIsolated { NtkProbeNotificationHub.shared.deliver(event) } }
    }

    // MARK: launch response, permission, schedule

    public static var launchResponse: NtkProbeNotificationEvent? { NtkProbeLaunch.current }

    /// Starts recording the launch notifications (idempotent; install also starts it). Main only.
    public static func startRecording() { NtkProbeLaunch.start() }

    /// Callers check hasAppBundle first. The authorization status (UNAuthorizationStatus raw value:
    /// 0 notDetermined, 1 denied, 2 authorized, 3 provisional) comes on main.
    public static func authorizationStatus(completion: @escaping (Int) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus.rawValue
            DispatchQueue.main.async { completion(status) }
        }
    }

    /// Callers check hasAppBundle first. The completion comes on main.
    public static func requestPermission(completion: @escaping (Bool, Error?) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async { completion(granted, error) }
        }
    }

    /// Callers check hasAppBundle first. The completion comes on main.
    public static func scheduleMarked(seconds: UInt32, identifier: String, title: String, completion: @escaping (Error?) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "native-toolkit 1a-9 probe"
        content.userInfo = [markerKey: 1]
        let trigger = seconds == 0 ? nil : UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { error in
            NtkProbeRecord.mark("scheduled id=\(identifier) seconds=\(seconds) error=\(error.map { "\($0)" } ?? "nil")")
            DispatchQueue.main.async { completion(error) }
        }
    }
}
