// macOS C ABI 1a-9 probe: the receivers behind the C entries. They check the input, accept or reject,
// and call NtkProbeMac (the MacLibrary stand-in). Completions and releases go to main (D-6).
import AppKit
@preconcurrency import NtkProbeMac

private func notificationCode(_ value: Int) -> ntk_notification_error { ntk_notification_error(value) }

enum ProbeReceiver {
    static func threadInfo(_ outIsMain: UnsafeMutablePointer<Int32>?, _ outThreadId: UnsafeMutablePointer<UInt64>?,
                           _ outHasNSApp: UnsafeMutablePointer<Int32>?) -> ntk_probe_error {
        outIsMain?.pointee = pthread_main_np() != 0 ? 1 : 0
        var tid: UInt64 = 0
        pthread_threadid_np(nil, &tid)
        outThreadId?.pointee = tid
        outHasNSApp?.pointee = NtkProbeCore.appIfExists != nil ? 1 : 0
        return ntk_probe_error(NTK_PROBE_ERROR_NONE)
    }

    static func echo(_ value: Int32, _ delayMs: UInt32, _ callback: ntk_probe_echo_fn?, _ userData: UnsafeMutableRawPointer?,
                     _ release: ntk_release_fn?) -> ntk_probe_error {
        guard let callback else {
            rejectRelease(userData, release)
            return ntk_probe_error(NTK_PROBE_ERROR_INVALID_PARAMETER)
        }
        let isMain: Int32 = pthread_main_np() != 0 ? 1 : 0
        let request = Request(callback, userData, release)
        if delayMs == 0 {
            request.finishAsync { callback, userData in callback(userData, value, isMain) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs))) {
                NtkProbeRecord.mark("echo \(value) delivered (after \(delayMs) ms)")
                request.finishOnMain { callback, userData in callback(userData, value, isMain) }
            }
        }
        request.returned()
        return ntk_probe_error(NTK_PROBE_ERROR_NONE)
    }

    static func redact(_ path: UnsafePointer<CChar>?) -> OpaquePointer? {
        guard case .value(let text) = CApiString.input(path) else { return nil }
        return Handle.string(NtkProbeCore.displayPath(text))
    }

    static func describe() -> OpaquePointer {
        var parts: [String] = []
        parts.append("bundle-id=\(Bundle.main.bundleIdentifier ?? "nil")")
        parts.append("bundle=\(NtkProbeCore.displayPath(Bundle.main.bundleURL.path))")
        parts.append("build-token=\(Bundle.main.object(forInfoDictionaryKey: "NTKProbeBuildToken") as? String ?? "nil")")
        parts.append("pid=\(getpid())")
        parts.append("app-bundle=\(NtkProbeCore.hasAppBundle ? 1 : 0)")
        parts.append("sandbox=\(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil ? 1 : 0)")
        parts.append("main=\(pthread_main_np())")
        if pthread_main_np() != 0 {
            MainActor.assumeIsolated {
                if let app = NtkProbeCore.appIfExists {
                    parts.append("nsapp=\(String(describing: type(of: app))) active=\(app.isActive ? 1 : 0)")
                    if let window = app.keyWindow ?? app.mainWindow {
                        parts.append("window=\(String(describing: type(of: window))) key=\(window.isKeyWindow ? 1 : 0) fullScreen=\(window.styleMask.contains(.fullScreen) ? 1 : 0)")
                    } else {
                        parts.append("window=nil")
                    }
                } else {
                    parts.append("nsapp=nil")
                }
            }
        }
        parts.append("capi=\(NtkProbeCore.displayPath(NtkProbeCore.imagePath(of: #dsohandle)))")
        parts.append("core=\(NtkProbeCore.imagePath)")
        parts.append("core-version=\(NtkProbeCore.version)")
        return Handle.string(parts.joined(separator: " "))
    }
}

