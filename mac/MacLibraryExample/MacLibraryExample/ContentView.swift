//
//  ContentView.swift
//  MacLibraryExample
//
//  Created by Kim Jong Hyun on 2025/04/20.
//

import SwiftUI

/// Single source of truth for the accessibility identifiers of the main menu cards.
enum MenuIdentifiers {
    static let dialog = "menu.dialog"
    static let notification = "menu.notification"
    static let share = "menu.share"
    static let clipboard = "menu.clipboard"
}

struct ContentView: View {

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Native Toolkit macOS Example")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.top, 8)

                    NavigationLink {
                        DialogSampleView()
                    } label: {
                        menuCard(
                            title: "Dialog Example",
                            subtitle: "Show native macOS dialogs"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(MenuIdentifiers.dialog)

                    NavigationLink {
                        NotificationSampleView()
                    } label: {
                        menuCard(
                            title: "Notification Example",
                            subtitle: "Test local notification features"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(MenuIdentifiers.notification)

                    NavigationLink {
                        ShareSampleView()
                    } label: {
                        menuCard(
                            title: "Share Example",
                            subtitle: "Share content via the system sharing picker"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(MenuIdentifiers.share)

                    NavigationLink {
                        ClipboardSampleView()
                    } label: {
                        menuCard(
                            title: "Clipboard Example",
                            subtitle: "Copy, read, detect, observe and paste"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(MenuIdentifiers.clipboard)

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationTitle("Main Menu")
        }
    }

    @ViewBuilder
    private func menuCard(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
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
