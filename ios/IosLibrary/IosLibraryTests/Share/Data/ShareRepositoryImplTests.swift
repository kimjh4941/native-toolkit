//
//  ShareRepositoryImplTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
@testable import IosLibrary

struct ShareRepositoryImplTests {

    // MARK: - URL validation

    @Test(arguments: [
        "https://example.com",
        "http://example.com",
        "file:///tmp/a.txt"
    ])
    func buildActivityItemsAcceptsValidURLs(value: String) throws {
        let repo = ShareRepositoryImpl()
        let content = ShareContent(items: [.url(value)])
        let items = try repo.buildActivityItems(from: content)
        #expect(items.count == 1)
        #expect(items[0] is URL)
    }

    @Test(arguments: [
        "",
        "   ",
        "example.com",
        "https://",
        "ftp://example.com"
    ])
    func buildActivityItemsRejectsInvalidURLs(value: String) {
        let repo = ShareRepositoryImpl()
        let content = ShareContent(items: [.url(value)])
        #expect(throws: ShareError.self) {
            try repo.buildActivityItems(from: content)
        }
    }

    // MARK: - File existence

    @Test func buildActivityItemsAcceptsExistingFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "test".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let repo = ShareRepositoryImpl()
        let content = ShareContent(items: [.file(path: tempURL.path)])
        let items = try repo.buildActivityItems(from: content)
        #expect(items.count == 1)
        #expect(items[0] is URL)
    }

    @Test func buildActivityItemsThrowsFileNotFoundForMissingFile() {
        let repo = ShareRepositoryImpl()
        let content = ShareContent(items: [.file(path: "/nonexistent/path/\(UUID().uuidString).pdf")])
        #expect(throws: ShareError.self) {
            try repo.buildActivityItems(from: content)
        }
    }

    // MARK: - Image loading

    @Test func buildActivityItemsThrowsImageLoadFailedForInvalidImage() {
        let repo = ShareRepositoryImpl()
        let content = ShareContent(items: [.imageFile(path: "/nonexistent/path/\(UUID().uuidString).png")])
        #expect(throws: ShareError.self) {
            try repo.buildActivityItems(from: content)
        }
    }

    // MARK: - Primary item replacement (no duplication)

    @Test func buildActivityItemsReplacesPrimaryItemWhenSubjectProvided() throws {
        let repo = ShareRepositoryImpl()
        let content = ShareContent(items: [.text("hello"), .text("world")], subject: "Subject")
        let items = try repo.buildActivityItems(from: content)
        #expect(items.count == 2)
        #expect(items[0] is ShareItemSource)
        #expect(items[1] is String)
    }

    @Test func buildActivityItemsReplacesPrimaryItemWhenPreviewTitleProvided() throws {
        let repo = ShareRepositoryImpl()
        let content = ShareContent(items: [.text("hello")], previewTitle: "Preview")
        let items = try repo.buildActivityItems(from: content)
        #expect(items.count == 1)
        #expect(items[0] is ShareItemSource)
    }

    @Test func buildActivityItemsDoesNotWrapWhenNoMetadataProvided() throws {
        let repo = ShareRepositoryImpl()
        let content = ShareContent(items: [.text("hello")])
        let items = try repo.buildActivityItems(from: content)
        #expect(items.count == 1)
        #expect(items[0] is String)
    }

    // MARK: - excludedActivityTypes conversion (via present())

    @Test func presentConvertsExcludedActivityTypesAndDelegatesToPresenter() async throws {
        let presenter = MockShareSheetPresenter()
        presenter.stubbedResult = ShareResult(completed: true, activityType: "x")
        let repo = ShareRepositoryImpl(presenter: presenter)
        let content = ShareContent(items: [.text("hello")],
                                   excludedActivityTypes: ["com.apple.UIKit.activity.PostToFacebook"])
        _ = try await repo.present(content: content)
        #expect(presenter.lastExcluded?.map { $0.rawValue } == ["com.apple.UIKit.activity.PostToFacebook"])
        #expect(presenter.lastItems?.count == 1)
    }
}
