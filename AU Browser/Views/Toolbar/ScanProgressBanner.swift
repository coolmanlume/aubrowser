// AU Browser/Views/Toolbar/ScanProgressBanner.swift

import AUBrowserCore
import SwiftUI

/// Compact progress indicator shown in the toolbar during (or after stopping) a scan.
struct ScanProgressBanner: View {

    @EnvironmentObject private var scanManager: ScanQueueManager

    var body: some View {
        HStack(spacing: 8) {
            if scanManager.isScanning {
                ProgressView(value: scanManager.progress.fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }

            if scanManager.progress.total > 0 {
                Text("\(scanManager.progress.completed) / \(scanManager.progress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if scanManager.isScanning {
                Text("Scanning…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Stop / Resume control
            if scanManager.isScanning {
                Button {
                    scanManager.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Stop scan")
            } else if scanManager.canResume {
                Button {
                    scanManager.resumeScan()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.green.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Resume scan")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
