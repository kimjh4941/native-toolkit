//
//  FailureDetailTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
@testable import IosLibrary

/// UT-06: `FailureDetail` keeps the domain and the code only (design 6.3.5, S-P7).
struct FailureDetailTests {

    private static let secret = "sentinel-localized-description-7c1e"

    private enum SampleError: Error {
        case first
        case second(String)
    }

    @Test func keepsTheDomainAndTheCodeOfAnNSError() {
        let error = NSError(domain: "com.example.domain", code: 42, userInfo: [NSLocalizedDescriptionKey: Self.secret])
        let detail = FailureDetail(systemError: error)

        #expect(detail == FailureDetail(domain: "com.example.domain", code: 42))
        #expect(detail.domain == "com.example.domain")
        #expect(detail.code == 42)
    }

    @Test func keepsNothingElse() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [
            NSLocalizedDescriptionKey: Self.secret,
            NSFilePathErrorKey: "/private/\(Self.secret)",
        ])
        let detail = FailureDetail(systemError: error)

        // Only two stored values, and neither the description nor the user info shows up.
        #expect(Mirror(reflecting: detail).children.map(\.label) == ["domain", "code"])
        #expect(!String(describing: detail).contains(Self.secret))
        #expect(!String(reflecting: detail).contains(Self.secret))
    }

    @Test func bridgesASwiftErrorAsSwiftDoes() {
        let detail = FailureDetail(systemError: SampleError.second(Self.secret))
        let bridged = SampleError.second(Self.secret) as NSError

        #expect(detail.domain == bridged.domain)
        #expect(detail.code == bridged.code)
        #expect(!String(describing: detail).contains(Self.secret))
    }

    @Test func equalityComparesDomainAndCode() {
        #expect(FailureDetail(domain: "a", code: 1) == FailureDetail(domain: "a", code: 1))
        #expect(FailureDetail(domain: "a", code: 1) != FailureDetail(domain: "a", code: 2))
        #expect(FailureDetail(domain: "a", code: 1) != FailureDetail(domain: "b", code: 1))
    }
}
