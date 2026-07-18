//
//  MockShareRepository.swift
//  MacLibraryTests
//
@testable import MacLibrary

/// A mock implementation of `ShareRepository` for unit testing.
final class MockShareRepository: ShareRepository {

    // MARK: - Stubs

    var shouldFail = false
    var errorToThrow: ShareError = .noAnchorView
    var stubbedResult = ShareResult(completed: true, serviceName: "Mail")
    var stubbedCanPerform = true

    // MARK: - Call Counts

    var presentPickerCallCount = 0
    var performServiceCallCount = 0
    var canPerformServiceCallCount = 0
    var lastContent: ShareContent?
    var lastServiceName: String?

    // MARK: - ShareRepository

    func presentPicker(content: ShareContent) async throws -> ShareResult {
        presentPickerCallCount += 1
        lastContent = content
        if shouldFail { throw errorToThrow }
        return stubbedResult
    }

    func performService(content: ShareContent, serviceName: String) async throws -> ShareResult {
        performServiceCallCount += 1
        lastContent = content
        lastServiceName = serviceName
        if shouldFail { throw errorToThrow }
        return stubbedResult
    }

    func canPerformService(content: ShareContent, serviceName: String) async throws -> Bool {
        canPerformServiceCallCount += 1
        lastContent = content
        lastServiceName = serviceName
        if shouldFail { throw errorToThrow }
        return stubbedCanPerform
    }
}
