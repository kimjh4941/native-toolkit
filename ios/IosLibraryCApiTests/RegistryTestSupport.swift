//
//  RegistryTestSupport.swift
//  IosLibraryCApiTests
//

import Foundation
import Synchronization
import XCTest
@testable import IosLibraryCApi

// No public function is asynchronous yet (TB-2), so these tests use the Registry through a test-only
// operation and a test-only event, with C callbacks that record into the object behind `user_data`.

/// The form of a completion that carries the request id, as `ntk_dialog_result_fn` does.
typealias OperationCallback = @convention(c) (UnsafeMutableRawPointer?, UInt64, Int32, UInt32) -> Void
/// The form of an event, as `ntk_notification_interaction_fn` does; the event is a number here.
typealias EventCallback = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void

let successValue: Int32 = 0
/// What the test operation completes with when cancelled; a feature's value in the real thing.
let canceledValue: Int32 = 106

/// What the C callbacks saw. The callbacks' own hooks run on whichever thread called them.
final class Recorder: @unchecked Sendable {
    struct Completion: Equatable {
        let id: UInt64
        let error: Int32
        let systemCode: UInt32
        let onMain: Bool
    }

    private let lock = NSLock()
    private var completionList: [Completion] = []
    private var eventList: [Int32] = []
    private var releaseList: [Bool] = []
    private var order: [String] = []
    private var steps: [String] = []

    /// Runs inside the callback, after it was recorded.
    var onCompletion: (@Sendable (Completion) -> Void)?
    var onEvent: (@Sendable (Int32) -> Void)?
    var onRelease: (@Sendable () -> Void)?

    let outRequestID: UnsafeMutablePointer<UInt64>
    let outListener: UnsafeMutablePointer<OpaquePointer?>

    init() {
        outRequestID = .allocate(capacity: 1)
        outRequestID.initialize(to: 0)
        outListener = .allocate(capacity: 1)
        outListener.initialize(to: nil)
    }

    deinit {
        outRequestID.deallocate()
        outListener.deallocate()
    }

    /// `user_data`. The tests keep the recorder alive past its release.
    var userData: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    static func from(_ userData: UnsafeMutableRawPointer?) -> Recorder? {
        userData.map { Unmanaged<Recorder>.fromOpaque($0).takeUnretainedValue() }
    }

    var completions: [Completion] { lock.withLock { completionList } }
    var events: [Int32] { lock.withLock { eventList } }
    var releases: [Bool] { lock.withLock { releaseList } }
    var calls: [String] { lock.withLock { order } }
    /// Each callback's entry and return, and each release, as they happened.
    var timeline: [String] { lock.withLock { steps } }

    func recordCompletion(id: UInt64, error: Int32, systemCode: UInt32) {
        let completion = Completion(id: id, error: error, systemCode: systemCode, onMain: Thread.isMainThread)
        lock.withLock {
            completionList.append(completion)
            order.append("completion")
            steps.append("enter")
        }
        onCompletion?(completion)
        lock.withLock { steps.append("return") }
    }

    func recordEvent(_ event: Int32) {
        lock.withLock {
            eventList.append(event)
            order.append("event \(event)")
            steps.append("enter")
        }
        onEvent?(event)
        lock.withLock { steps.append("return") }
    }

    func recordRelease() {
        let onMain = Thread.isMainThread
        lock.withLock {
            releaseList.append(onMain)
            order.append("release")
            steps.append("release")
        }
        onRelease?()
    }
}

func recordingOperationCallback(_ userData: UnsafeMutableRawPointer?, _ id: UInt64, _ error: Int32, _ systemCode: UInt32) {
    Recorder.from(userData)?.recordCompletion(id: id, error: error, systemCode: systemCode)
}

func recordingEventCallback(_ userData: UnsafeMutableRawPointer?, _ event: Int32) {
    Recorder.from(userData)?.recordEvent(event)
}

func recordingRelease(_ userData: UnsafeMutableRawPointer?) {
    Recorder.from(userData)?.recordRelease()
}

/// Holds what a block on the main thread produced, for the test body after it.
@MainActor
final class MainHolder<Value> {
    var value: Value?
}

/// The test operation: what a receiver does after its checks.
@discardableResult
func acceptTestOperation(_ recorder: Recorder, cancellable: CancellableKind? = DialogReceiver.cancelKind, hasRelease: Bool = true, writesID: Bool = true,
                         start: @escaping @MainActor @Sendable (Registration<OperationCallback>) -> Void = { _ in }) -> Int32 {
    Registry.accept(callback: recordingOperationCallback as OperationCallback, userData: recorder.userData, release: hasRelease ? recordingRelease : nil,
                    cancellable: cancellable,
                    canceled: { callback, userData, id in callback(userData, id, canceledValue, 0) },
                    outRequestID: writesID ? recorder.outRequestID : nil, start: start)
}

extension Registration<OperationCallback> {
    @MainActor
    func completeWithSuccess(result: OwnedResult? = nil) {
        complete(result: result) { callback, userData, id in callback(userData, id, successValue, 0) }
    }
}

/// Lets every block queued so far run, in order. The test body is on the main thread, so nothing queued
/// runs until this is called: that is how a test holds an order in place.
@MainActor
func runMainQueue(file: StaticString = #filePath, line: UInt = #line) {
    let done = MainHolder<Bool>()
    MainQueue.async { done.value = true }
    let deadline = Date(timeIntervalSinceNow: 10)
    while done.value == nil, Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
    }
    XCTAssertEqual(done.value, true, "the main queue did not get to the block", file: file, line: line)
}

/// Exactly one release, with no callback on the stack (part 1, 5.7).
func assertReleasedOnceOutsideCallbacks(_ recorder: Recorder, file: StaticString = #filePath, line: UInt = #line) {
    var depth = 0
    var releases = 0
    for step in recorder.timeline {
        switch step {
        case "enter": depth += 1
        case "return": depth -= 1
        default:
            releases += 1
            XCTAssertEqual(depth, 0, "a release inside a callback: \(recorder.timeline)", file: file, line: line)
        }
    }
    XCTAssertEqual(depth, 0, "a callback did not return: \(recorder.timeline)", file: file, line: line)
    XCTAssertEqual(releases, 1, "\(recorder.timeline)", file: file, line: line)
}

/// A folder with one file, as `IosLibrary` gives a `.file` load.
func makeLoadedFile() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RegistryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("loaded.txt")
    try Data("loaded".utf8).write(to: file)
    return file
}

/// Starts the two sides of a race together: the other thread spins until `go`, and `go` comes after the
/// thread is spinning.
final class RaceStart: Sendable {
    private let ready = Atomic<Bool>(false)
    private let started = Atomic<Bool>(false)

    func waitForGo() {
        ready.store(true, ordering: .releasing)
        while !started.load(ordering: .acquiring) {}
    }

    /// `spins` shifts this side against the other.
    func go(afterSpinning spins: Int) {
        while !ready.load(ordering: .acquiring) {}
        started.store(true, ordering: .releasing)
        for index in 0..<spins {
            _ = ready.load(ordering: .relaxed) && index >= 0
        }
    }
}
