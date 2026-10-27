// Housekeeping — the Local Models screen
//
// One list of everything on this Mac that can hold a model in memory, what each one
// weighs on disk, and which of them are holding memory right now — with a button on
// each row that puts it in or takes it out.
//
// The screen is deliberately quiet about the biggest number on it. Total memory in
// use is the honest figure and it moves every second; what a reader needs before
// pressing Load is whether *this* model fits in what is left, so the row says that,
// in its own words, and the button is only offered when the answer is yes.

import SwiftUI

struct ModelsView: View {
    @ObservedObject var model: LocalModelInventory
    @Environment(\.uiStyle) private var style

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                memoryPanel

                if let problem = model.problem {
                    ThemePanel(padding: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(style.caution)
                            Text(problem)
                                .font(style.smallFont)
                                .foregroundColor(style.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !model.hasRead {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading what is installed…")
                            .font(style.smallFont)
                            .foregroundColor(style.secondaryText)
                    }
                    .padding(.vertical, 20)
                }

                ForEach(model.groups) { group in
                    groupSection(group)
                }

                if model.hasRead && model.groups.isEmpty {
                    ThemePanel(padding: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nothing local is installed.")
                                .font(style.labelFont)
                            Text("None of the runtimes Housekeeping reads has a model on disk. Installing one is done in the runtime's own app — nothing is downloaded from here.")
                                .font(style.smallFont)
                                .foregroundColor(style.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                footer
            }
            .padding(20)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.readIfNeeded() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Local Models")
                    .font(style.titleFont)
                Text("Every model installed on this Mac, and what each one is holding in memory. Loading and unloading happen here; nothing is downloaded.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            ThemeButton(
                title: model.isReading ? "Reading…" : "Look Again",
                systemImage: "arrow.clockwise",
                isEnabled: !model.isReading,
                help: "Reads the runtimes again. This only reads: nothing is loaded, unloaded or downloaded by it."
            ) {
                Task { await model.read() }
            }
        }
    }

    // MARK: Memory

    private var memoryPanel: some View {
        ThemePanel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Memory")
                        .font(style.labelFont)
                    Spacer(minLength: 8)
                    if model.anythingLoaded {
                        Text(loadedSummary)
                            .font(style.smallFont)
                            .foregroundColor(style.secondaryText)
                        ThemeButton(
                            title: "Unload Everything",
                            systemImage: "eject",
                            isEnabled: model.busy == nil,
                            help: "Takes every model this screen can see out of memory, one at a time. Nothing is deleted from disk."
                        ) {
                            Task { await model.freeEverything() }
                        }
                    }
                }

                MeterBar(fraction: usedFraction, color: barColour)
                    .frame(height: 8)

                HStack(spacing: 14) {
                    reading("In use", gigabytes(model.memory.used))
                    reading("Free", gigabytes(model.memory.free))
                    reading("This Mac", gigabytes(model.memory.total))
                    Spacer(minLength: 0)
                }

                Text("“Free” is what is left after the memory apps are currently using, the memory macOS will not page out, and what the compressor is holding. A model does not have to fit inside it exactly — macOS will page and compress — but a model larger than it is how a session ends, so Housekeeping will not offer to load one.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var usedFraction: Double {
        model.memory.total > 0 ? Double(model.memory.used) / Double(model.memory.total) : 0
    }

    /// The bar says the same thing the numbers do: a machine with room left is not
    /// a warning, whatever the number is.
    private var barColour: Color {
        switch usedFraction {
        case ..<0.8: return style.positive
        case ..<0.92: return style.caution
        default: return style.negative
        }
    }

    private var loadedSummary: String {
        let count = model.groups.reduce(0) { $0 + $1.models.filter(\.loaded).count }
        let held = model.loadedBytes
        let label = count == 1 ? "1 model loaded" : "\(count) models loaded"
        guard held > 0 else { return label }
        return "\(label), holding \(ByteCountFormatter.string(fromByteCount: held, countStyle: .memory))"
    }

    private func reading(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(style.secondaryText)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(style.text)
        }
    }

    private func gigabytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    // MARK: One runtime

    private func groupSection(_ group: ModelGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.runtime.title)
                    .font(style.labelFont)
                Text(group.models.count == 1 ? "1 model" : "\(group.models.count) models")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                Spacer(minLength: 0)
            }
            Text(group.runtime.summary)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let hint = group.hint {
                Text(hint)
                    .font(style.smallFont)
                    .foregroundColor(style.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !group.models.isEmpty {
                ThemePanel(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(group.models.enumerated()), id: \.element.id) { index, entry in
                            row(entry)
                            if index < group.models.count - 1 {
                                Rectangle()
                                    .fill(style.border)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: One model

    private func row(_ entry: LocalModel) -> some View {
        let refusal = model.refusal(for: entry)
        let working = model.busy == entry.id
        let blocked = model.busy != nil && !working

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(style.bodyFont)
                        .foregroundColor(style.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    if entry.loaded {
                        Text("IN MEMORY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(style.positive)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(style.positive.opacity(0.5), lineWidth: 1)
                            )
                    }
                }

                if !entry.facts.isEmpty {
                    Text(entry.facts.joined(separator: " · "))
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .lineLimit(1)
                }

                if let note = entry.note {
                    Text(note)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The refusal is the honest thing to show where the button would
                // have been, rather than a button that is only going to say no.
                if !entry.loaded, let refusal {
                    Text(refusal)
                        .font(style.smallFont)
                        .foregroundColor(style.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            control(for: entry, refusal: refusal, working: working, blocked: blocked)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func control(for entry: LocalModel, refusal: String?, working: Bool, blocked: Bool) -> some View {
        if working {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(entry.loaded ? "Unloading…" : "Loading…")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            .frame(width: 130, alignment: .trailing)
        } else if entry.loaded {
            ThemeButton(
                title: "Unload",
                systemImage: "eject",
                isEnabled: !blocked,
                help: "Takes \(entry.name) out of memory. The file on disk is untouched."
            ) {
                Task { await model.unload(entry) }
            }
            .frame(width: 130, alignment: .trailing)
        } else if entry.control == .loadAndUnload {
            ThemeButton(
                title: "Load",
                systemImage: "arrow.down.circle",
                isEnabled: refusal == nil && !blocked,
                help: refusal ?? "Puts \(entry.name) into memory so it is ready to answer at once. It stays until it is unloaded or the runtime drops it."
            ) {
                Task { await model.load(entry) }
            }
            .frame(width: 130, alignment: .trailing)
        } else if entry.control == .unloadOnly {
            ThemeButton(
                title: "Unload",
                systemImage: "eject",
                isEnabled: !blocked,
                help: "Takes \(entry.name) out of memory."
            ) {
                Task { await model.unload(entry) }
            }
            .frame(width: 130, alignment: .trailing)
        } else {
            Text("Not loadable")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .frame(width: 130, alignment: .trailing)
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text("Read from Ollama's own service, LM Studio's model store and command, the housekeeper's weights, a local MLX server if one is running, and the Hugging Face cache. Nothing here is downloaded and nothing is deleted; the only change this screen makes is to memory.")
            .font(style.smallFont)
            .foregroundColor(style.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}
