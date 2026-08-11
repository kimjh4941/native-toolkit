//
//  ClipboardSampleViewTests.swift
//  IosLibraryExampleTests
//

import Foundation
import Testing
@testable import IosLibraryExample

/// Pins the contracts that the sample app's manual procedures and XCUITests rely on.
///
/// `ClipboardSampleView` is `@MainActor`-isolated, so its static members are too.
@MainActor
struct ClipboardSampleViewTests {

    // MARK: - Check Foreground Change display contract (design v6 §5.8 / U-12)

    @Test("The real return value is reported, never overwritten to false")
    func checkForegroundPayloadKeepsTheRealReturnValue() {
        #expect(
            ClipboardSampleView.checkForegroundPayload(changed: true, isFirstInThisView: true)
                == "changed=true (first check in this screen)"
        )
        #expect(
            ClipboardSampleView.checkForegroundPayload(changed: false, isFirstInThisView: true)
                == "changed=false (first check in this screen)"
        )
        #expect(ClipboardSampleView.checkForegroundPayload(changed: true, isFirstInThisView: false) == "changed=true")
        #expect(ClipboardSampleView.checkForegroundPayload(changed: false, isFirstInThisView: false) == "changed=false")
    }

    @Test("The note never asserts the manager's internal baseline state")
    func checkForegroundPayloadNeverClaimsManagerState() {
        for changed in [true, false] {
            for isFirst in [true, false] {
                let payload = ClipboardSampleView.checkForegroundPayload(changed: changed, isFirstInThisView: isFirst)
                #expect(!payload.contains("baseline"))
                #expect(!payload.contains("established"))
                #expect(!payload.contains("updated"))
            }
        }
    }

    // MARK: - M-16 / U-11 fixtures (design v6 §5.3 / §5.4 / §5.2)

    @Test("M-16 tells its three fixtures apart by character length alone")
    func m16FixturesHaveDistinctLengths() {
        #expect(ClipboardSampleView.localOnlyBody.count == 14)
        #expect(ClipboardSampleView.appendMarker.count == 24)
        #expect(ClipboardSampleView.deviceBBaseline.count == 31)

        let lengths = Set([
            ClipboardSampleView.localOnlyBody.count,
            ClipboardSampleView.appendMarker.count,
            ClipboardSampleView.deviceBBaseline.count
        ])
        #expect(lengths.count == 3)
    }

    @Test("The append marker stays 24 characters across invocations")
    func appendMarkerLengthIsStable() {
        for _ in 0..<20 {
            #expect(ClipboardSampleView.appendMarker.count == 24)
        }
    }

    @Test("U-11 asserts fileSize=64, so the fixture must be exactly 64 bytes")
    func fileFixtureIs64Bytes() {
        #expect(ClipboardSampleView.fileFixturePayload.count == 64)
    }

    @Test("The isolated fixtures contain nothing but their own pattern")
    func isolatedDetectionFixturesAreSingleValued() {
        // `number` / `probableWebSearch` appear to classify the whole clipboard, so these fixtures
        // must not carry anything else that could be extracted instead.
        #expect(ClipboardSampleView.numberFixture == "42")
        #expect(ClipboardSampleView.searchFixture == "swift concurrency")

        for fixture in [ClipboardSampleView.numberFixture, ClipboardSampleView.searchFixture] {
            #expect(!fixture.contains("http"))
            #expect(!fixture.contains("@"))
            #expect(!fixture.contains("\n"))
        }
    }

    @Test("The detection fixture carries the inputs for all 11 patterns")
    func detectionFixtureCoversEveryPattern() {
        let fixture = ClipboardSampleView.detectionFixture
        for token in [
            "https://www.apple.com",     // probableWebURL / link
            "support@example.com",       // emailAddress
            "+1 (408) 996-1010",         // phoneNumber
            "1 Infinite Loop",           // postalAddress
            "March 3, 2027",             // calendarEvent
            "AA100",                     // flightNumber
            "1,234.56 USD",              // moneyAmount
            "1Z999AA10123456784",        // shipmentTrackingNumber
            "swift concurrency",         // probableWebSearch
            "42"                         // number
        ] {
            #expect(fixture.contains(token), "detection fixture is missing \(token)")
        }
    }

    // MARK: - Identifier / marker contract (design v6 §4.5 / §9.1)

    @Test("Button identifiers are derived from the marker, so the two cannot drift apart")
    func buttonIdentifierIsDerivedFromTheMarker() {
        #expect(ClipboardSampleIdentifiers.button("read") == "clipboard.button.read")
        #expect(ClipboardSampleIdentifiers.section("copy") == "clipboard.section.copy")
        #expect(ClipboardSampleIdentifiers.result == "clipboard.result")
        #expect(ClipboardSampleIdentifiers.status == "clipboard.status")
        #expect(ClipboardSampleIdentifiers.pasteSummary == "clipboard.pasteSummary")
    }

    @Test("All 52 result markers and 2 control markers are distinct")
    func markersAreDistinct() {
        let resultMarkers = Self.allResultMarkers
        #expect(resultMarkers.count == 52)
        #expect(Set(resultMarkers).count == 52)

        let controlMarkers = [
            ClipboardSampleIdentifiers.ControlAction.cancelLoads,
            ClipboardSampleIdentifiers.ControlAction.mountPasteControl
        ]
        #expect(Set(resultMarkers).isDisjoint(with: Set(controlMarkers)))
    }

    private static let allResultMarkers: [String] = {
        typealias A = ClipboardSampleIdentifiers.Action
        return [
            A.useGeneral, A.createNamed, A.useFixedNamed, A.createUnique, A.removeActive, A.probeRemoved,
            A.copyPlainText, A.copyPlainTextEmpty, A.copyHtml, A.copyURL, A.copyImageFile, A.copyImageData,
            A.copyColor, A.copyCustomData, A.copyFileFixture, A.copyMultipleText, A.copyMultiRepresentation,
            A.copyDetectionFixture, A.copyNumberFixture, A.copySearchFixture,
            A.copyLocalOnlyTrue, A.copyLocalOnlyFalse, A.copyBBaseline, A.copyExpiring,
            A.appendPlainText, A.appendURL, A.appendUniversalMarker,
            A.read, A.readData, A.snapshot, A.snapshotMatching,
            A.loadText, A.loadURL, A.loadImage, A.loadFile,
            A.detectPatterns, A.detectValues,
            A.startObserving, A.stopObserving, A.checkForeground,
            A.clear,
            A.errMultipleEmpty, A.errMultiRepEmpty, A.errImageMissing, A.errCopyInvalidUTI, A.errInvalidURL,
            A.errInvalidColor, A.errReadInvalidUTI, A.errRemoveGeneral, A.errObserveMissing, A.errEmptyPatterns,
            A.errEmptyAcceptedTypes
        ]
    }()
}
