import Foundation
import Darwin
import AppKit

// MARK: - Process Safety Level

public enum ProcessSafetyLevel: String, Equatable, Codable {
    case safeToQuit = "Safe to Quit"
    case caution = "Caution"
    case systemProtected = "System Protected"
}

// MARK: - Process Identity

public struct ProcessIdentity: Equatable {
    public let pid: pid_t
    public let name: String
    public let displayName: String
    public let category: String
    public let summary: String
    public let parentPid: pid_t?
    public let parentName: String?
    public let parentApp: String?
    public let workingOn: String?
    public let executablePath: String?
    public let safetyLevel: ProcessSafetyLevel
    public let safetyAdvice: String
    public let icon: String

    public var safetyLevelText: String {
        safetyLevel.rawValue
    }
}

// MARK: - Process Knowledge Engine

public enum ProcessKnowledge {

    private struct Profile {
        let displayName: String
        let category: String
        let summary: String
        let safetyLevel: ProcessSafetyLevel
        let safetyAdvice: String
        let icon: String
    }

    // MARK: - Encyclopedia of Common Mac & Developer Processes

    private static let encyclopedia: [String: Profile] = [
        // Swift & Xcode Developer Tooling
        "swift-frontend": Profile(
            displayName: "Swift Compiler Frontend",
            category: "Developer Tool · Compiler",
            summary: "Compiles Swift source code into native machine code binaries and interface files.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Cancels the active build job cleanly without harming project source files.",
            icon: "swift"
        ),
        "swift-driver": Profile(
            displayName: "Swift Build Coordinator",
            category: "Developer Tool · Build System",
            summary: "Coordinates module build targets, dependency planning, and compiler sub-processes.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Stops the active build process.",
            icon: "hammer.fill"
        ),
        "swift": Profile(
            displayName: "Swift Language Runner",
            category: "Developer Tool",
            summary: "Executes Swift scripts, package manager actions, or command-line developer commands.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Terminates the running Swift script or package command.",
            icon: "swift"
        ),
        "clang": Profile(
            displayName: "Clang C/C++ Compiler",
            category: "Developer Tool · Compiler",
            summary: "Compiles C, C++, or Objective-C source files into binary object code.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Halts the compilation job without damaging source code.",
            icon: "hammer.fill"
        ),
        "clang++": Profile(
            displayName: "Clang C++ Compiler",
            category: "Developer Tool · Compiler",
            summary: "Compiles modern C++ source code into native binaries.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Halts the compilation job cleanly.",
            icon: "hammer.fill"
        ),
        "xcodebuild": Profile(
            displayName: "Xcode Build Engine",
            category: "Developer Tool · Build System",
            summary: "Command-line tool that coordinates building, testing, and packaging Xcode projects.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Cancels ongoing build or test execution.",
            icon: "hammer.fill"
        ),
        "lldb": Profile(
            displayName: "LLVM Debugger",
            category: "Developer Tool · Debugger",
            summary: "Interactive debugger inspecting, pausing, and controlling an application in development.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Detaches from or terminates the program under inspection.",
            icon: "ladybug.fill"
        ),
        "debugserver": Profile(
            displayName: "LLDB Debug Server",
            category: "Developer Tool · Debugger",
            summary: "Low-level kernel agent attaching debuggers (Xcode/VS Code) to target processes.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Ends the active debugging connection.",
            icon: "ladybug.fill"
        ),
        "SourceKitService": Profile(
            displayName: "Xcode SourceKit Service",
            category: "Developer Tool · Language Server",
            summary: "Powers real-time Swift autocompletion, type lookup, and syntax checking in Xcode.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Xcode automatically respawns it within seconds if indexing is active.",
            icon: "character.cursor.ibeam"
        ),
        "git": Profile(
            displayName: "Git Version Control",
            category: "Developer Tool · VCS",
            summary: "Tracks source code revisions, commits, diffs, branches, and remote synchronization.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. If stopped during a commit or rebase, you may need to clear an index lock.",
            icon: "arrow.triangle.branch"
        ),

        // Languages & Runtimes
        "node": Profile(
            displayName: "Node.js JavaScript Runtime",
            category: "Runtime Environment",
            summary: "Executes JavaScript code for local servers, development tools (Vite/Webpack), or scripts.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Stops the active local web server or script.",
            icon: "curlybraces"
        ),
        "bun": Profile(
            displayName: "Bun JavaScript Runtime",
            category: "Runtime Environment",
            summary: "Fast JavaScript and TypeScript runtime running local development servers and scripts.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Stops the running script or dev server.",
            icon: "curlybraces"
        ),
        "deno": Profile(
            displayName: "Deno TypeScript Runtime",
            category: "Runtime Environment",
            summary: "Secure JavaScript and TypeScript runtime running scripts or services.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Terminates the running program.",
            icon: "curlybraces"
        ),
        "python": Profile(
            displayName: "Python Runtime",
            category: "Scripting & Data Runtime",
            summary: "Executes Python scripts, automation tools, or machine learning pipelines.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Stops the active Python script.",
            icon: "curlybraces"
        ),
        "python3": Profile(
            displayName: "Python 3 Runtime",
            category: "Scripting & Data Runtime",
            summary: "Executes modern Python 3 scripts, background utilities, or data processing.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Stops the active Python script.",
            icon: "curlybraces"
        ),
        "ollama": Profile(
            displayName: "Ollama Local AI Server",
            category: "Artificial Intelligence",
            summary: "Serves local Large Language Models (LLMs) on Apple Silicon GPU and Neural Engine.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Instantly frees up multiple gigabytes of unified system RAM and VRAM.",
            icon: "sparkles"
        ),
        "llama-server": Profile(
            displayName: "llama.cpp AI Engine",
            category: "Artificial Intelligence",
            summary: "Runs local neural network inference for AI chatbots and embeddings.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Frees held model memory; can be restarted anytime an AI question is asked.",
            icon: "sparkles"
        ),

        // macOS System & Windowing Services
        "WindowServer": Profile(
            displayName: "macOS Window Compositor",
            category: "macOS Core Graphics",
            summary: "The master engine that renders and composites all windows, screens, and visuals.",
            safetyLevel: .systemProtected,
            safetyAdvice: "System protected! Force quitting WindowServer will instantly terminate your session and log you out.",
            icon: "macwindow.on.rectangle"
        ),
        "kernel_task": Profile(
            displayName: "macOS Darwin Kernel",
            category: "Operating System Kernel",
            summary: "Core operating system kernel: manages memory virtualization, device drivers, and thermals.",
            safetyLevel: .systemProtected,
            safetyAdvice: "Cannot be terminated. It is the operating system itself.",
            icon: "cpu.fill"
        ),
        "launchd": Profile(
            displayName: "macOS Master Supervisor (PID 1)",
            category: "Operating System Core",
            summary: "The root initialization process that bootstraps the Mac and manages all daemons.",
            safetyLevel: .systemProtected,
            safetyAdvice: "Cannot be terminated. Stopping PID 1 crashes the operating system.",
            icon: "bolt.fill"
        ),
        "loginwindow": Profile(
            displayName: "macOS Login Window",
            category: "macOS System",
            summary: "Coordinates user authentication, desktop session startup, lock screens, and logout.",
            safetyLevel: .systemProtected,
            safetyAdvice: "Caution! Terminating loginwindow immediately logs out the current user session.",
            icon: "lock.desktopcomputer"
        ),
        "fseventsd": Profile(
            displayName: "File System Events Daemon",
            category: "macOS Core System",
            summary: "Broadcasts real-time file change events to Spotlight, Time Machine, and editors.",
            safetyLevel: .systemProtected,
            safetyAdvice: "Protected system daemon. Required for file tracking.",
            icon: "doc.badge.gearshape"
        ),
        "mds": Profile(
            displayName: "Spotlight Metadata Coordinator",
            category: "macOS Search & Indexing",
            summary: "Coordinates metadata indexing across internal drives and attached storage.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. macOS restarts it automatically. Search indexing temporarily pauses.",
            icon: "magnifyingglass"
        ),
        "mdworker": Profile(
            displayName: "Spotlight Content Indexer",
            category: "macOS Search & Indexing",
            summary: "Scans individual file contents and extracts search terms for Spotlight.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. macOS automatically restarts it if more files need indexing.",
            icon: "magnifyingglass"
        ),
        "mdworker_shared": Profile(
            displayName: "Spotlight Shared Indexer",
            category: "macOS Search & Indexing",
            summary: "Worker process extracting text and metadata from user documents and caches.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Will respawn automatically as needed.",
            icon: "magnifyingglass"
        ),
        "cloudd": Profile(
            displayName: "iCloud Sync Daemon",
            category: "Apple Cloud Services",
            summary: "Synchronizes files, photos, notes, and cloud databases across your Apple devices.",
            safetyLevel: .caution,
            safetyAdvice: "Caution. Quitting pauses active iCloud transfers. macOS will restart it automatically.",
            icon: "icloud.fill"
        ),
        "bird": Profile(
            displayName: "iCloud Documents Daemon",
            category: "Apple Cloud Services",
            summary: "Monitors iCloud Drive documents and coordinates desktop and document folder sync.",
            safetyLevel: .caution,
            safetyAdvice: "Caution. Quitting pauses active document syncing.",
            icon: "icloud.fill"
        ),
        "caffeinate": Profile(
            displayName: "macOS Sleep Inhibitor",
            category: "macOS Utility",
            summary: "Prevents your Mac or display from going to sleep while a long task runs.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Allows your Mac to resume normal energy-saving and display sleep.",
            icon: "cup.and.saucer.fill"
        ),
        "coreaudiod": Profile(
            displayName: "Core Audio Daemon",
            category: "macOS Audio Subsystem",
            summary: "Directs all audio input and output, microphone streams, and system sound effects.",
            safetyLevel: .caution,
            safetyAdvice: "Caution. Restarts the audio subsystem; will briefly silence playing music or calls.",
            icon: "speaker.wave.2.fill"
        ),
        "trustd": Profile(
            displayName: "Certificate Verification Daemon",
            category: "Security & Keychain",
            summary: "Checks SSL/TLS certificates and cryptographic code signatures for apps and websites.",
            safetyLevel: .systemProtected,
            safetyAdvice: "System protected security daemon. Managed by macOS.",
            icon: "shield.checkerboard"
        ),
        "syspolicyd": Profile(
            displayName: "Gatekeeper Security Policy",
            category: "Security & Privacy",
            summary: "Enforces macOS Gatekeeper checks, app notarization, and malware scans.",
            safetyLevel: .systemProtected,
            safetyAdvice: "System protected security service.",
            icon: "shield.checkerboard"
        ),
        "containermanagerd": Profile(
            displayName: "Sandbox Container Manager",
            category: "Security & Sandbox",
            summary: "Manages isolated sandboxed folders in ~/Library/Containers for Mac App Store apps.",
            safetyLevel: .systemProtected,
            safetyAdvice: "System protected service.",
            icon: "shippingbox.fill"
        ),
        "distnoted": Profile(
            displayName: "Distributed Notification Server",
            category: "macOS System IPC",
            summary: "Routes broadcast notifications between independent macOS applications.",
            safetyLevel: .systemProtected,
            safetyAdvice: "System protected IPC daemon.",
            icon: "bell.badge"
        ),
        "bluetoothd": Profile(
            displayName: "Bluetooth Subsystem",
            category: "macOS Wireless",
            summary: "Manages connections to Bluetooth keyboards, mice, trackpads, and AirPods.",
            safetyLevel: .caution,
            safetyAdvice: "Caution. Quitting will briefly disconnect wireless mice, keyboards, and audio.",
            icon: "antenna.radiowaves.left.and.right"
        ),

        // Web Browsers & Electron Subprocesses
        "Google Chrome Helper": Profile(
            displayName: "Google Chrome Tab Process",
            category: "Web Browser Subprocess",
            summary: "Isolated sandboxed process rendering a web page tab or extension in Google Chrome.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Only that single browser tab will crash with 'Aw, Snap!'. Chrome stays open.",
            icon: "globe"
        ),
        "Google Chrome Helper (Renderer)": Profile(
            displayName: "Chrome Web Renderer",
            category: "Web Browser Subprocess",
            summary: "Sandboxed engine rendering HTML, CSS, and JavaScript for a specific Chrome tab.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Only that specific webpage tab will display a crash notice.",
            icon: "globe"
        ),
        "Google Chrome Helper (GPU)": Profile(
            displayName: "Chrome GPU Compositor",
            category: "Web Browser Subprocess",
            summary: "Hardware GPU acceleration process powering WebGL and smooth scrolling in Chrome.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Chrome will restart GPU acceleration automatically.",
            icon: "display"
        ),
        "Safari Web Content": Profile(
            displayName: "Safari Web Pages",
            category: "Open Browser Tabs",
            summary: "Renders web pages and open browser tabs in Apple Safari.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Closes or reloads background website tabs.",
            icon: "safari"
        ),
        "com.apple.WebKit.WebContent": Profile(
            displayName: "Safari Web Pages",
            category: "Open Browser Tabs",
            summary: "Renders web pages and open browser tabs in Safari or Mac web views.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Closes or reloads background website tabs.",
            icon: "safari"
        ),
        "com.apple.WebKit.GPU": Profile(
            displayName: "Safari Video & Graphics",
            category: "Web Browser",
            summary: "Accelerates video playback and graphics rendering in Safari.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Safari restarts it automatically.",
            icon: "safari"
        ),
        "com.apple.WebKit.Networking": Profile(
            displayName: "Safari Network",
            category: "Web Browser",
            summary: "Handles web downloads and secure network connections for Safari.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Active downloads will pause.",
            icon: "safari"
        ),
        "cua-driver": Profile(
            displayName: "AI Desktop Assistant",
            category: "Desktop Automation",
            summary: "Manages native UI controls and automation actions for your AI assistant.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Stops active automated desktop tasks.",
            icon: "sparkles"
        ),
        "Finder": Profile(
            displayName: "Finder",
            category: "Desktop & Files",
            summary: "Manages desktop folders, open file windows, and connected drives.",
            safetyLevel: .caution,
            safetyAdvice: "Quitting restarts Finder to refresh desktop windows and drives.",
            icon: "macwindow"
        ),
        "Codex (Renderer)": Profile(
            displayName: "Codex",
            category: "Code Editor",
            summary: "The main editor window and project canvas in Codex.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Codex will reload the editor window.",
            icon: "curlybraces"
        ),
        "ChatGPT": Profile(
            displayName: "ChatGPT",
            category: "AI Chat",
            summary: "Desktop application for ChatGPT conversations and voice.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Closes the ChatGPT window.",
            icon: "bubble.left.and.bubble.right.fill"
        ),
        "Telegram": Profile(
            displayName: "Telegram",
            category: "Messaging",
            summary: "Telegram desktop messaging application.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Closes Telegram cleanly.",
            icon: "paperplane.fill"
        ),
        "Slack Helper": Profile(
            displayName: "Slack Workspace Renderer",
            category: "Desktop App Helper",
            summary: "Sandboxed Electron process rendering a Slack workspace, channel, or call view.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Slack will automatically reload the workspace view.",
            icon: "bubble.left.and.bubble.right.fill"
        ),
        "Slack Helper (Renderer)": Profile(
            displayName: "Slack Web Renderer",
            category: "Desktop App Helper",
            summary: "Sandboxed Electron process rendering Slack chat history or media.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Slack will reload the chat channel.",
            icon: "bubble.left.and.bubble.right.fill"
        ),
        "Discord Helper": Profile(
            displayName: "Discord Channel Helper",
            category: "Desktop App Helper",
            summary: "Sandboxed Electron process rendering Discord channels, streams, or voice audio.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Discord will reload the active view.",
            icon: "bubble.left.and.bubble.right.fill"
        ),
        "Code Helper": Profile(
            displayName: "VS Code Editor Helper",
            category: "Developer Tool · Editor",
            summary: "Isolated process running an editor window or terminal session in Visual Studio Code.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. Reloads that specific editor window.",
            icon: "chevron.left.forwardslash.chevron.right"
        ),
        "Code Helper (Renderer)": Profile(
            displayName: "VS Code Web Renderer",
            category: "Developer Tool · Editor",
            summary: "Renders the Monaco text editor canvas and extension views in Visual Studio Code.",
            safetyLevel: .safeToQuit,
            safetyAdvice: "Safe to quit. VS Code will prompt to reload the editor window.",
            icon: "chevron.left.forwardslash.chevron.right"
        )
    ]

