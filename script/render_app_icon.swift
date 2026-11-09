// Housekeeping — render an app icon from the versioned original mascot.
//
// Creates two 1024px PNG layers for Apple's Icon Composer, plus a flattened
// legacy preview. Never changes the silhouette, eyes, or costume: the mascot
// is drawn as an image, not recreated with approximated shapes.
// Usage: swift render_app_icon.swift <original-mascot.png> <output-directory>

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift render_app_icon.swift mascot.png output-directory\n", stderr)
    exit(2)
}
let mascotURL = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)

guard let mascot = NSImage(contentsOf: mascotURL),
      mascot.size.width > 0, mascot.size.height > 0 else {
    fputs("Unable to read the canonical Housekeeping mascot.\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func bitmap(_ drawing: () -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not allocate icon rendering context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSBezierPath(rect: canvas).fill()
    drawing()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ image: NSBitmapImageRep, as filename: String) throws {
    guard let data = image.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    try data.write(to: output.appendingPathComponent(filename), options: .atomic)
}

// Square, unmasked layers: Icon Composer will apply the native rounded mask,
// depth, glass and appearance treatment. Soft pearl is intentional: glass
// highlights must not destroy the octopus's strong dark-red silhouette.
func paintBackground() {
    let light = NSColor(calibratedRed: 0.99, green: 0.975, blue: 0.95, alpha: 1)
    let mid = NSColor(calibratedRed: 0.945, green: 0.92, blue: 0.92, alpha: 1)
    let lilac = NSColor(calibratedRed: 0.87, green: 0.85, blue: 0.91, alpha: 1)
    NSGradient(colors: [light, mid, lilac])?.draw(in: canvas, angle: -55)

    // Quiet curved reflection, more restrained than adding glossy bubbles.
    let reflection = NSBezierPath()
    reflection.move(to: NSPoint(x: 55, y: 790))
    reflection.curve(to: NSPoint(x: 960, y: 920),
                     controlPoint1: NSPoint(x: 330, y: 1140),
                     controlPoint2: NSPoint(x: 710, y: 800))
    reflection.line(to: NSPoint(x: 1024, y: 1024))
    reflection.line(to: NSPoint(x: 0, y: 1024))
    reflection.close()
    NSColor.white.withAlphaComponent(0.32).setFill()
    reflection.fill()
}

let mascotBox: NSRect = {
    // Keep generous clearance around outer tentacles even at 64px.
    let fit = min(810 / mascot.size.width, 810 / mascot.size.height)
    let width = mascot.size.width * fit
    let height = mascot.size.height * fit
    return NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2 - 12,
                  width: width, height: height)
}()

func paintMascot() {
    mascot.draw(in: mascotBox, from: .zero, operation: .sourceOver, fraction: 1)
}

let background = bitmap { paintBackground() }
let foreground = bitmap { paintMascot() }

let legacy = bitmap {
    // A traditional .icns preview still needs its own rounded-rectangle mask.
    // The layer files themselves deliberately remain unmasked.
    let mask = NSBezierPath(roundedRect: canvas.insetBy(dx: 12, dy: 12),
                            xRadius: 220, yRadius: 220)
    mask.addClip()
    paintBackground()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 33
    shadow.shadowOffset = NSSize(width: 0, height: -15)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.19)
    shadow.set()
    paintMascot()
    NSGraphicsContext.restoreGraphicsState()
}

try save(background, as: "Icon-01-Background.png")
try save(foreground, as: "Icon-02-Octopus-Foreground.png")
try save(legacy, as: "AppIcon-1024.png")
print("Rendered unmasked Icon Composer layers and the legacy preview from \(mascotURL.lastPathComponent)")
