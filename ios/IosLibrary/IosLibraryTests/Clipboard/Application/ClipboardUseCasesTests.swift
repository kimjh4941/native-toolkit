//
//  ClipboardUseCasesTests.swift
//  IosLibraryTests
//
//  Covers the remaining, simpler UseCases (P-2〜P-10, P-12, P-15) not covered by
//  CopyContentUseCaseTests.
//

import Testing
import Foundation
@testable import IosLibrary

@Suite(.serialized)
@MainActor
struct ClipboardUseCasesTests {
    // A generous margin: under full-suite parallel execution, many other @MainActor tests
    // (several of which perform real, synchronous UIPasteboard system calls) can transiently
    // saturate the main actor's queue. This timeout exists only to bound the race in
    // ClipboardAsyncRaceCoordinator; the mock resolves near-instantly once scheduled.
    private static let generousTimeouts = ClipboardTimeouts(detection: 90, providerLoad: 90, imageCoding: 90)!

    // MARK: - AppendContentUseCase

    @Test func appendCallsRepositoryOnce() async throws {
        let repository = MockClipboardRepository()
        let useCase = AppendContentUseCase(repository: repository, typeValidator: MockClipboardTypeIdentifierValidating())
        try await useCase.execute(.plainText("hi"), scope: .general)
        #expect(repository.appendCallCount == 1)
    }

    // MARK: - ReadContentUseCase

    @Test func readReturnsStubbedResultWithoutThrowingWhenEmpty() throws {
        let repository = MockClipboardRepository()
        repository.stubbedReadResult = ClipboardReadResult(items: [], numberOfItems: 0)
        let useCase = ReadContentUseCase(repository: repository)
        let result = try useCase.execute(scope: .general)
        #expect(result.items.isEmpty)
    }

    // MARK: - ReadDataUseCase

    @Test func readDataReturnsStubbedData() throws {
        let repository = MockClipboardRepository()
        repository.stubbedData = Data([1, 2, 3])
        let useCase = ReadDataUseCase(repository: repository, typeValidator: MockClipboardTypeIdentifierValidating())
        let data = try useCase.execute(utType: "public.png", scope: .general)
        #expect(data == Data([1, 2, 3]))
        #expect(repository.readDataCallCount == 1)
    }

