import SwiftUI

struct ContentView: View {

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Native Toolkit iOS Example")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.top, 8)

                    NavigationLink {
                        DialogSampleView()
                    } label: {
                        menuCard(
                            title: "Dialog Example",
                            subtitle: "Show native iOS dialogs"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NotificationSampleView()
                    } label: {
                        menuCard(
                            title: "Notification Example",
                            subtitle: "Test local notification features"
                        )
                    }
                    .buttonStyle(.plain)

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
        .background(Color(white: 0.95))
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
