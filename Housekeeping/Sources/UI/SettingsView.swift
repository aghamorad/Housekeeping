// Housekeeping — SettingsView

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { appState.currentTheme },
                    set: { appState.setTheme($0) }
                )) {
                    ForEach(AppState.Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                Text(themeDescription)
                    .font(.callout)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Scanning") {
                Toggle("Also measure folders Housekeeping can't name", isOn: Binding(
                    get: { appState.deepSweep },
                    set: { appState.setDeepSweep($0) }
                ))

                Text(appState.deepSweep
                     ? "The deep sweep is on. It measures the folders where undeclared data collects — usually where the larger wins are, since nothing else reports them. It adds up to a minute to a scan, and anything it finds can only be cleaned after an extra typed confirmation."
                     : "The deep sweep is off. Housekeeping will only report what its list of \(RuleEngine.shared.applications.count) known applications and tools covers, so anything not on that list goes unmeasured.")
                    .font(.callout)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Safety") {
                safetyLine("Housekeeping never ticks anything for you. Every scan starts with an empty selection.", icon: "checkmark.square")
                safetyLine("Cleaning moves items into Quarantine. Nothing is deleted, and everything moved can be put back.", icon: "arrow.uturn.backward")
                safetyLine("Anything Housekeeping cannot prove is replaceable is shown but locked, with the reason stated.", icon: "lock.fill")
            }

            // Where the "ignore this one from now on" choice is undone. The choice
            // is made on the update screen, which is the right place for it, but a
            // decision with no way back is a trap — so the way back lives here,
            // with the other things that are about the whole app rather than one
            // screen, and it names every entry rather than offering a reset.
            Section("Updates you have told Housekeeping to leave alone") {
                if let note = appState.updateExceptionNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if appState.updateExceptionEntries.isEmpty {
                    Text("Nothing yet. Every application and package Housekeeping finds will be offered the next time you open Update Apps.")
                        .font(.callout)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(appState.updateExceptionEntries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.callout)
                                Text(entry.displayKey)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(style.secondaryText)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 8)
                            Button("Offer Again") { appState.offerUpdateAgain(key: entry.key) }
                                .help("Put this back in the update list. Nothing is installed by doing this — it only stops Housekeeping from hiding it.")
                        }
                    }

                    Button("Offer Everything Again") { appState.offerAllUpdatesAgain() }
                        .help("Put every one of these back in the update list at once.")
                }
            }

            Section("Where quarantine lives") {
                Text(CleanupEngine().quarantineURL.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)

                Text(CleanupEngine().quarantineExists
                     ? "That is the whole path. It is a normal folder at the top of your home folder, in plain sight — not hidden inside Library or an application support folder. Things can be dragged back out of it by hand, without Housekeeping."
                     : "That is where it will be. The folder does not exist yet because nothing has been quarantined; it is created the first time you clean something. It sits at the top of your home folder in plain sight — not hidden inside Library.")
                    .font(.callout)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Show Me the Folder") { CleanupEngine().revealQuarantine() }
                    .help("Open Housekeeping's Quarantine in the Finder. It is an ordinary folder you can browse, and files can be dragged back out of it by hand without the app.")
            }

            Section("Housekeeper") {
                Text("The housekeeper is the reader that explains what Housekeeping is showing you. It is a small model running on this Mac, and it explains; Housekeeping is the one that decides and the one that runs anything.")
                    .font(.callout)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                AskHousekeeperButton(
                    topic: housekeeperTopic,
                    title: "Ask About Housekeeping"
                )
            }

            Section("About") {
                LabeledContent("App", value: "Housekeeping")
                LabeledContent("Version", value: AppState.currentVersion.isEmpty ? "Unknown" : AppState.currentVersion)
                updateRow
                LabeledContent("Rules loaded", value: "\(RuleEngine.shared.applications.count)")
                LabeledContent("Purpose", value: "Find storage, explain it, and move nothing without you.")
            }
        }
        .formStyle(.grouped)
        // The grouped form draws the system's own panel behind its sections.
        // Left on, this window is grey cards on a red window; off, the surface
        // the rest of the app wears comes through.
        .scrollContentBackground(.hidden)
        .padding(20)
        .frame(width: 540, height: 560)
    }

    /// Four states, said four ways. "Could not check" is not "up to date", and a
    /// row that claimed the second while holding the first would be telling
    /// someone on an old copy to sit still.
    @ViewBuilder
    private var updateRow: some View {
        switch appState.updateStatus {
        case .checking:
            LabeledContent("Newer release", value: "Checking…")
        case .current:
            LabeledContent("Newer release", value: "None — this is the newest")
        case .newer(let available):
            LabeledContent("Newer release") {
                Link("Get \(available)", destination: AppState.releasesURL)
            }
        case .unknown:
            LabeledContent("Newer release", value: "Could not check")
        }
    }

    private func safetyLine(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(style.secondaryText)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the housekeeper is handed when it is opened from Settings. This screen
    /// is in a window of its own, so the button routes through `WindowOpener`
    /// rather than stepping a sheet aside — there is no sheet here to step aside.
    private var housekeeperTopic: HousekeeperTopic {
        var facts: [String] = []
        facts.append("These are Housekeeping's own settings. Nothing on this screen cleans anything or changes anything on disk; every switch here changes how Housekeeping behaves and nothing else.")
        facts.append("Theme: \(appState.currentTheme.displayName). \(themeDescription)")
        facts.append(appState.deepSweep
                     ? "The deep sweep is on, so Housekeeping also measures the folders where undeclared data collects. That adds up to a minute to a scan, and anything found that way needs an extra typed confirmation before it can be cleaned."
                     : "The deep sweep is off, so Housekeeping only reports what its list of \(RuleEngine.shared.applications.count) known applications and tools covers.")
        facts.append("The safety promises are: Housekeeping never ticks anything on the reader's behalf; cleaning moves items into Quarantine and deletes nothing, and everything moved can be put back; and anything it cannot prove is replaceable is shown but locked, with the reason stated.")
        facts.append("Quarantine is at \(CleanupEngine().quarantineURL.path), a normal folder in plain sight at the top of the home folder\(CleanupEngine().quarantineExists ? "" : " — it does not exist yet because nothing has been quarantined, and it is created the first time something is")")
        if appState.updateExceptionEntries.isEmpty {
            facts.append("Nothing has been told to leave alone in the update list, so every application and package found will be offered next time.")
        } else {
            facts.append("Told to leave alone in the update list: \(appState.updateExceptionEntries.count).")
            for entry in appState.updateExceptionEntries.prefix(15) {
                facts.append("- \(entry.name) — \(entry.displayKey)")
            }
            facts.append("“Offer Again” puts one back in the list. It installs nothing; it only stops Housekeeping from hiding it.")
        }
        facts.append("This is Housekeeping \(AppState.currentVersion.isEmpty ? "of unknown version" : AppState.currentVersion), with \(RuleEngine.shared.applications.count) rules loaded.")

        return HousekeeperTopic(
            id: "settings",
            title: "Housekeeping's settings",
            label: appState.currentTheme.displayName,
            tone: .plain,
            facts: facts,
            opener: "What do these settings change, and what does Housekeeping never do?"
        )
    }

    private var themeDescription: String {
        switch appState.currentTheme {
        case .classic9:
            return "Mac OS 9 / Platinum is the original retro interface: monospaced type, drawn buttons, light appearance. Every screen and button in Housekeeping is identical to the other theme — only the look changes."
        case .liquidGlass:
            return "Liquid Glass uses native macOS navigation, materials, and controls, with real Liquid Glass surfaces on macOS 26 and later. Every screen and button in Housekeeping is identical to the other theme — only the look changes."
        }
    }
}
