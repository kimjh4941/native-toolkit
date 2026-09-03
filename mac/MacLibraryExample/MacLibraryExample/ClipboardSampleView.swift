//
//  ClipboardSampleView.swift
//  MacLibraryExample
//

import SwiftUI
import AppKit
import MacLibrary

/// Exercises every public operation of `MacClipboardManager` from the native library alone.
///
/// The sample imports `MacLibrary` and never `UnityMacPlugin` (common.md). AppKit appears only
/// to host the paste button `MacClipboardManager` hands back (OP-19); no clipboard operation is
/// performed against AppKit directly.
struct ClipboardSampleView: View {

    private let TAG = "ClipboardSampleView"

    private let sampleName = "nt-sample"
    private let acceptedPasteTypes = ["public.utf8-plain-text", "public.png"]

    @State private var resultText = "Result will be displayed here"
    @State private var activeScope: PasteboardScope = .general
    /// The named pasteboard `CreateNamedPasteboard` made, while it exists.
    @State private var createdNamed: PasteboardScope?
    /// The unique pasteboard `CreateUniquePasteboard` made, while it exists.
    @State private var createdUnique: PasteboardScope?
    /// Counts the results the screen has shown, so a test can tell a new one from a repeat.
    @State private var resultSequence = 0
    @State private var localOnly = true
    /// The ownership the last copy returned, for `AppendWithLastOwnership`.
    @State private var lastOwnership: PasteboardOwnership?
    @State private var isObserving = false
    @State private var reachedCodes: Set<Int> = []
    @State private var pasteButton: NSView?
    @State private var pasteButtonError: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("MacClipboardManager Example")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 8)

            Text(resultText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)
                .accessibilityIdentifier("clipboard.result")
                // The counter travels with the text. Read separately, the two could come from
                // either side of a new result, and the pair that slipped through was the one
                // the counter exists to reject (R-SA24).
                .accessibilityValue("#\(resultSequence) \(resultText)")

            HStack {
                Picker("Active scope", selection: scopeSelection) {
                    Text("general").tag(ScopeChoice.general)
                    Text("named").tag(ScopeChoice.named)
                    Text("unique").tag(ScopeChoice.unique)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .accessibilityIdentifier("clipboard.scopePicker")

                Text("Active scope: \(scopeLabel)")
                    .accessibilityIdentifier("clipboard.activeScope")
                Text("#\(resultSequence)")
                    .accessibilityIdentifier("clipboard.resultSequence")
                Spacer()
                Text(isObserving ? "Observing" : "Not observing")
                    .foregroundColor(isObserving ? .green : .secondary)
                    .accessibilityIdentifier("clipboard.observeStatus")
            }
            .font(.caption)
            .padding(.horizontal)

            ScrollView {
                VStack(spacing: 16) {
                    scopeSection
                    copySection
                    copyOptionsSection
                    appendSection
                    readSection
                    detectSection
                    observeSection
                    pasteControlSection
                    clearSection
                    errorCasesSection
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .navigationTitle("Clipboard Example")
        .onAppear(perform: buildPasteButton)
        .onDisappear(perform: teardown)
    }

    /// Which kind of pasteboard the operations that take a scope should use.
    enum ScopeChoice: Hashable { case general, named, unique }

    /// The picker's selection, derived from `activeScope` rather than stored beside it.
    ///
    /// A second stored property would have to be pushed back into step after every operation
    /// that moves the scope, and `onChange` cannot tell that assignment from a click: the
    /// picker's own action would run on top of the operation that just finished (R-SA5).
    /// Deriving the value removes the second copy, so there is nothing to put back.
    private var scopeSelection: Binding<ScopeChoice> {
        Binding(get: { choice(for: activeScope) }, set: { selectScope($0) })
    }

    private func choice(for scope: PasteboardScope) -> ScopeChoice {
        switch scope {
        case .general: return .general
        case .named: return .named
        case .unique: return .unique
        // The library may add a kind the sample predates; the picker then shows general.
        @unknown default: return .general
        }
    }

    /// Points the active scope at a pasteboard that already exists.
    ///
    /// The picker only selects; it never creates. `createPasteboard` belongs to the buttons in
    /// section 1, so choosing a pasteboard nobody has made yet is reported and refused rather
    /// than quietly making a second one and orphaning the first (R-SA9).
    private func selectScope(_ choice: ScopeChoice) {
        Log.d(TAG, "[selectScope] choice: \(choice)")
        switch choice {
        case .general:
            activeScope = .general
            updateResult(.success(label: "scopePicker", detail: "active scope is now general"))
        case .named:
            select(created: createdNamed, kind: "named")
        case .unique:
            select(created: createdUnique, kind: "unique")
        }
    }

    private func select(created scope: PasteboardScope?, kind: String) {
        Log.d(TAG, "[select] kind: \(kind), exists: \(scope != nil)")
        guard let scope else {
            updateResult(.otherFailure(
                label: "scopePicker",
                description: "no \(kind) pasteboard exists yet; create one in section 1"))
            return
        }
        activeScope = scope
        updateResult(.success(label: "scopePicker", detail: "active scope is now \(kind)"))
    }

    // MARK: - 1. Scope

    private var scopeSection: some View {
        sectionView(title: "1. Scope", identifier: "scope") {
            Text("A named or unique pasteboard is not released when this screen goes away. "
                 + "Use RemoveCurrentPasteboard; creating a unique one releases the previous.")
                .font(.caption)
                .foregroundColor(.secondary)
            sampleButton("CreateNamedPasteboard") { _ in
                Task { await runScopeCreating(label: "createNamedPasteboard",
                                              request: .named(sampleName)) }
            }
            sampleButton("CreateUniquePasteboard") { _ in
                Task { await runScopeCreating(label: "createUniquePasteboard", request: .unique) }
            }
            sampleButton("RemoveCurrentPasteboard") { inputs in
                let scope = inputs.scope
                Task { await removeCurrentPasteboard(label: "removeCurrentPasteboard",
                                                     scope: scope) }
            }
            sampleButton("RemoveGeneral") { _ in
                Task {
                    await runExpectingError(label: "removeGeneral", expected: 1508) {
                        try await MacClipboardManager.shared.removePasteboard(.general)
                    }
                }
            }
            sampleButton("CreateEmptyNamedPasteboard") { _ in
                Task {
                    await runExpectingError(label: "createEmptyNamedPasteboard", expected: 1505) {
                        _ = try await MacClipboardManager.shared.createPasteboard(.named(""))
                    }
                }
            }
        }
    }

    // MARK: - 2. Copy

    private var copySection: some View {
        sectionView(title: "2. Copy", identifier: "copy") {
            sampleButton("CopyText") { inputs in
                let scope = inputs.scope
                Task { await copy("copyText", ClipboardSampleFixtures.text(), scope: scope) }
            }
            sampleButton("CopyURL") { inputs in
                let scope = inputs.scope
                Task { await copy("copyURL", ClipboardSampleFixtures.url(), scope: scope) }
            }
            sampleButton("CopyImage") { inputs in
                let scope = inputs.scope
                Task { await copy("copyImage", ClipboardSampleFixtures.png(), scope: scope) }
            }
            sampleButton("CopyMultipleItems") { inputs in
                let scope = inputs.scope
                Task { await copy("copyMultipleItems", ClipboardSampleFixtures.multipleItems(),
                                  scope: scope) }
            }
            sampleButton("CopyMultipleRepresentations") { inputs in
                let scope = inputs.scope
                Task { await copy("copyMultipleRepresentations",
                                  ClipboardSampleFixtures.multipleRepresentations(),
                                  scope: scope) }
            }
            sampleButton("CopyPartialPasteContent") { inputs in
                let scope = inputs.scope
                Task { await copy("copyPartialPasteContent",
                                  ClipboardSampleFixtures.partialPasteContent(),
                                  scope: scope) }
            }
            sampleButton("CopyEmpty") { inputs in
                let scope = inputs.scope
                Task {
                    await runExpectingError(label: "copyEmpty", expected: 1501) {
                        _ = try await MacClipboardManager.shared.copy(
                            ClipboardSampleFixtures.empty(), scope: scope)
                    }
                }
            }
            sampleButton("CopyEmptyRepresentations") { inputs in
                let scope = inputs.scope
                Task {
                    await runExpectingError(label: "copyEmptyRepresentations", expected: 1502) {
                        _ = try await MacClipboardManager.shared.copy(
                            ClipboardSampleFixtures.emptyRepresentations(), scope: scope)
                    }
                }
            }
        }
    }

    // MARK: - 3. Copy Options

    private var copyOptionsSection: some View {
        sectionView(title: "3. Copy Options", identifier: "copyOptions") {
            Toggle("localOnly", isOn: $localOnly)
                .toggleStyle(.switch)
                .accessibilityIdentifier("clipboard.toggle.localOnly")
            sampleButton("CopyWithCurrentOptions") { inputs in
                let scope = inputs.scope
                let options = inputs.options
                Task {
                    await run(label: "copyWithCurrentOptions") {
                        let ownership = try await MacClipboardManager.shared.copy(
                            ClipboardSampleFixtures.text(), options: options, scope: scope)
                        lastOwnership = ownership
                        return "localOnly=\(options.localOnly), changeCount=\(ownership.changeCount)"
                    }
                }
            }
        }
    }

    // MARK: - 4. Append

    private var appendSection: some View {
        sectionView(title: "4. Append", identifier: "append") {
            Text("Append follows the ownership the preceding copy returned, not the active "
                 + "scope: the operation takes no scope of its own.")
                .font(.caption)
                .foregroundColor(.secondary)
            sampleButton("CopyThenAppend") { inputs in
                let scope = inputs.scope
                Task {
                    await run(label: "copyThenAppend") {
                        let ownership = try await MacClipboardManager.shared.copy(
                            ClipboardSampleFixtures.text(), scope: scope)
                        let appended = try await MacClipboardManager.shared.append(
                            ClipboardSampleFixtures.text("appended"), ownership: ownership)
                        return "changeCount=\(appended.changeCount)"
                    }
                }
            }
            sampleButton("AppendWithLastOwnership") { inputs in
                // MT-03 asks that append fails plainly when another app has taken the
                // pasteboard since the copy. Only a person can produce that: copy here, copy
                // in another app, then press this. Nothing in the sample can invalidate the
                // ownership from outside, so this reports whatever happens rather than
                // declaring an expected failure (R-SA26).
                Task {
                    guard let ownership = inputs.lastOwnership else {
                        updateResult(.otherFailure(label: "appendWithLastOwnership",
                                                   description: "copy something first"))
                        return
                    }
                    await run(label: "appendWithLastOwnership") {
                        let appended = try await MacClipboardManager.shared.append(
                            ClipboardSampleFixtures.text("late"), ownership: ownership)
                        lastOwnership = appended
                        return "changeCount=\(appended.changeCount)"
                    }
                }
            }
            sampleButton("AppendWithStaleOwnership") { inputs in
                let scope = inputs.scope
                Task {
                    // The first copy's ownership is invalidated by the second one.
                    //
                    // The setup is an arrange, and a failed arrange means there is nothing to
                    // append to. Its error goes through the one reporting path so the code
                    // survives and reaches the error list, as the Detect arrange does; `try?`
                    // turned every one of them into the same fixed sentence (R-SA18).
                    let stale: PasteboardOwnership
                    do {
                        stale = try await MacClipboardManager.shared.copy(
                            ClipboardSampleFixtures.text("first"), scope: scope)
                        _ = try await MacClipboardManager.shared.copy(
                            ClipboardSampleFixtures.text("second"), scope: scope)
                    } catch {
                        reportFailure(label: "appendWithStaleOwnership", error: error)
                        return
                    }
                    await runExpectingError(label: "appendWithStaleOwnership", expected: 1511) {
                        _ = try await MacClipboardManager.shared.append(
                            ClipboardSampleFixtures.text("late"), ownership: stale)
                    }
                }
            }
        }
    }

    // MARK: - 5. Read / Inspect

    private var readSection: some View {
        sectionView(title: "5. Read / Inspect", identifier: "read") {
            sampleButton("Read") { inputs in
                let scope = inputs.scope
                Task {
                    await run(label: "read") {
                        let result = try await MacClipboardManager.shared.read(scope: scope)
                        // Per item, not just a total. Two devices telling their fixtures apart
                        // need each item's own text length: a sum across items and across the
                        // flavors AppKit adds cannot say which item is which (R-SA27).
                        let described = result.items.enumerated().map { index, item in
                            "\(index):\(Self.describe(item))"
                        }
                        return "items=\(result.items.count), "
                            + "bytes=\(result.items.reduce(0) { $0 + $1.totalBytes }), "
                            + "[\(described.joined(separator: " / "))]"
                    }
                }
            }
            sampleButton("ReadDataPlainText") { inputs in
                let scope = inputs.scope
                Task {
                    await run(label: "readDataPlainText") {
                        let data = try await MacClipboardManager.shared.readData(
                            utType: ClipboardSampleFixtures.plainTextType, scope: scope)
                        // The value itself is never shown; only whether it was there and how big.
                        return data.map { "present, bytes=\($0.count)" } ?? "no such type (success)"
                    }
                }
            }
            sampleButton("Snapshot") { inputs in
                let scope = inputs.scope
                Task {
                    await run(label: "snapshot") {
                        let snapshot = try await MacClipboardManager.shared.snapshot(scope: scope)
                        return "items=\(snapshot.itemTypes.count), changeCount=\(snapshot.changeCount)"
                    }
                }
            }
            sampleButton("SnapshotFiltered") { inputs in
                let scope = inputs.scope
                Task {
                    await run(label: "snapshotFiltered") {
                        let snapshot = try await MacClipboardManager.shared.snapshot(
                            matchingTypes: [ClipboardSampleFixtures.plainTextType], scope: scope)
                        return "matching=\(snapshot.matchingItemIndexes.count) of \(snapshot.itemTypes.count)"
                    }
                }
            }
            sampleButton("SnapshotEmptyFilter") { inputs in
                let scope = inputs.scope
                Task {
                    await runExpectingError(label: "snapshotEmptyFilter", expected: 1512) {
                        _ = try await MacClipboardManager.shared.snapshot(matchingTypes: [],
                                                                          scope: scope)
                    }
                }
            }
            sampleButton("AccessBehavior") { inputs in
                let scope = inputs.scope
                runSync(label: "accessBehavior") {
                    let behavior = try MacClipboardManager.shared.accessBehavior(scope: scope)
                    return "\(behavior)"
                }
            }
        }
    }

    // MARK: - 6. Detect

    private var detectSection: some View {
        sectionView(title: "6. Detect", identifier: "detect") {
            sampleButton("DetectPatterns") { inputs in
                let scope = inputs.scope
                Task {
                    do {
                        try await arrangeDetectionText(scope: scope)
                    } catch {
                        // Named for the arrange, so the screen says which half failed. The
                        // sibling DetectMetadata already did this; the two now agree (R-SA21).
                        reportFailure(label: "detectPatternsArrange", error: error)
                        return
                    }
                    await run(label: "detectPatterns") {
                        let found = try await MacClipboardManager.shared.detectPatterns(
                            ClipboardSampleFixtures.detectionPatterns, scope: scope)
                        return "found=[\(found.map(\.rawValue).sorted().joined(separator: ", "))]"
                    }
                }
            }
            sampleButton("DetectValues") { inputs in
                let scope = inputs.scope
                Task {
                    do {
                        try await arrangeDetectionText(scope: scope)
                    } catch {
                        // Named for the arrange, so the screen says which half failed. The
                        // sibling DetectMetadata already did this; the two now agree (R-SA21).
                        reportFailure(label: "detectValuesArrange", error: error)
                        return
                    }
                    await run(label: "detectValues") {
                        let values = try await MacClipboardManager.shared.detectValues(
                            ClipboardSampleFixtures.detectionPatterns, scope: scope)
                        // Counts and presence only. The detected values are the payload.
                        return "patterns=\(values.patterns.count), links=\(values.links.count), "
                            + "emails=\(values.emailAddresses.count), "
                            + "probableWebURL=\(values.probableWebURL != nil)"
                    }
                }
            }
            sampleButton("DetectMetadata") { inputs in
                let scope = inputs.scope
                Task {
                    // The arrange decides what is being detected. Swallowing its failure would
                    // check whatever happened to be on the pasteboard already.
                    do {
                        try await arrangePlainText(scope: scope)
                    } catch {
                        // The arrange decides what is being detected, so a failed arrange means
                        // there is nothing to detect. Its error goes through the one reporting
                        // path, keeping the code rather than replacing it with a fixed line.
                        reportFailure(label: "detectMetadata", error: error)
                        return
                    }
                    await runExpectingError(label: "detectMetadata", expected: 1515) {
                        _ = try await MacClipboardManager.shared.detectMetadata(scope: scope)
                    }
                }
            }
            sampleButton("DetectEmptyPatterns") { inputs in
                let scope = inputs.scope
                Task {
                    await runExpectingError(label: "detectEmptyPatterns", expected: 1503) {
                        _ = try await MacClipboardManager.shared.detectPatterns([], scope: scope)
                    }
                }
            }
        }
    }

    // MARK: - 7. Observe

    private var observeSection: some View {
        sectionView(title: "7. Observe", identifier: "observe") {
            sampleButton("StartObserving") { inputs in
                let scope = inputs.scope
                runSync(label: "startObserving") {
                    try MacClipboardManager.shared.startObserving(scope: scope) { event in
                        updateResult(.success(label: "observed",
                                              detail: "changeCount=\(event.changeCount)"))
                    }
                    isObserving = true
                    return "started"
                }
            }
            sampleButton("StartObservingInvalidInterval") { inputs in
                let scope = inputs.scope
                runSyncExpectingError(label: "startObservingInvalidInterval", expected: 1523) {
                    try MacClipboardManager.shared.startObserving(scope: scope,
                                                                  interval: 0) { _ in }
                }
            }
            sampleButton("StopObserving") { _ in
                MacClipboardManager.shared.stopObserving()
                isObserving = false
                updateResult(.success(label: "stopObserving", detail: "stopped"))
            }
            sampleButton("CheckForegroundChange") { inputs in
                let scope = inputs.scope
                runSync(label: "checkForegroundChange") {
                    "changed=\(try MacClipboardManager.shared.checkForegroundChange(scope: scope))"
                }
            }
        }
    }

    // MARK: - 8. Paste Control

    private var pasteControlSection: some View {
        sectionView(title: "8. Paste Control", identifier: "pasteControl") {
            Text("The button is general scope only, and stays enabled whether or not the "
                 + "pasteboard holds an accepted type.")
                .font(.caption)
                .foregroundColor(.secondary)
            if let pasteButton {
                PasteButtonHost(view: pasteButton)
                    .frame(height: 32)
                    .accessibilityIdentifier("clipboard.pasteButton")
            } else {
                Text(pasteButtonError ?? "The paste button could not be built.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            sampleButton("MakePasteButtonInvalidType") { _ in
                runSyncExpectingError(label: "makePasteButtonInvalidType", expected: 1504) {
                    _ = try MacClipboardManager.shared.makePasteButton(
                        acceptedTypes: ["not a uti"], timeout: 5) { _ in }
                }
            }
            sampleButton("MakePasteButtonUndeclaredType") { _ in
                runSyncExpectingError(label: "makePasteButtonUndeclaredType", expected: 1504) {
                    _ = try MacClipboardManager.shared.makePasteButton(
                        acceptedTypes: ["com.mycompany.myformat"], timeout: 5) { _ in }
                }
            }
        }
    }

    // MARK: - 9. Clear

    private var clearSection: some View {
        sectionView(title: "9. Clear", identifier: "clear") {
            sampleButton("Clear") { inputs in
                let scope = inputs.scope
                Task {
                    await run(label: "clear") {
                        // The value is the pasteboard's new change count, not a number of
                        // items: `clearContents()` reports the former. Calling it "removed"
                        // said something the operation never returns (R-SA25).
                        "changeCount=\(try await MacClipboardManager.shared.clear(scope: scope))"
                    }
                }
            }
        }
    }

    // MARK: - 10. Error Cases

    private var errorCasesSection: some View {
        sectionView(title: "10. Error Cases", identifier: "errorCases") {
            Text(reachedCodes.isEmpty
                 ? "No error code reached yet."
                 : "Reached: \(reachedCodes.sorted().map(String.init).joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("clipboard.reachedCodes")
            sampleButton("ExpectFailureThatSucceeds") { inputs in
                let scope = inputs.scope
                Task {
                    // A copy that works, declared as if it had to fail. The screen must call
                    // this a failure: the contract it was checked against did not hold.
                    await runExpectingError(label: "expectFailureThatSucceeds", expected: 1501) {
                        _ = try await MacClipboardManager.shared.copy(
                            ClipboardSampleFixtures.text(), scope: scope)
                    }
                }
            }
            sampleButton("ResetReachedCodes") { _ in
                reachedCodes = []
                updateResult(.success(label: "resetReachedCodes", detail: "cleared"))
            }
        }
    }

    // MARK: - Operations

    /// The plain copies of section 2, which demonstrate `copy` with the library's defaults.
    ///
    /// Passing the Copy Options toggle here made every ordinary copy change behaviour with a
    /// control that belongs to another section, so the two demonstrations were not separable
    /// (R-SA19). Section 3 is where the options are shown.
    private func copy(_ label: String, _ content: ClipboardContent,
                      scope: PasteboardScope) async {
        await run(label: label) {
            let ownership = try await MacClipboardManager.shared.copy(content, scope: scope)
            lastOwnership = ownership
            return "changeCount=\(ownership.changeCount)"
        }
    }

    private func runScopeCreating(label: String, request: PasteboardCreationRequest) async {
        await run(label: label) {
            // A unique pasteboard gets a new name every time, so creating a second one while
            // the first is still open would leave the first with no handle on this screen and
            // no way to release it. The library requires an explicit release, so naming the
            // orphan in the result was not enough (R-SA17).
            //
            // Releasing first, not last: a release that fails is then reported on its own,
            // instead of being buried under the success of the creation that followed it.
            let note = try await releasePrevious(for: request)
            let scope = try await MacClipboardManager.shared.createPasteboard(request)
            if case .named = scope { createdNamed = scope } else { createdUnique = scope }
            activeScope = scope
            return "active scope is now \(scopeLabel)" + note
        }
    }

    /// Releases the unique pasteboard this request is about to replace, if there is one.
    ///
    /// **Only unique.** A named pasteboard is addressed by a name the sample chooses, so
    /// asking for it again fetches the same one with its contents intact -- that is the
    /// "creates *or fetches*" half of the operation. Releasing it made a second press of
    /// `CreateNamedPasteboard` throw the contents away without saying so (R-SA20). A unique
    /// one gets a new system name every time, so the previous handle would be lost.
    private func releasePrevious(for request: PasteboardCreationRequest) async throws -> String {
        Log.d(TAG, "[releasePrevious]")
        if case .named = request { return "" }
        guard let previous = createdUnique else { return "" }
        // The scope moves off the doomed pasteboard before the call, but the handle is kept
        // until the release succeeds: dropping it first would lose a resource that is still
        // there if the release throws.
        activeScope = .general
        try await MacClipboardManager.shared.removePasteboard(previous)
        createdUnique = nil
        return "; released the previous unique pasteboard"
    }

    private func removeCurrentPasteboard(label: String, scope removed: PasteboardScope) async {
        await run(label: label) {
            try await MacClipboardManager.shared.removePasteboard(removed)
            if case .named = removed { createdNamed = nil } else { createdUnique = nil }
            activeScope = .general
            return "removed; active scope is now general"
        }
    }

    /// Puts the detection fixture on the pasteboard so a detect call has a fixed subject.
    private func arrangeDetectionText(scope: PasteboardScope) async throws {
        _ = try await MacClipboardManager.shared.copy(
            ClipboardSampleFixtures.text(ClipboardSampleFixtures.detectionText), scope: scope)
    }

    private func arrangePlainText(scope: PasteboardScope) async throws {
        _ = try await MacClipboardManager.shared.copy(ClipboardSampleFixtures.text(),
                                                       scope: scope)
    }

    private func buildPasteButton() {
        Log.d(TAG, "[buildPasteButton]")
        // Built once. makePasteButton registers a loader, so calling it per re-evaluation
        // would pile registrations up (sample plan section 5.4).
        guard pasteButton == nil else { return }
        do {
            pasteButton = try MacClipboardManager.shared.makePasteButton(
                acceptedTypes: acceptedPasteTypes, timeout: 5) { result in
                    let detail = "items=\(result.items.count), failures=\(result.failures.count), "
                        + "partial=\(result.isPartial)"
                    updateResult(.success(label: "onPaste", detail: detail))
                }
        } catch let error as ClipboardError {
            pasteButtonError = "errorCode=\(error.errorCode)"
            reportFailure(label: "makePasteButton", error: error)
        } catch {
            pasteButtonError = error.localizedDescription
            updateResult(.otherFailure(label: "makePasteButton",
                                       description: error.localizedDescription))
        }
    }

    private func teardown() {
        Log.d(TAG, "[teardown] observing: \(isObserving)")
        // The manager is shared, so observation outlives this view unless it is stopped here.
        MacClipboardManager.shared.stopObserving()
        isObserving = false
    }

    // MARK: - Runners

    private func run(label: String, _ body: () async throws -> String) async {
        Log.d(TAG, "[run] label: \(label)")
        do {
            updateResult(.success(label: label, detail: try await body()))
        } catch {
            reportFailure(label: label, error: error)
        }
    }

    /// The synchronous operations report through the same rules as the asynchronous ones.
    private func runSync(label: String, _ body: () throws -> String) {
        Log.d(TAG, "[runSync] label: \(label)")
        do {
            updateResult(.success(label: label, detail: try body()))
        } catch {
            reportFailure(label: label, error: error)
        }
    }

    /// The one way a thrown error reaches the screen.
    ///
    /// Section 10 lists the error codes the run has reached. While only the expected-failure
    /// buttons recorded them, a 1513 or 1514 met by an ordinary operation was shown and then
    /// left out of the list the screen calls "reached" (R-SA10).
    private func reportFailure(label: String, error: Error) {
        Log.d(TAG, "[reportFailure] label: \(label)")
        guard let clipboardError = error as? ClipboardError else {
            updateResult(.otherFailure(label: label, description: error.localizedDescription))
            return
        }
        reachedCodes.insert(clipboardError.errorCode)
        updateResult(.clipboardFailure(label: label, code: clipboardError.errorCode,
                                       message: clipboardError.errorMessage))
    }

    /// For a call that is supposed to fail. Succeeding is itself a failure.
    private func runExpectingError(label: String, expected: Int,
                                   _ body: () async throws -> Void) async {
        Log.d(TAG, "[runExpectingError] label: \(label), expected: \(expected)")
        var actual: Int?
        // Whether the code is one the library produced. A code invented here to stand for
        // "something else went wrong" must not join the list of codes the run has reached
        // (R-SA22): the screen would name a contract nothing exercised.
        var fromTheLibrary = false
        do {
            try await body()
        } catch let error as ClipboardError {
            actual = error.errorCode
            fromTheLibrary = true
        } catch {
            actual = ClipboardError.unknown("").errorCode
        }
        report(label: label, recordCode: fromTheLibrary,
               verdict: ExpectedErrorJudge.verdict(expected: expected, actualCode: actual))
    }

    private func runSyncExpectingError(label: String, expected: Int, _ body: () throws -> Void) {
        Log.d(TAG, "[runSyncExpectingError] label: \(label), expected: \(expected)")
        var actual: Int?
        // Whether the code is one the library produced. A code invented here to stand for
        // "something else went wrong" must not join the list of codes the run has reached
        // (R-SA22): the screen would name a contract nothing exercised.
        var fromTheLibrary = false
        do {
            try body()
        } catch let error as ClipboardError {
            actual = error.errorCode
            fromTheLibrary = true
        } catch {
            actual = ClipboardError.unknown("").errorCode
        }
        report(label: label, recordCode: fromTheLibrary,
               verdict: ExpectedErrorJudge.verdict(expected: expected, actualCode: actual))
    }

    private func report(label: String, recordCode: Bool, verdict: ExpectedErrorVerdict) {
        if recordCode, case .matched(let code) = verdict { reachedCodes.insert(code) }
        if recordCode, case .differentCode(_, let actual) = verdict { reachedCodes.insert(actual) }
        updateResult(verdict.isSuccess
                     ? .success(label: label, detail: verdict.detail)
                     : .otherFailure(label: label, description: verdict.detail))
    }

    /// One item as its index, its text length and the types it carries.
    ///
    /// The text length is the size of the plain text representation alone, which is what
    /// identifies a fixture across devices. The value itself is never shown (section 3.4).
    private static func describe(_ item: ClipboardItemData) -> String {
        let plainText = item.representations[ClipboardSampleFixtures.plainTextType]
        let text = plainText.map { "text=\($0.count)B" } ?? "text=none"
        return "\(text) \(item.representations.keys.sorted().joined(separator: "|"))"
    }

    // MARK: - Display

    private var scopeLabel: String {
        switch activeScope {
        case .general: return "general"
        case .named: return "named"
        case .unique: return "unique"
        @unknown default: return "unknown"
        }
    }

    private func updateResult(_ outcome: SampleOutcome) {
        Log.d(TAG, "[updateResult] \(outcome.logText)")
        DispatchQueue.main.async {
            resultText = outcome.displayText
            // A test cannot tell a repeat of the same operation from a click that did nothing
            // by reading the text alone, because the text is identical (R-SA11).
            resultSequence += 1
        }
    }

    /// A section button, identified by its own name, handed the inputs it was clicked with.
    ///
    /// The identifier is derived from the label so the two cannot drift, and so the UI tests
    /// select by identifier rather than by display text (sample plan section 7.2).
    ///
    /// **The capture happens here, once, for every button.** Each body used to read the
    /// screen's state itself, which was only correct as long as every one of them read it
    /// before suspending -- a property a scan of the source can check for the names it knows,
    /// and that a single computed property put out of its reach (R-SA23). Passing the values
    /// in leaves the bodies with nothing to read at the wrong moment.
    private func sampleButton(_ name: String,
                              action: @escaping (SampleInputs) -> Void) -> some View {
        Button(name) {
            action(SampleInputs(scope: activeScope,
                                options: ClipboardCopyOptions(localOnly: localOnly),
                                lastOwnership: lastOwnership))
        }
        .accessibilityIdentifier("clipboard.button.\(name)")
    }

    @ViewBuilder
    private func sectionView<Content: View>(title: String, identifier: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
                .buttonStyle(ClipboardSampleButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        // Without this the section's identifier is pushed onto every button inside it, and
        // the buttons' own identifiers never reach the tests (R-SA15).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clipboard.section.\(identifier)")
    }
}

/// What a button was clicked with.
///
/// Taken from the screen at the moment of the click and handed to the body, so that no body
/// can read a value that changed while it was suspended.
struct SampleInputs {
    let scope: PasteboardScope
    let options: ClipboardCopyOptions
    let lastOwnership: PasteboardOwnership?
}

private struct ClipboardSampleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(configuration.isPressed ? Color.blue.opacity(0.65) : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}

#Preview {
    ClipboardSampleView()
}
