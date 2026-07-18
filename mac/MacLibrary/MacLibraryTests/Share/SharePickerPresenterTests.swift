//
//  SharePickerPresenterTests.swift
//  MacLibraryTests
//
import Testing
@testable import MacLibrary

/// Verifies the busy-guard that protects the presenter's single `continuation` slot from being
/// overwritten by a concurrent `presentPicker`/`performService` call (regression test for the
/// continuation-overwrite finding from the implementation review).
///
/// Uses `beginInFlightForTesting()`/`resumeInFlightForTesting(_:)` (module-internal test helpers)
/// to simulate an in-flight operation without depending on real AppKit UI (no window/anchor is
/// available in the test process).
struct SharePickerPresenterTests {

    @Test func presentPickerThrowsAlreadyInProgressWhenBusy() async throws {
        let presenter = SharePickerPresenter()
        let inFlight = Task { try? await presenter.beginInFlightForTesting() }
        try await Task.sleep(nanoseconds: 50_000_000)

        do {
            _ = try await presenter.presentPicker(items: ["x"], excludedServiceTitles: [])
            Issue.record("Expected presentPicker to throw .alreadyInProgress")
        } catch let error as ShareError {
            #expect(error.errorCode == ShareError.alreadyInProgress.errorCode)
        } catch {
            Issue.record("Expected ShareError.alreadyInProgress, got \(error)")
        }

        await presenter.resumeInFlightForTesting(ShareResult(completed: true, serviceName: nil))
        _ = await inFlight.value
    }

    @Test func performServiceThrowsAlreadyInProgressWhenBusy() async throws {
        let presenter = SharePickerPresenter()
        let inFlight = Task { try? await presenter.beginInFlightForTesting() }
        try await Task.sleep(nanoseconds: 50_000_000)

        do {
            _ = try await presenter.performService(items: ["x"],
                                                   serviceName: "com.apple.share.Mail.compose",
                                                   recipients: [],
                                                   subject: nil)
            Issue.record("Expected performService to throw .alreadyInProgress")
        } catch let error as ShareError {
            #expect(error.errorCode == ShareError.alreadyInProgress.errorCode)
        } catch {
            Issue.record("Expected ShareError.alreadyInProgress, got \(error)")
        }

        await presenter.resumeInFlightForTesting(ShareResult(completed: true, serviceName: nil))
        _ = await inFlight.value
    }
}
