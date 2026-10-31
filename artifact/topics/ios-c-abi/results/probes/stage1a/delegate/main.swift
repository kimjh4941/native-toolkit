// Stage 1a throwaway harness for the delegate forwarding matrix (C1) and the install function (C2).
// The scenario comes from PROBE_SCENARIO (XCUIApplication.launchEnvironment or SIMCTL_CHILD_*),
// or, on a cold start from a notification, from Documents/cold.txt written by the arming launch.
// Every event is appended to Documents/events.log (tab separated) and sent to NSLog.
import UIKit
import UserNotifications

// MARK: - Log

/// Seconds since the process was created (so cold-start events can be compared).
let processStart: Double = {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, 4, &info, &size, nil, 0)
    let tv = info.kp_proc.p_un.__p_starttime
    return Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000
}()

final class EventFile: @unchecked Sendable {
    static let shared = EventFile()
    private let lock = NSLock()
    private let handle: FileHandle?
    var scenario = "?"
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() {
        let url = docs.appendingPathComponent("events.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    func write(_ event: String, _ fields: [String: String]) {
        let t = Date().timeIntervalSince1970 - processStart
        let thread = pthread_main_np() != 0 ? "main" : "bg"
        let rest = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        lock.withLock {
            let line = String(format: "%.3f", t) + "\t\(getpid())\t\(scenario)\t\(thread)\t\(event)\t\(rest)\n"
            try? handle?.write(contentsOf: Data(line.utf8))
            NSLog("[PROBE] %@", line)
        }
    }
}

func plog(_ event: String, _ fields: [String: String] = [:]) { EventFile.shared.write(event, fields) }

@MainActor func appState() -> String {
    switch UIApplication.shared.applicationState {
    case .active: "active"
    case .inactive: "inactive"
    case .background: "background"
    @unknown default: "unknown"
    }
}

// MARK: - Host delegates

enum Behavior: String {
    case sync, asyncMain, asyncBg, twice, never, hold, async5, listonly
}

/// A host delegate whose answer for willPresent / didReceive is configurable. `disabled` makes
/// `responds(to:)` say no for those selectors (what the system and the proxy check).
final class HostDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    let name: String
    let behavior: Behavior
    let disabled: Set<Selector>
    /// When true, behaves like a host that forwards to the delegate it replaced.
    weak var forwardTo: (any UNUserNotificationCenterDelegate)?
    var forwards = false
    private var callCount = [String: Int]()
    private var held: [@Sendable () -> Void] = []

    init(_ name: String, _ behavior: Behavior, disabled: Set<Selector> = []) {
        self.name = name
        self.behavior = behavior
        self.disabled = disabled
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if disabled.contains(aSelector) { return false }
        return super.responds(to: aSelector)
    }

    /// Which method the behaviour applies to ("wp", "dr" or "both"); the other one answers sync.
    var target = "both"

    /// The configured behaviour applies to the first call of the target method only; later calls are sync.
    private func behaviorFor(_ method: String) -> Behavior {
        let n = (callCount[method] ?? 0) + 1
        callCount[method] = n
        return n == 1 && (target == "both" || target == method) ? behavior : .sync
    }

    private func perform(_ b: Behavior, _ what: String, _ id: String, _ done: @escaping @Sendable () -> Void) {
        switch b {
        case .sync, .listonly: plog("\(name).complete", ["what": what, "id": id, "how": "sync"]); done()
        case .twice:
            plog("\(name).complete", ["what": what, "id": id, "how": "twice#1"]); done()
            plog("\(name).complete", ["what": what, "id": id, "how": "twice#2"]); done()
        case .asyncMain, .async5:
            let delay = b == .async5 ? 5.0 : 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                plog("\(self.name).complete", ["what": what, "id": id, "how": "asyncMain"]); done()
            }
        case .asyncBg:
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                plog("\(self.name).complete", ["what": what, "id": id, "how": "asyncBg"]); done()
            }
        case .never: plog("\(name).complete", ["what": what, "id": id, "how": "never"]) // closure dropped
        case .hold:
            // Kept alive but never called (a host that stores the handler and forgets it).
            held.append(done)
            plog("\(name).complete", ["what": what, "id": id, "how": "hold"])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let id = notification.request.identifier
        plog("\(name).willPresent", ["id": id, "state": MainActor.assumeIsolated { appState() }])
        if forwards, let next = forwardTo, next.responds(to: ForwardingDelegate.wpSel) {
            plog("\(name).forwardsBack", ["method": "willPresent", "id": id])
            next.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
            return
        }
        let options: UNNotificationPresentationOptions = behavior == .listonly && target != "dr" ? [.list] : [.banner]
        let box = UncheckedBox(completionHandler)
        perform(behaviorFor("wp"), "willPresent", id) { box.value(options) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        plog("\(name).didReceive", ["id": id, "action": response.actionIdentifier, "state": MainActor.assumeIsolated { appState() }])
        if forwards, let next = forwardTo, next.responds(to: ForwardingDelegate.drSel) {
            plog("\(name).forwardsBack", ["method": "didReceive", "id": id])
            next.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
            return
        }
        let box = UncheckedBox(completionHandler)
        perform(behaviorFor("dr"), "didReceive", id) { box.value() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        plog("\(name).openSettings", ["id": notification?.request.identifier ?? "nil"])
    }
}

/// A host delegate that implements none of the optional methods.
final class BareHostDelegate: NSObject, UNUserNotificationCenterDelegate {}

/// Watches `UNUserNotificationCenter.delegate` with KVO to see whether a replacement is observable.
final class DelegateObserver: NSObject, @unchecked Sendable {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let new = change?[.newKey].map { String(describing: type(of: $0)) } ?? "nil"
        plog("kvo.delegateChanged", ["new": new])
    }
}

