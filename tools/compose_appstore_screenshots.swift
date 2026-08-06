#!/usr/bin/env swift
// Composes the App Store screenshot boards from raw simulator captures.
// Run from the repo root:
//
//   swift tools/compose_appstore_screenshots.swift
//   swift tools/compose_appstore_screenshots.swift --input /tmp/raw --output /tmp/out
//
// Input:  <input>/<family>/<name>.png   — untouched `simctl io screenshot` grabs
// Output: <output>/<family>/<name>.png  — the boards uploaded to App Store Connect
//
// A board is the brand gradient, a two-line white caption at the top, and the
// capture below with rounded corners and a soft shadow. Output sizes are fixed
// by App Store Connect and asserted before writing:
//
//   iphone-6.9  1320 × 2868
//   ipad-13     2064 × 2752
//   watch        416 ×  496
//
// The capture is always scaled to *fit* the space left under the caption, so a
// screen can never be clipped at the bottom edge. Captures are never cropped
// implicitly — a shot that needs trimming (a modal sheet whose dimmed parent
// leaked a grey band into the grab) asks for it explicitly via `trimTop`.
//
// Captions live in the `shots` table below. That table is the only thing the
// owner edits between releases; everything under it is layout machinery.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Families

enum Family: String {
    case iphone = "iphone-6.9"
    case ipad = "ipad-13"
    case watch = "watch"
}

// MARK: - Captions — edit here

/// One board: a raw capture plus the two caption lines drawn above it.
///
/// `trimTop` / `trimBottom` are source pixels shaved off the capture *before*
/// it is laid out. They exist for one case only: a sheet captured over a dimmed
/// parent, where the parent's grey band would otherwise show above the sheet.
/// Prefer capturing the sheet full-screen and leaving these at zero.
///
/// `scrolls` marks a screen whose content runs past the bottom of the display.
/// Those boards get a short fade into the background at the bottom of the card,
/// so a half-visible row reads as "there is more below" rather than as a
/// mis-cropped screenshot. Leave it off for screens that end on their own.
struct Shot {
    let family: Family
    let file: String
    let lines: [String]
    var scrolls: Bool = false
    var trimTop: Int = 0
    var trimBottom: Int = 0
}

let shots: [Shot] = [
    // iPhone 6.9"
    Shot(family: .iphone, file: "01_onboarding", lines: ["Bouge un peu,", "chaque jour"]),
    Shot(family: .iphone, file: "02_home", lines: ["Ta journée,", "en un coup d'œil"], scrolls: true),
    Shot(family: .iphone, file: "03_walk", lines: ["Suis ta sortie", "en direct"]),
    Shot(family: .iphone, file: "04_streak", lines: ["Garde ta", "série vivante"], scrolls: true),
    Shot(family: .iphone, file: "05_stats", lines: ["Visualise", "tes progrès"], scrolls: true),
    Shot(family: .iphone, file: "06_minutes", lines: ["Chaque métrique", "compte"], scrolls: true),
    Shot(family: .iphone, file: "07_hydration", lines: ["N'oublie plus", "de boire"], scrolls: true),
    Shot(family: .iphone, file: "08_summary", lines: ["Tout ton", "historique"], scrolls: true),
    Shot(family: .iphone, file: "09_settings", lines: ["Tes objectifs,", "ton rythme"], scrolls: true),
    Shot(family: .iphone, file: "10_weather", lines: ["La météo,", "avant de sortir"]),

    // iPad 13"
    Shot(family: .ipad, file: "01_onboarding-ipad", lines: ["Bouge un peu,", "chaque jour"]),
    Shot(family: .ipad, file: "02_home-ipad", lines: ["Ta journée,", "en un coup d'œil"], scrolls: true),
    Shot(family: .ipad, file: "04_streak-ipad", lines: ["Garde ta", "série vivante"], scrolls: true),
    Shot(family: .ipad, file: "05_stats-ipad", lines: ["Visualise", "tes progrès"], scrolls: true),
    Shot(family: .ipad, file: "07_hydration-ipad", lines: ["N'oublie plus", "de boire"], scrolls: true),

    // Apple Watch
    Shot(family: .watch, file: "watch-01-today", lines: ["Ta série", "au poignet"], scrolls: true),
    Shot(family: .watch, file: "watch-02-hydration", lines: ["Bois,", "d'un tap"], scrolls: true),
    Shot(family: .watch, file: "watch-03-walk", lines: ["Ta sortie", "en direct"])
]

// MARK: - Layout

/// Per-family board geometry, in output pixels, measured from the top-left.
struct Geometry {
    let canvas: CGSize
    /// Horizontal margin around both the caption and the capture.
    let sideInset: CGFloat
    /// Space kept free under the capture.
    let bottomInset: CGFloat
    /// Top of the first caption line.
    let captionTop: CGFloat
    let captionSize: CGFloat
    /// Line height, as a multiple of the font size.
    let captionLeading: CGFloat
    /// Space between the caption block and the top of the capture.
    let captionGap: CGFloat
    let cornerRadius: CGFloat
}

