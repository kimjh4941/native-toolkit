//
//  CopyContentUseCase.swift
//  IosLibrary
//

import Foundation

/// Validates and writes `content` to the clipboard, replacing existing items (P-1).
@MainActor
public struct CopyContentUseCase {
    private let TAG = "CopyContentUseCase"
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

    public func execute(
        _ content: ClipboardContent,
        options: ClipboardCopyOptions,
        scope: PasteboardScope
    ) async throws {
        Log.d(TAG, "[execute] scope: \(scope), localOnly: \(options.localOnly)")
        try contentValidator.validate(content)
        try contentValidator.validateExpirationDate(options.expirationDate)
        try validateTypeIdentifiers(of: content)
        try await repository.copy(content, options: options, scope: scope)
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