    // MARK: - Inspection & Resolution

    public static func resolve(pid: pid_t, name: String) -> ProcessIdentity {
        let execPath = path(for: pid)
        let (parentApp, parentPid, parentName) = resolveParentHierarchy(pid: pid)
        let containingApp = extractBundleAppName(from: execPath)
        let effectiveApp = parentApp ?? containingApp

        let args = commandLineArgs(for: pid)
        let work = detectWorkload(name: name, args: args)

        // Try exact match or base executable match in encyclopedia
        let baseExec = URL(fileURLWithPath: execPath).lastPathComponent
        let profile = encyclopedia[name]
            ?? encyclopedia[name.lowercased()]
            ?? encyclopedia[baseExec]
            ?? fallbackProfile(name: name, execPath: execPath, effectiveApp: effectiveApp)

        return ProcessIdentity(
            pid: pid,
            name: name,
            displayName: profile.displayName,
            category: profile.category,
            summary: profile.summary,
            parentPid: parentPid,
            parentName: parentName,
            parentApp: effectiveApp,
            workingOn: work,
            executablePath: execPath.isEmpty ? nil : execPath,
            safetyLevel: profile.safetyLevel,
            safetyAdvice: profile.safetyAdvice,
            icon: profile.icon
        )
    }

    // MARK: - Parent Hierarchy Resolution

