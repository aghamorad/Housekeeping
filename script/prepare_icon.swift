// Full-bleed the source art onto the 1024 canvas, with no transparency left.
//
// macOS Tahoe masks every app icon into its own rounded square, and puts a pale
// plinth behind any icon that does not reach the edges. Art with transparent
// padding, or even just rounded corners, therefore renders as a small square
// floating inside a bigger one. So: crop to the artwork's solid bounds, scale it
// to fill the canvas edge to edge, and back the corners with the artwork's own
// border colour. Tahoe's mask then cuts the rounded square itself.
//
// Usage: swift prepare_icon.swift <source.png> <out.png>

import AppKit
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count > 2 else {
    FileHandle.standardError.write("usage: prepare_icon.swift <source.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let sourcePath = arguments[1]
let outputPath = arguments[2]

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("could not read \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

let srcW = art.width
let srcH = art.height
let canvas = 1024

// Read the art into a known RGBA8 buffer so the alpha channel can be scanned.
guard let probe = CGContext(data: nil, width: srcW, height: srcH,
                            bitsPerComponent: 8, bytesPerRow: srcW * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let probeData = probe.data else {
    exit(1)
}
probe.draw(art, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))

// Solid bounds: a high threshold ignores the glow and finds the shape itself.
let pixels = probeData.bindMemory(to: UInt8.self, capacity: srcW * srcH * 4)
let threshold: UInt8 = 200
var minX = srcW, maxX = -1, minY = srcH, maxY = -1
for y in 0..<srcH {
    let row = y * srcW * 4
    for x in 0..<srcW where pixels[row + x * 4 + 3] > threshold {
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}
guard maxX > minX, maxY > minY else {
    FileHandle.standardError.write("no solid pixels found in \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

// Average the artwork's own border colour, sampled just inside each edge
// midpoint, for the corner backing. The buffer is premultiplied, so undo that.
func patchColour(_ cx: Int, _ cy: Int) -> (Double, Double, Double) {
    var r = 0.0, g = 0.0, b = 0.0, n = 0.0
    for y in max(cy - 2, 0)...min(cy + 2, srcH - 1) {
        for x in max(cx - 2, 0)...min(cx + 2, srcW - 1) {
            let i = (y * srcW + x) * 4
            let a = Double(pixels[i + 3]) / 255
            guard a > 0.1 else { continue }
            r += Double(pixels[i]) / 255 / a
            g += Double(pixels[i + 1]) / 255 / a
            b += Double(pixels[i + 2]) / 255 / a
            n += 1
        }
    }
    guard n > 0 else { return (0, 0, 0) }
    return (r / n, g / n, b / n)
}

let inset = 20
let edge = [patchColour((minX + maxX) / 2, minY + inset),
            patchColour((minX + maxX) / 2, maxY - inset),
            patchColour(minX + inset, (minY + maxY) / 2),
            patchColour(maxX - inset, (minY + maxY) / 2)]
let backing = (edge.map { $0.0 }.reduce(0, +) / 4,
               edge.map { $0.1 }.reduce(0, +) / 4,
               edge.map { $0.2 }.reduce(0, +) / 4)

let boxW = CGFloat(maxX - minX + 1)
let boxH = CGFloat(maxY - minY + 1)
let midX = CGFloat(minX) + boxW / 2
let midY = CGFloat(minY) + boxH / 2

let scale = CGFloat(canvas) / max(boxW, boxH)
let drawW = CGFloat(srcW) * scale
let drawH = CGFloat(srcH) * scale

// Place the solid bounds at the centre of the canvas. CGContext draws images
// top-down from the rect's top edge, so the vertical origin is measured there.
let originX = CGFloat(canvas) / 2 - midX * scale
let topY = CGFloat(canvas) / 2 + midY * scale
let rect = CGRect(x: originX, y: topY - drawH, width: drawW, height: drawH)

guard let ctx = CGContext(data: nil, width: canvas, height: canvas,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
ctx.interpolationQuality = .high
ctx.setFillColor(red: backing.0, green: backing.1, blue: backing.2, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
ctx.draw(art, in: rect)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outputPath) as CFURL,
                                                "public.png" as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("wrote \(outputPath) (solid bounds \(Int(boxW))x\(Int(boxH)) at \(minX),\(minY), scale \(String(format: "%.3f", scale)))")