    @Test func readDataRejectsInvalidUTIBeforeCallingRepository() {
        let repository = MockClipboardRepository()
        let validator = MockClipboardTypeIdentifierValidating()
        validator.shouldFailGeneric = true
        let useCase = ReadDataUseCase(repository: repository, typeValidator: validator)
        #expect(throws: ClipboardError.self) {
            try useCase.execute(utType: "bad", scope: .general)
        }
        #expect(repository.readDataCallCount == 0)
    }

    @Test func readDataReturnsNilWhenAbsent() throws {
        let repository = MockClipboardRepository()
        repository.stubbedData = nil
        let useCase = ReadDataUseCase(repository: repository, typeValidator: MockClipboardTypeIdentifierValidating())
        let data = try useCase.execute(utType: "public.png", scope: .general)
        #expect(data == nil)
    }

    // MARK: - GetSnapshotUseCase

    @Test func snapshotPassesMatchingTypesThrough() throws {
        let repository = MockClipboardRepository()
        let useCase = GetSnapshotUseCase(repository: repository)
        _ = try useCase.execute(matchingTypes: ["public.png"], scope: .general)
        #expect(repository.lastMatchingTypes == ["public.png"])
    }

    @Test func snapshotWithoutMatchingTypesPassesNil() throws {
        let repository = MockClipboardRepository()
        let useCase = GetSnapshotUseCase(repository: repository)
        _ = try useCase.execute(matchingTypes: nil, scope: .general)
        #expect(repository.lastMatchingTypes == nil)
    }

    // MARK: - ClearClipboardUseCase

    @Test func clearCallsRepositoryOnce() throws {
        let repository = MockClipboardRepository()
        let useCase = ClearClipboardUseCase(repository: repository)
        try useCase.execute(scope: .general)
        #expect(repository.clearCallCount == 1)
    }

    // MARK: - CreatePasteboardUseCase

    @Test func createPasteboardRejectsBlankName() {
        let repository = MockClipboardRepository()
        let useCase = CreatePasteboardUseCase(repository: repository)
        #expect(throws: ClipboardError.invalidPasteboardName("  ")) {
            try useCase.execute(.named("  "))
        }
    }

    @Test func createPasteboardReturnsGeneratedUniqueScope() throws {
        let repository = MockClipboardRepository()
        repository.stubbedCreatedScope = .unique("generated-name")
        let useCase = CreatePasteboardUseCase(repository: repository)
        let scope = try useCase.execute(.unique)
        #expect(scope == .unique("generated-name"))
    }

    // MARK: - RemovePasteboardUseCase

    @Test func removeGeneralIsRejected() {
        let repository = MockClipboardRepository()
        let useCase = RemovePasteboardUseCase(repository: repository)
        #expect(throws: ClipboardError.cannotRemoveGeneralPasteboard) {
            try useCase.execute(.general)
        }
        #expect(repository.removePasteboardCallCount == 0)
    }

    @Test func removeNamedDelegatesToRepository() throws {
        let repository = MockClipboardRepository()
        let useCase = RemovePasteboardUseCase(repository: repository)
        try useCase.execute(.named("group.example"))
        #expect(repository.removePasteboardCallCount == 1)
    }

    // MARK: - DetectPatternsUseCase / DetectValuesUseCase

    @Test func detectPatternsRejectsEmptySet() async {
        let repository = MockClipboardRepository()
        let useCase = DetectPatternsUseCase(repository: repository)
        await #expect(throws: ClipboardError.emptyDetectionPatterns) {
            try await useCase.execute([], scope: .general)
        }
    }

    @Test func detectPatternsReturnsStubbedValue() async throws {
        let repository = MockClipboardRepository()
        repository.stubbedDetectedPatterns = [.probableWebURL]
        // A generous timeout avoids flakiness when many @MainActor tests contend for the main
        // actor under parallel test execution; the mock resolves near-instantly regardless.
        let useCase = DetectPatternsUseCase(repository: repository, timeouts: Self.generousTimeouts)
        let result = try await useCase.execute([.probableWebURL], scope: .general)
        #expect(result == [.probableWebURL])
    }

    @Test func detectValuesRejectsEmptySet() async {
        let repository = MockClipboardRepository()
        let useCase = DetectValuesUseCase(repository: repository)
        await #expect(throws: ClipboardError.emptyDetectionPatterns) {
            try await useCase.execute([], scope: .general)
        }
    }

    @Test func detectValuesReturnsAllElevenFieldsFromStub() async throws {
        let repository = MockClipboardRepository()
        let stub = ClipboardDetectedValues(
            detectedPatterns: [.number, .link],
            probableWebURL: nil, probableWebSearch: nil, number: 42,
            links: ["https://example.com"], emailAddresses: [], phoneNumbers: [],
            postalAddresses: [], calendarEvents: [], flightNumbers: [], moneyAmounts: [],
            shipmentTrackingNumbers: []
        )
        repository.stubbedDetectedValues = stub
        let useCase = DetectValuesUseCase(repository: repository, timeouts: Self.generousTimeouts)
        let result = try await useCase.execute([.number, .link], scope: .general)
        #expect(result.number == 42)
        #expect(result.links == ["https://example.com"])
        #expect(result.detectedPatterns == [.number, .link])
    }

    // MARK: - CancelAllLoadsUseCase

    @Test func cancelAllLoadsDelegatesToLoader() {
        let loader = MockClipboardItemLoader()
        let useCase = CancelAllLoadsUseCase(loader: loader)
        useCase.execute()
        #expect(loader.cancelAllCallCount == 1)
    }

    // MARK: - CheckForegroundChangeUseCase

    @Test func checkForegroundChangeResyncThenNoChange() {
        let repository = MockClipboardRepository()
        repository.stubbedChangeCount = 5
        let useCase = CheckForegroundChangeUseCase(repository: repository)
        useCase.resync(scope: .general)
        #expect(useCase.execute(scope: .general) == false)
    }

    @Test func checkForegroundChangeDetectsChange() {
        let repository = MockClipboardRepository()
        repository.stubbedChangeCount = 1
        let useCase = CheckForegroundChangeUseCase(repository: repository)
        useCase.resync(scope: .general)
        repository.stubbedChangeCount = 2
        #expect(useCase.execute(scope: .general) == true)
        #expect(useCase.execute(scope: .general) == false)
    }

    @Test func checkForegroundChangeMarkReportedPreventsDoubleReport() {
        let repository = MockClipboardRepository()
        repository.stubbedChangeCount = 1
        let useCase = CheckForegroundChangeUseCase(repository: repository)
        useCase.resync(scope: .general)
        repository.stubbedChangeCount = 2
        useCase.markReported(scope: .general)
        #expect(useCase.execute(scope: .general) == false)
    }
}
