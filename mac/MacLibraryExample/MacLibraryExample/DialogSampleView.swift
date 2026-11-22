//
//  DialogSampleView.swift
//  MacLibraryExample
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

import SwiftUI
import MacLibrary

/// Single source of truth for the accessibility identifiers exposed by `DialogSampleView`.
///
/// A button's name is its title without the part in parentheses, starting with a capital
/// letter (the rule of the Clipboard screen's `clipboard.button.<name>`).
enum DialogSampleIdentifiers {

    static let result = "dialog.result"
    /// The three most recent results, newest first, each with its number.
    static let resultHistory = "dialog.resultHistory"

    static func button(_ name: ButtonName) -> String { "dialog.button.\(name.rawValue)" }

    enum ButtonName: String, CaseIterable {
        case showDialog = "ShowDialog"
        case showFileDialog = "ShowFileDialog"
        case showMultiFileDialog = "ShowMultiFileDialog"
        case showFolderDialog = "ShowFolderDialog"
        case showMultiFolderDialog = "ShowMultiFolderDialog"
        case showSaveFileDialog = "ShowSaveFileDialog"
    }
}

struct DialogSampleView: View {

    private typealias ID = DialogSampleIdentifiers

    /// How many results `dialog.resultHistory` keeps.
    private static let historyLimit = 3

