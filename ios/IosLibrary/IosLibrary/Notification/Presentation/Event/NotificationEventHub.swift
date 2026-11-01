//
//  NotificationEventHub.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationEventHub")
private let registrationLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationEventRegistration")

/// The listeners of one kind of notification event, and the events kept while there are none
/// (design 8.4, S-P10).
///
/// The library's hubs are ``IosNotificationManager/responses`` and
/// ``IosNotificationManager/settingsRequests``; you cannot create one.
///
/// ## Delivering and keeping
/// | When | What the hub does |
/// |---|---|
/// | An event arrives and there are listeners | Calls every listener once, oldest first. A listener removed by an earlier one in the same delivery is not called |
/// | An event arrives and there is no listener | Keeps it: up to 32 events, in the order they arrived, for the life of the process (never written to disk), duplicates included. Beyond 32 the oldest is dropped (logged) |
/// | ``addListener(_:)`` while events are kept | Hands every kept event to the new listener inside the call, in order, before it returns. If that listener removes itself on the way, the rest go on to the oldest remaining listener (also one added on the way); with none left, they are kept again, in front of any newer ones |
/// | ``NotificationEventRegistration/remove()`` | Takes the listener out at once; a second call does nothing |
///
/// So the events that arrived while nobody listened (a cold start, for example) go to the first
/// listener that is added, once. The existing receivers of ``IosNotificationManager`` are not
/// listeners: they neither take the kept events nor stop the hub from keeping.
///
/// ## Threading
/// Main actor only: add and remove listeners on the main actor; listeners are called on the
/// main actor (inside ``addListener(_:)`` for kept events, otherwise in a later main-queue block).
/// Reading ``IosNotificationManager/responses`` itself is allowed on any thread.
@MainActor
public final class NotificationEventHub<Event: Sendable> {

    /// How many events the hub keeps while there is no listener (design 8.4.2).
    nonisolated static var defaultCapacity: Int { 32 }

    private let name: String
    private let capacity: Int
    private let isDelegateInstalled: @Sendable () -> Bool
    private var listeners: [NotificationEventRegistration] = []
    private var listenerCalls: [ObjectIdentifier: @MainActor (Event, NotificationEventRegistration) -> Void] = [:]
    private var kept: [Event] = []
    private var hasLoggedADrop = false

    /// - Parameters:
    ///   - name: The hub's name for the log (`responses`, `settingsRequests`).
    ///   - capacity: How many events to keep while there is no listener.
    ///   - isDelegateInstalled: Whether the library's delegate has been installed in this process
    ///     (`IosNotificationManager.isDelegateInstalled`; tests pass their own).
    nonisolated init(name: String, capacity: Int = NotificationEventHub.defaultCapacity, isDelegateInstalled: @escaping @Sendable () -> Bool) {
        logger.log(level: .libraryDebug, "[init] name: \(name, privacy: .public), capacity: \(capacity, privacy: .public), isDelegateInstalled: provided")
        self.name = name
        self.capacity = capacity
        self.isDelegateInstalled = isDelegateInstalled
    }

    /// Adds a listener and returns its registration.
    ///
    /// The listener receives every event that arrives from now on, on the main actor, with its
    /// registration (call ``NotificationEventRegistration/remove()`` on it to stop, also from
    /// inside the listener). When events were kept because there was no listener, this new one
    /// receives them inside this call, before it returns (see the type's table).
    ///
    /// - Parameter listener: Called with each event and this listener's registration.
    /// - Returns: The registration. The hub keeps the listener until it is removed; dropping the
    ///   registration does not remove it.
    /// - Throws: ``NotificationError/delegateNotInstalled`` when
    ///   ``IosNotificationManager/installDelegate()`` has not installed the library's delegate in
    ///   this process (no event can arrive then). Nothing is added.
    @discardableResult
    public func addListener(
        _ listener: @escaping @MainActor (Event, NotificationEventRegistration) -> Void
    ) throws(NotificationError) -> NotificationEventRegistration {
        logger.log(level: .libraryDebug, "[addListener] hub: \(self.name, privacy: .public), listener: provided, listeners: \(self.listeners.count, privacy: .public), kept: \(self.kept.count, privacy: .public)")
        guard isDelegateInstalled() else {
            logger.error("[addListener] hub: \(self.name, privacy: .public): the library's delegate is not installed; call IosNotificationManager.installDelegate() first")
            throw .delegateNotInstalled
        }
        let registration = NotificationEventRegistration(hubName: name) { [weak self] registration in
            self?.remove(registration)
        }
        listeners.append(registration)
        listenerCalls[ObjectIdentifier(registration)] = listener
        guard !kept.isEmpty else { return registration }
        // Take the kept events out first, so that a listener added inside a listener does not
        // receive them a second time.
        let pending = kept
        kept = []
        logger.log(level: .libraryDebug, "[addListener] hub: \(self.name, privacy: .public), handing \(pending.count, privacy: .public) kept events to the new listener")
        handOver(pending, startingWith: registration)
        return registration
    }

