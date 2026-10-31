// Stage 1a prototype: XCTest for the C ABI, run normally, under ASan and under TSan.
// Lines starting with "STAGE1A:" are the measured values copied into the working notes.
import Foundation
import IosLibraryCApi
import ObjectiveC
import UIKit
import XCTest

/// Everything one request reports. Shared with the C callbacks through user_data.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var callbackCount = 0
    private(set) var releaseCount = 0
    private(set) var callbackOnMain = false
    private(set) var releaseOnMain = false
    private(set) var releaseAfterCallback = false
    private(set) var callbackBeforeReturn = false
    private(set) var releaseThread: Thread?
    private(set) var error: Int32 = -1
    private(set) var requestId: UInt64 = 0
    private(set) var bytes: [UInt8]?
    private var returned = false
    let expectation: XCTestExpectation?

    init(_ expectation: XCTestExpectation? = nil) { self.expectation = expectation }

    var pointer: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
    static func from(_ p: UnsafeMutableRawPointer?) -> Recorder { Unmanaged.fromOpaque(p!).takeUnretainedValue() }

    func markReturned() { lock.withLock { returned = true } }

    func onCallback(requestId: UInt64, error: Int32, text: OpaquePointer?) {
        lock.withLock {
            callbackCount += 1
            callbackOnMain = Thread.isMainThread
            callbackBeforeReturn = !returned
            self.requestId = requestId
            self.error = error
            if let text, let data = ntk_string_data(text) {
                bytes = Array(UnsafeRawBufferPointer(start: data, count: ntk_string_size(text)))
            }
        }
        ntk_string_free(text)
    }

    func onRelease() {
        lock.withLock {
            releaseCount += 1
            releaseOnMain = Thread.isMainThread
            releaseThread = Thread.current
            releaseAfterCallback = callbackCount == 1
        }
        expectation?.fulfill()
    }
}

let textCallback: ntk_probe_text_fn = { userData, requestId, error, _, text in
    Recorder.from(userData).onCallback(requestId: requestId, error: error, text: text)
}
let releaseCallback: ntk_release_fn = { userData in Recorder.from(userData).onRelease() }

private let pasteboardName = UIPasteboard.Name("com.jonghyunkim.nativetoolkit.stage1a.probe")

private func probePasteboard() -> UIPasteboard { UIPasteboard(name: pasteboardName, create: true)! }