    private static func resolveParentHierarchy(pid: pid_t) -> (parentApp: String?, parentPid: pid_t?, parentName: String?) {
        var currentPid = pid
        var directParentPid: pid_t?
        var directParentName: String?

        for depth in 0..<4 {
            var bsdInfo = proc_bsdinfo()
            let size = proc_pidinfo(currentPid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.stride))
            guard size == MemoryLayout<proc_bsdinfo>.stride else { break }

            let ppid = pid_t(bsdInfo.pbi_ppid)
            guard ppid > 1, ppid != currentPid else { break }

            let ppath = path(for: ppid)
            let pname = URL(fileURLWithPath: ppath).lastPathComponent

            if depth == 0 {
                directParentPid = ppid
                directParentName = pname.isEmpty ? nil : pname
            }

            // Check if NSRunningApplication knows this parent
            if let runningApp = NSRunningApplication(processIdentifier: ppid),
               let appName = runningApp.localizedName, !appName.isEmpty {
                return (appName, ppid, directParentName)
            }

            // Check if parent's executable path is inside a .app bundle
            if let bundleName = extractBundleAppName(from: ppath) {
                return (bundleName, ppid, directParentName)
            }

            // Check known interactive shells or IDE parent executables
            if ["zsh", "bash", "sh", "fish"].contains(pname) {
                // Keep walking up from shell to find Terminal, Ghostty, iTerm, Xcode, etc.
                currentPid = ppid
                continue
            }

            if !ppath.isEmpty && depth > 0 {
                // If we found a meaningful parent executable
                return (pname, ppid, directParentName)
            }

            currentPid = ppid
        }