// MARK: - Scenario

@MainActor enum Probe {
    static var scenario = "idle"
    static var parts: [String] { scenario.split(separator: ".").map(String.init) }
    static var hosts: [AnyObject] = []
    static var stateLabel: UILabel?
    static var isColdRun = false
    static let observer = DelegateObserver()

    static var lastState = "starting"

    static func setState(_ s: String) {
        plog("state", ["value": s])
        lastState = s
        stateLabel?.text = s
        stateLabel?.accessibilityValue = s
    }

    static var coldFile: URL { EventFile.shared.docs.appendingPathComponent("cold.txt") }

    static func loadScenario() {
        if let env = ProcessInfo.processInfo.environment["PROBE_SCENARIO"], !env.isEmpty {
            scenario = env
        } else if let saved = try? String(contentsOf: coldFile, encoding: .utf8) {
            try? FileManager.default.removeItem(at: coldFile)
            scenario = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            isColdRun = true
        }
        EventFile.shared.scenario = (isColdRun ? "coldrun:" : "") + scenario
    }

    static func content(kind: String, title: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = "probe \(kind)"
        switch kind {
        case "lib": c.userInfo = [ntkMarkerKey: 2, "k": "v"]
        case "host": c.userInfo = ["host": 1]
        default: c.userInfo = ["k": "v"] // an unmarked 1.x notification looks like this
        }
        return c
    }

