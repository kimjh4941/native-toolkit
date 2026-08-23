//
//  ClipboardUseCases.swift
//  IosLibrary
//

import Foundation

/// Aggregates every clipboard UseCase for convenient construction and injection into
/// `IosClipboardManager`.
@MainActor
public struct ClipboardUseCases {
    public let copyContent: CopyContentUseCase
    public let appendContent: AppendContentUseCase
    public let readContent: ReadContentUseCase
    public let readData: ReadDataUseCase
    public let getSnapshot: GetSnapshotUseCase
    public let clearClipboard: ClearClipboardUseCase
    public let createPasteboard: CreatePasteboardUseCase
    public let removePasteboard: RemovePasteboardUseCase
    public let detectPatterns: DetectPatternsUseCase
    public let detectValues: DetectValuesUseCase
    public let loadItem: LoadItemUseCase
    public let cancelAllLoads: CancelAllLoadsUseCase
    public let checkForegroundChange: CheckForegroundChangeUseCase

    public init(
        repository: ClipboardRepository,
        loader: ClipboardItemLoader,
        typeValidator: ClipboardTypeIdentifierValidating,
        contentValidator: ClipboardContentValidator = ClipboardContentValidator(),
        timeouts: ClipboardTimeouts = .default
    ) {
        self.copyContent = CopyContentUseCase(
            repository: repository, contentValidator: contentValidator, typeValidator: typeValidator
        )
        self.appendContent = AppendContentUseCase(
            repository: repository, contentValidator: contentValidator, typeValidator: typeValidator
        )
        self.readContent = ReadContentUseCase(repository: repository)
        self.readData = ReadDataUseCase(repository: repository, typeValidator: typeValidator)
        self.getSnapshot = GetSnapshotUseCase(repository: repository)
        self.clearClipboard = ClearClipboardUseCase(repository: repository)
        self.createPasteboard = CreatePasteboardUseCase(repository: repository)
        self.removePasteboard = RemovePasteboardUseCase(repository: repository)
        self.detectPatterns = DetectPatternsUseCase(repository: repository, timeouts: timeouts)
        self.detectValues = DetectValuesUseCase(repository: repository, timeouts: timeouts)
        self.loadItem = LoadItemUseCase(loader: loader)
        self.cancelAllLoads = CancelAllLoadsUseCase(loader: loader)
        self.checkForegroundChange = CheckForegroundChangeUseCase(repository: repository)
    }
}
