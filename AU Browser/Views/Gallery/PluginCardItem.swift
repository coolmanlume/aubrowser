// AU Browser/Views/Gallery/PluginCardItem.swift

import AppKit
import AUBrowserCore
import SwiftUI

/// A single card in the plugin grid.
///
/// Shows the JPEG thumbnail (or a placeholder), the plugin name and manufacturer,
/// and a hover overlay with quick-action buttons.
struct PluginCardItem: View {

    let row: PluginRow
    var isSelected: Bool = false
    var onSelect: () -> Void = {}
    var onToggleSelection: () -> Void = {}

    @EnvironmentObject private var store: PluginStore
    @EnvironmentObject private var scanManager: ScanQueueManager

    @State private var image: NSImage?
    @State private var isHovered = false

    private var isFavorite: Bool   { row.userData?.isFavorite ?? false }
    private var isCapturing: Bool  { scanManager.progress.inProgress.contains(row.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailArea
            labelArea
        }
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(6)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
            }
        }
        .shadow(color: .black.opacity(isHovered ? 0.18 : 0.07), radius: isHovered ? 8 : 3, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                onToggleSelection()
            } else {
                onSelect()
            }
        }
        .contextMenu { contextMenuItems }
        .task(id: row.thumbnail?.jpegPath) {
            image = nil
            if let thumb = row.thumbnail {
                image = await ThumbnailCache.shared.image(for: thumb)
            }
        }
    }

    // MARK: - Subviews

    private var thumbnailArea: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity.animation(.easeIn(duration: 0.3)))
                } else {
                    PlaceholderThumbnail()
                }
            }
            .frame(width: 220, height: 140)
            .clipped()

            // Per-card capture progress indicator
            if isCapturing {
                ZStack {
                    Color.black.opacity(0.35)
                    VStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.white)
                        Text("Capturing…")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }
                .transition(.opacity)
            } else if isHovered {
                hoverOverlay
                    .transition(.opacity.animation(.easeIn(duration: 0.1)))
            }
        }
        .frame(height: 140)
        .animation(.easeInOut(duration: 0.2), value: isCapturing)
    }

    private var hoverOverlay: some View {
        HStack(spacing: 12) {
            overlayButton(
                icon: isFavorite ? "heart.fill" : "heart",
                tint: isFavorite ? .red : .white
            ) {
                Task { await store.toggleFavorite(pluginId: row.id) }
            }

            overlayButton(icon: "arrow.clockwise", tint: .white) {
                scanManager.rescan(row.plugin)
            }

            overlayButton(icon: "doc.on.doc", tint: .white) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.plugin.name, forType: .string)
            }
        }
        .padding(.bottom, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private func overlayButton(
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .shadow(radius: 2)
        }
        .buttonStyle(.plain)
    }

    private var labelArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.plugin.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(row.plugin.manufacturer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            Task { await store.toggleFavorite(pluginId: row.id) }
        }
        Button("Rescan") {
            scanManager.rescan(row.plugin)
        }
        Divider()
        Button("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.plugin.name, forType: .string)
        }
        Button("Copy Bundle Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.plugin.bundlePath, forType: .string)
        }
        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(row.plugin.bundlePath,
                                          inFileViewerRootedAtPath: "")
        }
    }
}
