//
//  SharePickerPresenter.swift
//  MacLibrary
//

import AppKit

/// Contract for presenting the sharing service picker / performing a named service.
protocol SharePickerPresenting {
    /// Presents the sharing service picker with the given items.
    /// - Parameters:
    ///   - items: Activation items (see `ShareItemConverter`).
    ///   - excludedServiceTitles: Service display titles to exclude (best-effort match).
    /// - Returns: The interaction result.
    /// - Throws: `ShareError` if presentation preconditions fail or the system reports an error.
    func presentPicker(items: [Any], excludedServiceTitles: [String]) async throws -> ShareResult

    /// Performs a single named sharing service directly.
    /// - Parameters:
    ///   - items: Activation items.
    ///   - serviceName: Raw `NSSharingService.Name` value.
    ///   - recipients: Recipients to set on the service (ignored if empty).
    ///   - subject: Subject to set on the service (ignored if nil).
    /// - Returns: The interaction result.
    /// - Throws: `ShareError.serviceUnavailable` if the service is unknown or cannot perform.
    func performService(items: [Any], serviceName: String,
                        recipients: [String], subject: String?) async throws -> ShareResult

    /// Reports whether the named service can share the given items.
    func canPerform(items: [Any], serviceName: String) async -> Bool
}

/// Presents `NSSharingServicePicker` / `NSSharingService` and bridges delegate callbacks to `async/await`.
///
/// ## Delegate Ownership
/// This is the single class that implements `NSSharingServicePickerDelegate` and
/// `NSSharingServiceDelegate` (per common.md's single-owner rule for system delegates).
///
/// ## Anchor View Resolution
/// Falls back from the key window's content view to the main window's content view.
/// `ShareError.noAnchorView` is thrown when neither is available.
///
/// ## mouseDown Requirement
/// `NSSharingServicePicker.show(relativeTo:of:preferredEdge:)` is documented to require a
/// `mouseDown` event context. Callers (Manager / Bridge) must invoke this from a user-initiated
/// action (e.g. a button click), not from an arbitrary background call.
///
/// ## Continuation Safety
/// The continuation is resumed exactly once via the `resume(_:)` helper, which clears
/// `continuation` before resuming. A single `continuation` slot is shared by both
/// `presentPicker` and `performService`, so each begins with a busy-guard
/// (`continuation == nil`) that throws `ShareError.alreadyInProgress` instead of overwriting
/// an in-flight operation's continuation (which would silently drop the first caller's
/// callback/`async` result).
///
/// ## Actor Isolation
/// The class itself is not `@MainActor` (its delegate methods satisfy AppKit's non-isolated
/// `NSSharingServicePickerDelegate`/`NSSharingServiceDelegate` requirements, which are
/// synchronous and must not be actor-isolated). Instead, the three driving entry points
/// (`presentPicker`/`performService`/`canPerform`) and the anchor resolution are individually
/// marked `@MainActor`, since satisfying an `async` protocol requirement with an actor-isolated
/// implementation is permitted. AppKit invokes the delegate callbacks on the main thread, so all
/// access to `continuation`/`excludedServiceTitles` in practice happens on the main thread.
final class SharePickerPresenter: NSObject, SharePickerPresenting,
                                  NSSharingServicePickerDelegate, NSSharingServiceDelegate {

    private let TAG = "SharePickerPresenter"

    private var continuation: CheckedContinuation<ShareResult, Error>?
    private var excludedServiceTitles: [String] = []

    // MARK: - SharePickerPresenting

    @MainActor
    func presentPicker(items: [Any], excludedServiceTitles: [String]) async throws -> ShareResult {
        Log.d(TAG, "[presentPicker] items: \(items.count), excluded: \(excludedServiceTitles.count)")
        guard continuation == nil else {
            Log.e(TAG, "[presentPicker] a share operation is already in progress")
            throw ShareError.alreadyInProgress
        }
        guard let anchor = resolveAnchorView() else {
            Log.e(TAG, "[presentPicker] no anchor view available")
            throw ShareError.noAnchorView
        }
        self.excludedServiceTitles = excludedServiceTitles
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = self
            // NOTE: show() must be invoked within a mouseDown event context.
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    @MainActor
    func performService(items: [Any], serviceName: String,
                        recipients: [String], subject: String?) async throws -> ShareResult {
        Log.d(TAG, "[performService] serviceName: \(serviceName), items: \(items.count)")
        guard continuation == nil else {
            Log.e(TAG, "[performService] a share operation is already in progress")
            throw ShareError.alreadyInProgress
        }
        guard let service = NSSharingService(named: NSSharingService.Name(serviceName)) else {
            Log.e(TAG, "[performService] unknown service: \(serviceName)")
            throw ShareError.serviceUnavailable(name: serviceName)
        }
        service.delegate = self
        if !recipients.isEmpty { service.recipients = recipients }
        if let subject { service.subject = subject }
        guard service.canPerform(withItems: items) else {
            Log.e(TAG, "[performService] cannot perform: \(serviceName)")
            throw ShareError.serviceUnavailable(name: serviceName)
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            service.perform(withItems: items)
        }
    }

    @MainActor
    func canPerform(items: [Any], serviceName: String) async -> Bool {
        Log.d(TAG, "[canPerform] serviceName: \(serviceName), items: \(items.count)")
        guard let service = NSSharingService(named: NSSharingService.Name(serviceName)) else {
            return false
        }
        return service.canPerform(withItems: items)
    }

    // MARK: - Resume helper

    private func resume(_ result: Result<ShareResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    // MARK: - Anchor resolution

    @MainActor
    private func resolveAnchorView() -> NSView? {
        NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView
    }

    // MARK: - Testing support (module-internal only; not part of the public API)

    /// Starts a synthetic in-flight operation, without any AppKit dependency, so tests can
    /// verify the busy-guard in `presentPicker`/`performService` deterministically.
    @MainActor
    func beginInFlightForTesting() async throws -> ShareResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// Resolves whatever operation is currently in-flight (used to clean up after a test).
    @MainActor
    func resumeInFlightForTesting(_ result: ShareResult) {
        resume(.success(result))
    }

    // MARK: - NSSharingServicePickerDelegate

    func sharingServicePicker(_ picker: NSSharingServicePicker,
                              sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        Log.d(TAG, "[sharingServicesForItems] proposed: \(proposed.count)")
        guard !excludedServiceTitles.isEmpty else { return proposed }
        // best-effort: NSSharingService exposes no raw name, only a (possibly localized) title.
        return proposed.filter { !excludedServiceTitles.contains($0.title) }
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        Log.d(TAG, "[didChoose] service: \(service?.title ?? "nil")")
        guard service == nil else {
            // Completion is handled by NSSharingServiceDelegate (delegateFor supplies self).
            return
        }
        resume(.success(ShareResult(completed: false, serviceName: nil)))   // cancelled
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker,
                              delegateFor service: NSSharingService) -> NSSharingServiceDelegate? {
        Log.d(TAG, "[delegateFor] service: \(service.title)")
        return self
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
        Log.d(TAG, "[didShareItems] service: \(service.title)")
        resume(.success(ShareResult(completed: true, serviceName: service.title)))
    }

    func sharingService(_ service: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        Log.e(TAG, "[didFailToShareItems] service: \(service.title), error: \(error)")
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError {
            resume(.success(ShareResult(completed: false, serviceName: service.title)))   // user cancelled
        } else {
            resume(.failure(ShareError.presentationFailed(error)))
        }
    }
}
