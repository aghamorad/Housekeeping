import AppKit
import SwiftUI

// MARK: - Housekeeper Mascot Provider

/// Centralized loader and renderer for the unboxed Housekeeper mascot across the app.
/// Preserves natural alpha transparency so the character floats cleanly without
/// being boxed into rectangular plates or borders.
public enum HousekeeperMascot {

    /// Loads the high-resolution transparent mascot image.
    public static func loadMascot() -> NSImage? {
        // 1. App Bundle Resources
        let bundlePaths = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/housekeeper_octopus_maid.png"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/mascot.png"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.png")
        ]
        for url in bundlePaths {
            if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                return img
            }
        }

        // 2. Development Workspace Paths
        let devPaths = [
            URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/housekeeper_octopus_maid.png"),
            URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/mascot.png"),
            URL(fileURLWithPath: "/Users/Morad/Desktop/30e46a86-0c5a-4a6f-ab23-6bb3f8d430ee.png")
        ]
        for url in devPaths {
            if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                return img
            }
        }

        return nil
    }
}
