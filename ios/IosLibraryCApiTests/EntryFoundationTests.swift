//
//  EntryFoundationTests.swift
//  IosLibraryCApiTests
//

import Foundation
import OSLog
import XCTest
@testable import IosLibraryCApi

/// What the receivers share: the values of the entry errors, the main queue, and the version check.
@MainActor
final class EntryFoundationTests: XCTestCase {

    // MARK: - The values every feature shares (AP-12)

    func testTheEntryErrorsAreTheValuesOfEveryHeader() {
        XCTAssertEqual(Entry.accepted, 0)
        for none in [NTK_CLIPBOARD_ERROR_NONE, NTK_DIALOG_ERROR_NONE, NTK_NOTIFICATION_ERROR_NONE, NTK_SHARE_ERROR_NONE] {
            XCTAssertEqual(Int32(none), Entry.accepted)
        }
        for value in [NTK_CLIPBOARD_ERROR_INVALID_PARAMETER, NTK_DIALOG_ERROR_INVALID_PARAMETER,
                      NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, NTK_SHARE_ERROR_INVALID_PARAMETER] {
            XCTAssertEqual(Int32(value), EntryError.invalidParameter.rawValue)
        }
        for value in [NTK_CLIPBOARD_ERROR_NOT_INITIALIZED, NTK_DIALOG_ERROR_NOT_INITIALIZED,
                      NTK_NOTIFICATION_ERROR_NOT_INITIALIZED, NTK_SHARE_ERROR_NOT_INITIALIZED] {
            XCTAssertEqual(Int32(value), EntryError.notInitialized.rawValue)
        }
        for value in [NTK_CLIPBOARD_ERROR_NOT_SUPPORTED, NTK_DIALOG_ERROR_NOT_SUPPORTED,
                      NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, NTK_SHARE_ERROR_NOT_SUPPORTED] {
            XCTAssertEqual(Int32(value), EntryError.notSupported.rawValue)
        }
    }

    // MARK: - MainQueue (P1-4)

    func testAFromMainBlockRunsAfterTheCall() {
        let ran = MainHolder<Bool>()
        MainQueue.async { ran.value = true }
        XCTAssertNil(ran.value)
        runMainQueue()
        XCTAssertEqual(ran.value, true)
    }

    /// P1-4: a block of the main queue, not a `Task` on the main actor, whose start has no documented order.
    func testABlockIsNotATask() {
        let inTask = MainHolder<Bool>()
        MainQueue.async { inTask.value = withUnsafeCurrentTask { $0 != nil } }
        runMainQueue()
        XCTAssertEqual(inTask.value, false)
    }

    func testBlocksFromAnotherThreadRunOnMainInOrder() {
        let order = MainHolder<[Int]>()
        order.value = []
        let done = onAnotherThread { () -> Bool in
            for index in 0..<100 {
                MainQueue.async {
                    XCTAssertTrue(Thread.isMainThread)
                    order.value?.append(index)
                }
            }
            return true
        }
        XCTAssertEqual(done, true, "queuing does not wait for the main thread")
        XCTAssertEqual(order.value, [])

        runMainQueue()

        XCTAssertEqual(order.value, Array(0..<100))
    }

    // MARK: - The version check (C-9, P1-19)

    func testComparison() {
        XCTAssertEqual(VersionCheck.compare(library: "2.0.0", capi: "2.0.0"), .same)
        XCTAssertEqual(VersionCheck.compare(library: "1.3.0", capi: "2.0.0"), .different)
        XCTAssertEqual(VersionCheck.compare(library: "2.0", capi: "2.0.0"), .different)
        XCTAssertEqual(VersionCheck.compare(library: nil, capi: "2.0.0"), .unreadable)
    }

    /// Whichever of these comes first in a process is what logs: each one has to run the check.
    func testEveryFirstCallRunsTheCheck() {
        func assertRunsTheCheck(_ name: String, _ call: () -> Void) {
            let before = VersionCheck.runCount
            call()
            XCTAssertEqual(VersionCheck.runCount, before + 1, name)
        }
        let recorder = Recorder()
        assertRunsTheCheck("accept") { acceptTestOperation(recorder) { $0.completeWithSuccess() } }
        runMainQueue()
        assertRunsTheCheck("reject") { _ = Entry.reject(.invalidParameter, userData: nil, release: nil) }
        let ledger = EventLedger<Int32, EventCallback>(holdLimit: 0, deliver: { callback, userData, event in callback(userData, event) })
        let listening = Recorder()
        assertRunsTheCheck("add") {
            _ = ledger.add(callback: recordingEventCallback as EventCallback, userData: listening.userData, release: nil,
                           outListener: listening.outListener)
        }
        Registry.removeListener(listening.outListener.pointee)
        runMainQueue()
        assertRunsTheCheck("install") { _ = onAnotherThread { ntk_notification_install() } }
    }

    func testTheVersionsAreThoseOfTheTwoFrameworks() throws {
        let library = try XCTUnwrap(Bundle(identifier: "com.jonghyunkim.nativetoolkit.IosLibrary"))
        XCTAssertEqual(VersionCheck.libraryVersion, library.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertNotNil(VersionCheck.libraryVersion)
        let capi = try XCTUnwrap(Bundle(identifier: "com.jonghyunkim.nativetoolkit.IosLibraryCApi"))
        XCTAssertEqual(VersionCheck.capiVersion, capi.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    /// What this run's two frameworks are decides the line: one line when they differ (1.3.0 and 2.0.0
    /// until the release raises the library's version), none when they are the same. A mismatch does not
    /// stop anything: the call goes through.
    func testAMismatchIsLoggedOnceAndStopsNothing() throws {
        VersionCheck.run()
        VersionCheck.run()
        let recorder = Recorder()
        acceptTestOperation(recorder) { $0.completeWithSuccess() }
        runMainQueue()
        XCTAssertEqual(recorder.completions.count, 1)
        XCTAssertEqual(Entry.reject(.invalidParameter, userData: nil, release: nil), 1)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let lines = try store.getEntries(at: store.position(date: Date(timeIntervalSinceNow: -3600)))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == "com.jonghyunkim.nativetoolkit.IosLibraryCApi" && $0.composedMessage.hasPrefix("[VersionCheck]") }
            .map(\.composedMessage)
        let expected = VersionCheck.compare(library: VersionCheck.libraryVersion, capi: VersionCheck.capiVersion) == .different ? 1 : 0
        XCTAssertEqual(lines.count, expected, "\(lines)")
        if expected == 1, let line = lines.first {
            XCTAssertTrue(line.contains(VersionCheck.libraryVersion ?? "?"), line)
            XCTAssertTrue(line.contains(VersionCheck.capiVersion), line)
        }
    }

}
