import SwiftUI
import UIKit
import IosLibrary

/// Single source of truth for the accessibility identifiers exposed by `ClipboardSampleView`.
///
/// The `<action>` suffix of a button identifier is reused verbatim as the operation marker shown
/// in the result line, so the marker and the identifier can never drift apart.
enum ClipboardSampleIdentifiers {

    static let result = "clipboard.result"
    static let status = "clipboard.status"
    static let pasteSummary = "clipboard.pasteSummary"

    static func section(_ name: String) -> String { "clipboard.section.\(name)" }
    static func button(_ action: String) -> String { "clipboard.button.\(action)" }

    /// Markers of every operation that writes a result line (50 entries).
    enum Action {
        // Scope
        static let useGeneral = "useGeneral"
        static let createNamed = "createNamed"
        static let useFixedNamed = "useFixedNamed"
        static let createUnique = "createUnique"
        static let removeActive = "removeActive"
        static let probeRemoved = "probeRemoved"
        // Copy
        static let copyPlainText = "copyPlainText"
        static let copyPlainTextEmpty = "copyPlainTextEmpty"
        static let copyHtml = "copyHtml"
        static let copyURL = "copyURL"
        static let copyImageFile = "copyImageFile"
        static let copyImageData = "copyImageData"
        static let copyColor = "copyColor"
        static let copyCustomData = "copyCustomData"
        static let copyFileFixture = "copyFileFixture"
        static let copyMultipleText = "copyMultipleText"
        static let copyMultiRepresentation = "copyMultiRepresentation"
        static let copyDetectionFixture = "copyDetectionFixture"
        static let copyNumberFixture = "copyNumberFixture"
        static let copySearchFixture = "copySearchFixture"
        // Copy options
        static let copyLocalOnlyTrue = "copyLocalOnlyTrue"
        static let copyLocalOnlyFalse = "copyLocalOnlyFalse"
        static let copyBBaseline = "copyBBaseline"
        static let copyExpiring = "copyExpiring"
        // Append
        static let appendPlainText = "appendPlainText"
        static let appendURL = "appendURL"
        static let appendUniversalMarker = "appendUniversalMarker"
        // Read / inspect
        static let read = "read"
        static let readData = "readData"
        static let snapshot = "snapshot"
        static let snapshotMatching = "snapshotMatching"
        // Load
        static let loadText = "loadText"
        static let loadURL = "loadURL"
        static let loadImage = "loadImage"
        static let loadFile = "loadFile"
        // Detect
        static let detectPatterns = "detectPatterns"
        static let detectValues = "detectValues"
        // Observe
        static let startObserving = "startObserving"
        static let stopObserving = "stopObserving"
        static let checkForeground = "checkForeground"
        // Clear
        static let clear = "clear"
        // Error cases
        static let errMultipleEmpty = "errMultipleEmpty"
        static let errMultiRepEmpty = "errMultiRepEmpty"
        static let errImageMissing = "errImageMissing"
        static let errCopyInvalidUTI = "errCopyInvalidUTI"
        static let errInvalidURL = "errInvalidURL"
        static let errInvalidColor = "errInvalidColor"
        static let errReadInvalidUTI = "errReadInvalidUTI"
        static let errRemoveGeneral = "errRemoveGeneral"
        static let errObserveMissing = "errObserveMissing"
        static let errEmptyPatterns = "errEmptyPatterns"
        static let errEmptyAcceptedTypes = "errEmptyAcceptedTypes"
    }

    /// Markers of control-only operations. These never write a result line.
    enum ControlAction {
        static let cancelLoads = "cancelLoads"
        static let mountPasteControl = "mountPasteControl"
    }
}

/// Exercises every native `IosClipboardManager` operation (S1〜S11).
///
/// - Important: Clipboard values, file paths, URLs and pasteboard names are never rendered on
///   screen and never logged. Only counts, byte/character lengths, kinds, type identifiers and
///   error codes are shown.
@MainActor
struct ClipboardSampleView: View {

    private let TAG = "ClipboardSampleView"

    private typealias ID = ClipboardSampleIdentifiers
    private typealias Action = ClipboardSampleIdentifiers.Action
    private typealias ControlAction = ClipboardSampleIdentifiers.ControlAction

    // MARK: - Fixtures

    static let fixedName = "com.jonghyunkim.nativetoolkit.example.sample"
    static let customTypeIdentifier = "com.jonghyunkim.nativetoolkit.example.custom"

    /// 64 bytes of fixed payload, so `Load File (public.data)` can assert `fileSize=64`.
    static let fileFixturePayload = Data(repeating: 0x41, count: 64)

    /// 14 characters. M-16 tells this apart from the 24-character append marker by length alone.
    static let localOnlyBody = "LOCALONLY-BODY"

    /// 31 characters. Used as device B's known baseline sentinel in M-16.
    static let deviceBBaseline = String(repeating: "B", count: 31)

    /// 24 characters ("APPENDED-MARKER-" plus the first 8 characters of a UUID).
    static var appendMarker: String { "APPENDED-MARKER-" + UUID().uuidString.prefix(8) }

