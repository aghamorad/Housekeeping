import AppKit
import SwiftUI

// MARK: - Housekeeper Mascot Provider

/// Centralized loader and renderer for the official Housekeeper octopus mascots across the app.
/// Preserves natural alpha transparency so characters float cleanly without boxed frames or rectangular borders.
public enum HousekeeperMascot {

    // MARK: - 1. Monochrome Menu Bar Template Icon

    /// Embedded canonical menu bar template (black with alpha, 18x18pt @2x Retina, 36x36px).
    /// Guarantees instant zero-IO loading and native macOS dynamic tinting in light & dark menu bars.
    private static let canonicalMenuBarTemplate: NSImage? = {
        let encoded = [
            "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAEaklEQVR4nO3Xa8jfYxgH8M+zZwcbszFsc3hCwjKHWkjzYkJ4gZxCQl4QwwuStURkqZVCrSnN",
            "5hURqznlVLMY5rRhOcx5zUhaWHZ8nj1eXNfd737+z//Z/7HyRq66+933777v6/7+rsP3un/8L/9R6UJ39kfm8zK8gpdxbr47ECdUa7r+bWAF1KXor9oWPIgf",
            "sR3v4bAE1j1YDfYQbFe2/bEYa/EMvsGOBLINOytwpb+k0jNiTw5vJ93Zlhlokd21HdnWYhZ6qo8rz+4E2fVPwBZT74etwhXl0NW4T7jubJyPO7C8BVg//sh1",
            "RWcBdj+OGi6Y+mtOwc+pfKMI5sNxIebhCTyEG3ESTsc7uf6vfH6LvYQ1xuLOfP8xZnQCU0zZI4JzW25ehUm4Bb9p764+LMAELNTE1CYRhzBaZOWm/JjDOgEq",
            "rnoyFfbiO+yLRQbHys6q35dzH6UlluZ4aaW76L8YEzuBoXHXB5o4mIW7sr8tD941RNua617CIXhVWLsO4FHVWR3Tv5Da/an4NRyZIHZ2AFNacfM1bXSfl/1h",
            "Z1dBPU6Y+krM0bipE5hd1brlqWuUcPmSBHtFAtojftpHZM0uYaFeYaXeFhC91XxvfsAvmjgZjetEfB1vmO4qUpDfJOJntYEsXFoNqDXbCgcd2qJ7Sj7bgmln",
            "srJwHOZijCBFIkNWCa5ZmGt35tz3OAv3VsC2i/JSzhohrDYi5ztKXQhHiso9CS9orHB1zh8sXFMYfH61d2Ouf1+TXUV3fXPYrdQmHN8yd4PGRcsxHQ8YGOif",
            "42TcXoG8p0XPuCHOG1IuwIfC9y9iam4cL64WxRUlaGsKaGXtTYKHiMB+It99KoKbDll2RqW41KJnqvnLc367JqvqoO7LVjhodrW3sP7KCnBdcNvK07nwsRzP",
            "xiPCQqPz3RcaC7Xjn2K5DSIGR+X+BeI2QBTkPsHggwCNrPoHpNLfc7ywmtshKvmUPHQoU3flYeNxrLgTEQW5yE+5bmKOdw2hyzzxdX8K/pkkLDMF12sypzV2",
            "WluZ/wGXYO/U3y3KRonFx/N9bZQBMhnrND7egE8Eb9TB+pWGrQuwery+Zf3XeEMwdAG8GccYxo2xR/xFtLvrrMO1uM3AdO+rxv24Gbfi1yH0rMFped4gMDUX",
            "jND4cwaOE37uEhyzUrDu25ipYe/RacXxou49JzJossjco4W7Ngvrvprg6/OGlBLxE0WFv1dctIqcWlnkWU3WzcXrecBmHFHtmZZ6zmlzzm6lVN8xgrwKD82p",
            "5t5MQFsFW6/JdVcJnipuWZw6p2b/NQ1zD7t0FH8enpvfqubGCH4qBz6c719JgI/muCRFryg3RQ4SRXhV9fEdpVhhrEjZflE+5otsK2BWiJrUhYs0VNGDEw38",
            "XXpe1LzPWj5kyFRvlWLK8wVBtt59ntIU3mLRuxPEohyfiS8Nzq53haV2ezFrN1Gif7owe4/4L1smXFT29VfPaSKu1ufeCaKAzsw1KwQRbqn2/C//DfkbC/ay",
            "VL5EnJcAAAAASUVORK5CYII=",
        ]
        guard let data = Data(base64Encoded: encoded.joined()),
              let img = NSImage(data: data) else { return nil }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }()

