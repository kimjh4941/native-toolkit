//
//  RowListView.swift
//  IosLibraryCApiUITestApp
//

import SwiftUI

/// The result lines over the rows of the drawn sections. Both are plain stacks and not lists, so that
/// every identifier is in the accessibility tree whether it is on the screen or not.
struct RowListView: View {
    @ObservedObject private var log = ResultLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.caption)
                            .accessibilityIdentifier("result.line.\(index)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 140)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CApiRowCatalog.drawn) { section in
                        Text(section.id)
                            .font(.headline)
                        ForEach(section.rows) { row in
                            RowView(row: row)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}

private struct RowView: View {
    let row: CApiRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.id)
            HStack {
                Button("Run") { RowRunner.run(row) }
                    .accessibilityIdentifier("row.\(row.id).run")
                Button("After \(Int(RowRunner.delay)) s") { RowRunner.runAfterDelay(row) }
                    .accessibilityIdentifier("row.\(row.id).runAfterDelay")
            }
            .buttonStyle(.bordered)
        }
    }
}
