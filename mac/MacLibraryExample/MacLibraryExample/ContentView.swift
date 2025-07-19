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
    
    var body: some View {
        VStack {
            Button("ShowDialog", action: {
                MacDialogManager.shared.showDialog(
                    title: "Hello",
                    message: "This is an alert!",
                    options: DialogOptions()
                ) { result in
                    switch result {
                    case .success(let dialogResult):
                        Log.d(TAG, "ShowDialog success: \(dialogResult)")
                    case .failure(let error):
                        Log.e(TAG, "ShowDialog error: \(error)")
                    }
                }
            })
            
            Button("ShowFileDialog", action: {
                MacDialogManager.shared.showFileDialog(
                    title: "ファイルを選択",
                    message: "単一ファイルを選択してください",
                    allowedContentTypes: ["txt", "pdf", "png", "jpg"],
                    directoryURL: nil
                ) { result in
                    switch result {
                    case .success(let openResult):
                        Log.d(TAG, "ShowFileDialog success: \(openResult)")
                    case .failure(let error):
                        Log.e(TAG, "ShowFileDialog error: \(error)")
                    }
                }
            })
            
            Button("ShowMultiFileDialog", action: {
                MacDialogManager.shared.showMultiFileDialog(
                    title: "ファイルを選択",
                    message: "複数ファイルを選択してください",
                    allowedContentTypes: ["txt", "pdf", "png", "jpg"],
                    directoryURL: nil
                ) { result in
                    switch result {
                    case .success(let openResult):
                        Log.d(TAG, "ShowMultiFileDialog success: \(openResult)")
                    case .failure(let error):
                        Log.e(TAG, "ShowMultiFileDialog error: \(error)")
                    }
                }
            })
            
            Button("ShowFolderDialog", action: {
                MacDialogManager.shared.showFolderDialog(
                    title: "フォルダを選択",
                    message: "単一フォルダを選択してください",
                    directoryURL: nil
                ) { result in
                    switch result {
                    case .success(let openResult):
                        Log.d(TAG, "ShowFolderDialog success: \(openResult)")
                    case .failure(let error):
                        Log.e(TAG, "ShowFolderDialog error: \(error)")
                    }
                }
            })
            
            Button("ShowMultiFolderDialog", action: {
                MacDialogManager.shared.showMultiFolderDialog(
                    title: "フォルダを選択",
                    message: "複数フォルダを選択してください",
                    directoryURL: nil
                ) { result in
                    switch result {
                    case .success(let openResult):
                        Log.d(TAG, "ShowMultiFolderDialog success: \(openResult)")
                    case .failure(let error):
                        Log.e(TAG, "ShowMultiFolderDialog error: \(error)")
                    }
                }
            })
            
            Button("ShowSaveFileDialog", action: {
                MacDialogManager.shared.showSaveFileDialog(
                    title: "ファイルを保存",
                    message: "ファイルを保存してください",
                    nameFieldStringValue: "sample.txt",
                    allowedContentTypes: ["txt", "pdf", "png", "jpg"],
                    directoryURL: nil
                ) { result in
                    switch result {
                    case .success(let saveResult):
                        Log.d(TAG, "ShowSaveFileDialog success: \(saveResult)")
                    case .failure(let error):
                        Log.e(TAG, "ShowSaveFileDialog error: \(error)")
                    }
                }
            })
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
