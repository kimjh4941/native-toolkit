//
//  AppendContentUseCase.swift
//  IosLibrary
//

import Foundation

/// Validates and appends `content` to the existing clipboard items (P-2).
///
/// Cannot carry privacy options: `UIPasteboard.addItems(_:)` has no options overload, and
/// whether privacy options set by a prior `copy` are inherited by the newly appended item is not
/// guaranteed by the system. Sensitive data should use `CopyContentUseCase` instead.
@MainActor
public struct AppendContentUseCase {
    private let TAG = "AppendContentUseCase"
    private let repository: ClipboardRepository
    private let contentValidator: ClipboardContentValidator
    private let typeValidator: ClipboardTypeIdentifierValidating

    public init(
        repository: ClipboardRepository,
        contentValidator: ClipboardContentValidator = ClipboardContentValidator(),
        typeValidator: ClipboardTypeIdentifierValidating
    ) {
        self.repository = repository
        self.contentValidator = contentValidator
        self.typeValidator = typeValidator
    }

    public func execute(_ content: ClipboardContent, scope: PasteboardScope) async throws {
        Log.d(TAG, "[execute] scope: \(scope.redactedDescription)")
        try contentValidator.validate(content)
        try validateTypeIdentifiers(of: content)
        try await repository.append(content, scope: scope)
    }

    private func validateTypeIdentifiers(of content: ClipboardContent) throws {
        switch content {
        case .imageData(_, let utType):
            try typeValidator.validateImage(utType)
        case .customData(_, let utType):
            try typeValidator.validateGeneric(utType)
        case .multiRepresentation(let representations):
            for key in representations.keys {
                try typeValidator.validateGeneric(key)
            }
        default:
            break
        }
    }
}
