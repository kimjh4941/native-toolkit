//
//  ClipboardUseCases.swift
//  MacLibrary
//

import Foundation

/// Every clipboard use case, assembled once and handed to the manager.
///
/// The aggregate exists so that ``MacClipboardManager`` takes one dependency instead of
/// seventeen, and so that the wiring order is expressed in a single place. It holds no state
/// and calls no port itself: it only builds the use cases and hands them out.
@MainActor
public struct ClipboardUseCases {

    private let TAG = "ClipboardUseCases"

    // MARK: Content

    /// OP-01. Replaces the pasteboard contents.
    public let copy: CopyContentUseCase
    /// OP-02. Adds items to a pasteboard this app still owns.
    public let append: AppendContentUseCase
    /// OP-03. Reads every item and representation.
    public let read: ReadContentUseCase
    /// OP-04. Reads the bytes for one type identifier.
    public let readData: ReadDataUseCase
    /// OP-05. Describes the types present without reading any payload.
    public let snapshot: GetSnapshotUseCase
    /// OP-06. Empties the pasteboard.
    public let clear: ClearClipboardUseCase

    // MARK: Pasteboard lifetime

    /// OP-07. Creates or fetches a pasteboard.
    public let createPasteboard: CreatePasteboardUseCase
    /// OP-08. Releases a pasteboard's server side resources.
    public let removePasteboard: RemovePasteboardUseCase

    // MARK: Detection

    /// OP-09. Reports which patterns the pasteboard matches.
    public let detectPatterns: DetectPatternsUseCase
    /// OP-10. Reads the matched values themselves.
    public let detectValues: DetectValuesUseCase
    /// OP-11. Reads limited metadata.
    public let detectMetadata: DetectMetadataUseCase
    /// OP-12. Current pasteboard access behaviour.
    public let accessBehavior: GetAccessBehaviorUseCase

    // MARK: Observation

    /// OP-15. One-shot change check for returning to the foreground.
    public let checkForegroundChange: CheckForegroundChangeUseCase
    /// Shared with the polling monitor so both see the same last observed change count.
    public let changeTracker: ClipboardChangeTracker

    // MARK: File promises

    /// OP-16. Promises a file without producing its bytes yet.
    public let provideFilePromise: ProvideFilePromiseUseCase
    /// OP-17. Releases a file promise registration.
    public let releaseFilePromise: ReleaseFilePromiseUseCase
    /// OP-18. Starts receiving files another app has promised.
    public let receiveFilePromises: ReceiveFilePromisesUseCase
    /// OP-20. Ends a receive session early.
    public let cancelReceiveFilePromises: CancelReceiveFilePromisesUseCase

    /// Builds every use case from the four ports.
    ///
    /// - Parameter limits: Size thresholds for the content validator. Injectable so tests can
    ///   use small values without allocating large payloads.
    public init(repository: any ClipboardRepository,
                registry: any ClipboardPromiseRegistry,
                snapshotter: any FilePromiseSnapshotting,
                typeValidator: any ClipboardTypeIdentifierValidating,
                limits: ClipboardLimits = .default) {
        Log.d("ClipboardUseCases", "[init] limits: \(limits.maxTotalBytes)")
        let validator = ClipboardContentValidator(limits: limits, typeValidator: typeValidator)
        let tracker = ClipboardChangeTracker()

        self.copy = CopyContentUseCase(repository: repository, registry: registry,
                                       validator: validator)
        self.append = AppendContentUseCase(repository: repository, validator: validator)
        self.read = ReadContentUseCase(repository: repository)
        self.readData = ReadDataUseCase(repository: repository)
        self.snapshot = GetSnapshotUseCase(repository: repository)
        self.clear = ClearClipboardUseCase(repository: repository)

        self.createPasteboard = CreatePasteboardUseCase(repository: repository)
        self.removePasteboard = RemovePasteboardUseCase(repository: repository)

        self.detectPatterns = DetectPatternsUseCase(repository: repository)
        self.detectValues = DetectValuesUseCase(repository: repository)
        self.detectMetadata = DetectMetadataUseCase(repository: repository)
        self.accessBehavior = GetAccessBehaviorUseCase(repository: repository)

        self.changeTracker = tracker
        self.checkForegroundChange = CheckForegroundChangeUseCase(repository: repository,
                                                                  tracker: tracker)

        self.provideFilePromise = ProvideFilePromiseUseCase(repository: repository,
                                                            registry: registry,
                                                            snapshotter: snapshotter,
                                                            typeValidator: typeValidator)
        self.releaseFilePromise = ReleaseFilePromiseUseCase(registry: registry)
        self.receiveFilePromises = ReceiveFilePromisesUseCase(repository: repository,
                                                              registry: registry)
        self.cancelReceiveFilePromises = CancelReceiveFilePromisesUseCase(registry: registry)
    }
}
