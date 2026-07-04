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
                            runShare(
                                label: "shareText",
                                content: ShareContent(items: [.text("Shared from IosLibraryExample")])
                            )
                        }
                    }

                    sectionView(title: "URL") {
                        Button("ShareURL") {
                            runShare(
                                label: "shareURL",
                                content: ShareContent(items: [.url("https://www.apple.com")])
                            )
                        }

                        Button("ShareURLWithPreview") {
                            runShare(
                                label: "shareURLWithPreview",
                                content: ShareContent(
                                    items: [.url("https://www.apple.com")],
                                    previewTitle: "Apple"
                                )
                            )
                        }
                    }

                    sectionView(title: "Image") {
                        Button("ShareImage") {
                            guard let imagePath = bundledImagePath() else {
                                updateResult(isSuccess: false, result: "[shareImage] Sample image not found in bundle")
                                return
                            }
                            runShare(
                                label: "shareImage",
                                content: ShareContent(items: [.imageFile(path: imagePath)])
                            )
                        }
                    }

                    sectionView(title: "File") {
                        Button("ShareFile") {
                            guard let fileURL = prepareSampleFileURL() else {
                                updateResult(isSuccess: false, result: "[shareFile] Sample file preparation failed")
                                return
                            }
                            runShare(
                                label: "shareFile",
                                content: ShareContent(items: [.file(path: fileURL.path)])
                            )
                        }
                    }

                    sectionView(title: "Combination") {
                        Button("ShareMultiple") {
                            runShare(
                                label: "shareMultiple",
                                content: ShareContent(items: [
                                    .text("Check this out"),
                                    .url("https://www.apple.com")
                                ])
                            )
                        }

                        Button("ShareWithSubject") {
                            runShare(
                                label: "shareWithSubject",
                                content: ShareContent(
                                    items: [.text("Body text")],
                                    subject: "Sample Subject"
                                )
                            )
                        }

                        Button("ShareExcludingActivities") {
                            runShare(
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

                    sectionView(title: "Error") {
                        Button("ShareEmpty") {
                            runShare(label: "shareEmpty", content: ShareContent(items: []))
                        }

                        Button("ShareInvalidURL") {
                            runShare(
                                label: "shareInvalidURL",
                                content: ShareContent(items: [.url("not a valid url")])
                            )
                        }

                        Button("ShareMissingFile") {
                            runShare(
                                label: "shareMissingFile",
                                content: ShareContent(items: [.file(path: "/nonexistent/share-missing.txt")])
                            )
                        }

                        Button("ShareMissingImage") {
                            runShare(
                                label: "shareMissingImage",
                                content: ShareContent(items: [.imageFile(path: "/nonexistent/share-missing.png")])
                            )
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

    private func runShare(label: String, content: ShareContent) {
        Log.d(TAG, "[runShare] label: \(label), items: \(content.items.count)")
        IosShareManager.shared.share(content: content) { isSuccess, completed, activityType, errorMessage in
            Log.d(
                TAG,
                "[runShare][completion] label: \(label), isSuccess: \(isSuccess), completed: \(completed), activityType: \(activityType ?? "nil"), errorMessage: \(errorMessage ?? "nil")"
            )
            let detail: String
            if isSuccess {
                detail = completed
                    ? "[\(label)] completed=true, activityType=\(activityType ?? "nil")"
                    : "[\(label)] completed=false (cancelled)"
            } else {
                detail = "[\(label)] errorMessage=\(errorMessage ?? "nil")"
            }
            updateResult(isSuccess: isSuccess, result: detail)
        }
    }

    // MARK: - Sample data helpers

    private func bundledImagePath() -> String? {
        Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path
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