    private let TAG = "DialogSampleView"
    @State private var resultText = "Result will be displayed here"
    /// Counts the results the screen has shown, so a test can tell a new one from a repeat.
    @State private var resultSequence = 0
    /// The most recent results as `#<number> <text>`, newest first.
    @State private var resultHistory: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("MacDialogManager Example")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 8)

                Text(resultText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .accessibilityIdentifier(ID.result)
                    // The number travels with the text, so a test reads both from one value.
                    .accessibilityValue("#\(resultSequence) \(resultText)")

                Text(historyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(ID.resultHistory)
                    .accessibilityValue(historyText)

                Button(action: {
                    Log.d(TAG, "[ShowDialog] called")
                    let buttons = [
                        DialogButton(title: "OK", isDefault: true),
                        DialogButton(title: "Cancel", keyEquivalent: "\u{1b}"),
                        DialogButton(title: "Delete", keyEquivalent: "d")
                    ]

                    let options = DialogOptions(
                        alertStyle: .informational,
                        buttons: buttons,
                        showsHelp: true,
                        showsSuppressionButton: true,
                        suppressionButtonTitle: "Don't show this again",
                        icon: IconConfiguration(
                            type: .systemSymbol,
                            value: "info.square.fill",
                            renderingMode: .palette,
                            colors: ["white", "systemblue", "systemblue"],
                            size: 64,
                            weight: .regular,
                            scale: .medium
                        ),
                        accessoryView: nil
                    )

                    MacDialogManager.shared.showDialog(
                        title: "Hello from macOS",
                        message: "This is a native macOS dialog!",
                        options: options
                    ) { result in
                        switch result {
                        case .success(let dialogResult):
                            Log.d(TAG, "[ShowDialog] success: \(dialogResult)")
                            updateResult(isSuccess: true, result: "ShowDialog - result: \(dialogResult)")
                        case .failure(let error):
                            Log.e(TAG, "[ShowDialog] error: \(error)")
                            updateResult(isSuccess: false, result: "ShowDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowDialog")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(.showDialog))

                Button(action: {
                    Log.d(TAG, "[ShowFileDialog] called")
                    MacDialogManager.shared.showFileDialog(
                        title: "Select a file",
                        message: "Please select a file to open.",
                        allowedContentTypes: ["txt", "png"],
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let openResult):
                            Log.d(TAG, "[ShowFileDialog] success: \(openResult)")
                            updateResult(isSuccess: true, result: "ShowFileDialog - result: \(openResult)")
                        case .failure(let error):
                            Log.e(TAG, "[ShowFileDialog] error: \(error)")
                            updateResult(isSuccess: false, result: "ShowFileDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowFileDialog")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(.showFileDialog))

                Button(action: {
                    Log.d(TAG, "[ShowMultiFileDialog] called")
                    MacDialogManager.shared.showMultiFileDialog(
                        title: "Select files",
                        message: "Please select files to open.",
                        allowedContentTypes: ["txt", "png"],
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let openResult):
                            Log.d(TAG, "[ShowMultiFileDialog] success: \(openResult)")
                            updateResult(isSuccess: true, result: "ShowMultiFileDialog - result: \(openResult)")
                        case .failure(let error):
                            Log.e(TAG, "[ShowMultiFileDialog] error: \(error)")
                            updateResult(isSuccess: false, result: "ShowMultiFileDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowMultiFileDialog")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(.showMultiFileDialog))

                Button(action: {
                    Log.d(TAG, "[ShowFolderDialog] called")
                    MacDialogManager.shared.showFolderDialog(
                        title: "Select a folder",
                        message: "Please select a folder to open.",
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let openResult):
                            Log.d(TAG, "[ShowFolderDialog] success: \(openResult)")
                            updateResult(isSuccess: true, result: "ShowFolderDialog - result: \(openResult)")
                        case .failure(let error):
                            Log.e(TAG, "[ShowFolderDialog] error: \(error)")
                            updateResult(isSuccess: false, result: "ShowFolderDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowFolderDialog")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(.showFolderDialog))

                Button(action: {
                    Log.d(TAG, "[ShowMultiFolderDialog] called")
                    MacDialogManager.shared.showMultiFolderDialog(
                        title: "Select folders",
                        message: "Please select folders to open.",
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let openResult):
                            Log.d(TAG, "[ShowMultiFolderDialog] success: \(openResult)")
                            updateResult(isSuccess: true, result: "ShowMultiFolderDialog - result: \(openResult)")
                        case .failure(let error):
                            Log.e(TAG, "[ShowMultiFolderDialog] error: \(error)")
                            updateResult(isSuccess: false, result: "ShowMultiFolderDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowMultiFolderDialog")
                        .buttonStyle()
                }
                .accessibilityIdentifier(ID.button(.showMultiFolderDialog))

                Button(action: {
                    Log.d(TAG, "[ShowSaveFileDialog] called")
                    MacDialogManager.shared.showSaveFileDialog(
                        title: "Save File",
                        message: "Choose a destination",
                        nameFieldStringValue: "default",
                        allowedContentTypes: ["txt"],
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let saveResult):
                            Log.d(TAG, "[ShowSaveFileDialog] success: \(saveResult)")
                            updateResult(isSuccess: true, result: "ShowSaveFileDialog - result: \(saveResult)")
                        case .failure(let error):
                            Log.e(TAG, "[ShowSaveFileDialog] error: \(error)")
                            updateResult(isSuccess: false, result: "ShowSaveFileDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowSaveFileDialog")
                        .buttonStyle(backgroundColor: .green)
                }
                .accessibilityIdentifier(ID.button(.showSaveFileDialog))
            }
            .padding()
        }
        .navigationTitle("Dialog Example")
    }

    /// The value of `dialog.resultHistory`: `#5 <text> / #4 <text> / #3 <text>`, or `-` before
    /// the first result.
    private var historyText: String {
        resultHistory.isEmpty ? "-" : resultHistory.joined(separator: " / ")
    }

    /// Shows a result. The text, its number and the history change together, synchronously, as
    /// the text did before the number was added (the order of the updates is kept on purpose).
    private func updateResult(isSuccess: Bool, result: String?) {
        if isSuccess {
            resultText = "✅ \nResult: \(result ?? "nil")"
        } else {
            resultText = "❌ \nResult: \(result ?? "nil")"
        }
        resultSequence += 1
        resultHistory.insert("#\(resultSequence) \(resultText)", at: 0)
        if resultHistory.count > Self.historyLimit {
            resultHistory.removeLast(resultHistory.count - Self.historyLimit)
        }
    }
}

#Preview {
    DialogSampleView()
}