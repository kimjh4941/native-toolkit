//
//  ContentView.swift
//  MacLibraryExample
//
//  Created by Kim Jong Hyun on 2025/04/20.
//

import SwiftUI
import MacLibrary

struct ContentView: View {
    
    private let TAG = "ContentView"
    @State private var resultText = "Result will be displayed here"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("MacDialogManager Example")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()
                
                Text(resultText)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    let options = DialogOptions(
                        alertStyle: .informational,
                        buttons: [
                            DialogButton(title: "OK", isDefault: true),
                            DialogButton(title: "Cancel", keyEquivalent: "\u{1b}"),
                            DialogButton(title: "Delete", keyEquivalent: "d")
                        ],
                        showsHelp: true,
                        showsSuppressionButton: true,
                        suppressionButtonTitle: "Don't show this again",
                        icon: {
                            switch IconConfiguration(
                                type: .systemImage,
                                value: "cautionName",
                                renderingMode: .palette,
                                colors: ["white", "systemblue", "systemblue"],
                                size: 100,
                                weight: "ultralight",
                                scale: "large").createImage() {
                            case .success(let image):
                                return image
                            case .failure(_):
                                return nil
                            }
                        }()
                    )
                    
                    MacDialogManager.shared.showDialog(
                        title: "Hello",
                        message: "This is an alert!",
                        options: options
                    ) { result in
                        switch result {
                        case .success(let dialogResult):
                            Log.d(TAG, "ShowDialog success: \(dialogResult)")
                            updateResult(isSuccess: true, result: "ShowDialog - result: \(dialogResult)")
                        case .failure(let error):
                            Log.e(TAG, "ShowDialog error: \(error)")
                            updateResult(isSuccess: false, result: "ShowDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowDialog")
                        .buttonStyle()
                }
                
                Button(action: {
                    MacDialogManager.shared.showFileDialog(
                        title: "Select File",
                        message: "Please select a single file",
                        allowedContentTypes: ["txt", "pdf", "png", "jpg"],
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let openResult):
                            Log.d(TAG, "ShowFileDialog success: \(openResult)")
                            updateResult(isSuccess: true, result: "ShowFileDialog - result: \(openResult)")
                        case .failure(let error):
                            Log.e(TAG, "ShowFileDialog error: \(error)")
                            updateResult(isSuccess: false, result: "ShowFileDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowFileDialog")
                        .buttonStyle()
                }
                
                Button(action: {
                    MacDialogManager.shared.showMultiFileDialog(
                        title: "Select Files",
                        message: "Please select multiple files",
                        allowedContentTypes: ["txt", "pdf", "png", "jpg"],
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let openResult):
                            Log.d(TAG, "ShowMultiFileDialog success: \(openResult)")
                            updateResult(isSuccess: true, result: "ShowMultiFileDialog - result: \(openResult)")
                        case .failure(let error):
                            Log.e(TAG, "ShowMultiFileDialog error: \(error)")
                            updateResult(isSuccess: false, result: "ShowMultiFileDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowMultiFileDialog")
                        .buttonStyle()
                }
                
                Button(action: {
                    MacDialogManager.shared.showFolderDialog(
                        title: "Select Folder",
                        message: "Please select a single folder",
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let openResult):
                            Log.d(TAG, "ShowFolderDialog success: \(openResult)")
                            updateResult(isSuccess: true, result: "ShowFolderDialog - result: \(openResult)")
                        case .failure(let error):
                            Log.e(TAG, "ShowFolderDialog error: \(error)")
                            updateResult(isSuccess: false, result: "ShowFolderDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowFolderDialog")
                        .buttonStyle()
                }
                
                Button(action: {
                    MacDialogManager.shared.showMultiFolderDialog(
                        title: "Select Folders",
                        message: "Please select multiple folders",
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let openResult):
                            Log.d(TAG, "ShowMultiFolderDialog success: \(openResult)")
                            updateResult(isSuccess: true, result: "ShowMultiFolderDialog - result: \(openResult)")
                        case .failure(let error):
                            Log.e(TAG, "ShowMultiFolderDialog error: \(error)")
                            updateResult(isSuccess: false, result: "ShowMultiFolderDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowMultiFolderDialog")
                        .buttonStyle()
                }
                
                Button(action: {
                    MacDialogManager.shared.showSaveFileDialog(
                        title: "Save File",
                        message: "Please save the file",
                        nameFieldStringValue: "sample.txt",
                        allowedContentTypes: ["txt", "pdf", "png", "jpg"],
                        directoryURL: nil
                    ) { result in
                        switch result {
                        case .success(let saveResult):
                            Log.d(TAG, "ShowSaveFileDialog success: \(saveResult)")
                            updateResult(isSuccess: true, result: "ShowSaveFileDialog - result: \(saveResult)")
                        case .failure(let error):
                            Log.e(TAG, "ShowSaveFileDialog error: \(error)")
                            updateResult(isSuccess: false, result: "ShowSaveFileDialog - error: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Text("ShowSaveFileDialog")
                        .buttonStyle(backgroundColor: .green)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func updateResult(isSuccess: Bool, result: String?) {
        if isSuccess {
            resultText = "✅ \nResult: \(result ?? "nil")"
        } else {
            resultText = "❌ \nResult: \(result ?? "nil")"
        }
    }
}

extension Text {
    func buttonStyle(backgroundColor: Color = .blue) -> some View {
        self.padding()
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
