// CaptureHelper/main.swift
// Called as: CaptureHelper <type> <subtype> <manufacturer> <outputPath> <maxWidth>
//
// Exit codes:
//  0  Success — JPEG written, dimensions printed to stdout as "WxH"
//  1  Invalid arguments
//  2  Component not found
//  3  TIMEOUT: instantiation (>10s)
//  4  FAILED: instantiation
//  5  TIMEOUT: GUI render (>8s)
//  6  FAILED: no view returned
//  7  FAILED: bitmap capture
//  8  FAILED: JPEG encoding
//  9  FAILED: disk write

import AudioToolbox
import AVFoundation
import AppKit
import CoreAudioKit
import Foundation

// NSApplication must be initialised before any AppKit (window/view) operations.
// .prohibited keeps the helper out of the Dock and App Switcher.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

guard CommandLine.arguments.count == 6 else {
    fputs("Invalid arguments\n", stderr)
    exit(1)
}

let typeCode         = UInt32(CommandLine.arguments[1])!
let subTypeCode      = UInt32(CommandLine.arguments[2])!
let manufacturerCode = UInt32(CommandLine.arguments[3])!
let outputPath       = CommandLine.arguments[4]
let maxWidth         = Int(CommandLine.arguments[5])!

var desc = AudioComponentDescription(
    componentType:        typeCode,
    componentSubType:     subTypeCode,
    componentManufacturer: manufacturerCode,
    componentFlags:       UInt32(0),
    componentFlagsMask:   UInt32(0)
)

guard AudioComponentFindNext(nil, &desc) != nil else {
    fputs("Component not found\n", stderr)
    exit(2)
}

// MARK: - Instantiate AU

let instantiateSemaphore = DispatchSemaphore(value: 0)
var audioUnit: AVAudioUnit?

AVAudioUnit.instantiate(with: desc, options: .loadInProcess) { au, _ in
    audioUnit = au
    instantiateSemaphore.signal()
}

if instantiateSemaphore.wait(timeout: .now() + 10) == .timedOut {
    fputs("TIMEOUT:instantiation\n", stderr)
    exit(3)
}

guard let au = audioUnit else {
    fputs("FAILED:instantiation\n", stderr)
    exit(4)
}

// MARK: - Request view controller

var viewController: NSViewController?
let viewSemaphore = DispatchSemaphore(value: 0)

au.auAudioUnit.requestViewController { vc in
    viewController = vc
    viewSemaphore.signal()
}

if viewSemaphore.wait(timeout: .now() + 8) == .timedOut {
    fputs("TIMEOUT:gui_render\n", stderr)
    exit(5)
}

guard let vc = viewController else {
    fputs("FAILED:no_view\n", stderr)
    exit(6)
}

let pluginView = vc.view
// Initial layout pass with whatever frame the plugin provided.
pluginView.layoutSubtreeIfNeeded()
let initialSize = pluginView.bounds.size

// Choose window size:
// • Plugin knows its own size (both dims > 0): use it as-is so the view
//   isn't auto-stretched to a larger canvas.
// • Plugin reports zero width/height (e.g. BitterSweet starts at 0×350 and
//   settles to 900×700 during the RunLoop): give it a generous 1024×768 canvas
//   so it has room to self-size. The actual capture size is measured AFTER the
//   RunLoop, so the window size only needs to be "big enough".
let windowSize: CGSize
if initialSize.width > 0 && initialSize.height > 0 {
    windowSize = initialSize
} else {
    windowSize = CGSize(width: 1024, height: 768)
}

let offscreenWindow = NSWindow(
    contentRect: NSRect(origin: .zero, size: windowSize),
    styleMask:   .borderless,
    backing:     .buffered,
    defer:       false
)
offscreenWindow.isReleasedWhenClosed = false
offscreenWindow.contentView = pluginView

// Position far off-screen and order the window front.
// CALayer-backed plugin views (and iLok-secured plugins) require a live,
// visible window backing to trigger layer compositing and self-sizing.
// Without this, the window's backing store is never allocated and the
// plugin view stays at near-zero width regardless of how long we wait.
offscreenWindow.setFrameOrigin(NSPoint(x: -32_000, y: -32_000))
offscreenWindow.orderFrontRegardless()

// Give the plugin 4 s to finish drawing, validate iLok/licences, and
// finalise its layout.
RunLoop.main.run(until: Date(timeIntervalSinceNow: 4.0))

// Measure AFTER the run loop — size may differ significantly from initialSize.
let originalSize = pluginView.bounds.size

// Use >= 1 rather than > 0 to reject near-zero floats (e.g. 0.001 px)
// that would round to Int(0) and produce a degenerate JPEG.
guard originalSize.width >= 1, originalSize.height >= 1 else {
    fputs("FAILED:zero_size\n", stderr)
    exit(7)
}

let scale = min(CGFloat(maxWidth) / originalSize.width, 1.0)
let targetSize = CGSize(
    width:  round(originalSize.width  * scale),
    height: min(round(originalSize.height * scale), CGFloat(maxWidth))
)

// MARK: - Resize window to plugin's settled size, then capture

// Resize the window to exactly the plugin's settled size so the compositor
// buffer is precisely the plugin content area — no letterboxing or padding.
offscreenWindow.setContentSize(originalSize)
// Brief run to let the compositor update after the resize.
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

// MARK: - Capture bitmap
//
// Primary: CGWindowListCreateImage reads from the window server's compositor
// buffer, which includes GPU-rendered content (Metal, OpenGL, IOSurface-backed
// layers). Plugins that use custom rendering engines (e.g. Flux "Pure") render
// via CAMetalLayer and appear black with bitmapImageRepForCachingDisplay.
//
// Fallback: bitmapImageRepForCachingDisplay for software/Core-Animation-only
// views (works for the majority of plugins).

let bitmapRep: NSBitmapImageRep
let windowID = CGWindowID(offscreenWindow.windowNumber)

if let cgImage = CGWindowListCreateImage(
    .null,
    .optionIncludingWindow,
    windowID,
    [.boundsIgnoreFraming, .nominalResolution]
), cgImage.width > 0, cgImage.height > 0 {
    bitmapRep = NSBitmapImageRep(cgImage: cgImage)
} else {
    guard let rep = pluginView.bitmapImageRepForCachingDisplay(in: pluginView.bounds) else {
        fputs("FAILED:bitmap\n", stderr)
        exit(7)
    }
    pluginView.cacheDisplay(in: pluginView.bounds, to: rep)
    bitmapRep = rep
}

// MARK: - Scale and encode as JPEG

let finalImage = NSImage(size: targetSize)
finalImage.lockFocus()
bitmapRep.draw(
    in:             NSRect(origin: .zero, size: targetSize),
    from:           NSRect(origin: .zero, size: originalSize),
    operation:      .copy,
    fraction:       1.0,
    respectFlipped: true,
    hints:          [.interpolation: NSImageInterpolation.high.rawValue]
)
finalImage.unlockFocus()

guard
    let tiffData  = finalImage.tiffRepresentation,
    let bitmap    = NSBitmapImageRep(data: tiffData),
    let jpegData  = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5])
else {
    fputs("FAILED:jpeg_encoding\n", stderr)
    exit(8)
}

// MARK: - Write to disk

do {
    try jpegData.write(to: URL(fileURLWithPath: outputPath))
    print("\(Int(targetSize.width))x\(Int(targetSize.height))")
    exit(0)
} catch {
    fputs("FAILED:write:\(error)\n", stderr)
    exit(9)
}