let geometries: [Family: Geometry] = [
    .iphone: Geometry(
        canvas: CGSize(width: 1320, height: 2868),
        sideInset: 155, bottomInset: 180, captionTop: 150,
        captionSize: 104, captionLeading: 1.16, captionGap: 96, cornerRadius: 60
    ),
    .ipad: Geometry(
        canvas: CGSize(width: 2064, height: 2752),
        sideInset: 210, bottomInset: 190, captionTop: 140,
        captionSize: 116, captionLeading: 1.16, captionGap: 96, cornerRadius: 60
    ),
    .watch: Geometry(
        canvas: CGSize(width: 416, height: 496),
        sideInset: 32, bottomInset: 28, captionTop: 16,
        captionSize: 31, captionLeading: 1.16, captionGap: 18, cornerRadius: 48
    )
]

// Brand gradient, top to bottom. Same purple family as the app icon, lightened
// at the top so the white caption always sits on the brightest end.
let gradientTop = CGColor(srgbRed: 0xC7 / 255, green: 0x7D / 255, blue: 0xFF / 255, alpha: 1)
let gradientBottom = CGColor(srgbRed: 0x5B / 255, green: 0x21 / 255, blue: 0xB6 / 255, alpha: 1)

/// Height of the fade at the bottom of a scrolling screen, as a fraction of the
/// card. Enough to soften a half-visible row, short enough to keep it readable.
let scrollFadeFraction: CGFloat = 0.09

// MARK: - Drawing helpers

func roundedFont(size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded),
          let rounded = NSFont(descriptor: descriptor, size: size) else {
        return base
    }
    return rounded
}

/// Largest size at which every caption line still fits the content width.
func fittedCaptionSize(_ lines: [String], _ geometry: Geometry) -> CGFloat {
    let maxWidth = geometry.canvas.width - 2 * geometry.sideInset
    var size = geometry.captionSize
    while size > 8 {
        let font = roundedFont(size: size)
        let widest = lines
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        if widest <= maxWidth { break }
        size -= 1
    }
    return size
}

func makeContext(_ size: CGSize) -> CGContext {
    let width = Int(size.width), height = Int(size.height)
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        // No alpha channel: App Store Connect rejects screenshots that carry one.
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("CGContext creation failed for \(width)×\(height)")
    }
    context.interpolationQuality = .high
    return context
}

func drawBackground(in context: CGContext, size: CGSize) {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let gradient = CGGradient(
        colorsSpace: space,
        colors: [gradientTop, gradientBottom] as CFArray,
        locations: [0, 1]
    ) else {
        fatalError("Gradient creation failed")
    }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size.height),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

func drawCaption(_ lines: [String], in context: CGContext, geometry: Geometry) {
    let size = fittedCaptionSize(lines, geometry)
    let font = roundedFont(size: size)
    let lineHeight = size * geometry.captionLeading

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byClipping

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -geometry.canvas.width * 0.004)
    shadow.shadowBlurRadius = geometry.canvas.width * 0.014

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
        .shadow: shadow
    ]

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for (index, line) in lines.enumerated() {
        let top = geometry.captionTop + CGFloat(index) * lineHeight
        let rect = CGRect(
            x: geometry.sideInset,
            y: geometry.canvas.height - top - lineHeight,
            width: geometry.canvas.width - 2 * geometry.sideInset,
            height: lineHeight
        )
        (line as NSString).draw(in: rect, withAttributes: attributes)
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// Where the capture sits: centred in the band left between the caption block
/// and the bottom margin, scaled to *fit* so nothing is ever cut off.
///
/// The caption block is reserved at the *nominal* size, not the fitted one, so
/// a long caption that had to shrink doesn't shift its card out of line with
/// the neighbouring boards.
func screenRect(for source: CGSize, lineCount: Int, geometry: Geometry) -> CGRect {
    let captionHeight = CGFloat(lineCount) * geometry.captionSize * geometry.captionLeading
    let top = geometry.captionTop + captionHeight + geometry.captionGap
    let availableWidth = geometry.canvas.width - 2 * geometry.sideInset
    let availableHeight = geometry.canvas.height - geometry.bottomInset - top
    let scale = min(availableWidth / source.width, availableHeight / source.height)
    let width = (source.width * scale).rounded()
    let height = (source.height * scale).rounded()
    return CGRect(
        x: ((geometry.canvas.width - width) / 2).rounded(),
        y: (top + (availableHeight - height) / 2).rounded(),
        width: width,
        height: height
    )
}

/// The background gradient's colour at a given distance down the canvas.
func backgroundColor(atY y: CGFloat, geometry: Geometry) -> CGColor {
    let ratio = min(max(y / geometry.canvas.height, 0), 1)
    let top = gradientTop.components ?? [0, 0, 0, 1]
    let bottom = gradientBottom.components ?? [0, 0, 0, 1]
    return CGColor(
        srgbRed: top[0] + (bottom[0] - top[0]) * ratio,
        green: top[1] + (bottom[1] - top[1]) * ratio,
        blue: top[2] + (bottom[2] - top[2]) * ratio,
        alpha: 1
    )
}

/// Melts the bottom of a scrolling screen into the background so a row the
/// display happened to cut in half reads as deliberate.
func drawScrollFade(in context: CGContext, flipped: CGRect, geometry: Geometry) {
    let solid = backgroundColor(atY: geometry.canvas.height - flipped.minY, geometry: geometry)
    guard let components = solid.components else { return }
    let clear = CGColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 0)
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [clear, solid] as CFArray,
        locations: [0, 1]
    ) else {
        return
    }
    let height = flipped.height * scrollFadeFraction
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: flipped.minY + height),
        end: CGPoint(x: 0, y: flipped.minY),
        options: [.drawsAfterEndLocation]
    )
}