enum DialogReceiver {
    static func showAlert(_ title: UnsafePointer<CChar>?, _ message: UnsafePointer<CChar>?, _ positive: UnsafePointer<CChar>?,
                          _ negative: UnsafePointer<CChar>?, _ autoCloseMs: UInt32, _ callback: ntk_dialog_done_fn?,
                          _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                          _ outRequestId: UnsafeMutablePointer<UInt64>?,
                          entry: NtkProbeDialog.Entry) -> ntk_dialog_error {
        outRequestId?.pointee = 0
        guard let callback,
              case .value(let titleText) = CApiString.input(title), !titleText.isEmpty,
              case .value(let positiveText) = CApiString.input(positive), !positiveText.isEmpty,
              let messageText = optionalText(message), let negativeText = optionalText(negative) else {
            rejectRelease(userData, release)
            return ntk_dialog_error(NTK_DIALOG_ERROR_INVALID_PARAMETER)
        }
        let request = Request(callback, userData, release)
        outRequestId?.pointee = request.id
        let id = request.id
        NtkProbeDialog.enqueueAlert(title: titleText, message: messageText.value, positive: positiveText,
                                    negative: negativeText.value, autoCloseMs: autoCloseMs, entry: entry) { outcome in
            let (error, button): (Int, Int32)
            switch outcome {
            case .button(let index): (error, button) = (NTK_DIALOG_ERROR_NONE, index)
            case .canceled: (error, button) = (NTK_DIALOG_ERROR_CANCELED, -1)
            case .showFailed: (error, button) = (NTK_DIALOG_ERROR_SHOW_FAILED, -1)
            @unknown default: (error, button) = (NTK_DIALOG_ERROR_SHOW_FAILED, -1)
            }
            request.finishAsync { callback, userData in callback(userData, id, ntk_dialog_error(error), button) }
        }
        request.returned()
        return ntk_dialog_error(NTK_DIALOG_ERROR_NONE)
    }

    /// NULL is fine (nil inside); invalid UTF-8 is not (outer nil).
    private struct Optional2 { let value: String? }
    private static func optionalText(_ pointer: UnsafePointer<CChar>?) -> Optional2? {
        switch CApiString.input(pointer) {
        case .absent: return Optional2(value: nil)
        case .value(let text): return Optional2(value: text)
        case .invalid: return nil
        }
    }
}

enum ShareReceiver {
    static func show(_ text: UnsafePointer<CChar>?, _ autoCloseMs: UInt32, _ callback: ntk_share_done_fn?,
                     _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_share_error {
        guard let callback else {
            rejectRelease(userData, release)
            return ntk_share_error(NTK_SHARE_ERROR_INVALID_PARAMETER)
        }
        let value: String
        switch CApiString.input(text) {
        case .invalid:
            rejectRelease(userData, release)
            return ntk_share_error(NTK_SHARE_ERROR_INVALID_PARAMETER)
        case .absent:
            rejectRelease(userData, release)
            return ntk_share_error(NTK_SHARE_ERROR_EMPTY_CONTENT)
        case .value(let content):
            guard !content.isEmpty else {
                rejectRelease(userData, release)
                return ntk_share_error(NTK_SHARE_ERROR_EMPTY_CONTENT)
            }
            value = content
        }
        let request = Request(callback, userData, release)
        NtkProbeShare.enqueue(text: value, autoCloseMs: autoCloseMs) { outcome in
            switch outcome {
            case .notForeground:
                request.finishAsync { callback, userData in callback(userData, ntk_share_error(NTK_SHARE_ERROR_NOT_FOREGROUND), 0, nil) }
            case .closed:
                request.finishAsync { callback, userData in callback(userData, ntk_share_error(NTK_SHARE_ERROR_NONE), 0, nil) }
            case .chosen(let title):
                request.finishAsync { callback, userData in callback(userData, ntk_share_error(NTK_SHARE_ERROR_NONE), 1, Handle.string(title)) }
            @unknown default:
                request.finishAsync { callback, userData in callback(userData, ntk_share_error(NTK_SHARE_ERROR_NONE), 0, nil) }
            }
        }
        request.returned()
        return ntk_share_error(NTK_SHARE_ERROR_NONE)
    }
}

/// A registered listener. The C ABI keeps one list on main; NtkProbeMac's hub gets one listener that
/// fans out to it. Its insertion on main waits for add_listener's last statement (ReturnGate).
final class ListenerRegistration: ReturnGate, @unchecked Sendable {
    let callback: ntk_probe_notification_event_fn
    let userData: UnsafeMutableRawPointer?
    let release: ntk_release_fn?
    var active = true   // main only