    static let pasteAcceptedTypes = ["public.plain-text", "public.url", "public.image"]

    static let detectionFixture = """
    Visit https://www.apple.com or email support@example.com.
    Call +1 (408) 996-1010. Ship to 1 Infinite Loop, Cupertino, CA 95014.
    Meeting on March 3, 2027 at 10:00 AM. Flight AA100. Total 1,234.56 USD.
    Tracking 1Z999AA10123456784. Search: swift concurrency. Number 42.
    """

    /// Isolated fixtures for the detection patterns that `detectionFixture` cannot reach.
    ///
    /// A manual run detected 9 of the 11 patterns from `detectionFixture`; `number` and
    /// `probableWebSearch` did not appear. The likely reason is that those classify the clipboard
    /// **as a whole** rather than extracting occurrences from it, and a four-line paragraph is
    /// neither a number nor a search phrase — a single combined fixture cannot exercise both
    /// families at once. These two fixtures isolate them so the question can be decided.
    static let numberFixture = "42"
    static let searchFixture = "swift concurrency"

    // MARK: - State

    @State private var resultText = "Result will be displayed here"
    @State private var resultSequence = 0
    @State private var activeScope: PasteboardScope = .general
    @State private var lastRemovedScope: PasteboardScope?
    @State private var observedEventCount = 0
    @State private var isObserving = false
    @State private var pastedSummary = "-"
    @State private var isPasteControlMounted = false
    /// Scopes whose `Check Foreground Change` button has been pressed **in this screen**. Keyed by
    /// the scope itself rather than by its display label, because two different named pasteboards
    /// share a label whenever their names are the same length.
    @State private var didCheckForegroundInThisView: Set<PasteboardScope> = []
    /// Item count reported by the most recent `onPaste`, so `onPartialFailure` (which fires after
    /// `onPaste`) can report `items=N, failures=M`.
    @State private var lastPastedItemCount = 0

