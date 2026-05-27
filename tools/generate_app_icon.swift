#!/usr/bin/env swift
// Generates the Foulée app icon (1024x1024 PNG, no alpha) for both the
// iOS and watchOS targets. Run from the repo root:
//
//   swift tools/generate_app_icon.swift
//
// Outputs:
//   Foulee/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//   FouleeWatch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// The icon is the brand accent gradient with a bold white walking
// figure (SF Symbol) sitting in the centre.

import AppKit
import CoreGraphics
import Foundation

let canvasSize = 1024
let symbolPointSize: CGFloat = 720

func makeIcon() -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("CGContext creation failed")
    }

    // Brand accent gradient (D97AFF → BF5AF2 → 7C3AED), 135° (top-left to
    // bottom-right). Fully opaque so the icon has no alpha channel.
    let stops: [CGFloat] = [0, 0.5, 1]
    let colors = [
        CGColor(srgbRed: 0xD9 / 255, green: 0x7A / 255, blue: 0xFF / 255, alpha: 1),
        CGColor(srgbRed: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255, alpha: 1),
        CGColor(srgbRed: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255, alpha: 1)
    ] as CFArray
    guard let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: stops) else {
        fatalError("Gradient creation failed")
    }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(canvasSize)),
        end: CGPoint(x: CGFloat(canvasSize), y: 0),
        options: []
    )

    // Walking figure via SF Symbol, rendered white, centred.
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .bold)
    guard let baseSymbol = NSImage(
        systemSymbolName: "figure.walk.motion",
        accessibilityDescription: nil
    )?.withSymbolConfiguration(symbolConfig) else {
        fatalError("SF Symbol load failed — make sure you're on macOS 11+")
    }

    // Tint the symbol white.
    let tinted = NSImage(size: baseSymbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let rect = NSRect(origin: .zero, size: baseSymbol.size)
    baseSymbol.draw(in: rect, from: rect, operation: .sourceOver, fraction: 1)
    rect.fill(using: .sourceIn)
    tinted.unlockFocus()

    // Centre the symbol in the canvas with a subtle drop shadow.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.shadowBlurRadius = 32
    shadow.set()

    let symbolSize = tinted.size
    let drawRect = NSRect(
        x: (CGFloat(canvasSize) - symbolSize.width) / 2,
        y: (CGFloat(canvasSize) - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    tinted.draw(in: drawRect)

    NSGraphicsContext.restoreGraphicsState()

    guard let image = context.makeImage() else {
        fatalError("CGImage creation failed")
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    return data
}

let pngData = makeIcon()

let outputs = [
    "Foulee/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "FouleeWatch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
]

for relative in outputs {
    let url = URL(fileURLWithPath: relative)
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    try pngData.write(to: url)
    print("wrote \(relative) (\(pngData.count) bytes)")
}
