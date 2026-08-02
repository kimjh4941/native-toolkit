//
//  CopyContentUseCaseTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
@testable import IosLibrary

@MainActor
struct CopyContentUseCaseTests {
    private func makeUseCase(
        repository: MockClipboardRepository,
        typeValidator: MockClipboardTypeIdentifierValidating
    ) -> CopyContentUseCase {
        CopyContentUseCase(repository: repository, typeValidator: typeValidator)
    }

    @Test func executeCallsRepositoryOnce() async throws {
        let repository = MockClipboardRepository()
        let validator = MockClipboardTypeIdentifierValidating()
        let useCase = makeUseCase(repository: repository, typeValidator: validator)
        try await useCase.execute(.plainText("hi"), options: .default, scope: .general)
        #expect(repository.copyCallCount == 1)
        #expect(repository.lastCopyOptions == .default)
    }

    @Test func executeRejectsInvalidContentBeforeCallingRepository() async {
        let repository = MockClipboardRepository()
        let validator = MockClipboardTypeIdentifierValidating()
        let useCase = makeUseCase(repository: repository, typeValidator: validator)
        await #expect(throws: ClipboardError.self) {
            try await useCase.execute(.multipleText([]), options: .default, scope: .general)
        }
        #expect(repository.copyCallCount == 0)
    }

    @Test func executeRejectsInvalidTypeIdentifierBeforeCallingRepository() async {
        let repository = MockClipboardRepository()
        let validator = MockClipboardTypeIdentifierValidating()
        validator.shouldFailGeneric = true
        let useCase = makeUseCase(repository: repository, typeValidator: validator)
        await #expect(throws: ClipboardError.self) {
            try await useCase.execute(.customData(Data([1]), utType: "bad"), options: .default, scope: .general)
        }
        #expect(repository.copyCallCount == 0)
        #expect(validator.validateGenericCallCount == 1)
    }

    @Test func executePropagatesRepositoryError() async {
        let repository = MockClipboardRepository()
        repository.shouldFail = true
        let validator = MockClipboardTypeIdentifierValidating()
        let useCase = makeUseCase(repository: repository, typeValidator: validator)
        await #expect(throws: ClipboardError.self) {
            try await useCase.execute(.plainText("hi"), options: .default, scope: .general)
        }
    }
}
