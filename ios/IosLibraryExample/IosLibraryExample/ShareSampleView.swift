import IosLibrary
import os
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "ShareSampleView")

/// Single source of truth for the accessibility identifiers exposed by `ShareSampleView`.
///
/// A button's `<name>` is the lowerCamelCase of its title.
enum ShareSampleIdentifiers {

    static let result = "share.result"

    static func section(_ name: String) -> String { "share.section.\(name)" }
    static func button(_ name: String) -> String { "share.button.\(name)" }

    enum Section {
        static let text = "text"
        static let url = "url"
        static let image = "image"
        static let file = "file"
        static let combination = "combination"
        static let error = "error"
        static let swiftAPI = "swiftAPI"
    }

    enum ButtonName {
        static let shareText = "shareText"
        static let shareURL = "shareURL"
        static let shareURLWithPreview = "shareURLWithPreview"
        static let shareImage = "shareImage"
        static let shareMultipleImages = "shareMultipleImages"
        static let shareFile = "shareFile"
        static let shareMultipleFiles = "shareMultipleFiles"
        static let shareMultiple = "shareMultiple"
        static let shareWithSubject = "shareWithSubject"
        static let shareExcludingActivities = "shareExcludingActivities"
        static let shareEmpty = "shareEmpty"
        static let shareInvalidURL = "shareInvalidURL"
        static let shareMissingFile = "shareMissingFile"
        static let shareMissingImage = "shareMissingImage"
        // Swift API (2.0.0): `share(content:presenter:)` and `share(content:presenter:completion:)`.
        static let shareRequestText = "shareRequestText"
        static let shareThenDismissFromOutside = "shareThenDismissFromOutside"
        static let shareAfter3Seconds = "shareAfter3Seconds"
    }
}

/// What the sample saw at the moment it dismissed a share sheet of the Swift API section, added
/// to that request's result line (`shown=true`). A UI test then reads it from the result line
/// instead of having to find the sheet before the timer ends it.
@MainActor
final class ShareMoment {
    var note = ""
}

struct ShareSampleView: View {

    private typealias ID = ShareSampleIdentifiers

    @State private var resultText = "Result will be displayed here"
    /// Number of result updates, exposed as the result line's `accessibilityValue` so a UI test
    /// can tell a new result from an identical old one.
    @State private var resultUpdateCount = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("IosShareManager Example")
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
                .accessibilityValue("updates=\(resultUpdateCount)")

