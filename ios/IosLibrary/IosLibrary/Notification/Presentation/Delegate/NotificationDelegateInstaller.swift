//
//  NotificationDelegateInstaller.swift
//  IosLibrary
//

import Foundation
import os
import Synchronization
import UIKit
import UserNotifications

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationDelegateInstaller")

/// What the installer sets the delegate on: `UNUserNotificationCenter`, or a stand-in in tests
/// (an `NSObject` whose `delegate` is key-value observable).
protocol NotificationDelegateCenter: NSObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }
}

extension UNUserNotificationCenter: NotificationDelegateCenter {}

/// What the manager reads of the library's delegate: whether it was installed in this process
/// (P1-6: the event listeners and the launch response throw `delegateNotInstalled` before) and
/// the launch response the router found (P1-22, H2-1).
///
/// The manager composes the library's status from the library's installer; tests pass their own
/// closures, because a test that installs the real proxy leaves the process flag set for every
/// later test.
struct NotificationDelegateStatus: Sendable {
    /// Whether the library's delegate has been installed in this process. Any thread.
    let isInstalled: @Sendable () -> Bool
    /// The launch response, or `nil` when there is none (yet). Any thread.
    let launchResponse: @Sendable () -> NotificationDelegateResponse?
}

/// Installs the library's delegate proxy (design 8.3.1; part 1, 1.4 and 5.12.6) and keeps the
/// flag of whether it was ever installed in this process (S-14, P1-6).
///
/// The installer knows only the sink protocol (``NotificationDelegateEventSink``): the manager
/// composes the library's installer (`IosNotificationManager.delegateInstaller`), whose proxy is
/// the one `UNUserNotificationCenter` gets and whose flag is
/// `IosNotificationManager.isDelegateInstalled`. Tests create their own installer with a
/// stand-in center.
///
/// ## Threading
/// ``install(on:applicationIsActive:)`` runs on the main actor; the main-thread check of the
/// public entry is done before it (`pthread_main_np()`). ``isInstalled`` can be read on any
/// thread.
///
/// `Sendable` without `@unchecked`: the proxy is `Sendable` and the flag is an `Atomic`. There
/// is no `deinit` work: the library's installer is never freed (part 1, 5.14); a test installer
/// stops the observing itself.
final class NotificationDelegateInstaller: Sendable {
    let proxy: NotificationDelegateProxy
    private let installed = Atomic<Bool>(false)
    private let notificationCenter: NotificationCenter

    /// - Parameters:
    ///   - sink: Receives what the library handles.
    ///   - presentationOptions: The options of the notifications the library presents in the
    ///     foreground. Any thread.
    ///   - notificationCenter: Where `UIApplication.didBecomeActiveNotification` is observed.
    ///   - isApplicationInForeground: Whether the application is in the foreground (main actor;
    ///     the router reads it for a response to a custom action). By default
    ///     ``NotificationDelegateProxy/bringsAppToForeground(_:)`` of
    ///     `UIApplication.shared.applicationState`.
    init(
        sink: any NotificationDelegateEventSink,
        presentationOptions: @escaping @Sendable () -> UNNotificationPresentationOptions,
        notificationCenter: NotificationCenter = .default,
        isApplicationInForeground: @escaping @MainActor @Sendable () -> Bool = {
            NotificationDelegateProxy.bringsAppToForeground(UIApplication.shared.applicationState)
        }
    ) {
        logger.log(level: .libraryDebug, "[init] sink: \(String(describing: type(of: sink)), privacy: .public), presentationOptions: provided, notificationCenter: \(notificationCenter === NotificationCenter.default ? "default" : "custom", privacy: .public), isApplicationInForeground: provided")
        let router = NotificationDelegateRouter(sink: sink, isApplicationInForeground: isApplicationInForeground)
        self.proxy = NotificationDelegateProxy(router: router, presentationOptions: presentationOptions)
        self.notificationCenter = notificationCenter
    }

    /// The application object, or `nil` before `UIApplicationMain` has created it (a SwiftUI
    /// `App.init`, or a UIKit `main.swift` before `UIApplicationMain`; MS-12). Read through the
    /// Objective-C class method `sharedApplication`, whose result may be `nil`:
    /// `UIApplication.shared` is a non-optional Swift reference and must not be read then.
    @MainActor
    static func sharedApplication() -> UIApplication? {
        logger.log(level: .libraryDebug, "[sharedApplication]")
        let application = (UIApplication.self as AnyObject)
            .perform(NSSelectorFromString("sharedApplication"))?
            .takeUnretainedValue() as? UIApplication
        if application == nil {
            logger.log(level: .libraryDebug, "[sharedApplication] the application object does not exist yet")
        }
        return application
    }

