// Housekeeping — Daemon and Security Audit: detects orphaned root daemons, zombie TCC grants, and excessive permissions

import Foundation
import AppKit

struct DaemonAndSecurityAudit: Sendable {
    let runner: ProcessRunner

    func audit(installedIdentifiers: Set<String>) async -> [EnvironmentFinding] {
        var findings: [EnvironmentFinding] = []
        let fm = FileManager.default

        // 1. Audit LaunchDaemons and LaunchAgents for missing executables or deleted apps
        let daemonDirs: [URL] = [
            URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        ]

        for dir in daemonDirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for file in files where file.pathExtension.lowercased() == "plist" {
                guard let data = try? Data(contentsOf: file),
                      let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
                    continue
                }

                var programPath: String? = plist["Program"] as? String
                if programPath == nil, let args = plist["ProgramArguments"] as? [String], let first = args.first {
                    programPath = first
                }

                guard let program = programPath else { continue }

                // Check if executable exists
                if !fm.fileExists(atPath: program) {
                    findings.append(EnvironmentFinding(
                        id: "daemon-missing-\(file.path)",
                        category: .securityAndDaemons,
                        severity: .broken,
                        title: "Daemon points to missing executable: \(file.lastPathComponent)",
                        summary: "The background service at \(file.path) references a missing executable at \(program).",
                        evidence: ["Daemon plist: \(file.path)", "Missing binary: \(program)"],
                        steps: ["Move the orphaned plist aside or run the clean-orphaned-mac-permissions script."],
                        fix: nil,
                        isSelected: false
                    ))
                    continue
                }

                // Check if program belongs to an application bundle (contains .app/)
                if program.contains(".app/") {
                    let parts = program.components(separatedBy: ".app/")
                    if let appRoot = parts.first {
                        let fullAppPath = appRoot + ".app"
                        if !fm.fileExists(atPath: fullAppPath) {
                            findings.append(EnvironmentFinding(
                                id: "daemon-orphan-\(file.path)",
                                category: .securityAndDaemons,
                                severity: .broken,
                                title: "Orphaned daemon from deleted application: \(file.lastPathComponent)",
                                summary: "The service runs a helper for an application that is no longer installed (\(fullAppPath)).",
                                evidence: ["Daemon plist: \(file.path)", "Uninstalled app: \(fullAppPath)"],
                                steps: ["Remove the leftover plist from \(file.path)."],
                                fix: nil,
                                isSelected: false
                            ))
                        }
                    }
                }
            }
        }

        // 2. Audit TCC.db for zombie grants and excessive permissions
        let tccDB = "/Library/Application Support/com.apple.TCC/TCC.db"
        if fm.isReadableFile(atPath: tccDB) {
            if let result = try? await runner.run(
                executable: "/usr/bin/sqlite3",
                arguments: [tccDB, "SELECT service, client FROM access WHERE auth_value = 2;"]
            ), result.succeeded {
                let lines = result.stdout.components(separatedBy: "\n")
                for line in lines where line.contains("|") {
                    let cols = line.components(separatedBy: "|")
                    guard cols.count >= 2 else { continue }
                    let service = cols[0].trimmingCharacters(in: .whitespaces)
                    let client = cols[1].trimmingCharacters(in: .whitespaces)

                    if client.hasPrefix("com.apple.") || client.hasPrefix("/System/") { continue }

                    let cleanClient = client.lowercased()

                    let hasApp = installedIdentifiers.contains(cleanClient) ||
                                 NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) != nil

                    if !hasApp {
                        let readableService: String
                        switch service {
                        case "kTCCServiceSystemPolicyAllFiles": readableService = "Full Disk Access"
                        case "kTCCServiceScreenCapture": readableService = "Screen Recording"
                        case "kTCCServiceAccessibility": readableService = "Accessibility"
                        case "kTCCServiceEndpointSecurityClient": readableService = "Endpoint Security"
                        default: readableService = service.replacingOccurrences(of: "kTCCService", with: "")
                        }

                        findings.append(EnvironmentFinding(
                            id: "tcc-zombie-\(service)-\(client)",
                            category: .securityAndDaemons,
                            severity: .broken,
                            title: "Zombie permission grant: \(client) (\(readableService))",
                            summary: "An uninstalled application still retains \(readableService) privileges in macOS Privacy & Security.",
                            evidence: ["Database: \(tccDB)", "Client: \(client)", "Permission: \(service)"],
                            steps: ["Use System Settings > Privacy & Security to remove the dead entry, or run clean-orphaned-mac-permissions.sh."],
                            fix: nil,
                            isSelected: false
                        ))
                    } else {
                        if client == "com.microsoft.Word" && service == "kTCCServiceSystemPolicyAllFiles" {
                            findings.append(EnvironmentFinding(
                                id: "tcc-excessive-word-fda",
                                category: .securityAndDaemons,
                                severity: .untidy,
                                title: "Excessive privilege: Microsoft Word has Full Disk Access",
                                summary: "Word does not require Full Disk Access to edit documents. macOS Sandboxing safely provides access to opened files.",
                                evidence: ["Client: com.microsoft.Word", "Permission: Full Disk Access"],
                                steps: ["Open System Settings > Privacy & Security > Full Disk Access and turn off Microsoft Word."],
                                fix: nil,
                                isSelected: false
                            ))
                        }
                    }
                }
            }
        }

        // 3. Sudoers audit
        let sudoersD = "/etc/sudoers.d"
        if let sudoFiles = try? fm.contentsOfDirectory(atPath: sudoersD) {
            for f in sudoFiles where f != "." && f != ".." {
                findings.append(EnvironmentFinding(
                    id: "sudoers-rule-\(f)",
                    category: .securityAndDaemons,
                    severity: .untidy,
                    title: "Non-standard sudoers rule: /etc/sudoers.d/\(f)",
                    summary: "A third-party utility configured custom privilege rules in /etc/sudoers.d/.",
                    evidence: ["File: /etc/sudoers.d/\(f)"],
                    steps: ["Review /etc/sudoers.d/\(f) to verify whether this privilege escalation rule is still desired."],
                    fix: nil,
                    isSelected: false
                ))
            }
        }

        return findings
    }
}