            ScrollView {
                VStack(spacing: 16) {
                    sectionView(title: "Text", identifier: ID.Section.text) {
                        Button("ShareText") {
                            Task {
                                await runShare(
                                    label: "shareText",
                                    content: ShareContent(items: [.text("Shared from IosLibraryExample")])
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareText))
                    }

                    sectionView(title: "URL", identifier: ID.Section.url) {
                        Button("ShareURL") {
                            Task {
                                await runShare(
                                    label: "shareURL",
                                    content: ShareContent(items: [.url("https://www.apple.com")])
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareURL))

                        Button("ShareURLWithPreview") {
                            Task {
                                await runShare(
                                    label: "shareURLWithPreview",
                                    content: ShareContent(
                                        items: [.url("https://www.apple.com")],
                                        previewTitle: "Apple"
                                    )
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareURLWithPreview))
                    }

                    sectionView(title: "Image", identifier: ID.Section.image) {
                        Button("ShareImage") {
                            Task {
                                guard let imagePath = bundledImagePath() else {
                                    updateResult(isSuccess: false, result: "[shareImage] Sample image not found in bundle")
                                    return
                                }
                                await runShare(
                                    label: "shareImage",
                                    content: ShareContent(items: [.imageFile(path: imagePath)])
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareImage))

                        Button("ShareMultipleImages") {
                            Task {
                                guard let imagePaths = prepareSampleImagePaths(count: 2) else {
                                    updateResult(isSuccess: false, result: "[shareMultipleImages] Sample image preparation failed")
                                    return
                                }
                                await runShare(
                                    label: "shareMultipleImages",
                                    content: ShareContent(items: imagePaths.map { .imageFile(path: $0) })
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareMultipleImages))
                    }

                    sectionView(title: "File", identifier: ID.Section.file) {
                        Button("ShareFile") {
                            Task {
                                guard let fileURL = prepareSampleFileURL() else {
                                    updateResult(isSuccess: false, result: "[shareFile] Sample file preparation failed")
                                    return
                                }
                                await runShare(
                                    label: "shareFile",
                                    content: ShareContent(items: [.file(path: fileURL.path)])
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareFile))

                        Button("ShareMultipleFiles") {
                            Task {
                                guard let fileURLs = prepareSampleFileURLs(count: 2) else {
                                    updateResult(isSuccess: false, result: "[shareMultipleFiles] Sample file preparation failed")
                                    return
                                }
                                await runShare(
                                    label: "shareMultipleFiles",
                                    content: ShareContent(items: fileURLs.map { .file(path: $0.path) })
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareMultipleFiles))
                    }

                    sectionView(title: "Combination", identifier: ID.Section.combination) {
                        Button("ShareMultiple") {
                            Task {
                                await runShare(
                                    label: "shareMultiple",
                                    content: ShareContent(items: [
                                        .text("Check this out"),
                                        .url("https://www.apple.com")
                                    ])
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareMultiple))

                        Button("ShareWithSubject") {
                            Task {
                                await runShare(
                                    label: "shareWithSubject",
                                    content: ShareContent(
                                        items: [.text("Body text")],
                                        subject: "Sample Subject"
                                    )
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareWithSubject))

                        Button("ShareExcludingActivities") {
                            Task {
                                await runShare(
                                    label: "shareExcludingActivities",
                                    content: ShareContent(
                                        items: [.url("https://www.apple.com")],
                                        excludedActivityTypes: [
                                            "com.apple.UIKit.activity.CopyToPasteboard",
                                            "com.apple.UIKit.activity.PostToFacebook"
                                        ]
                                    )
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareExcludingActivities))
                    }

                    sectionView(title: "Error", identifier: ID.Section.error) {
                        Button("ShareEmpty") {
                            Task {
                                await runShare(label: "shareEmpty", content: ShareContent(items: []))
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareEmpty))

                        Button("ShareInvalidURL") {
                            Task {
                                await runShare(
                                    label: "shareInvalidURL",
                                    content: ShareContent(items: [.url("not a valid url")])
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareInvalidURL))

                        Button("ShareMissingFile") {
                            Task {
                                await runShare(
                                    label: "shareMissingFile",
                                    content: ShareContent(items: [.file(path: "/nonexistent/share-missing.txt")])
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareMissingFile))

                        Button("ShareMissingImage") {
                            Task {
                                await runShare(
                                    label: "shareMissingImage",
                                    content: ShareContent(items: [.imageFile(path: "/nonexistent/share-missing.png")])
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareMissingImage))
                    }

                    sectionView(title: "Swift API (2.0.0)", identifier: ID.Section.swiftAPI) {
                        // `share(content:presenter:)` (async) from the foreground (SA-14).
                        Button("ShareRequestText") {
                            logger.debug("[shareRequestText]")
                            Task {
                                do {
                                    let result = try await IosShareManager.shared.share(
                                        content: ShareContent(items: [.text("Shared through the Swift API")]),
                                        presenter: .foreground
                                    )
                                    report("shareRequestText", .success(result))
                                } catch let error as ShareError {
                                    report("shareRequestText", .failure(error))
                                } catch {
                                    updateResult(isSuccess: false, result: "[shareRequestText] failure \(error)")
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareRequestText))

                        // Dismissed by the sample from outside the library 3 seconds after the tap (the
                        // release watch: dismissedBySystem). The result line says whether the sheet was
                        // shown when it was dismissed (`shown=true`). The callback form, which the C ABI
                        // uses (SA-14).
                        Button("ShareThenDismissFromOutside") {
                            logger.debug("[shareThenDismissFromOutside]")
                            let moment = ShareMoment()
                            IosShareManager.shared.share(
                                content: ShareContent(items: [.text("Dismissed from outside after 3 seconds")]),
                                presenter: .foreground
                            ) { result in
                                report("shareThenDismissFromOutside", result, note: moment.note)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                moment.note = "shown=\(Self.isSheetShown())"
                                let top = IosDialogManager.shared.foregroundViewController()
                                top?.presentingViewController?.dismiss(animated: true)
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareThenDismissFromOutside))

                        #if DEBUG
                        // Test only: requested 3 seconds later, so that a UI test can move the app to the
                        // background (notForeground). The scene's state when the request is made is in the
                        // result line (SA-05).
                        Button("ShareAfter3Seconds") {
                            logger.debug("[shareAfter3Seconds]")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                let state = Self.sceneState()
                                IosShareManager.shared.share(
                                    content: ShareContent(items: [.text("Requested 3 seconds later")]),
                                    presenter: .foreground
                                ) { result in
                                    report("shareAfter3Seconds@\(state)", result)
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.shareAfter3Seconds))
                        #endif
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Section helper

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

    // MARK: - Share execution

    private func runShare(label: String, content: ShareContent) async {
        logger.debug("[runShare] label: \(label, privacy: .public), items: \(content.items.count, privacy: .public)")
        do {
            let result = try await IosShareManager.shared.share(content: content)
            logger.debug("[runShare][result] label: \(label, privacy: .public), completed: \(result.completed, privacy: .public), activityType: \(result.activityType ?? "nil", privacy: .public)")
            let detail = result.completed
                ? "[\(label)] completed=true, activityType=\(result.activityType ?? "nil")"
                : "[\(label)] completed=false (cancelled)"
            updateResult(isSuccess: true, result: detail)
        } catch {
            logger.error("[runShare][error] label: \(label, privacy: .public), error: \(error, privacy: .private)")
            updateResult(isSuccess: false, result: "[\(label)] errorMessage=\(error.localizedDescription)")
        }
    }

    /// Writes a result of the Swift API to the result line:
    /// `[<label>] success completed=true, activityType=<type>`, `[<label>] success completed=false`
    /// or `[<label>] failure <case>`, followed by ` <note>` when `note` is not empty.
    private func report(_ label: String, _ result: Result<ShareResult, ShareError>, note: String = "") {
        let suffix = note.isEmpty ? "" : " \(note)"
        switch result {
        case .success(let share):
            logger.debug("[\(label, privacy: .public)] success completed: \(share.completed, privacy: .public), activityType: \(share.activityType ?? "nil", privacy: .public), note: \(note, privacy: .public)")
            let detail = share.completed
                ? "completed=true, activityType=\(share.activityType ?? "nil")"
                : "completed=false"
            updateResult(isSuccess: true, result: "[\(label)] success \(detail)\(suffix)")
        case .failure(let error):
            logger.debug("[\(label, privacy: .public)] failure: \(Self.caseName(of: error), privacy: .public), note: \(note, privacy: .public)")
            updateResult(isSuccess: false, result: "[\(label)] failure \(Self.caseName(of: error))\(suffix)")
        }
    }

    /// The case of a share error, without the URL or path some cases carry.
    private static func caseName(of error: ShareError) -> String {
        switch error {
        case .noValidItems: return "noValidItems"
        case .invalidURL: return "invalidURL"
        case .imageLoadFailed: return "imageLoadFailed"
        case .fileNotFound: return "fileNotFound"
        case .noRootViewController: return "noRootViewController"
        case .notForeground: return "notForeground"
        case .presentationFailed: return "presentationFailed"
        case .dismissedBySystem: return "dismissedBySystem"
        case .activityFailed(let detail): return "activityFailed(domain=\(detail.domain), code=\(detail.code))"
        @unknown default: return "unknown"
        }
    }

    /// Whether the view controller in the foreground is a share sheet.
    private static func isSheetShown() -> Bool {
        IosDialogManager.shared.foregroundViewController() is UIActivityViewController
    }

    /// The activation state of the sample's window scenes (`foregroundActive`, ...).
    private static func sceneState() -> String {
        let states = UIApplication.shared.connectedScenes.map { scene -> String in
            switch scene.activationState {
            case .foregroundActive: return "foregroundActive"
            case .foregroundInactive: return "foregroundInactive"
            case .background: return "background"
            case .unattached: return "unattached"
            @unknown default: return "unknown"
            }
        }
        return states.sorted().joined(separator: ",")
    }

    // MARK: - Sample data helpers

    private func bundledImagePath() -> String? {
        Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path
    }

    /// Copies the bundled sample image to `count` distinct temporary files, so multiple
    /// `.imageFile` items can be shared at once (there is only one bundled image asset).
    private func prepareSampleImagePaths(count: Int) -> [String]? {
        guard let sourceURL = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png") else {
            return nil
        }
        var paths: [String] = []
        for index in 0..<count {
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("share-sample-image-\(index).png")
            do {
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                paths.append(destURL.path)
            } catch {
                logger.error("[prepareSampleImagePaths] failed: \(error, privacy: .private)")
                return nil
            }
        }
        return paths
    }

    private func prepareSampleFileURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("share-sample.txt")
        do {
            try "Shared from IosLibraryExample.".write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            logger.error("[prepareSampleFileURL] failed: \(error, privacy: .private)")
            return nil
        }
    }

    /// Generates `count` distinct temporary text files, so multiple `.file` items can be
    /// shared at once.
    private func prepareSampleFileURLs(count: Int) -> [URL]? {
        var urls: [URL] = []
        for index in 0..<count {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("share-sample-file-\(index).txt")
            do {
                try "Shared from IosLibraryExample (\(index)).".write(to: url, atomically: true, encoding: .utf8)
                urls.append(url)
            } catch {
                logger.error("[prepareSampleFileURLs] failed: \(error, privacy: .private)")
                return nil
            }
        }
        return urls
    }

    // MARK: - Result display

    private func updateResult(isSuccess: Bool, result: String?) {
        logger.debug("[updateResult] isSuccess: \(isSuccess, privacy: .public), result: \(result ?? "nil", privacy: .private)")
        DispatchQueue.main.async {
            resultUpdateCount += 1
            if isSuccess {
                resultText = "✅ \nResult: \(result ?? "nil")"
            } else {
                resultText = "❌ \nResult: \(result ?? "nil")"
            }
        }
    }
}

private struct FullWidthPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(configuration.isPressed ? Color.blue.opacity(0.65) : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ShareSampleView()
}
