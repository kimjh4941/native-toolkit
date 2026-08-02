//
//  ReadDataUseCase.swift
//  IosLibrary
//

import Foundation

/// Reads the raw `Data` for a given uniform type identifier (P-4).
@MainActor
public struct ReadDataUseCase {
    private let TAG = "ReadDataUseCase"
    private let repository: ClipboardRepository
    private let typeValidator: ClipboardTypeIdentifierValidating

    public init(repository: ClipboardRepository, typeValidator: ClipboardTypeIdentifierValidating) {
        self.repository = repository
        self.typeValidator = typeValidator
    }

    public func execute(utType: String, scope: PasteboardScope) throws -> Data? {
        Log.d(TAG, "[execute] utType: \(utType), scope: \(scope)")
        try typeValidator.validateGeneric(utType)
        return try repository.readData(utType: utType, scope: scope)
    }
}