    /// Loads the dedicated monochrome menu bar template icon.
    /// Configured with `isTemplate = true` and standard 18x18 point menu bar sizing.
    public static func loadMenuBarTemplate() -> NSImage? {
        let markSize = NSSize(width: 18, height: 18)

        // 0. The canonical embedded mask: exact silhouette, crisp at every scale
        if let img = canonicalMenuBarTemplate {
            img.size = markSize
            img.isTemplate = true
            return img
        }

        // 1. App Bundle Resources
        let bundlePaths = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/menu_bar_template.png"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/menu_bar_template@2x.png"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/menu_bar_template.tiff"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/housekeeper_menubar.png")
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
            URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/menu_bar_template.png"),
            URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/menu_bar_template@2x.png"),
            URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/menu_bar_template.tiff")
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

    // MARK: - 2. Main Dashboard & Popover: Mac Cleaning Octopus

    /// Mac cleaning octopus (MacBook + feather duster + spray bottle).
    /// Used in Main Dashboard (OverviewView) and Menu Bar Popover Header.
    public static func loadMacCleaning() -> NSImage? {
        loadNamedAsset("housekeeper_mac_cleaning.png")
    }

    // MARK: - 3. Cooling & Fans: Vacuuming Octopus

    /// Vacuuming octopus (happily vacuuming with yellow vacuum cleaner).
    /// Used in Cooling & Fans (FanControlView).
    public static func loadVacuuming() -> NSImage? {
        loadNamedAsset("housekeeper_vacuuming.png")
    }

    // MARK: - 4. Clean Up: Clutter-Cleaning Octopus

    /// Clutter-cleaning octopus (carrying black rubbish bag with trash symbol).
    /// Used in Clean Up (CleanerView, CleanupView).
    public static func loadClutterCleaning() -> NSImage? {
        loadNamedAsset("housekeeper_clutter.png")
    }

    // MARK: - 5. Background Activity & Maintenance: System Maintenance Octopus

    /// System maintenance octopus (holding computer components, hard drive, gear, broom).
    /// Used in Background Activity, App Updates, and App Repair.
    public static func loadMaintenance() -> NSImage? {
        loadNamedAsset("housekeeper_maintenance.png")
    }

    // MARK: - 6. About Housekeeper: Original Transparent Mascot

    /// Original transparent housekeeper mascot (mascot.png).
    /// Used in About Housekeeper (SettingsView) and Sidebar headers.
    public static func loadOriginalMascot() -> NSImage? {
        loadNamedAsset("mascot.png")
    }

    // MARK: - Legacy / Generic Mascot Loader

    /// Backwards-compatible generic mascot loader.
    public static func loadMascot() -> NSImage? {
        loadOriginalMascot() ?? loadMacCleaning()
    }

    // MARK: - Helper Loader

    private static func loadNamedAsset(_ filename: String) -> NSImage? {
        // 1. App Bundle Resources
        let bundleURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/\(filename)")
        if FileManager.default.fileExists(atPath: bundleURL.path), let img = NSImage(contentsOf: bundleURL) {
            return img
        }

        // 2. Direct bundle resource lookup
        if let resourceURL = Bundle.main.url(forResource: (filename as NSString).deletingPathExtension,
                                             withExtension: (filename as NSString).pathExtension,
                                             subdirectory: "BenignMonster"),
           let img = NSImage(contentsOf: resourceURL) {
            return img
        }

        // 3. Development Workspace Paths
        let devURL = URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/\(filename)")
        if FileManager.default.fileExists(atPath: devURL.path), let img = NSImage(contentsOf: devURL) {
            return img
        }

        let fallbackDevURL = URL(fileURLWithPath: "/Users/Morad/C3PO/.work/hkfix/Housekeeping/Housekeeping/Resources/BenignMonster/\(filename)")
        if FileManager.default.fileExists(atPath: fallbackDevURL.path), let img = NSImage(contentsOf: fallbackDevURL) {
            return img
        }

        return nil
    }
}
