import AppKit
import Foundation

private let canvasSize = NSSize(width: 1920, height: 1080)

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

private func centeredText(
    _ text: String,
    y: CGFloat,
    font: NSFont,
    color: NSColor,
    tracking: CGFloat = 0
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking,
    ]
    let size = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (canvasSize.width - size.width) / 2, y: y),
        withAttributes: attributes
    )
}

private func renderCard(
    outputPath: String,
    iconPath: String,
    title: String,
    lines: [(String, CGFloat, NSFont, NSColor, CGFloat)]
) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: Int(canvasSize.width) * 4,
        bitsPerPixel: 32
    ) else {
        throw NSError(domain: "SofterTitleCards", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    color(8, 19, 21).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

    if let icon = NSImage(contentsOfFile: iconPath) {
        let iconSize = NSSize(width: 250, height: 250)
        icon.draw(
            in: NSRect(
                x: (canvasSize.width - iconSize.width) / 2,
                y: 680,
                width: iconSize.width,
                height: iconSize.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    centeredText(
        title,
        y: 560,
        font: .systemFont(ofSize: 78, weight: .bold),
        color: .white,
        tracking: 8
    )
    for line in lines {
        centeredText(line.0, y: line.1, font: line.2, color: line.3, tracking: line.4)
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SofterTitleCards", code: 2)
    }
    try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconPath = root.appendingPathComponent("site/assets/softer-icon-512.png").path
let frames = root.appendingPathComponent("output/video/frames")

try renderCard(
    outputPath: frames.appendingPathComponent("00-title.png").path,
    iconPath: iconPath,
    title: "SOFTER",
    lines: [
        ("Make the next minute smaller.", 475, .systemFont(ofSize: 42, weight: .semibold), color(99, 215, 215), 0),
        ("Private mental wellbeing support for macOS", 405, .systemFont(ofSize: 28, weight: .regular), color(216, 224, 226), 0),
        ("Hack for Humanity | Summer 2026", 120, .systemFont(ofSize: 22, weight: .medium), color(151, 165, 168), 0),
    ]
)

try renderCard(
    outputPath: frames.appendingPathComponent("09-closing.png").path,
    iconPath: iconPath,
    title: "CLEAR. PRIVATE. OPTIONAL.",
    lines: [
        ("Softer does not promise calm.", 475, .systemFont(ofSize: 34, weight: .regular), color(216, 224, 226), 0),
        ("It makes the next minute smaller.", 405, .systemFont(ofSize: 40, weight: .semibold), color(99, 215, 215), 0),
        ("github.com/TanavG223/Softer", 120, .systemFont(ofSize: 24, weight: .medium), color(151, 165, 168), 0),
    ]
)

try renderCard(
    outputPath: frames.appendingPathComponent("01b-private-start.png").path,
    iconPath: iconPath,
    title: "NO ACCOUNT. NO CLOUD.",
    lines: [
        ("No questionnaire. No streak to protect.", 475, .systemFont(ofSize: 38, weight: .semibold), color(99, 215, 215), 0),
        ("Start without saving.", 405, .systemFont(ofSize: 30, weight: .regular), color(216, 224, 226), 0),
        ("Private by default", 120, .systemFont(ofSize: 22, weight: .medium), color(151, 165, 168), 0),
    ]
)

try renderCard(
    outputPath: frames.appendingPathComponent("04e-finite-play.png").path,
    iconPath: iconPath,
    title: "FINITE PLAY",
    lines: [
        ("No score. No timer. No losing.", 475, .systemFont(ofSize: 42, weight: .semibold), color(99, 215, 215), 0),
        ("Hint and Undo appear only when requested.", 405, .systemFont(ofSize: 28, weight: .regular), color(216, 224, 226), 0),
        ("Stopping is a valid ending", 120, .systemFont(ofSize: 22, weight: .medium), color(151, 165, 168), 0),
    ]
)

try renderCard(
    outputPath: frames.appendingPathComponent("07b-local-design.png").path,
    iconPath: iconPath,
    title: "LOCAL BY DESIGN",
    lines: [
        ("SwiftUI | CryptoKit | macOS Keychain", 475, .systemFont(ofSize: 38, weight: .semibold), color(99, 215, 215), 0),
        ("No model, chatbot, analytics, or cloud backend.", 405, .systemFont(ofSize: 28, weight: .regular), color(216, 224, 226), 0),
        ("58 behavioral checks", 120, .systemFont(ofSize: 22, weight: .medium), color(151, 165, 168), 0),
    ]
)
