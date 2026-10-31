//
//  ReadDataUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ReadDataUseCase")

/// Reads the raw `Data` for a given uniform type identifier (P-4).
@MainActor
public struct ReadDataUseCase {
    private let repository: ClipboardRepository
    private let typeValidator: ClipboardTypeIdentifierValidating

    public init(repository: ClipboardRepository, typeValidator: ClipboardTypeIdentifierValidating) {
        self.repository = repository
        self.typeValidator = typeValidator
    }

    public func execute(utType: String, scope: PasteboardScope) throws -> Data? {
        logger.log(level: .libraryDebug, "[execute] utType: \(utType, privacy: .private), scope: \(scope.redactedDescription, privacy: .public)")
        try typeValidator.validateGeneric(utType)
        return try repository.readData(utType: utType, scope: scope)
    }
}
