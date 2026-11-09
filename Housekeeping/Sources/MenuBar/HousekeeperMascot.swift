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

    /// The canonical maid-octopus mark, embedded so the menu bar never depends on
    /// a resource copy: the original dark artwork becomes one tintable alpha mask
    /// with the white details as transparent cut-outs. Codex's canonical menu bar
    /// icon (PR #1), integrated here.
    private static let canonicalMenuBarTemplate: NSImage? = {
        let encoded = [
            "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",
        ]
        guard let data = Data(base64Encoded: encoded.joined()) else { return nil }
        return NSImage(data: data)
    }()

    /// Loads the dedicated menu bar template icon.
    /// Configured with `isTemplate = true` and standard 18x18 point menu bar sizing.
    public static func loadMenuBarTemplate() -> NSImage? {
        let markSize = NSSize(width: 18, height: 18)

        // 0. The canonical embedded mask: exact silhouette, crisp at every scale.
        if let img = canonicalMenuBarTemplate {
            img.size = markSize
            img.isTemplate = true
            return img
        }

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
