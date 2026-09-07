//
//  ClipboardPasteReceiverViewTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import IosLibrary

/// Verifies the aggregate callback truth table (D-4) and, in particular, the separation the
/// design draws between the *internal* completion (exactly-once, `.cancelled` included, U-84) and
/// the *UI* callbacks (never fired on cancellation, U-90).
@MainActor
struct ClipboardPasteReceiverViewTests {

    private final class Recorder {
        var pasted: [[ClipboardLoadedItem]] = []
        var partialFailures: [[ClipboardError]] = []
        var failures: [ClipboardError] = []
        var order: [String] = []
    }

    private func makeView(acceptedTypes: [String] = [UTType.plainText.identifier]) -> (ClipboardPasteReceiverView, Recorder) {
        let view = ClipboardPasteReceiverView(
            acceptedTypes: acceptedTypes,
            loader: PasteItemProviderLoader(fileStore: ClipboardTemporaryFileStore(sessionID: UUID().uuidString))
        )
        let recorder = Recorder()
        view.onPaste = { recorder.pasted.append($0); recorder.order.append("paste") }
        view.onPartialFailure = { recorder.partialFailures.append($0); recorder.order.append("partial") }
        view.onPasteFailure = { recorder.failures.append($0); recorder.order.append("failure") }
        return (view, recorder)
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    @Test func allSuccessCallsOnPasteOnce() async {
        let (view, recorder) = makeView()
        view.paste(itemProviders: [NSItemProvider(object: "a" as NSString)])
        await settle()
        #expect(recorder.pasted == [[.text("a")]])
        #expect(recorder.partialFailures.isEmpty)
        #expect(recorder.failures.isEmpty)
    }

    @Test func partialSuccessCallsOnPasteThenOnPartialFailure() async {
        let (view, recorder) = makeView()
        view.paste(itemProviders: [NSItemProvider(object: "a" as NSString), NSItemProvider()])
        await settle()
        #expect(recorder.pasted == [[.text("a")]])
        #expect(recorder.partialFailures.count == 1)
        #expect(recorder.order == ["paste", "partial"])
    }

    @Test func allFailuresCallOnPasteFailureOnce() async {
        let (view, recorder) = makeView()
        view.paste(itemProviders: [NSItemProvider(), NSItemProvider()])
        await settle()
        #expect(recorder.pasted.isEmpty)
        #expect(recorder.failures.count == 1)
    }

    @Test func emptyProviderListCallsOnPasteFailureWithNoMatchingItem() async {
        // U-89: the loader reports "no items, no failures"; the mapping onto `.noMatchingItem`
        // happens here.
        let (view, recorder) = makeView()
        view.paste(itemProviders: [])
        await settle()
        #expect(recorder.failures == [.noMatchingItem])
        #expect(recorder.pasted.isEmpty)
    }

    @Test func cancellationNeverSurfacesAsAUICallback() async {
        // U-90: the internal completion receives `.cancelled` (asserted in the loader tests), but
        // none of the three UI callbacks may fire.
        let (view, recorder) = makeView()
        view.paste(itemProviders: [NSItemProvider(object: "a" as NSString)])
        view.cancelPendingLoad()
        await settle()
        #expect(recorder.order.isEmpty)
    }

    @Test func releasingTheReceiverCleansUpPendingFileLoads() async throws {
        // The raw `PasteControlFactory.makeComponents` path has no container to cancel on
        // teardown, so releasing the receiver alone must still cancel the load and leave no
        // temporary file — and must not fire a UI callback while doing so (U-90).
        let fileStore = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).bin")
        try Data(repeating: 0x41, count: 64).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let recorder = Recorder()
        var view: ClipboardPasteReceiverView? = ClipboardPasteReceiverView(
            acceptedTypes: [UTType.data.identifier],
            loader: PasteItemProviderLoader(fileStore: fileStore)
        )
        view?.onPaste = { recorder.pasted.append($0); recorder.order.append("paste") }
        view?.onPartialFailure = { recorder.partialFailures.append($0); recorder.order.append("partial") }
        view?.onPasteFailure = { recorder.failures.append($0); recorder.order.append("failure") }
        view?.paste(itemProviders: [Self.delayedFileProvider(source, delay: 1.0)])
        view = nil

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(recorder.order.isEmpty)
        let remaining = try? FileManager.default.contentsOfDirectory(
            at: fileStore.sessionDirectory, includingPropertiesForKeys: nil
        )
        #expect((remaining ?? []).isEmpty)
    }

    private static func delayedFileProvider(_ url: URL, delay: TimeInterval) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all
        ) { handler in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                handler(url, true, nil)
            }
            return nil
        }
        return provider
    }

    @Test func consecutivePastesOnlyReportTheLatestSession() async {
        let (view, recorder) = makeView()
        view.paste(itemProviders: [NSItemProvider(object: "first" as NSString)])
        view.paste(itemProviders: [NSItemProvider(object: "second" as NSString)])
        await settle()
        // The superseded session is cancelled, so only the second paste reaches the UI.
        #expect(recorder.pasted == [[.text("second")]])
        #expect(recorder.failures.isEmpty)
    }
}