    init(_ callback: @escaping ntk_probe_notification_event_fn, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) {
        self.callback = callback
        self.userData = userData
        self.release = release
    }

    @MainActor func send(_ event: NtkProbeNotificationEvent) {
        let kind = event.kind == .response ? NTK_PROBE_NOTIFICATION_EVENT_RESPONSE : NTK_PROBE_NOTIFICATION_EVENT_SETTINGS
        callback(userData, ntk_probe_notification_event_kind(kind), event.identifier.map(Handle.string),
                 event.action.map(Handle.string), event.userText.map(Handle.string), event.isLaunchResponse ? 1 : 0)
    }
}

/// Main only. Events that come while no listener is active (before the first one, and after the last
/// one was removed) are held here, up to 32, and handed to the next listener inside its insertion.
@MainActor enum ListenerLedger {
    static var listeners: [ListenerRegistration] = []
    static var held: [NtkProbeNotificationEvent] = []
    static var hubConnected = false

    static func add(_ registration: ListenerRegistration) {
        guard registration.active else { return }   // removed before it was inserted
        listeners.append(registration)
        if !hubConnected {
            hubConnected = true   // the hub hands the events it held so far to dispatch here
            NtkProbeNotificationHub.shared.setListener { event in dispatch(event) }
        }
        let pending = held
        held = []
        for event in pending where registration.active { registration.send(event) }
    }

    static func dispatch(_ event: NtkProbeNotificationEvent) {
        let active = listeners.filter { $0.active }
        guard !active.isEmpty else {
            held.append(event)
            if held.count > 32 { held.removeFirst(held.count - 32) }
            return
        }
        for listener in active where listener.active { listener.send(event) }
    }

    static func remove(_ registration: ListenerRegistration) {
        guard registration.active else { return }
        registration.active = false
        listeners.removeAll { $0 === registration }
        registration.release?(registration.userData)
    }
}

enum NotificationReceiver {
    private static func reject(_ error: Int, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
        rejectRelease(userData, release)
        return notificationCode(error)
    }

    static func install() -> ntk_notification_error {
        switch NtkProbeNotificationProxy.install() {
        case .installed: return notificationCode(NTK_NOTIFICATION_ERROR_NONE)
        case .wrongThread: return notificationCode(NTK_NOTIFICATION_ERROR_WRONG_THREAD)
        case .notSupported: return notificationCode(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED)
        @unknown default: return notificationCode(NTK_NOTIFICATION_ERROR_UNKNOWN)
        }
    }