    static func post(kind: String, title: String, after: Double?) {
        let trigger = after.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        let c = content(kind: kind, title: title)
        if parts.contains("bga") {
            // A background action (no .foreground): the completion ends the background execution.
            let action = UNNotificationAction(identifier: "bg", title: "BgAct", options: [])
            UNUserNotificationCenter.current().setNotificationCategories([
                UNNotificationCategory(identifier: "probe.cat", actions: [action], intentIdentifiers: [])
            ])
            c.categoryIdentifier = "probe.cat"
        }
        let req = UNNotificationRequest(identifier: title, content: c, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { err in plog("posted", ["id": title, "err": err.map { "\($0)" } ?? "nil"]) }
    }

    static func logDelivered(_ tag: String) {
        UNUserNotificationCenter.current().getDeliveredNotifications { list in
            plog("delivered", ["tag": tag, "ids": list.map(\.request.identifier).joined(separator: ",")])
        }
    }

    /// Sets the host delegate for `prev` (and keeps it alive like a host's AppDelegate would).
    static func setHost(_ prev: String, name: String = "host") {
        let center = UNUserNotificationCenter.current()
        switch prev {
        case "none": break
        case "noimpl":
            let h = BareHostDelegate(); hosts.append(h); center.delegate = h
        default:
            let h = HostDelegate(name, Behavior(rawValue: prev) ?? .sync)
            let p = parts
            h.target = p.first == "raw" ? p[1] : (["wp", "dr"].contains(p.first ?? "") ? p[0] : "both")
            hosts.append(h); center.delegate = h
        }
    }

    static func install() -> Int32 {
        // Called through the C symbol, as a host's native code would.
        typealias Fn = @convention(c) () -> Int32
        let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ntk_notification_install") // RTLD_DEFAULT
        guard let sym else { plog("install.dlsymFailed"); return -1 }
        let state = appState()
        let code = unsafeBitCast(sym, to: Fn.self)()
        plog("install.called", ["code": "\(code)", "appState": state])
        return code
    }

    static func after(_ s: Double, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { MainActor.assumeIsolated(body) }
    }

    // MARK: Launch hooks

    static func willFinish(_ options: [UIApplication.LaunchOptionsKey: Any]?) {
        plog("launch.willFinish", ["appState": appState(), "options": options.map { $0.keys.map(\.rawValue).joined(separator: ",") } ?? "nil"])
        NotificationCenter.default.addObserver(forName: UIApplication.didFinishLaunchingNotification, object: nil, queue: nil) { _ in
            plog("launch.didFinishNotification")
        }
        if isColdRun { coldHook("willFinish") }
        if parts.first == "c2" { c2AtWillFinish() }
    }

    static func didFinish() {
        plog("launch.didFinish", ["appState": appState()])
        if isColdRun {
            coldHook("didFinish")
            DispatchQueue.main.async { MainActor.assumeIsolated { plog("launch.mainAsync"); coldHook("mainAsync") } }
            after(1) { coldHook("delay1") }
            after(3) { coldHook("delay3") }
            after(8) { setState("done") }
            return
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        run()
    }

    static func becameActive() {
        plog("launch.becameActive", ["appState": appState()])
        if isColdRun { coldHook("becomeActive") }
    }

    /// Cold run: `cold.<timing>.<kind>[.noproxy]`. A host delegate of kind `host` is set at
    /// willFinish; the proxy is installed at <timing>. With `noproxy`, only a sync host delegate is
    /// set at <timing> (does the system keep the response until a delegate exists?).
    static func coldHook(_ point: String) {
        let p = parts
        guard p.count >= 3 else { return }
        if point == "willFinish", p[2] == "host", !p.contains("noproxy") { setHost("sync") }
        guard p[1] == point else { return }
        if p.contains("noproxy") { setHost("sync"); plog("cold.hostSet"); return }
        if p[1] != "never" { _ = install() }
    }

    // MARK: Scenarios

    static func run() {
        let p = parts
        switch p.first {
        case "auth":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings]) { ok, err in
                plog("auth", ["granted": "\(ok)", "err": err.map { "\($0)" } ?? "nil"])
                DispatchQueue.main.async { MainActor.assumeIsolated { setState("done") } }
            }
        case "wp", "dr", "os":
            // <method>.<prev>.<kind>[.wd]  (prev: none/noimpl/sync/asyncMain/asyncBg/twice/never)
            setHost(p[1])
            if p.contains("wd") { Installer.shared.proxy.policy.watchdog = 3 }
            _ = install()
            runMethod(p[0], kind: p.count > 2 ? p[2] : "lib")
        case "raw":
            // raw.<method>.<behavior>: the host delegate alone, no proxy (system behaviour).
            switch p[2] {
            case "nodelegate": break
            case "noimpl": setHost("noimpl")
            default: setHost(p[2])
            }
            runMethod(p[1], kind: "host")
        case "cold":
            // Arming launch: save the scenario, schedule, and wait to be terminated.
            try? scenario.write(to: coldFile, atomically: true, encoding: .utf8)
            post(kind: p.count > 2 ? p[2] : "lib", title: "P \(scenario)", after: 4)
            setState("armed")
        case "push":
            setHost("sync")
            _ = install()
            setState("armed")
            after(10) { logDelivered("end"); setState("done") }
        case "osdirect":
            // openSettingsFor could not be triggered by the system on the simulator; call the proxy directly.
            setHost(p[1])
            _ = install()
            Installer.shared.proxy.userNotificationCenter(UNUserNotificationCenter.current(), openSettingsFor: nil)
            setState("done")
        case "rep": runReplace(p)
        case "weak": runWeak()
        case "c2": c2AfterLaunch()
        case "c2late":
            // First install only after launch has finished (what a C# / Dart caller would do).
            setHost("sync")
            c2AfterLaunch()
        default: setState("idle")
        }
    }

