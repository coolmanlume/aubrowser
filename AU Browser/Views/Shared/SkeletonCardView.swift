// AU Browser/Views/Shared/SkeletonCardView.swift

import SwiftUI

/// Animated shimmer placeholder shown in the grid while a capture is in progress.
struct SkeletonCardView: View {

    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            Rectangle()
                .fill(shimmerGradient)
                .frame(height: 140)

            // Text rows
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 130, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 90, height: 10)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(width: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(NSColor.controlBackgroundColor), location: phase - 0.3),
                .init(color: Color(NSColor.separatorColor).opacity(0.4), location: phase),
                .init(color: Color(NSColor.controlBackgroundColor), location: phase + 0.3),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