    /// Delivers `event` to every listener, or keeps it when there is none (main queue; the
    /// library's delegate calls it).
    func deliver(_ event: Event) {
        logger.log(level: .libraryDebug, "[deliver] hub: \(self.name, privacy: .public), event: \(Self.summary(of: event), privacy: .public), listeners: \(self.listeners.count, privacy: .public)")
        let current = listeners
        guard !current.isEmpty else {
            keep([event])
            return
        }
        for registration in current where !registration.isRemoved {
            listenerCalls[ObjectIdentifier(registration)]?(event, registration)
        }
    }

    /// The number of kept events (tests, log).
    var keptCount: Int { kept.count }

    /// The number of listeners (tests, log).
    var listenerCount: Int { listeners.count }

    // MARK: Helpers

    /// Hands `events` to `first`, and when it removes itself on the way, the rest to the oldest
    /// remaining listener; with none left, the rest are kept again in front of newer ones.
    private func handOver(_ events: [Event], startingWith first: NotificationEventRegistration) {
        logger.log(level: .libraryDebug, "[handOver] hub: \(self.name, privacy: .public), events: \(events.count, privacy: .public), first: \(first.number, privacy: .public)")
        var target = first
        var index = events.startIndex
        while index < events.endIndex {
            if target.isRemoved {
                guard let next = listeners.first else {
                    logger.log(level: .libraryDebug, "[handOver] hub: \(self.name, privacy: .public), no listener left; keeping \(events.endIndex - index, privacy: .public) events again")
                    keep(Array(events[index...]), inFront: true)
                    return
                }
                target = next
            }
            let event = events[index]
            index += 1
            listenerCalls[ObjectIdentifier(target)]?(event, target)
        }
    }

    /// Keeps `events` (at the end, or in front of the kept ones), dropping the oldest beyond the
    /// capacity. The first drop of the hub is logged with `.info`, later ones with `.debug`
    /// (SR-23).
    private func keep(_ events: [Event], inFront: Bool = false) {
        logger.log(level: .libraryDebug, "[keep] hub: \(self.name, privacy: .public), events: \(events.count, privacy: .public), inFront: \(inFront, privacy: .public), kept: \(self.kept.count, privacy: .public)")
        kept = inFront ? events + kept : kept + events
        let excess = kept.count - capacity
        guard excess > 0 else { return }
        kept.removeFirst(excess)
        if hasLoggedADrop {
            logger.log(level: .libraryDebug, "[keep] hub: \(self.name, privacy: .public), no listener: dropped the \(excess, privacy: .public) oldest kept events (at most \(self.capacity, privacy: .public) are kept)")
        } else {
            hasLoggedADrop = true
            logger.info("[keep] hub: \(self.name, privacy: .public), no listener: dropped the \(excess, privacy: .public) oldest kept events (at most \(self.capacity, privacy: .public) are kept; later drops are logged at the debug level)")
        }
    }

    /// Takes `registration` out (``NotificationEventRegistration/remove()``).
    private func remove(_ registration: NotificationEventRegistration) {
        logger.log(level: .libraryDebug, "[remove] hub: \(self.name, privacy: .public), registration: \(registration.number, privacy: .public)")
        listeners.removeAll { $0 === registration }
        listenerCalls[ObjectIdentifier(registration)] = nil
    }

    /// Identifiers and counts of `event` for the log, never its content.
    private static func summary(of event: Event) -> String {
        logger.log(level: .libraryDebug, "[summary(of:)] event: \(String(describing: Event.self), privacy: .public)")
        return (event as? any NotificationEventLogSummary)?.logSummary ?? String(describing: Event.self)
    }
}

/// One listener added to a ``NotificationEventHub``.
///
/// Main actor only. Keep it to remove the listener later; dropping it does not remove the
/// listener.
@MainActor
public final class NotificationEventRegistration {

    private static var lastNumber = 0

    /// A number for the log.
    let number: Int
    private let hubName: String
    private var onRemove: (@MainActor (NotificationEventRegistration) -> Void)?

    /// Whether ``remove()`` was called.
    private(set) var isRemoved = false

    init(hubName: String, onRemove: @escaping @MainActor (NotificationEventRegistration) -> Void) {
        registrationLogger.log(level: .libraryDebug, "[init] hubName: \(hubName, privacy: .public), number: \(Self.lastNumber + 1, privacy: .public), onRemove: provided")
        Self.lastNumber += 1
        number = Self.lastNumber
        self.hubName = hubName
        self.onRemove = onRemove
    }

    /// Removes the listener at once: it receives no more events, also none of the current
    /// delivery that it has not received yet. A second call does nothing.
    public func remove() {
        registrationLogger.log(level: .libraryDebug, "[remove] hubName: \(self.hubName, privacy: .public), number: \(self.number, privacy: .public), isRemoved: \(self.isRemoved, privacy: .public)")
        guard !isRemoved, let onRemove else { return }
        isRemoved = true
        self.onRemove = nil
        onRemove(self)
    }
}
