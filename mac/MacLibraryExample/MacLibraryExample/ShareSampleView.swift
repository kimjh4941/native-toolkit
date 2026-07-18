//
//  ShareSampleView.swift
//  MacLibraryExample
//
//  Created by Kim Jong Hyun on 2026/07/11.
//

import SwiftUI
import AppKit
import MacLibrary

struct ShareSampleView: View {

    private let TAG = "ShareSampleView"

    private let mailServiceName = "com.apple.share.Mail.compose"
    private let invalidServiceName = "invalid.service"

    @State private var resultText = "Result will be displayed here"

    var body: some View {
        VStack(spacing: 12) {
            Text("MacShareManager Example")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 8)

            Text(resultText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 16) {
                    sectionView(title: "Picker - Basic") {
                        Button("ShareText") {
                            Task {
                                await runShare(
                                    label: "shareText",
                                    content: ShareContent(items: [.text("Shared from MacLibraryExample")])
                                )
                            }
                        }

                        Button("ShareURL") {
                            Task {
                                await runShare(
                                    label: "shareURL",
                                    content: ShareContent(items: [.url("https://www.apple.com")])
                                )
                            }
                        }

                        Button("ShareImage") {
                            Task {
                                guard let imagePath = prepareSampleImagePath() else {
                                    updateResult(isSuccess: false, result: "[shareImage] Sample image preparation failed")
                                    return
                                }
                                await runShare(
                                    label: "shareImage",
                                    content: ShareContent(items: [.imageFile(path: imagePath)])
                                )
                            }
                        }

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
                    }

                    sectionView(title: "Picker - Multiple") {
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

                        Button("ShareTextAndURL") {
                            Task {
                                await runShare(
                                    label: "shareTextAndURL",
                                    content: ShareContent(items: [
                                        .text("Check this out"),
                                        .url("https://www.apple.com")
                                    ])
                                )
                            }
                        }
                    }

                    sectionView(title: "Picker - Filter") {
                        Button("ShareExcludingServices") {
                            Task {
                                await runShare(
                                    label: "shareExcludingServices",
                                    content: ShareContent(
                                        items: [.url("https://www.apple.com")],
                                        excludedServiceTitles: ["Add to Reading List"]
                                    )
                                )
                            }
                        }
                    }

                    sectionView(title: "Direct Service") {
                        Button("ShareViaMail") {
                            Task {
                                await runDirect(
                                    label: "shareViaMail",
                                    content: ShareContent(
                                        items: [.text("Body text")],
                                        recipients: ["test@example.com"],
                                        subject: "Sample Subject"
                                    ),
                                    serviceName: mailServiceName
                                )
                            }
                        }

                        Button("CanPerformMail") {
                            Task {
                                await runCanPerform(
                                    label: "canPerformMail",
                                    content: ShareContent(items: [.text("Body text")]),
                                    serviceName: mailServiceName
                                )
                            }
                        }
                    }

                    sectionView(title: "Error") {
                        Button("ShareEmpty") {
                            Task {
                                await runShare(label: "shareEmpty", content: ShareContent(items: []))
                            }
                        }

                        Button("ShareInvalidURL") {
                            Task {
                                await runShare(
                                    label: "shareInvalidURL",
                                    content: ShareContent(items: [.url("not a valid url")])
                                )
                            }
                        }

                        Button("ShareMissingFile") {
                            Task {
                                await runShare(
                                    label: "shareMissingFile",
                                    content: ShareContent(items: [.file(path: "/nonexistent/share-missing.txt")])
                                )
                            }
                        }

                        Button("ShareMissingImage") {
                            Task {
                                await runShare(
                                    label: "shareMissingImage",
                                    content: ShareContent(items: [.imageFile(path: "/nonexistent/share-missing.png")])
                                )
                            }
                        }

                        Button("ShareUnknownService") {
                            Task {
                                await runDirect(
                                    label: "shareUnknownService",
                                    content: ShareContent(items: [.text("Body text")]),
                                    serviceName: invalidServiceName
                                )
                            }
                        }
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            .padding()
        }
        .navigationTitle("Share Example")
    }

    // MARK: - Section helper

    @ViewBuilder
    private func sectionView<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
                .buttonStyle(FullWidthPressableButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Share execution

    /// Presents the sharing service picker. Invoked from a button action so the picker call
    /// originates from a user click; the underlying `Task { await ... }` hop does not guarantee
    /// `mouseDown` context is preserved (see implementation result v2). Stable display must be
    /// confirmed manually on real hardware.
    private func runShare(label: String, content: ShareContent) async {
        Log.d(TAG, "[runShare] label: \(label), items: \(content.items.count)")
        do {
            let result = try await MacShareManager.shared.share(content: content)
            Log.d(TAG, "[runShare][result] label: \(label), completed: \(result.completed), service: \(result.serviceName ?? "nil")")
            let detail = result.completed
                ? "[\(label)] completed=true, service=\(result.serviceName ?? "nil")"
                : "[\(label)] completed=false (cancelled)"
            updateResult(isSuccess: true, result: detail)
        } catch let error as ShareError {
            Log.e(TAG, "[runShare][error] label: \(label), error: \(error)")
            updateResult(isSuccess: false, result: "[\(label)] errorCode=\(error.errorCode), errorMessage=\(error.errorMessage)")
        } catch {
            Log.e(TAG, "[runShare][error] label: \(label), error: \(error)")
            updateResult(isSuccess: false, result: "[\(label)] error=\(error.localizedDescription)")
        }
    }

    /// Performs a named sharing service directly (no picker UI). Does not depend on `mouseDown`
    /// context, so this is a comparatively stable path to verify even without interactive UI.
    private func runDirect(label: String, content: ShareContent, serviceName: String) async {
        Log.d(TAG, "[runDirect] label: \(label), serviceName: \(serviceName), items: \(content.items.count)")
        do {
            let result = try await MacShareManager.shared.shareViaService(content: content, serviceName: serviceName)
            Log.d(TAG, "[runDirect][result] label: \(label), completed: \(result.completed), service: \(result.serviceName ?? "nil")")
            let detail = result.completed
                ? "[\(label)] completed=true, service=\(result.serviceName ?? "nil")"
                : "[\(label)] completed=false (cancelled)"
            updateResult(isSuccess: true, result: detail)
        } catch let error as ShareError {
            Log.e(TAG, "[runDirect][error] label: \(label), error: \(error)")
            updateResult(isSuccess: false, result: "[\(label)] errorCode=\(error.errorCode), errorMessage=\(error.errorMessage)")
        } catch {
            Log.e(TAG, "[runDirect][error] label: \(label), error: \(error)")
            updateResult(isSuccess: false, result: "[\(label)] error=\(error.localizedDescription)")
        }
    }

    private func runCanPerform(label: String, content: ShareContent, serviceName: String) async {
        Log.d(TAG, "[runCanPerform] label: \(label), serviceName: \(serviceName)")
        do {
            let canPerform = try await MacShareManager.shared.canPerform(content: content, serviceName: serviceName)
            Log.d(TAG, "[runCanPerform][result] label: \(label), canPerform: \(canPerform)")
            updateResult(isSuccess: true, result: "[\(label)] canPerform=\(canPerform)")
        } catch let error as ShareError {
            Log.e(TAG, "[runCanPerform][error] label: \(label), error: \(error)")
            updateResult(isSuccess: false, result: "[\(label)] errorCode=\(error.errorCode), errorMessage=\(error.errorMessage)")
        } catch {
            Log.e(TAG, "[runCanPerform][error] label: \(label), error: \(error)")
            updateResult(isSuccess: false, result: "[\(label)] error=\(error.localizedDescription)")
        }
    }

    // MARK: - Sample data helpers

    /// Renders the existing `test-image` asset catalog image to a temporary PNG file, since
    /// `.imageFile(path:)` requires a file path (not an asset catalog reference).
    private func prepareSampleImagePath() -> String? {
        guard let image = NSImage(named: "test-image") else {
            Log.e(TAG, "[prepareSampleImagePath] test-image asset not found")
            return nil
        }
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-sample-image-\(UUID().uuidString).png")
        guard writePNG(image: image, to: destURL) else {
            return nil
        }
        return destURL.path
    }

    /// Copies the rendered `test-image` PNG to `count` distinct temporary files, so multiple
    /// `.imageFile` items can be shared at once (there is only one source asset).
    private func prepareSampleImagePaths(count: Int) -> [String]? {
        guard let image = NSImage(named: "test-image") else {
            Log.e(TAG, "[prepareSampleImagePaths] test-image asset not found")
            return nil
        }
        var paths: [String] = []
        for index in 0..<count {
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("share-sample-image-\(index)-\(UUID().uuidString).png")
            guard writePNG(image: image, to: destURL) else {
                return nil
            }
            paths.append(destURL.path)
        }
        return paths
    }

    private func writePNG(image: NSImage, to url: URL) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            Log.e(TAG, "[writePNG] failed to render test-image as PNG")
            return false
        }
        do {
            try pngData.write(to: url)
            return true
        } catch {
            Log.e(TAG, "[writePNG] failed to write file: \(error)")
            return false
        }
    }

    private func prepareSampleFileURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("share-sample.txt")
        do {
            try "Shared from MacLibraryExample.".write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Log.e(TAG, "[prepareSampleFileURL] failed: \(error)")
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
                try "Shared from MacLibraryExample (\(index)).".write(to: url, atomically: true, encoding: .utf8)
                urls.append(url)
            } catch {
                Log.e(TAG, "[prepareSampleFileURLs] failed: \(error)")
                return nil
            }
        }
        return urls
    }

    // MARK: - Result display

    private func updateResult(isSuccess: Bool, result: String?) {
        Log.d(TAG, "[updateResult] isSuccess: \(isSuccess), result: \(result ?? "nil")")
        DispatchQueue.main.async {
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
            .padding(.vertical, 10)
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
