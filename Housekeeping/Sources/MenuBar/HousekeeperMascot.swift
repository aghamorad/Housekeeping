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

    /// Loads the dedicated menu bar template icon.
    /// Configured with `isTemplate = true` and standard 18x18 point menu bar sizing.
    public static func loadMenuBarTemplate() -> NSImage? {
        let markSize = NSSize(width: 18, height: 18)

        // 1. App Bundle Resources
        let bundlePaths = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/menu_bar_template.tiff"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/menu_bar_template.png"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/housekeeper_menubar.png"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/menu_bar_template@2x.png")
        ]
        for url in bundlePaths {
            if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                img.size = markSize
                img.isTemplate = true
                return img
            }
        }

        // 2. Development Workspace Paths
        let devPaths = [
            URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/menu_bar_template.tiff"),
            URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/menu_bar_template.png"),
            URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/housekeeper_menubar.png"),
            URL(fileURLWithPath: "/Users/Morad/Desktop/menu bar template Icon.png")
        ]
        for url in devPaths {
            if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                img.size = markSize
                img.isTemplate = true
                return img
            }
        }

        return nil
    }
}
