import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppRepairView: View {
    @Environment(\.uiStyle) private var style
    @EnvironmentObject private var appState: AppState
    @StateObject private var engine = AppRepairEngine.shared

    @State private var droppedAppURL: URL?
    @State private var selectedCandidate: AppRepairCandidate?
    @State private var isTargetedForDrop = false
    @State private var anywhereStatusNote: String?
    @State private var showAnywhereAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                dropZone
                if let outcome = engine.latestOutcome {
                    repairOutcomeCard(outcome)
                }
                if let selected = selectedCandidate {
                    selectedAppCard(selected)
                }
                quarantinedAppsShelf
                educationalCard
            }
            .padding(32)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { HousekeepingBackdrop(style: style) }
        .onAppear {
            Task {
                await engine.scanInstalledApps()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "bandage.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(style.accent)
                    Text("Repair 'Damaged' Apps & Gatekeeper")
                        .font(style.isRetro ? style.titleFont : .system(size: 26, weight: .bold))
                }
                Text("Fixes 'App is damaged and can't be opened. You should move it to the Trash' and 'Unidentified Developer' blocks with one click.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                ThemeButton(
                    title: "Scan Apps",
                    systemImage: "arrow.clockwise",
                    isEnabled: !engine.isScanning
                ) {
                    Task {
                        await engine.scanInstalledApps()
                    }
                }
                ThemeButton(
                    title: "Allow Anywhere",
                    systemImage: "lock.open.fill",
                    isPrimary: false
                ) {
                    enableAnywhere()
                }
                .help("Runs 'spctl --master-disable' to re-enable the 'Anywhere' Gatekeeper option in macOS System Settings.")
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isTargetedForDrop ? style.accent : style.border,
                        style: StrokeStyle(lineWidth: isTargetedForDrop ? 2.5 : 1.5, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isTargetedForDrop ? style.accent.opacity(0.08) : style.rowBackground)
                    )

                VStack(spacing: 10) {
                    Image(systemName: isTargetedForDrop ? "arrow.down.app.fill" : "square.and.arrow.down")
                        .font(.system(size: 36))
                        .foregroundStyle(isTargetedForDrop ? style.accent : .secondary)

                    Text(isTargetedForDrop ? "Release to diagnose and repair app" : "Drag and drop any .app here to repair Gatekeeper errors")
                        .font(.system(size: 15, weight: .semibold))

                    Text("Or select an app manually from your disk")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    ThemeButton(
                        title: "Choose App from Disk…",
                        systemImage: "folder.badge.gearshape",
                        isPrimary: true
                    ) {
                        chooseApp()
                    }
                    .padding(.top, 4)
                }
                .padding(32)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension == "app" else { return }
                    DispatchQueue.main.async {
                        self.droppedAppURL = url
                        self.selectedCandidate = engine.diagnoseApp(at: url)
                    }
                }
                return true
            }
        }
    }

    // MARK: - Selected App Card

    private func selectedAppCard(_ candidate: AppRepairCandidate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: candidate.url.path))
                    .resizable()
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(candidate.name)
                            .font(.system(size: 16, weight: .bold))
                        Text("v\(candidate.version)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(candidate.url.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if engine.isRepairing && engine.activeRepairApp == candidate.name {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Repairing…")
                            .font(.system(size: 12, weight: .medium))
                    }
                } else {
                    ThemeButton(
                        title: "Repair App Now",
                        systemImage: "bandage.fill",
                        isPrimary: true
                    ) {
                        Task {
                            _ = await engine.repairApp(candidate: candidate)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 16) {
                statusChip(
                    title: "Quarantine Flag",
                    present: candidate.hasQuarantine,
                    okText: "Clean (No Quarantine)",
                    badText: "Quarantine Attached"
                )
                statusChip(
                    title: "Provenance Flag",
                    present: candidate.hasProvenance,
                    okText: "Clean",
                    badText: "Provenance Attached"
                )
            }
        }
        .padding(18)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    private func statusChip(title: String, present: Bool, okText: String, badText: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(present ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(present ? badText : okText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(present ? .primary : .secondary)
            }
        }
    }

    // MARK: - Repair Outcome Card

    private func repairOutcomeCard(_ outcome: AppRepairOutcome) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: outcome.succeeded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(outcome.succeeded ? .green : .orange)
                Text(outcome.message)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if outcome.succeeded {
                    ThemeButton(
                        title: "Launch App",
                        systemImage: "arrow.up.forward.app.fill",
                        isPrimary: true
                    ) {
                        NSWorkspace.shared.open(outcome.url)
                    }
                    ThemeButton(
                        title: "Reveal",
                        systemImage: "folder",
                        isPrimary: false
                    ) {
                        NSWorkspace.shared.activateFileViewerSelecting([outcome.url])
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(outcome.stepsTaken, id: \.self) { step in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                        Text(step)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(outcome.succeeded ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(outcome.succeeded ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Quarantined Apps Shelf

    private var quarantinedAppsShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quarantined Apps on this Mac")
                        .font(.system(size: 16, weight: .bold))
                    Text("Installed applications currently marked with Gatekeeper quarantine flags.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !engine.candidates.isEmpty {
                    ThemeButton(
                        title: "Repair All (\(engine.candidates.count))",
                        systemImage: "bandage.fill",
                        isPrimary: true,
                        isEnabled: !engine.isRepairing
                    ) {
                        repairAll()
                    }
                }
            }

            if engine.isScanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Scanning /Applications for quarantine flags…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
            } else if engine.candidates.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                    Text("No quarantined applications detected. All scanned apps in /Applications are clean!")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    ForEach(engine.candidates) { candidate in
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: candidate.url.path))
                                .resizable()
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(candidate.name)
                                        .font(.system(size: 13, weight: .bold))
                                    Text("v\(candidate.version)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Text(candidate.statusText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }

                            Spacer()

                            ThemeButton(
                                title: "Repair",
                                systemImage: "bandage",
                                isPrimary: true,
                                isEnabled: !engine.isRepairing
                            ) {
                                Task {
                                    _ = await engine.repairApp(candidate: candidate)
                                }
                            }
                        }
                        .padding(12)
                        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.border, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Educational Guide

    private var educationalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(style.accent)
                Text("Why does macOS say an app is damaged?")
                    .font(.system(size: 12, weight: .bold))
            }

            Text("When you download software via a browser or third-party channel, macOS attaches an extended attribute named com.apple.quarantine. If the developer is unidentified, or if the application bundle was updated without Apple notarization, macOS refuses to open it with the warning: 'AppName is damaged and can't be opened. You should move it to the Trash'.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Text("Housekeeper removes this quarantine attribute and re-signs the app ad-hoc, allowing macOS to run it directly without throwing damage errors.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(style.rowBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.border, lineWidth: 1))
    }

    // MARK: - Actions

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            self.droppedAppURL = url
            self.selectedCandidate = engine.diagnoseApp(at: url)
        }
    }

    private func repairAll() {
        Task {
            let list = engine.candidates
            for item in list {
                _ = await engine.repairApp(candidate: item)
            }
        }
    }

    private func enableAnywhere() {
        Task {
            let res = await engine.enableGatekeeperAnywhere()
            if res.success {
                anywhereStatusNote = "'Allow from Anywhere' successfully enabled in Gatekeeper."
            } else {
                anywhereStatusNote = res.error
            }
            showAnywhereAlert = true
        }
    }
}
