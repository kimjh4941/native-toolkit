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
            Button("Show Dialog", action: {
                MacDialogManager.shared.showDialog(title: "Hello", message: "This is an alert!", handler: { result in
                    Log.d(TAG, "result: \(result)")})
            })
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
