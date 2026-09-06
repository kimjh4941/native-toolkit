//
//  DetectionUseCaseTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("Detection use cases")
@MainActor
struct DetectionUseCaseTests {

    @Test("detectPatterns rejects an empty request before reaching the port")
    func detectPatternsRejectsEmpty() async throws {
        let repository = MockClipboardRepository()
        let useCase = DetectPatternsUseCase(repository: repository)
        // An empty request would answer "nothing found", which is indistinguishable from a
        // genuine negative result.
        await #expect(throws: ClipboardError.emptyDetectionPatterns) {
            _ = try await useCase([], scope: .general)
        }
    }

    @Test("detectValues rejects an empty request")
    func detectValuesRejectsEmpty() async throws {
        let repository = MockClipboardRepository()
        let useCase = DetectValuesUseCase(repository: repository)
        await #expect(throws: ClipboardError.emptyDetectionPatterns) {
            _ = try await useCase([], scope: .general)
        }
    }

    @Test("detectPatterns forwards a non empty request")
    func detectPatternsForwards() async throws {
        let repository = MockClipboardRepository()
        let useCase = DetectPatternsUseCase(repository: repository)
        _ = try await useCase([.emailAddresses], scope: .general)
    }

    @Test("detectPatterns propagates unavailability below macOS 15.4")
    func detectPatternsPropagatesUnavailable() async throws {
        let repository = MockClipboardRepository()
        repository.shouldFail = .detectionUnavailable(minimumOS: "15.4")
        let useCase = DetectPatternsUseCase(repository: repository)

        await #expect(throws: ClipboardError.detectionUnavailable(minimumOS: "15.4")) {
            _ = try await useCase([.emailAddresses], scope: .general)
        }
    }

    @Test("detectValues propagates a denial")
    func detectValuesPropagatesDenial() async throws {
        let repository = MockClipboardRepository()
        repository.shouldFail = .detectionDenied
        let useCase = DetectValuesUseCase(repository: repository)

        await #expect(throws: ClipboardError.detectionDenied) {
            _ = try await useCase([.links], scope: .general)
        }
    }

    @Test("detectMetadata takes no pattern set and forwards directly")
    func detectMetadataForwards() async throws {
        let repository = MockClipboardRepository()
        let useCase = DetectMetadataUseCase(repository: repository)
        let metadata = try await useCase(scope: .general)
        #expect(metadata.metadataTypes.isEmpty)
    }

    @Test("accessBehavior reports unavailability as a value, not an error")
    func accessBehaviorReturnsUnavailable() throws {
        let repository = MockClipboardRepository()
        let useCase = GetAccessBehaviorUseCase(repository: repository)
        // Below macOS 15.4 not knowing the behaviour is a normal state (M-2).
        #expect(try useCase(scope: .general) == .unavailable)
    }

    @Test("accessBehavior propagates an unresolvable scope")
    func accessBehaviorPropagatesInvalidScope() throws {
        let repository = MockClipboardRepository()
        repository.shouldFail = .invalidPasteboardName("")
        let useCase = GetAccessBehaviorUseCase(repository: repository)

        #expect(throws: ClipboardError.invalidPasteboardName("")) {
            _ = try useCase(scope: .named(""))
        }
    }

    @Test("checkForegroundChange reports the first look as a change")
    func foregroundFirstLookIsAChange() throws {
        let repository = MockClipboardRepository()
        repository.stubbedChangeCount = 5
        let useCase = CheckForegroundChangeUseCase(repository: repository,
                                                   tracker: ClipboardChangeTracker())
        #expect(try useCase(scope: .general))
    }

    @Test("checkForegroundChange reports no change when the count is unmoved")
    func foregroundUnchanged() throws {
        let repository = MockClipboardRepository()
        repository.stubbedChangeCount = 5
        let useCase = CheckForegroundChangeUseCase(repository: repository,
                                                   tracker: ClipboardChangeTracker())
        _ = try useCase(scope: .general)
        #expect(!(try useCase(scope: .general)))

        repository.stubbedChangeCount = 6
        #expect(try useCase(scope: .general))
    }

    @Test("checkForegroundChange shares its tracker with the aggregate")
    func foregroundSharesTracker() throws {
        let repository = MockClipboardRepository()
        repository.stubbedChangeCount = 5
        let tracker = ClipboardChangeTracker()
        let useCase = CheckForegroundChangeUseCase(repository: repository, tracker: tracker)

        // The polling monitor records into the same tracker, so a change already seen there
        // must not be reported again here.
        tracker.hasChanged(scope: .general, changeCount: 5)
        #expect(!(try useCase(scope: .general)))
    }
}
