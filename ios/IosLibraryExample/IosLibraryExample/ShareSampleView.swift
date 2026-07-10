import SwiftUI
import IosLibrary

struct ShareSampleView: View {

    private let TAG = "ShareSampleView"

    @State private var resultText = "Result will be displayed here"

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

            ScrollView {
                VStack(spacing: 16) {
                    sectionView(title: "Text") {
                        Button("ShareText") {
                            Task {
                                await runShare(
                                    label: "shareText",
                                    content: ShareContent(items: [.text("Shared from IosLibraryExample")])
                                )
                            }
                        }
                    }

                    sectionView(title: "URL") {
                        Button("ShareURL") {
                            Task {
                                await runShare(
                                    label: "shareURL",
                                    content: ShareContent(items: [.url("https://www.apple.com")])
                                )
                            }
                        }

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
                    }

                    sectionView(title: "Image") {
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
                    }

                    sectionView(title: "File") {
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
                    }

                    sectionView(title: "Combination") {
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
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
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

    private func runShare(label: String, content: ShareContent) async {
        Log.d(TAG, "[runShare] label: \(label), items: \(content.items.count)")
        do {
            let result = try await IosShareManager.shared.share(content: content)
            Log.d(
                TAG,
                "[runShare][result] label: \(label), completed: \(result.completed), activityType: \(result.activityType ?? "nil")"
            )
            let detail = result.completed
                ? "[\(label)] completed=true, activityType=\(result.activityType ?? "nil")"
                : "[\(label)] completed=false (cancelled)"
            updateResult(isSuccess: true, result: detail)
        } catch {
            Log.e(TAG, "[runShare][error] label: \(label), error: \(error)")
            updateResult(isSuccess: false, result: "[\(label)] errorMessage=\(error.localizedDescription)")
        }
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
                Log.e(TAG, "[prepareSampleImagePaths] failed: \(error)")
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
                try "Shared from IosLibraryExample (\(index)).".write(to: url, atomically: true, encoding: .utf8)
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
