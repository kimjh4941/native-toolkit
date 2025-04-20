//
//  ContentView.swift
//  IosLibraryExample
//
//  Created by Kim Jong Hyun on 2025/04/12.
//

import SwiftUI
import IosLibrary

struct ContentView: View {
    var body: some View {
        VStack {
            Button(action: {
                IosDialogManager.shared.showDialog(title: "Hello", message: "This is an alert!", actions: [UIAlertAction(title: "OK", style: .default, handler: nil)])
                        }) {
                            Text("Show Alert")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
