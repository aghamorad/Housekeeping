// Full-bleed the source art onto the 1024 canvas with natural transparent background.
//
// The housekeeper mascot floats freely with a transparent background without
// being boxed into an artificial plate or solid tile.
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

// Read the art into a known RGBA8 buffer to scan the alpha channel for bounding box.
guard let probe = CGContext(data: nil, width: srcW, height: srcH,
                            bitsPerComponent: 8, bytesPerRow: srcW * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let probeData = probe.data else {
    exit(1)
}
probe.draw(art, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))

let pixels = probeData.bindMemory(to: UInt8.self, capacity: srcW * srcH * 4)
let threshold: UInt8 = 10
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
    FileHandle.standardError.write("no visible pixels found in \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

let boxW = CGFloat(maxX - minX + 1)
let boxH = CGFloat(maxY - minY + 1)

// Target size: 880 max dimension inside 1024 canvas for standard macOS icon proportions
let targetMax: CGFloat = 880.0
let scale = targetMax / max(boxW, boxH)
let drawW = boxW * scale
let drawH = boxH * scale

// Transparent RGBA output canvas
guard let outContext = CGContext(data: nil, width: canvas, height: canvas,
                                 bitsPerComponent: 8, bytesPerRow: canvas * 4,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

// Clear to full transparency
outContext.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

// Crop and draw
let cropRect = CGRect(x: minX, y: minY, width: Int(boxW), height: Int(boxH))
guard let croppedArt = art.cropping(to: cropRect) else {
    exit(1)
}

let destX = (CGFloat(canvas) - drawW) / 2.0
let destY = (CGFloat(canvas) - drawH) / 2.0
outContext.draw(croppedArt, in: CGRect(x: destX, y: destY, width: drawW, height: drawH))

guard let resultImage = outContext.makeImage() else {
    exit(1)
}

let destURL = URL(fileURLWithPath: outputPath) as CFURL
guard let destination = CGImageDestinationCreateWithURL(destURL, "public.png" as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(destination, resultImage, nil)
guard CGImageDestinationFinalize(destination) else {
    exit(1)
}
