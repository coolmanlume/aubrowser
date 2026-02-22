// AU Browser/Views/Shared/PlaceholderThumbnail.swift

import SwiftUI

/// Shown on cards whose capture failed, timed out, or hasn't run yet.
struct PlaceholderThumbnail: View {

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)

            VStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundStyle(.tertiary)
                Text("No Preview")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
    }
}