    /// Whether `application` is active, for ``install(on:applicationIsActive:)``. Without an
    /// application object (before `UIApplicationMain`), the app is not active yet: a launch
    /// response is still possible (P1-22).
    @MainActor
    static func isActive(_ application: UIApplication?) -> Bool {
        logger.log(level: .libraryDebug, "[isActive] application: \(application == nil ? "nil" : "provided", privacy: .public)")
        guard let application else { return false }
        return application.applicationState == .active
    }

    /// Whether the proxy has been installed in this process (it stays `true`).
    var isInstalled: Bool {
        installed.load(ordering: .acquiring)
    }

    /// Sets the proxy as `center.delegate` before it returns (part 1, 5.12.6).
    ///
    /// - When the proxy is already the delegate, nothing changes.
    /// - Otherwise the current delegate becomes the previous delegate, replacing the one kept
    ///   before (also after another object replaced the proxy: then it is installed again and
    ///   logged; 1a-10). Only one previous delegate is kept.
    /// - The first time, `UIApplication.didBecomeActiveNotification` and the center's `delegate`
    ///   start being observed, and when the app is already active no launch response is possible
    ///   (P1-22); ``isInstalled`` becomes `true` once the proxy is the delegate.
    /// - When it sets the delegate while the app is active, it logs that this may be after
    ///   launch, so a cold-start tap may have been lost (1a-11, part 1 R-36).
    ///
    /// Everything a delegate call reads is ready before the proxy is published as the delegate:
    /// the system may call the proxy on another thread as soon as it is set, and that call must
    /// see the previous delegate and whether the app was active.
    ///
    /// - Parameters:
    ///   - center: Returns the center (`UNUserNotificationCenter.current()`). It is read twice,
    ///     once for the previous delegate, which moves into the proxy, and once to set the
    ///     delegate; each read is a value of its own, so the previous delegate is not tied to
    ///     the center that is used afterwards.
    ///   - applicationIsActive: Whether the app is active (``isActive(_:)`` of
    ///     ``sharedApplication()``: `false` before the application object exists).
    @MainActor
    func install(on center: @Sendable () -> any NotificationDelegateCenter, applicationIsActive: Bool) -> NotificationDelegateInstallResult {
        let current = center().delegate
        logger.log(level: .libraryDebug, "[install] center: provided, applicationIsActive: \(applicationIsActive, privacy: .public), current: \(NotificationDelegateProxy.typeName(current), privacy: .public)")
        if current === proxy {
            logger.log(level: .libraryDebug, "[install] already installed")
            return .installed
        }
        if applicationIsActive {
            logger.info("[install] the app is already active: this may be after launch, and a notification response that launched the app may have been lost")
        }
        let wasInstalled = installed.load(ordering: .acquiring)
        if wasInstalled {
            logger.info("[install] the delegate was replaced by \(NotificationDelegateProxy.typeName(current), privacy: .public); installing the proxy again in front of it")
        }
        let previousName = NotificationDelegateProxy.typeName(current)
        // 1. The previous delegate: the reference moves into the proxy and is not used after.
        proxy.setPreviousDelegate(current)
        let target = center()
        if !wasInstalled {
            // 2. The first install: the launch response's start, `didBecomeActive`, and the
            // center's `delegate` (key-value observing; log only, part 1 R-22). Observed before
            // the proxy is set, so that no replacement right after it is missed; the proxy's own
            // assignment below is not counted as a replacement.
            logger.log(level: .libraryDebug, "[install] first install: observing didBecomeActive and the center's delegate")
            proxy.router.noteFirstInstall(applicationIsActive: applicationIsActive)
            notificationCenter.addObserver(
                proxy,
                selector: #selector(NotificationDelegateProxy.applicationDidBecomeActive(_:)),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
            target.addObserver(proxy, forKeyPath: NotificationDelegateProxy.delegateKeyPath, options: [.new], context: nil)
        }
        // 3. Publish the proxy, then the flag.
        target.delegate = proxy
        if !wasInstalled {
            installed.store(true, ordering: .releasing)
        }
        logger.log(level: .libraryDebug, "[install] installed, previous: \(previousName, privacy: .public)")
        return .installed
    }
}
