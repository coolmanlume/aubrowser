// AU Browser/Views/Sidebar/FilterRow.swift

import SwiftUI

/// A single tappable row in the sidebar, showing a checkmark when selected.
struct FilterRow: View {

    let label: String
    let isSelected: Bool
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .imageScale(.small)

            Text(label)
                .font(.callout)

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