    static func addListener(_ callback: ntk_probe_notification_event_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                            _ outListener: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_notification_error {
        outListener?.pointee = nil
        guard NtkProbeCore.hasAppBundle else { return reject(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, userData, release) }
        guard let callback, let outListener else { return reject(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, userData, release) }
        guard NtkProbeNotificationProxy.isInstalled else { return reject(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED, userData, release) }
        let registration = ListenerRegistration(callback, userData, release)
        outListener.pointee = Handle.make(registration)
        registration.onMainAfterReturn { MainActor.assumeIsolated { ListenerLedger.add(registration) } }
        registration.returned()
        return notificationCode(NTK_NOTIFICATION_ERROR_NONE)
    }

    static func removeListener(_ listener: OpaquePointer?) {
        guard let registration = Handle.borrow(listener, as: ListenerRegistration.self) else { return }
        Handle.free(listener)   // the caller's reference; the block below keeps its own
        DispatchQueue.main.async { MainActor.assumeIsolated { ListenerLedger.remove(registration) } }
    }

    static func launchResponse(_ outIdentifier: UnsafeMutablePointer<OpaquePointer?>?,
                               _ outAction: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_notification_error {
        outIdentifier?.pointee = nil
        outAction?.pointee = nil
        guard NtkProbeCore.hasAppBundle else { return notificationCode(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED) }
        guard let outIdentifier, let outAction else { return notificationCode(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER) }
        guard NtkProbeNotificationProxy.isInstalled else { return notificationCode(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED) }
        if let launch = NtkProbeNotificationProxy.launchResponse {
            outIdentifier.pointee = launch.identifier.map(Handle.string)
            outAction.pointee = launch.action.map(Handle.string)
        }
        return notificationCode(NTK_NOTIFICATION_ERROR_NONE)
    }

    static func requestPermission(_ callback: ntk_probe_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                  _ release: ntk_release_fn?) -> ntk_notification_error {
        guard NtkProbeCore.hasAppBundle else { return reject(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, userData, release) }
        guard let callback else { return reject(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, userData, release) }
        let request = Request(callback, userData, release)
        DispatchQueue.main.async {
            NtkProbeNotificationProxy.requestPermission { granted, error in
                let code = granted ? NTK_NOTIFICATION_ERROR_NONE : (error == nil ? NTK_NOTIFICATION_ERROR_PERMISSION_DENIED : NTK_NOTIFICATION_ERROR_UNKNOWN)
                request.finishAsync { callback, userData in callback(userData, notificationCode(code), granted ? 1 : 0) }
            }
        }
        request.returned()
        return notificationCode(NTK_NOTIFICATION_ERROR_NONE)
    }

    static func authorizationStatus(_ callback: ntk_probe_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                    _ release: ntk_release_fn?) -> ntk_notification_error {
        guard NtkProbeCore.hasAppBundle else { return reject(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, userData, release) }
        guard let callback else { return reject(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, userData, release) }
        let request = Request(callback, userData, release)
        NtkProbeNotificationProxy.authorizationStatus { status in
            request.finishAsync { callback, userData in callback(userData, notificationCode(NTK_NOTIFICATION_ERROR_NONE), Int32(status)) }
        }
        request.returned()
        return notificationCode(NTK_NOTIFICATION_ERROR_NONE)
    }

    static func scheduleMarked(_ seconds: UInt32, _ identifier: UnsafePointer<CChar>?, _ title: UnsafePointer<CChar>?,
                               _ callback: ntk_probe_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                               _ release: ntk_release_fn?) -> ntk_notification_error {
        guard NtkProbeCore.hasAppBundle else { return reject(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, userData, release) }
        guard let callback, case .value(let id) = CApiString.input(identifier), !id.isEmpty,
              case .value(let text) = CApiString.input(title), !text.isEmpty else {
            return reject(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, userData, release)
        }
        let request = Request(callback, userData, release)
        DispatchQueue.main.async {
            NtkProbeNotificationProxy.scheduleMarked(seconds: seconds, identifier: id, title: text) { error in
                let code = error == nil ? NTK_NOTIFICATION_ERROR_NONE : NTK_NOTIFICATION_ERROR_UNKNOWN
                request.finishAsync { callback, userData in callback(userData, notificationCode(code), 0) }
            }
        }
        request.returned()
        return notificationCode(NTK_NOTIFICATION_ERROR_NONE)
    }

    /// Observers registered by installAt (kept for the life of the process).
    nonisolated(unsafe) private static var hostObservers: [NSObjectProtocol] = []

    static func installAt(_ when: Int32) -> ntk_notification_error {
        guard pthread_main_np() != 0 else { return notificationCode(NTK_NOTIFICATION_ERROR_WRONG_THREAD) }
        let name: Notification.Name
        switch when {
        case 1: name = NSApplication.willFinishLaunchingNotification
        case 3: name = NSApplication.didFinishLaunchingNotification
        case 2:
            NtkProbeRecord.mark("install_at 2: install now")
            return install()
        default: return notificationCode(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER)
        }
        NtkProbeNotificationProxy.startRecording()
        NtkProbeRecord.mark("install_at \(when): observer for \(name.rawValue)")
        hostObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
            let result = install()
            NtkProbeRecord.mark("install_at \(when): \(name.rawValue) -> \(result)")
        })
        return notificationCode(NTK_NOTIFICATION_ERROR_NONE)
    }

    static func describe() -> OpaquePointer {
        let installed = NtkProbeNotificationProxy.isInstalled
        let summary = installed ? NtkProbeNotificationProxy.delegateSummary : "delegate=(not installed)"
        return Handle.string("installed=\(installed ? 1 : 0) \(summary) record: \(NtkProbeRecord.text)")
    }
}