    static func runMethod(_ method: String, kind: String) {
        switch method {
        case "wp":
            setState("armed")
            after(1) { post(kind: kind, title: "A \(scenario)", after: nil) }
            after(4) { logDelivered("afterA") }
            after(8) { post(kind: kind, title: "B \(scenario)", after: nil) }
            after(11) { logDelivered("end"); setState("done") }
        case "dr":
            post(kind: kind, title: "T \(scenario)", after: parts.contains("late") ? 12 : 3)
            setState("armed")
            after(18) { setState("done") }
        case "os":
            setState("armed")
            after(1) {
                UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!) { ok in
                    plog("openedSettings", ["ok": "\(ok)"])
                }
            }
            after(25) { setState("done") }
        default: break
        }
    }

    /// The host replaces the delegate after the proxy (`rep.kvo`, `rep.cycle`, `rep.cycle.noguard`, `rep.refuse`).
    static func runReplace(_ p: [String]) {
        let center = UNUserNotificationCenter.current()
        center.addObserver(observer, forKeyPath: "delegate", options: [.new], context: nil)
        let cycle = p.count > 1 && p[1] == "cycle"
        if p.contains("noguard") { Installer.shared.proxy.policy.cycleGuard = false }
        if p.contains("refuse") { Installer.shared.onReplaced = .refuse }
        if !cycle { setHost("sync", name: "host1") }
        _ = install()
        after(1) {
            let h2 = HostDelegate("host2", .sync)
            if cycle { h2.forwards = true; h2.forwardTo = center.delegate }
            hosts.append(h2)
            center.delegate = h2
            plog("host2.set", ["delegateIsProxy": "\((center.delegate as AnyObject?) === Installer.shared.proxy)"])
        }
        after(2) { post(kind: "lib", title: "R1 lib after replace", after: nil) }
        after(3) { post(kind: "host", title: "R2 host after replace", after: nil) }
        after(4) { _ = install() }
        after(5) { post(kind: "lib", title: "R3 lib after reinstall", after: nil) }
        after(6) { post(kind: "host", title: "R4 host after reinstall", after: nil) }
        after(8) { logDelivered("end"); setState("done") }
    }

    static func runWeak() {
        let center = UNUserNotificationCenter.current()
        autoreleasepool { center.delegate = BareHostDelegate() }
        plog("weak.sameTurn", ["delegate": center.delegate.map { String(describing: type(of: $0)) } ?? "nil"])
        after(0.5) {
            plog("weak.nextTurn", ["delegate": center.delegate.map { String(describing: type(of: $0)) } ?? "nil"])
            setState("done")
        }
    }

    // MARK: C2

    static func c2AtWillFinish() {
        let center = UNUserNotificationCenter.current()
        // Off the main thread, while the main thread is blocked waiting: must return at once.
        let sem = DispatchSemaphore(value: 0)
        let start = Date()
        DispatchQueue.global().async {
            let code = ntk_notification_install()
            plog("c2.offMain", ["code": "\(code)", "ms": String(format: "%.1f", Date().timeIntervalSince(start) * 1000)])
            sem.signal()
        }
        let waited = sem.wait(timeout: .now() + 2)
        plog("c2.offMainReturnedWhileMainBlocked", ["ok": "\(waited == .success)",
             "delegateAfter": center.delegate.map { String(describing: type(of: $0)) } ?? "nil"])
        let t = Thread { _ = ntk_notification_install() }
        t.start()
        // On the main thread but not on the main queue (dispatch_sync from main runs the block here).
        DispatchQueue(label: "c2.serial").sync {
            plog("c2.syncFromMain", ["pthread_main": "\(pthread_main_np() != 0)", "isMainThread": "\(Thread.isMainThread)"])
            if parts.contains("assume") {
                plog("c2.assume.before")
                MainActor.assumeIsolated { plog("c2.assume.ok") }
            }
        }
        setHost("sync")
        let first = install()
        plog("c2.first", ["code": "\(first)", "delegateIsProxy": "\((center.delegate as AnyObject?) === Installer.shared.proxy)"])
        let second = install()
        plog("c2.second", ["code": "\(second)", "previous": Installer.shared.proxy.previous.map { String(describing: type(of: $0)) } ?? "nil"])
    }

    static func c2AfterLaunch() {
        after(2) {
            let code = install()
            plog("c2.afterLaunch", ["code": "\(code)", "appState": appState()])
            setState("done")
        }
    }
}

// MARK: - App

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Probe.loadScenario()
        Probe.willFinish(launchOptions)
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") == nil {
            let w = UIWindow(frame: UIScreen.main.bounds)
            w.rootViewController = makeRoot()
            w.makeKeyAndVisible()
            window = w
        }
        Probe.didFinish()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) { Probe.becameActive() }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        plog("scene.willConnect", ["notificationResponse": connectionOptions.notificationResponse?.notification.request.identifier ?? "nil"])
        if Probe.isColdRun { Probe.coldHook("sceneConnect") }
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.rootViewController = makeRoot()
        w.makeKeyAndVisible()
        window = w
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        plog("scene.didBecomeActive")
        if Probe.isColdRun { Probe.coldHook("sceneActive") }
    }
}

@MainActor func makeRoot() -> UIViewController {
    let vc = UIViewController()
    vc.view.backgroundColor = .systemBackground
    let label = UILabel(frame: CGRect(x: 20, y: 120, width: 340, height: 60))
    label.accessibilityIdentifier = "probe.state"
    label.text = Probe.lastState
    label.accessibilityValue = Probe.lastState
    vc.view.addSubview(label)
    Probe.stateLabel = label
    return vc
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
