//
//  DialogSampleView.swift
//  MacLibraryExample
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

import SwiftUI
import MacLibrary

struct DialogSampleView: View {

    private let TAG = "DialogSampleView"
    @State private var resultText = "Result will be displayed here"

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
            }
            .padding()
        }
        .navigationTitle("Dialog Example")
    }

    private func updateResult(isSuccess: Bool, result: String?) {
        if isSuccess {
            resultText = "✅ \nResult: \(result ?? "nil")"
        } else {
            resultText = "❌ \nResult: \(result ?? "nil")"
        }
    }
}

#Preview {
    DialogSampleView()
}