    private var activeScopeLabel: String { Self.scopeLabel(activeScope) }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            Text("IosClipboardManager Example")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 8)

            Text(resultText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)
                .accessibilityIdentifier(ID.result)

            Text("Scope: \(activeScopeLabel) | Observing: \(isObserving ? "on" : "off") | Events: \(observedEventCount)")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .accessibilityIdentifier(ID.status)

            Text("Paste result: \(pastedSummary)")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .accessibilityIdentifier(ID.pasteSummary)

            ScrollView {
                VStack(spacing: 16) {
                    Group {
                        scopeSection
                        copySection
                        copyOptionsSection
                        appendSection
                        readSection
                    }
                    Group {
                        loadSection
                        detectSection
                        observeSection
                        pasteControlSection
                        clearSection
                        errorSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .onDisappear {
            IosClipboardManager.shared.stopObserving()
            isObserving = false
        }
    }

    // MARK: - Sections

    private var scopeSection: some View {
        sectionView(title: "Scope", identifier: "scope") {
            actionButton("Use General", marker: Action.useGeneral) {
                activeScope = .general
                updateResult(marker: Action.useGeneral, kind: .success, payload: "scope=general")
            }

            actionButton("Create Named Pasteboard", marker: Action.createNamed) {
                run(Action.createNamed) {
                    let scope = try await IosClipboardManager.shared.createPasteboard(.named(Self.fixedName))
                    activeScope = scope
                    return "scope=\(Self.scopeLabel(scope))"
                }
            }

            actionButton("Use Fixed Named Scope (no create)", marker: Action.useFixedNamed) {
                activeScope = .named(Self.fixedName)
                updateResult(
                    marker: Action.useFixedNamed,
                    kind: .success,
                    payload: "scope=\(Self.scopeLabel(activeScope)) (not created)"
                )
            }

            actionButton("Create Unique Pasteboard", marker: Action.createUnique) {
                run(Action.createUnique) {
                    let scope = try await IosClipboardManager.shared.createPasteboard(.unique)
                    activeScope = scope
                    return "scope=\(Self.scopeLabel(scope))"
                }
            }

            actionButton("Remove Active Pasteboard", marker: Action.removeActive) {
                let target = activeScope
                run(Action.removeActive) {
                    try await IosClipboardManager.shared.removePasteboard(target)
                    lastRemovedScope = target
                    activeScope = .general
                    return "removed=\(Self.scopeLabel(target)), scope=general"
                }
            }

            actionButton("Probe Last Removed Scope", marker: Action.probeRemoved) {
                guard let removed = lastRemovedScope else {
                    Log.e(TAG, "[probeRemoved] no pasteboard has been removed yet")
                    updateResult(marker: Action.probeRemoved, kind: .failure, payload: Self.localFailureText)
                    return
                }
                run(Action.probeRemoved) {
                    let result = try await IosClipboardManager.shared.read(scope: removed)
                    return "unexpected success: numberOfItems=\(result.numberOfItems)"
                }
            }
            // Nothing has been removed yet, so the probe has no target. Disabling it keeps the
            // screen from producing a failure that no `ClipboardError` stands behind.
            .disabled(lastRemovedScope == nil)

            Text("""
            Named / unique pasteboards are not a persistent store, but their contents are not \
            guaranteed to be discarded when this app quits — one has been observed to survive a \
            force-quit and relaunch on iOS 18.7.2. Remove sensitive data explicitly rather than \
            relying on termination.
            """)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isObserving)
    }

    private var copySection: some View {
        sectionView(title: "Copy", identifier: "copy") {
            Group {
                actionButton("Copy Plain Text", marker: Action.copyPlainText) {
                    copy(Action.copyPlainText, kind: "plainText", .plainText("Hello from IosLibraryExample"))
                }
                actionButton("Copy Plain Text (empty, allowed)", marker: Action.copyPlainTextEmpty) {
                    copy(Action.copyPlainTextEmpty, kind: "plainText(empty)", .plainText(""))
                }
                actionButton("Copy HTML Text", marker: Action.copyHtml) {
                    copy(Action.copyHtml, kind: "htmlText", .htmlText(plain: "plain body", html: "<b>html body</b>"))
                }
                actionButton("Copy URL", marker: Action.copyURL) {
                    copy(Action.copyURL, kind: "url", .url("https://www.apple.com"))
                }
                actionButton("Copy Image File", marker: Action.copyImageFile) {
                    guard let path = Self.bundledImagePath() else {
                        Log.e(TAG, "[copyImageFile] sample image not found in bundle")
                        updateResult(marker: Action.copyImageFile, kind: .failure, payload: Self.localFailureText)
                        return
                    }
                    copy(Action.copyImageFile, kind: "imageFile", .imageFile(path: path))
                }
                actionButton("Copy Image Data", marker: Action.copyImageData) {
                    guard let data = Self.bundledImageData() else {
                        Log.e(TAG, "[copyImageData] sample image not found in bundle")
                        updateResult(marker: Action.copyImageData, kind: .failure, payload: Self.localFailureText)
                        return
                    }
                    copy(Action.copyImageData, kind: "imageData", .imageData(data, utType: "public.png"))
                }
            }
            Group {
                actionButton("Copy Color", marker: Action.copyColor) {
                    copy(Action.copyColor, kind: "color", .color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
                }
                actionButton("Copy Custom Data", marker: Action.copyCustomData) {
                    copy(
                        Action.copyCustomData,
                        kind: "customData",
                        .customData(Data([0xCA, 0xFE]), utType: Self.customTypeIdentifier)
                    )
                }
                actionButton("Copy File Fixture (public.data)", marker: Action.copyFileFixture) {
                    copy(
                        Action.copyFileFixture,
                        kind: "customData(public.data)",
                        .customData(Self.fileFixturePayload, utType: "public.data")
                    )
                }
                actionButton("Copy Multiple Text", marker: Action.copyMultipleText) {
                    copy(Action.copyMultipleText, kind: "multipleText", .multipleText(["first", "second", "third"]))
                }
                actionButton("Copy Multi Representation", marker: Action.copyMultiRepresentation) {
                    copy(
                        Action.copyMultiRepresentation,
                        kind: "multiRepresentation",
                        .multiRepresentation([
                            "public.plain-text": Data("multi representation".utf8),
                            "public.utf8-plain-text": Data("multi representation".utf8)
                        ])
                    )
                }
                actionButton("Copy Detection Fixture", marker: Action.copyDetectionFixture) {
                    copy(Action.copyDetectionFixture, kind: "plainText(detectionFixture)", .plainText(Self.detectionFixture))
                }
            }
        }
    }

    private var copyOptionsSection: some View {
        sectionView(title: "Copy Options", identifier: "copyOptions") {
            actionButton("Copy (localOnly = true)", marker: Action.copyLocalOnlyTrue) {
                copy(
                    Action.copyLocalOnlyTrue,
                    kind: "plainText(len=\(Self.localOnlyBody.count))",
                    .plainText(Self.localOnlyBody),
                    options: ClipboardCopyOptions(localOnly: true, expirationDate: nil)
                )
            }
            actionButton("Copy (localOnly = false)", marker: Action.copyLocalOnlyFalse) {
                copy(
                    Action.copyLocalOnlyFalse,
                    kind: "plainText(len=\(Self.localOnlyBody.count))",
                    .plainText(Self.localOnlyBody),
                    options: ClipboardCopyOptions(localOnly: false, expirationDate: nil)
                )
            }
            actionButton("Copy B Baseline (localOnly = true)", marker: Action.copyBBaseline) {
                copy(
                    Action.copyBBaseline,
                    kind: "plainText(len=\(Self.deviceBBaseline.count))",
                    .plainText(Self.deviceBBaseline),
                    options: ClipboardCopyOptions(localOnly: true, expirationDate: nil)
                )
            }
            actionButton("Copy (expires in 30s)", marker: Action.copyExpiring) {
                copy(
                    Action.copyExpiring,
                    kind: "plainText(expiring)",
                    .plainText("expiring body"),
                    options: ClipboardCopyOptions(localOnly: true, expirationDate: Date().addingTimeInterval(30))
                )
            }

            Text("""
            The first three write the same kind of content under different ClipboardCopyOptions. \
            Their bodies differ in length (14 and 31 characters) so that a Read can tell them \
            apart without displaying their values. Whether localOnly actually suppresses transfer \
            to nearby devices is not something this screen can show.
            """)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appendSection: some View {
        sectionView(title: "Append", identifier: "append") {
            actionButton("Append Plain Text", marker: Action.appendPlainText) {
                append(Action.appendPlainText, kind: "plainText", .plainText("appended item"))
            }
            actionButton("Append URL", marker: Action.appendURL) {
                append(Action.appendURL, kind: "url", .url("https://developer.apple.com"))
            }
            actionButton("Append Universal Marker", marker: Action.appendUniversalMarker) {
                let marker = Self.appendMarker
                append(Action.appendUniversalMarker, kind: "plainText(len=\(marker.count))", .plainText(marker))
            }

            Text("""
            append cannot carry ClipboardCopyOptions, and privacy options set by a prior copy are \
            not guaranteed to apply to the appended item. Use copy for sensitive data.
            """)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readSection: some View {
        sectionView(title: "Read / Inspect", identifier: "read") {
            actionButton("Read", marker: Action.read) {
                let scope = activeScope
                run(Action.read) {
                    let result = try await IosClipboardManager.shared.read(scope: scope)
                    // `resolved` plus the item count separates the three states a named scope can
                    // be in — unavailable / resolvable but empty / resolvable with content — which
                    // a screen-less measurement (T-13's long-duration run) has no other way to
                    // tell apart. Counts only; item values are never logged.
                    Log.d(
                        TAG,
                        "[read] scope kind: \(Self.scopeKind(scope)), resolved: true, "
                            + "numberOfItems: \(result.numberOfItems)"
                    )
                    return Self.describe(result)
                }
            }
            actionButton("Read Data (public.png)", marker: Action.readData) {
                let scope = activeScope
                run(Action.readData) {
                    let data = try await IosClipboardManager.shared.readData(utType: "public.png", scope: scope)
                    return data.map { "bytes=\($0.count)" } ?? "data=nil"
                }
            }
            actionButton("Snapshot", marker: Action.snapshot) {
                let scope = activeScope
                run(Action.snapshot) {
                    let snapshot = try await IosClipboardManager.shared.snapshot(scope: scope)
                    Log.d(
                        TAG,
                        "[snapshot] numberOfItems: \(snapshot.numberOfItems), "
                            + "typeIdentifiers: [\(snapshot.typeIdentifiers.joined(separator: ", "))]"
                    )
                    return Self.describe(snapshot)
                }
            }
            actionButton("Snapshot (matching public.plain-text)", marker: Action.snapshotMatching) {
                let scope = activeScope
                run(Action.snapshotMatching) {
                    let snapshot = try await IosClipboardManager.shared.snapshot(
                        matchingTypes: ["public.plain-text"],
                        scope: scope
                    )
                    let indexes = snapshot.matchingItemIndexes.map { "\($0)" } ?? "nil"
                    return "\(Self.describe(snapshot)), matchingItemIndexes=\(indexes)"
                }
            }
        }
    }

    private var loadSection: some View {
        sectionView(title: "Load (async)", identifier: "load") {
            actionButton("Load Text", marker: Action.loadText) {
                load(Action.loadText, request: .text)
            }
            actionButton("Load URL", marker: Action.loadURL) {
                load(Action.loadURL, request: .url)
            }
            actionButton("Load Image", marker: Action.loadImage) {
                load(Action.loadImage, request: .image)
            }
            actionButton("Load File (public.data)", marker: Action.loadFile) {
                load(Action.loadFile, request: .file(utType: "public.data"))
            }
            actionButton("Cancel All Loads", marker: ControlAction.cancelLoads) {
                Log.d(TAG, "[cancelAllLoads]")
                IosClipboardManager.shared.cancelAllLoads()
            }

            Text("Cancel is control-only: the pending load's own completion writes the single result line.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detectSection: some View {
        sectionView(title: "Detect", identifier: "detect") {
            // The isolated fixtures live next to the Detect buttons because they are only
            // meaningful immediately before a detection call. `Copy Detection Fixture` stays in
            // the Copy section, where the plan's marker table places it.
            actionButton("Copy Number Fixture (42 only)", marker: Action.copyNumberFixture) {
                copy(Action.copyNumberFixture, kind: "plainText(numberFixture)", .plainText(Self.numberFixture))
            }
            actionButton("Copy Search Fixture (phrase only)", marker: Action.copySearchFixture) {
                copy(Action.copySearchFixture, kind: "plainText(searchFixture)", .plainText(Self.searchFixture))
            }

            actionButton("Detect Patterns (all 11)", marker: Action.detectPatterns) {
                let scope = activeScope
                run(Action.detectPatterns) {
                    let patterns = try await IosClipboardManager.shared.detectPatterns(
                        Set(ClipboardDetectionPattern.allCases),
                        scope: scope
                    )
                    let names = patterns.map(\.rawValue).sorted().joined(separator: ", ")
                    // Pattern names are type-level metadata, never the detected values, and are
                    // already on screen. Logging them lets the manual check (§8.1 #13) record which
                    // patterns the OS actually found without transcribing 11 names by hand.
                    Log.d(TAG, "[detectPatterns] count: \(patterns.count), detected: [\(names)]")
                    return "count=\(patterns.count), patterns=[\(names)]"
                }
            }
            actionButton("Detect Values (all 11)", marker: Action.detectValues) {
                let scope = activeScope
                run(Action.detectValues) {
                    let values = try await IosClipboardManager.shared.detectValues(
                        Set(ClipboardDetectionPattern.allCases),
                        scope: scope
                    )
                    // Pattern names and counts only. The detected values themselves (addresses,
                    // phone numbers, links) are never logged and never shown.
                    let names = values.detectedPatterns.map(\.rawValue).sorted().joined(separator: ", ")
                    Log.d(TAG, "[detectValues] count: \(values.detectedPatterns.count), detected: [\(names)]")
                    return Self.describe(values)
                }
            }
        }
    }

    private var observeSection: some View {
        sectionView(title: "Observe", identifier: "observe") {
            actionButton("Start Observing", marker: Action.startObserving) {
                startObserving()
            }
            .disabled(isObserving)

            actionButton("Stop Observing", marker: Action.stopObserving) {
                Log.d(TAG, "[stopObserving]")
                IosClipboardManager.shared.stopObserving()
                isObserving = false
                updateResult(marker: Action.stopObserving, kind: .success, payload: "observing=off")
            }
            .disabled(!isObserving)

            actionButton("Check Foreground Change", marker: Action.checkForeground) {
                checkForegroundChange()
            }

            Text("""
            Check Foreground Change makes this call's changeCount the comparison baseline for a \
            resolvable scope. The baseline is also updated by starting observation and by receiving \
            a change notification, so "first check in this screen" describes this screen's operation \
            history only — never the manager's internal state.
            """)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pasteControlSection: some View {
        sectionView(title: "Paste Control (UI)", identifier: "pasteControl") {
            if isPasteControlMounted {
                ClipboardPasteControlView(
                    acceptedTypes: Self.pasteAcceptedTypes,
                    onPaste: { items in
                        lastPastedItemCount = items.count
                        pastedSummary = "items=\(items.count), failures=0"
                    },
                    onPartialFailure: { errors in
                        let codes = errors.map(\.errorCode).joined(separator: ",")
                        pastedSummary = "items=\(lastPastedItemCount), failures=\(errors.count) [\(codes)]"
                    },
                    onPasteFailure: { error in
                        pastedSummary = "paste failed: \(error.errorCode)"
                    },
                    onCreationFailure: { error in
                        pastedSummary = "control creation failed: \(error.errorCode)"
                    }
                )
                .frame(height: 44)
            } else {
                actionButton("Mount Paste Control", marker: ControlAction.mountPasteControl) {
                    Log.d(TAG, "[mountPasteControl]")
                    isPasteControlMounted = true
                }
            }

            Text("""
            The paste button always targets the system general pasteboard, independently of the \
            active scope. It is not created until it is explicitly mounted, so a privacy \
            measurement can keep Check Foreground Change as the first clipboard-aware operation.
            """)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var clearSection: some View {
        sectionView(title: "Clear", identifier: "clear") {
            actionButton("Clear Active Scope", marker: Action.clear) {
                let scope = activeScope
                run(Action.clear) {
                    try await IosClipboardManager.shared.clear(scope: scope)
                    return "scope=\(Self.scopeLabel(scope))"
                }
            }
        }
    }

    private var errorSection: some View {
        sectionView(title: "Error Cases", identifier: "errorCases") {
            Group {
                actionButton("Copy Multiple (empty list) → EMPTY_ITEMS", marker: Action.errMultipleEmpty) {
                    copy(Action.errMultipleEmpty, kind: "multipleText(empty)", .multipleText([]))
                }
                actionButton("Copy Multi Representation (empty) → EMPTY_ITEMS", marker: Action.errMultiRepEmpty) {
                    copy(Action.errMultiRepEmpty, kind: "multiRepresentation(empty)", .multiRepresentation([:]))
                }
                actionButton("Copy Image File (missing) → FILE_NOT_FOUND", marker: Action.errImageMissing) {
                    copy(
                        Action.errImageMissing,
                        kind: "imageFile(missing)",
                        .imageFile(path: "/nonexistent/clipboard-missing.png")
                    )
                }
                actionButton("Copy Custom Data (invalid UTI) → INVALID_TYPE", marker: Action.errCopyInvalidUTI) {
                    copy(
                        Action.errCopyInvalidUTI,
                        kind: "customData(invalidUTI)",
                        .customData(Data([1]), utType: "not a valid identifier!!")
                    )
                }
                actionButton("Copy URL (no scheme) → INVALID_URL", marker: Action.errInvalidURL) {
                    copy(Action.errInvalidURL, kind: "url(noScheme)", .url("example.com"))
                }
                actionButton("Copy Color (out of range) → INVALID_COLOR", marker: Action.errInvalidColor) {
                    copy(Action.errInvalidColor, kind: "color(outOfRange)", .color(red: 2.0, green: 0, blue: 0, alpha: 1))
                }
            }
            Group {
                actionButton("Read Data (invalid UTI) → INVALID_TYPE", marker: Action.errReadInvalidUTI) {
                    let scope = activeScope
                    run(Action.errReadInvalidUTI) {
                        let data = try await IosClipboardManager.shared.readData(
                            utType: "not a valid identifier!!",
                            scope: scope
                        )
                        return "unexpected success: bytes=\(data?.count ?? -1)"
                    }
                }
                actionButton("Remove General → CANNOT_REMOVE_GENERAL", marker: Action.errRemoveGeneral) {
                    run(Action.errRemoveGeneral) {
                        try await IosClipboardManager.shared.removePasteboard(.general)
                        return "unexpected success"
                    }
                }
                actionButton("Observe Unresolvable Named → UNAVAILABLE", marker: Action.errObserveMissing) {
                    observeUnresolvableNamed()
                }
                .disabled(isObserving)

                actionButton("Detect Patterns (empty set) → EMPTY_PATTERNS", marker: Action.errEmptyPatterns) {
                    let scope = activeScope
                    run(Action.errEmptyPatterns) {
                        let patterns = try await IosClipboardManager.shared.detectPatterns([], scope: scope)
                        return "unexpected success: count=\(patterns.count)"
                    }
                }
                actionButton("Make Paste Control (empty types) → INVALID_REQUEST", marker: Action.errEmptyAcceptedTypes) {
                    makePasteControlWithEmptyTypes()
                }
            }
        }
    }

    // MARK: - Operations

    private func copy(
        _ marker: String,
        kind: String,
        _ content: ClipboardContent,
        options: ClipboardCopyOptions = .default
    ) {
        Log.d(TAG, "[copy] marker: \(marker), kind: \(kind), localOnly: \(options.localOnly)")
        let scope = activeScope
        run(marker) {
            try await IosClipboardManager.shared.copy(content, options: options, scope: scope)
            return "copied kind=\(kind), scope=\(Self.scopeLabel(scope))"
        }
    }

    private func append(_ marker: String, kind: String, _ content: ClipboardContent) {
        Log.d(TAG, "[append] marker: \(marker), kind: \(kind)")
        let scope = activeScope
        run(marker) {
            try await IosClipboardManager.shared.append(content, scope: scope)
            return "appended kind=\(kind), scope=\(Self.scopeLabel(scope))"
        }
    }

    private func load(_ marker: String, request: ClipboardLoadRequest) {
        Log.d(TAG, "[load] marker: \(marker)")
        let scope = activeScope
        Task { @MainActor in
            do {
                let item = try await IosClipboardManager.shared.loadItem(request, scope: scope)
                switch item {
                case .text(let value):
                    updateResult(marker: marker, kind: .success, payload: "textLength=\(value.count)")
                case .url(let value):
                    updateResult(marker: marker, kind: .success, payload: "urlLength=\(value.count)")
                case .imageData(let data, let utType):
                    updateResult(marker: marker, kind: .success, payload: "bytes=\(data.count), utType=\(utType)")
                case .file(let url):
                    let consumed = consumeLoadedFile(url)
                    updateResult(
                        marker: marker,
                        kind: consumed.cleanupFailed ? .warning : .success,
                        payload: consumed.detail
                    )
                @unknown default:
                    Log.e(TAG, "[load] unsupported loaded item kind")
                    updateResult(marker: marker, kind: .failure, payload: Self.localFailureText)
                }
            } catch ClipboardError.cancelled {
                updateResult(marker: marker, kind: .info, payload: "Cancellation completed (CLIPBOARD_CANCELLED)")
            } catch {
                updateResult(marker: marker, kind: .failure, payload: Self.failureText(error))
            }
        }
    }

    private func startObserving() {
        Log.d(TAG, "[startObserving] scope kind: \(Self.scopeKind(activeScope))")
        let scope = activeScope
        do {
            try IosClipboardManager.shared.startObserving(scope: scope) { event in
                // The manager delivers events on the main thread, so asserting main-actor
                // isolation here keeps the `@State` mutation on the main actor without a hop.
                MainActor.assumeIsolated {
                    observedEventCount += 1
                    Log.d(TAG, "[startObserving][event] kind: \(Self.eventKindLabel(event))")
                }
            }
            isObserving = true
            updateResult(
                marker: Action.startObserving,
                kind: .success,
                payload: "observing=on, scope=\(Self.scopeLabel(scope))"
            )
        } catch {
            // The manager stops the previous observation before resolving the new scope, so the
            // screen state must follow the manager rather than the previous flag value.
            isObserving = false
            updateResult(marker: Action.startObserving, kind: .failure, payload: Self.failureText(error))
        }
    }

    private func observeUnresolvableNamed() {
        Log.d(TAG, "[observeUnresolvableNamed]")
        let missing = PasteboardScope.named("com.jonghyunkim.nativetoolkit.example.missing-\(UUID().uuidString)")
        do {
            try IosClipboardManager.shared.startObserving(scope: missing) { _ in }
            isObserving = true
            updateResult(marker: Action.errObserveMissing, kind: .success, payload: "unexpected success")
        } catch {
            isObserving = false
            updateResult(marker: Action.errObserveMissing, kind: .failure, payload: Self.failureText(error))
        }
    }

    private func checkForegroundChange() {
        Log.d(TAG, "[checkForegroundChange] scope kind: \(Self.scopeKind(activeScope))")
        let scope = activeScope
        let isFirstInThisView = !didCheckForegroundInThisView.contains(scope)
        didCheckForegroundInThisView.insert(scope)

        let changed = IosClipboardManager.shared.checkForegroundChange(scope: scope)
        updateResult(
            marker: Action.checkForeground,
            kind: .success,
            payload: Self.checkForegroundPayload(changed: changed, isFirstInThisView: isFirstInThisView)
        )
    }

    /// Builds the `Check Foreground Change` payload.
    ///
    /// The real return value is always reported: the public `Bool` API cannot distinguish
    /// "resolved and unchanged" from "unresolvable", so the note describes this screen's operation
    /// history only and never claims that the manager's baseline was established or updated.
    /// Exposed as a static helper so a unit test can pin that contract.
    static func checkForegroundPayload(changed: Bool, isFirstInThisView: Bool) -> String {
        "changed=\(changed)" + (isFirstInThisView ? " (first check in this screen)" : "")
    }

    private func makePasteControlWithEmptyTypes() {
        Log.d(TAG, "[makePasteControlWithEmptyTypes]")
        do {
            _ = try IosClipboardManager.shared.makePasteControl(acceptedTypes: [], onPaste: { _ in })
            updateResult(marker: Action.errEmptyAcceptedTypes, kind: .success, payload: "unexpected success")
        } catch {
            updateResult(marker: Action.errEmptyAcceptedTypes, kind: .failure, payload: Self.failureText(error))
        }
    }

    /// Reads the size of a loaded file and then deletes the **request-scoped** directory the
    /// library handed over (the returned URL's parent). The active session directory is owned by
    /// the library and must not be touched. The path is never shown on screen or logged.
    private func consumeLoadedFile(_ url: URL) -> (detail: String, cleanupFailed: Bool) {
        Log.d(TAG, "[consumeLoadedFile]")
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let requestDirectory = url.deletingLastPathComponent()
        do {
            try FileManager.default.removeItem(at: requestDirectory)
            return ("fileSize=\(size)", false)
        } catch {
            Log.e(TAG, "[consumeLoadedFile] cleanup failed")
            return ("fileSize=\(size), cleanup=failed", true)
        }
    }

    // MARK: - Result display

    private enum ResultKind: String {
        case success = "✅"
        case failure = "❌"
        case info = "ℹ️"
        case warning = "⚠️"

        var name: String {
            switch self {
            case .success: return "success"
            case .failure: return "failure"
            case .info: return "info"
            case .warning: return "warning"
            }
        }
    }

    private func run(_ marker: String, operation: @escaping @MainActor () async throws -> String) {
        Log.d(TAG, "[run] marker: \(marker)")
        Task { @MainActor in
            do {
                let payload = try await operation()
                updateResult(marker: marker, kind: .success, payload: payload)
            } catch {
                // The error code is logged (never the message, which is fixed text anyway) so a
                // failure can be classified from the console alone.
                Log.e(TAG, "[run] marker: \(marker), errorCode: \(Self.errorCode(of: error))")
                updateResult(marker: marker, kind: .failure, payload: Self.failureText(error))
            }
        }
    }

    /// Writes the single result line. The payload is deliberately excluded from the log.
    private func updateResult(marker: String, kind: ResultKind, payload: String) {
        Log.d(TAG, "[updateResult] seq: \(resultSequence + 1), marker: \(marker), kind: \(kind.name)")
        DispatchQueue.main.async {
            resultSequence += 1
            resultText = "\(kind.rawValue) #\(resultSequence) [\(marker)] \(payload)"
        }
    }

    // MARK: - Formatting helpers (no clipboard values, paths, URLs or pasteboard names)

    /// Failure text for a screen-local precondition that has no `ClipboardError` behind it
    /// (missing bundle asset, unknown enum case, absent probe target).
    ///
    /// The `§4.5` failure format requires `errorCode=` / `errorMessage=`, so these paths report the
    /// library's fixed unknown-error pair rather than an ad-hoc sentence. The specific reason is
    /// written to the log instead, where it can carry detail without reaching the screen.
    static let localFailureText =
        "errorCode=\(ClipboardError.unknownErrorCode), errorMessage=\(ClipboardError.unknownMessage)"

    private static func errorCode(of error: Error) -> String {
        (error as? ClipboardError)?.errorCode ?? ClipboardError.unknownErrorCode
    }

    private static func failureText(_ error: Error) -> String {
        guard let clipboardError = error as? ClipboardError else {
            return "errorCode=\(ClipboardError.unknownErrorCode), errorMessage=\(ClipboardError.unknownMessage)"
        }
        return "errorCode=\(clipboardError.errorCode), errorMessage=\(clipboardError.errorDescription ?? "nil")"
    }

    private static func scopeKind(_ scope: PasteboardScope) -> String {
        switch scope {
        case .general: return "general"
        case .named: return "named"
        case .unique: return "unique"
        @unknown default: return "unknown"
        }
    }

    /// Kind plus name length only — the pasteboard name itself is never exposed.
    private static func scopeLabel(_ scope: PasteboardScope) -> String {
        switch scope {
        case .general: return "general"
        case .named(let name): return "named(len=\(name.count))"
        case .unique(let name): return "unique(len=\(name.count))"
        @unknown default: return "unknown"
        }
    }

    private static func eventKindLabel(_ event: ClipboardChangeEvent) -> String {
        switch event.kind {
        case .changed(let added, let removed): return "changed(added=\(added.count), removed=\(removed.count))"
        case .changedDetectedOnForeground: return "changedDetectedOnForeground"
        case .removed: return "removed"
        @unknown default: return "unknown"
        }
    }

    private static func describe(_ result: ClipboardReadResult) -> String {
        let items = result.items.enumerated().map { index, item -> String in
            let text = item.text.map { "text(len=\($0.count))" } ?? "noText"
            return "\(index):\(text) types=\(item.typeIdentifiers.count) url=\(item.urlString == nil ? "no" : "yes")"
        }
        return "numberOfItems=\(result.numberOfItems), items=[\(items.joined(separator: ", "))]"
    }

    /// Type identifiers are listed by name, not just counted: telling whether a paste source
    /// advertises an accepted type (8.1 #20) is impossible from a count alone. Identifiers are
    /// type information, never content — design §4.6 allows showing and logging them.
    private static func describe(_ snapshot: ClipboardSnapshot) -> String {
        "hasStrings=\(snapshot.hasStrings), hasURLs=\(snapshot.hasURLs), hasImages=\(snapshot.hasImages), "
            + "hasColors=\(snapshot.hasColors), numberOfItems=\(snapshot.numberOfItems), "
            + "typeIdentifiers=\(snapshot.typeIdentifiers.count) [\(snapshot.typeIdentifiers.joined(separator: ", "))]"
    }

    private static func describe(_ values: ClipboardDetectedValues) -> String {
        "patterns=\(values.detectedPatterns.count), links=\(values.links.count), "
            + "emails=\(values.emailAddresses.count), phones=\(values.phoneNumbers.count), "
            + "addresses=\(values.postalAddresses.count), events=\(values.calendarEvents.count), "
            + "flights=\(values.flightNumbers.count), money=\(values.moneyAmounts.count), "
            + "tracking=\(values.shipmentTrackingNumbers.count), hasNumber=\(values.number != nil), "
            + "hasWebURL=\(values.probableWebURL != nil), hasWebSearch=\(values.probableWebSearch != nil)"
    }

    private static func bundledImagePath() -> String? {
        Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path
    }

    private static func bundledImageData() -> Data? {
        guard let url = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png") else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - View helpers

    @ViewBuilder
    private func sectionView<Content: View>(
        title: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityIdentifier(ID.section(identifier))
            content()
                .buttonStyle(FullWidthPressableButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func actionButton(_ title: String, marker: String, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .accessibilityIdentifier(ID.button(marker))
    }
}

/// Hosts the library's `UIPasteControl` container inside SwiftUI.
struct ClipboardPasteControlView: UIViewRepresentable {

    private let TAG = "ClipboardPasteControlView"

    let acceptedTypes: [String]
    let onPaste: ([ClipboardLoadedItem]) -> Void
    let onPartialFailure: ([ClipboardError]) -> Void
    let onPasteFailure: (ClipboardError) -> Void
    let onCreationFailure: (ClipboardError) -> Void

    func makeUIView(context: Context) -> UIView {
        Log.d(TAG, "[makeUIView] acceptedTypesCount: \(acceptedTypes.count)")
        do {
            return try IosClipboardManager.shared.makePasteControl(
                acceptedTypes: acceptedTypes,
                onPaste: onPaste,
                onPartialFailure: onPartialFailure,
                onPasteFailure: onPasteFailure
            )
        } catch let error as ClipboardError {
            // Changing state synchronously inside `makeUIView` triggers "Modifying state during
            // view update", so the report is deferred to the next main-actor turn.
            Task { @MainActor in onCreationFailure(error) }
            return UIView()
        } catch {
            Task { @MainActor in
                onCreationFailure(.unknown(ClipboardFailureDetail(systemError: error)))
            }
            return UIView()
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct FullWidthPressableButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        // `Configuration` carries `isPressed` but not the enabled state, and a `ButtonStyle` is not
        // itself a `View`, so the environment is read from a nested view instead. Without this a
        // `.disabled` button keeps its enabled appearance and the screen gives no hint that Scope
        // controls are locked during observation (design §4.4 / §8.1 #16).
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(background)
                .foregroundColor(isEnabled ? .white : Color.white.opacity(0.75))
                .cornerRadius(10)
                .opacity(configuration.isPressed ? 0.85 : 1.0)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var background: Color {
            guard isEnabled else { return Color.gray.opacity(0.45) }
            return configuration.isPressed ? Color.blue.opacity(0.65) : Color.blue
        }
    }
}

#Preview {
    ClipboardSampleView()
}