private func hex(_ bytes: [UInt8]?) -> String { bytes.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") } ?? "nil" }

final class IosLibraryCApiTests: XCTestCase {

    func testVersionAndLastSystemCode() {
        XCTAssertEqual(ntk_version(), 0x020000)
        XCTAssertEqual(ntk_version(), UInt32(NTK_VERSION))
        XCTAssertEqual(ntk_last_system_code(), 0)
    }

    private func echo(size: UInt32, text: UnsafePointer<CChar>?, uppercase: Int32 = 0) -> (Int32, String?) {
        var request = ntk_probe_echo_request()
        request.struct_size = size
        request.text = text
        request.uppercase = uppercase
        var out: OpaquePointer?
        let error = ntk_probe_echo(&request, &out)
        defer { ntk_string_free(out) }
        return (error, out.flatMap { ntk_string_data($0) }.map { String(cString: $0) })
    }

    func testStructSize() {
        let size = UInt32(MemoryLayout<ntk_probe_echo_request>.size)
        XCTAssertEqual(size, 24)
        XCTAssertEqual(MemoryLayout<ntk_probe_echo_request>.offset(of: \.text), 8)
        XCTAssertEqual(MemoryLayout<ntk_probe_echo_request>.offset(of: \.uppercase), 16)
        "h\u{E9}llo".withCString { text in
            XCTAssertEqual(echo(size: size, text: text, uppercase: 1).1, "H\u{C9}LLO")
            XCTAssertEqual(echo(size: 0, text: text).0, Int32(NTK_PROBE_ERROR_INVALID_PARAMETER))
            XCTAssertEqual(echo(size: size - 1, text: text).0, Int32(NTK_PROBE_ERROR_INVALID_PARAMETER))
        }
        XCTAssertEqual(echo(size: size, text: nil).1, "")
        XCTAssertEqual(ntk_probe_echo(nil, nil), Int32(NTK_PROBE_ERROR_INVALID_PARAMETER))

        // A newer caller: a larger struct whose tail the library must not read past its known prefix.
        let big = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { big.deallocate() }
        big.initializeMemory(as: UInt8.self, repeating: 0xAB, count: 64)
        "x".withCString { text in
            var head = ntk_probe_echo_request()
            head.struct_size = 64
            head.text = text
            big.storeBytes(of: head, as: ntk_probe_echo_request.self)
            var out: OpaquePointer?
            XCTAssertEqual(ntk_probe_echo(big.assumingMemoryBound(to: ntk_probe_echo_request.self), &out), 0)
            XCTAssertEqual(String(cString: ntk_string_data(out)!), "x")
            ntk_string_free(out)
        }
    }

    func testInvalidUTF8IsRejected() {
        let size = UInt32(MemoryLayout<ntk_probe_echo_request>.size)
        for bad in [[0xC3, 0x28], [0xED, 0xA0, 0x80], [0xC0, 0xAF], [0xFF]] as [[UInt8]] {
            let cString = bad.map { CChar(bitPattern: $0) } + [0]
            cString.withUnsafeBufferPointer {
                XCTAssertEqual(echo(size: size, text: $0.baseAddress).0, Int32(NTK_PROBE_ERROR_INVALID_PARAMETER), hex(bad))
            }
        }
    }

    /// The probe sets a sentinel on a failure; the value must not leak to other threads.
    func testLastSystemCodeIsPerThread() {
        let size = UInt32(MemoryLayout<ntk_probe_echo_request>.size)
        let bad: [CChar] = [CChar(bitPattern: 0xFF), 0]
        let mainBefore = ntk_last_system_code()   // whatever earlier tests left on the main thread
        let group = DispatchGroup()
        let results = NSMutableDictionary()
        for index in 0..<8 {
            group.enter()
            Thread {
                bad.withUnsafeBufferPointer { buffer in
                    if index % 2 == 0 { _ = self.echo(size: size, text: buffer.baseAddress) } else { _ = self.echo(size: size, text: nil) }
                }
                usleep(20_000)
                let value = ntk_last_system_code()
                objc_sync_enter(results); results[index] = value; objc_sync_exit(results)
                group.leave()
            }.start()
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        for index in 0..<8 {
            XCTAssertEqual(results[index] as? UInt32, index % 2 == 0 ? 0xE0F : 0, "thread \(index)")
        }
        XCTAssertEqual(ntk_last_system_code(), mainBefore)
        print("STAGE1A: last_system_code main = \(mainBefore), per thread = \(results)")
    }

    private func readText(from thread: String) -> Recorder {
        let recorder = Recorder(expectation(description: "release \(thread)"))
        var requestId: UInt64 = 0
        let start = { [recorder] in
            let error = ntk_probe_clipboard_read_text_async(textCallback, recorder.pointer, releaseCallback, &requestId)
            recorder.markReturned()
            XCTAssertEqual(error, 0)
        }
        if thread == "main" { start() } else { DispatchQueue.global().async(execute: start) }
        wait(for: [recorder.expectation!], timeout: 5)
        return recorder
    }

    func testCallbackIsQueuedOnMainAndReleasedOnce() {
        probePasteboard().string = "stage1a"
        for thread in ["main", "background"] {
            let r = readText(from: thread)
            XCTAssertEqual(r.callbackCount, 1, thread)
            XCTAssertEqual(r.releaseCount, 1, thread)
            XCTAssertTrue(r.callbackOnMain, thread)
            XCTAssertTrue(r.releaseOnMain, thread)
            XCTAssertTrue(r.releaseAfterCallback, thread)
            XCTAssertFalse(r.callbackBeforeReturn, thread)
            XCTAssertEqual(r.error, 0, thread)
            XCTAssertEqual(r.bytes, Array("stage1a".utf8), thread)
            XCTAssertGreaterThan(r.requestId, 0)
        }
    }

    func testRejectedCallReleasesOnCallingThreadBeforeReturning() {
        let done = expectation(description: "background")
        DispatchQueue.global().async {
            let r = Recorder()
            let error = ntk_probe_clipboard_read_text_async(nil, r.pointer, releaseCallback, nil)
            XCTAssertEqual(error, Int32(NTK_PROBE_ERROR_INVALID_PARAMETER))
            XCTAssertEqual(r.releaseCount, 1)
            XCTAssertEqual(r.releaseThread, Thread.current)
            XCTAssertFalse(r.releaseOnMain)
            XCTAssertEqual(r.callbackCount, 0)
            // release == NULL is allowed.
            XCTAssertEqual(ntk_probe_clipboard_read_text_async(nil, nil, nil, nil), Int32(NTK_PROBE_ERROR_INVALID_PARAMETER))
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    /// Many threads at once (the TSan target): each request ends with one callback and one release.
    func testConcurrentRequests() {
        probePasteboard().string = "concurrent"
        let threads = 8, perThread = 25
        var recorders: [Recorder] = []
        for _ in 0..<(threads * perThread) { recorders.append(Recorder(expectation(description: "r"))) }
        let ids = NSMutableSet()
        DispatchQueue.concurrentPerform(iterations: threads) { t in
            for i in 0..<perThread {
                let r = recorders[t * perThread + i]
                var id: UInt64 = 0
                XCTAssertEqual(ntk_probe_clipboard_read_text_async(textCallback, r.pointer, releaseCallback, &id), 0)
                r.markReturned()
                objc_sync_enter(ids); ids.add(id); objc_sync_exit(ids)
            }
        }
        waitForExpectations(timeout: 20)
        XCTAssertEqual(ids.count, threads * perThread)
        XCTAssertTrue(recorders.allSatisfy { $0.callbackCount == 1 && $0.releaseCount == 1 && $0.callbackOnMain && $0.releaseAfterCallback })
    }

    /// NSString may hold unpaired surrogates and U+0000; the C ABI must hand out well-formed UTF-8.
    func testUnpairedSurrogatesAndNulBecomeReplacementCharacters() {
        let units: [unichar] = [0x41, 0xD800, 0x42, 0x0000, 0x43, 0xDC00, 0x44]
        let ns = NSString(characters: units, length: units.count)
        let utf8String = ns.utf8String
        print("STAGE1A: NSString.utf8String = \(utf8String.map { hex(Array(UnsafeRawBufferPointer(start: $0, count: strlen($0)))) } ?? "NULL")")
        print("STAGE1A: NSString.lengthOfBytes(utf8) = \(ns.lengthOfBytes(using: String.Encoding.utf8.rawValue))")
        print("STAGE1A: NSString.data(using: utf8) = \(hex(ns.data(using: String.Encoding.utf8.rawValue).map(Array.init)))")
        print("STAGE1A: Swift String(ns).utf8 = \(hex(Array(String(ns).utf8)))")

        // UIPasteboard.string refuses such a string (saving fails), so the data is placed the way
        // another app could place it: as raw UTF-16 / UTF-8 representations.
        let raw16 = units.withUnsafeBytes { Data($0) }   // little-endian, no BOM
        let cases: [(String, Data)] = [
            ("public.utf16-plain-text", raw16),
            ("public.utf16-external-plain-text", Data([0xFF, 0xFE]) + raw16),
            ("public.utf8-plain-text", Data([0x41, 0xED, 0xA0, 0x80, 0x42, 0x00, 0x43, 0xFF, 0x44])),
        ]
        for (type, data) in cases {
            let pb = probePasteboard()
            pb.items = []
            pb.setData(data, forPasteboardType: type)
            let back = pb.string.map { Array(($0 as NSString).utf16Units) }
            print("STAGE1A: [\(type)] UIPasteboard.string UTF-16 = \(back.map { $0.map { String(format: "%04X", $0) }.joined(separator: " ") } ?? "nil")")
            let value = pb.items.first?[type]
            let valueUnits = (value as? NSString).map { $0.utf16Units.map { String(format: "%04X", $0) }.joined(separator: " ") } ?? "not a string"
            print("STAGE1A: [\(type)] items value = \(value.map { String(describing: Swift.type(of: $0)) } ?? "nil"), UTF-16 = \(valueUnits)")
            let r = readText(from: "main")
            print("STAGE1A: [\(type)] C ABI error = \(r.error), bytes = \(hex(r.bytes))")
            if let bytes = r.bytes {
                XCTAssertNotNil(String(validating: bytes, as: UTF8.self), type)
                XCTAssertFalse(bytes.contains(0), type)
            }
        }
        let pb = probePasteboard()
        pb.items = []
        // IosLibrary reads pasteboard.items as String; only the BOM form arrives as a string.
        pb.setData(Data([0xFF, 0xFE]) + raw16, forPasteboardType: "public.utf16-external-plain-text")
        XCTAssertEqual(readText(from: "main").bytes, [0x41, 0xEF, 0xBF, 0xBD, 0x42, 0xEF, 0xBF, 0xBD, 0x43, 0xEF, 0xBF, 0xBD, 0x44])
    }

    func testNullHandlesAreSafe() {
        ntk_string_free(nil)
        ntk_bytes_free(nil)
        ntk_string_list_free(nil)
        XCTAssertNil(ntk_string_data(nil))
        XCTAssertEqual(ntk_string_size(nil), 0)
        XCTAssertNil(ntk_string_list_at(nil, 0, nil))
    }

    /// D-11 (2): which Objective-C classes the IosLibraryCApi image registers.
    func testObjectiveCClassesOfTheImage() {
        var info = Dl_info()
        let symbol = unsafeBitCast(ntk_version as @convention(c) () -> UInt32, to: UnsafeRawPointer.self)
        XCTAssertNotEqual(dladdr(symbol, &info), 0)
        let image = String(cString: info.dli_fname)
        var count: UInt32 = 0
        let names = objc_copyClassNamesForImage(info.dli_fname, &count)
        let list = (0..<Int(count)).map { String(cString: names![$0]) }
        free(names)
        print("STAGE1A: image = \(URL(fileURLWithPath: image).lastPathComponent), objc classes = \(list)")
    }
}

private extension NSString {
    var utf16Units: [unichar] { (0..<length).map { character(at: $0) } }
}