func drawScreen(_ image: CGImage, in context: CGContext, rect: CGRect, shot: Shot, geometry: Geometry) {
    // Flip the top-left design rect into the bottom-left CoreGraphics space.
    let flipped = CGRect(
        x: rect.minX,
        y: geometry.canvas.height - rect.maxY,
        width: rect.width,
        height: rect.height
    )
    let path = CGPath(
        roundedRect: flipped,
        cornerWidth: geometry.cornerRadius,
        cornerHeight: geometry.cornerRadius,
        transform: nil
    )

    // The shadow needs its own fill: a shadow set on a clipped draw is clipped too.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -geometry.canvas.width * 0.012),
        blur: geometry.canvas.width * 0.030,
        color: NSColor.black.withAlphaComponent(0.30).cgColor
    )
    context.addPath(path)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.draw(image, in: flipped)
    if shot.scrolls {
        drawScrollFade(in: context, flipped: flipped, geometry: geometry)
    }
    context.restoreGState()
}

// MARK: - Compose

func loadCapture(_ url: URL, shot: Shot) -> CGImage? {
    guard let image = NSImage(contentsOf: url),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    guard shot.trimTop > 0 || shot.trimBottom > 0 else { return cgImage }
    let height = cgImage.height - shot.trimTop - shot.trimBottom
    guard height > 0 else {
        fatalError("\(shot.file): trimTop + trimBottom leaves nothing of a \(cgImage.height)px capture")
    }
    // CGImage.cropping uses a top-left origin, which is what trimTop means here.
    let crop = CGRect(x: 0, y: shot.trimTop, width: cgImage.width, height: height)
    guard let cropped = cgImage.cropping(to: crop) else {
        fatalError("\(shot.file): cropping to \(crop) failed")
    }
    return cropped
}

func compose(_ shot: Shot, capture: CGImage, geometry: Geometry) -> Data {
    let context = makeContext(geometry.canvas)
    drawBackground(in: context, size: geometry.canvas)
    let source = CGSize(width: capture.width, height: capture.height)
    let rect = screenRect(for: source, lineCount: shot.lines.count, geometry: geometry)
    drawScreen(capture, in: context, rect: rect, shot: shot, geometry: geometry)
    drawCaption(shot.lines, in: context, geometry: geometry)

    guard let image = context.makeImage() else {
        fatalError("\(shot.file): CGImage creation failed")
    }
    guard image.width == Int(geometry.canvas.width), image.height == Int(geometry.canvas.height) else {
        fatalError("\(shot.file): produced \(image.width)×\(image.height), App Store Connect wants "
            + "\(Int(geometry.canvas.width))×\(Int(geometry.canvas.height))")
    }
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("\(shot.file): PNG encoding failed")
    }
    return data
}

// MARK: - Entry point

func argument(_ name: String, default fallback: String) -> String {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return fallback
    }
    return arguments[index + 1]
}

let inputRoot = URL(fileURLWithPath: argument("--input", default: "appstore-screenshots/raw"))
let outputRoot = URL(fileURLWithPath: argument("--output", default: "appstore-screenshots"))

var missing: [String] = []
var written = 0

for shot in shots {
    guard let geometry = geometries[shot.family] else { continue }
    let source = inputRoot.appendingPathComponent(shot.family.rawValue).appendingPathComponent("\(shot.file).png")
    guard let capture = loadCapture(source, shot: shot) else {
        missing.append(source.path)
        continue
    }
    let data = compose(shot, capture: capture, geometry: geometry)
    let destination = outputRoot
        .appendingPathComponent(shot.family.rawValue)
        .appendingPathComponent("\(shot.file).png")
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: destination)
    let size = "\(Int(geometry.canvas.width))×\(Int(geometry.canvas.height))"
    print("wrote \(destination.path) (\(size), \(data.count) bytes)")
    written += 1
}

print("\(written)/\(shots.count) boards composed")

if !missing.isEmpty {
    print("missing raw captures:")
    for path in missing { print("  \(path)") }
    exit(1)
}
