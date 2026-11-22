import XCTest

// Temporary probe for the ios-c-abi UI test design (Xcode facts). Removed after the experiment.

class FactProbeBase: XCTestCase {
    var gatePassed = false

    final override func setUpWithError() throws {
        continueAfterFailure = false
        let bundle = Bundle(for: FactProbeBase.self)
        let url = bundle.url(forResource: "FactProbe", withExtension: "json")
        print("NTKPROBE name=\(name) resource=\(url?.lastPathComponent ?? "nil")")
        if name.contains("testSkipped") {
            throw XCTSkip("NTK-GATED:probe")
        }
        gatePassed = true
    }

    override func tearDownWithError() throws {
        print("NTKPROBE tearDown name=\(name) gatePassed=\(gatePassed)")
    }
}

final class FactProbeTests: FactProbeBase {
    func testRuns() throws {
        print("NTKPROBE body testRuns")
    }

    func testSkipped() throws {
        print("NTKPROBE body testSkipped")
    }
}