        return (nil, directParentPid, directParentName)
    }

    // MARK: - Workload Detection

    private static func detectWorkload(name: String, args: [String]) -> String? {
        guard !args.isEmpty else { return nil }
        let lower = name.lowercased()

        if lower.contains("swift-frontend") || lower == "swift" {
            if let idx = args.firstIndex(of: "-module-name"), idx + 1 < args.count {
                let mod = args[idx + 1]
                if !mod.hasPrefix("-") {
                    return "Compiling module '\(mod)'"
                }
            }
            if let swiftFile = args.first(where: { $0.hasSuffix(".swift") }) {
                let fileName = URL(fileURLWithPath: swiftFile).lastPathComponent
                return "Compiling \(fileName)"
            }
            return "Compiling Swift code"
        }

        if lower.contains("clang") || lower == "cc" || lower == "c++" {
            if let srcFile = args.first(where: {
                $0.hasSuffix(".c") || $0.hasSuffix(".cpp") || $0.hasSuffix(".m") || $0.hasSuffix(".mm")
            }) {
                let fileName = URL(fileURLWithPath: srcFile).lastPathComponent
                return "Compiling \(fileName)"
            }
            return "Compiling C/C++ source"
        }

        if lower == "xcodebuild" {
            if let idx = args.firstIndex(of: "-scheme"), idx + 1 < args.count {
                return "Building scheme '\(args[idx + 1])'"
            }
            if let proj = args.first(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
                return "Building \(URL(fileURLWithPath: proj).lastPathComponent)"
            }
            return "Running Xcode build"
        }

        if lower.contains("python") {
            if let script = args.first(where: { $0.hasSuffix(".py") }) {
                return "Running script '\(URL(fileURLWithPath: script).lastPathComponent)'"
            }
            return "Executing Python script"
        }

        if lower == "node" || lower == "bun" || lower == "deno" {
            if let script = args.first(where: { $0.hasSuffix(".js") || $0.hasSuffix(".ts") || $0.hasSuffix(".mjs") }) {
                return "Running '\(URL(fileURLWithPath: script).lastPathComponent)'"
            }
            return "Running JavaScript server or script"
        }

        if lower == "git" {
            let subcommands = ["status", "commit", "push", "pull", "fetch", "checkout", "diff", "merge", "rebase", "clone"]
            if let sub = args.first(where: { subcommands.contains($0) }) {
                return "git \(sub)"
            }
            return "Git repository operation"
        }

        if lower == "caffeinate" {
            return "Holding display or system awake"
        }

        return nil
    }

    // MARK: - Dynamic Fallback Profile

    private static func fallbackProfile(name: String, execPath: String, effectiveApp: String?) -> Profile {
        if name.contains("WebKit") || name.contains("WebContent") || name.contains("Safari") {
            return Profile(
                displayName: "Safari Web Pages",
                category: "Open Browser Tabs",
                summary: "Renders web pages and open browser tabs in Safari.",
                safetyLevel: .safeToQuit,
                safetyAdvice: "Safe to quit. Closes or reloads background website tabs.",
                icon: "safari"
            )
        }

        if let app = effectiveApp {
            return Profile(
                displayName: "\(app)",
                category: "App Background Task",
                summary: "Background task helping \(app) run smoothly.",
                safetyLevel: .safeToQuit,
                safetyAdvice: "Safe to quit. \(app) will reload or restart the task as needed.",
                icon: "app.fill"
            )
        }

        if execPath.hasPrefix("/System/Library") || execPath.hasPrefix("/usr/libexec") {
            return Profile(
                displayName: name,
                category: "macOS System Service",
                summary: "Built-in macOS operating system service or daemon.",
                safetyLevel: .systemProtected,
                safetyAdvice: "System service. Terminating may impact macOS system stability.",
                icon: "gearshape.2.fill"
            )
        }

        if execPath.contains("homebrew") || execPath.hasPrefix("/opt/homebrew") || execPath.hasPrefix("/usr/local") {
            return Profile(
                displayName: name,
                category: "Homebrew CLI Tool",
                summary: "Command-line tool or package installed via Homebrew.",
                safetyLevel: .safeToQuit,
                safetyAdvice: "Safe to quit. Stops the command-line task cleanly.",
                icon: "terminal.fill"
            )
        }

        return Profile(
            displayName: name,
            category: "Background Process",
            summary: "Active running process on macOS.",
            safetyLevel: .caution,
            safetyAdvice: "Quit asks the process to exit cleanly. Force Quit immediately reclaims its held memory.",
            icon: "gearshape.fill"
        )
    }

    // MARK: - Darwin System API Wrappers

    public static func path(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, 4096)
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    public static func extractBundleAppName(from path: String) -> String? {
        guard let range = path.range(of: ".app") else { return nil }
        let prefix = path[..<range.lowerBound]
        guard let base = prefix.split(separator: "/").last else { return nil }
        return String(base)
    }

    public static func commandLineArgs(for pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return []
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            return []
        }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var offset = MemoryLayout<Int32>.size

        // Skip executable path
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // Skip trailing null bytes after executable path
        while offset < size && buffer[offset] == 0 { offset += 1 }

        var args: [String] = []
        while offset < size && args.count < argc {
            let start = offset
            while offset < size && buffer[offset] != 0 { offset += 1 }
            if offset > start {
                let data = buffer[start..<offset].map { UInt8(bitPattern: $0) }
                if let str = String(bytes: data, encoding: .utf8) {
                    args.append(str)
                }
            }
            offset += 1
        }
        return args
    }
}
