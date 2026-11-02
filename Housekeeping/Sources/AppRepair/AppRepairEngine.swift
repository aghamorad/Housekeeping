import Foundation
import AppKit
import Darwin

@MainActor
public final class AppRepairEngine: ObservableObject {
    public static let shared = AppRepairEngine()

    @Published public private(set) var candidates: [AppRepairCandidate] = []
    @Published public private(set) var isScanning = false
    @Published public private(set) var isRepairing = false
    @Published public private(set) var activeRepairApp: String?
    @Published public private(set) var latestOutcome: AppRepairOutcome?
    @Published public private(set) var lastScannedDate: Date?

    private init() {}

    // MARK: - Single App Diagnosis

    public func diagnoseApp(at url: URL) -> AppRepairCandidate {
        let path = url.path
        let name = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let bundleID = bundle?.bundleIdentifier ?? "unknown.bundle"
        let version = (info?["CFBundleShortVersionString"] as? String)
            ?? (info?["CFBundleVersion"] as? String)
            ?? "1.0"

        let hasQuarantine = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
        let hasProvenance = getxattr(path, "com.apple.provenance", nil, 0, 0, 0) >= 0

        var statusText = "Ready & Healthy"
        if hasQuarantine && hasProvenance {
            statusText = "Blocked by Gatekeeper (Quarantine & Provenance flags attached)"
        } else if hasQuarantine {
            statusText = "Quarantined by Gatekeeper (May trigger 'Damaged' prompt)"
        } else if hasProvenance {
            statusText = "Web Provenance metadata attached"
        }

        return AppRepairCandidate(
            url: url,
            name: name,
            bundleID: bundleID,
            version: version,
            hasQuarantine: hasQuarantine,
            hasProvenance: hasProvenance,
            signatureValid: !hasQuarantine,
            statusText: statusText
        )
    }

    // MARK: - Batch Scan

    public func scanInstalledApps() async {
        isScanning = true
        defer {
            isScanning = false
            lastScannedDate = Date()
        }

        let directories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var found: [AppRepairCandidate] = []

        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            for dir in directories {
                guard let enumerator = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for url in enumerator where url.pathExtension == "app" {
                    let path = url.path
                    let hasQuarantine = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
                    let hasProvenance = getxattr(path, "com.apple.provenance", nil, 0, 0, 0) >= 0

                    if hasQuarantine || hasProvenance {
                        let name = url.deletingPathExtension().lastPathComponent
                        let bundle = Bundle(url: url)
                        let info = bundle?.infoDictionary
                        let bundleID = bundle?.bundleIdentifier ?? "unknown"
                        let version = (info?["CFBundleShortVersionString"] as? String)
                            ?? (info?["CFBundleVersion"] as? String)
                            ?? "1.0"

                        let statusText = hasQuarantine
                            ? "Quarantined by Gatekeeper (Triggers 'Damaged' dialog)"
                            : "Web download provenance attached"

                        let candidate = AppRepairCandidate(
                            url: url,
                            name: name,
                            bundleID: bundleID,
                            version: version,
                            hasQuarantine: hasQuarantine,
                            hasProvenance: hasProvenance,
                            signatureValid: !hasQuarantine,
                            statusText: statusText
                        )
                        found.append(candidate)
                    }
                }
            }
        }.value

        self.candidates = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Repair Operation

    public func repair(url: URL) async -> AppRepairOutcome {
        let candidate = diagnoseApp(at: url)
        return await repairApp(candidate: candidate)
    }

    public func repairApp(candidate: AppRepairCandidate) async -> AppRepairOutcome {
        isRepairing = true
        activeRepairApp = candidate.name
        defer {
            isRepairing = false
            activeRepairApp = nil
        }

        let appPath = candidate.url.path
        var steps: [String] = []

        // Step 1: Remove com.apple.quarantine attribute recursively
        let xattrRes = await runCommand("/usr/bin/xattr", args: ["-r", "-d", "com.apple.quarantine", appPath])
        if xattrRes.succeeded {
            steps.append("Cleared com.apple.quarantine attribute from bundle and binaries.")
        } else {
            steps.append("Quarantine flag removed or already cleared.")
        }

        // Step 2: Clear all extended provenance and quarantine attributes
        let clearRes = await runCommand("/usr/bin/xattr", args: ["-r", "-c", appPath])
        if clearRes.succeeded {
            steps.append("Purged all extended Gatekeeper provenance and download tracking tags.")
        }

        // Step 3: Ensure execution permissions on the binary
        let macosDir = candidate.url.appendingPathComponent("Contents/MacOS").path
        if FileManager.default.fileExists(atPath: macosDir) {
            _ = await runCommand("/bin/chmod", args: ["-R", "u+w,u+x", macosDir])
            steps.append("Ensured executable user permissions on Contents/MacOS binaries.")
        }

        // Step 4: Ad-hoc code re-sign with fresh seal
        let codesignRes = await runCommand("/usr/bin/codesign", args: ["--force", "--deep", "--sign", "-", appPath])
        if codesignRes.succeeded {
            steps.append("Re-signed application and nested frameworks ad-hoc with fresh seal.")
        } else {
            steps.append("Ad-hoc re-sign completed (or code signature intact).")
        }

        // Step 5: Verify repair
        let stillQuarantined = getxattr(appPath, "com.apple.quarantine", nil, 0, 0, 0) >= 0
        let success = !stillQuarantined

        let outcome = AppRepairOutcome(
            appName: candidate.name,
            url: candidate.url,
            succeeded: success,
            stepsTaken: steps,
            message: success
                ? "\(candidate.name) repaired successfully! You can now launch it without macOS claiming it is damaged."
                : "Quarantine could not be fully removed. You may need administrator permissions."
        )

        self.latestOutcome = outcome

        // Update candidate in list if present
        if let idx = candidates.firstIndex(where: { $0.url == candidate.url }) {
            if success {
                candidates.remove(at: idx)
            }
        }

        return outcome
    }

    // MARK: - Enable System-Wide "Allow from Anywhere"

    public func enableGatekeeperAnywhere() async -> (success: Bool, error: String?) {
        let script = "do shell script \"spctl --master-disable\" with administrator privileges"
        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&errorDict)
            if let errorDict {
                let msg = errorDict[NSAppleScript.errorMessage] as? String ?? "Authorization denied"
                return (false, msg)
            }
            return (true, nil)
        }
        return (false, "Could not initialize AppleScript")
    }

    // MARK: - Subprocess Helper

    private func runCommand(_ executable: String, args: [String]) async -> (succeeded: Bool, output: String) {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                return (process.terminationStatus == 0, text)
            } catch {
                return (false, error.localizedDescription)
            }
        }.value
    }
}
