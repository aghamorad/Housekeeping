// Housekeeping — the Local Models screen
//
// One list of everything on this Mac that can hold a model in memory, what each one
// weighs on disk, which tools intersect with it, and what is necessary vs extra —
// with controls to load, unload, or safely move orphaned leftovers to Trash.

import SwiftUI
import AppKit

enum ModelFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case necessary = "Necessary"
    case optional = "Optional"
    case extra = "Extra / Orphaned"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .necessary: return "checkmark.shield.fill"
        case .optional: return "info.circle"
        case .extra: return "exclamationmark.triangle.fill"
        }
    }
}

struct ModelsView: View {
    @ObservedObject var model: LocalModelInventory
    @Environment(\.uiStyle) private var style
    @State private var selectedFilter: ModelFilter = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                memoryPanel
                filterBar

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
                Text("Local Models & AI Runtimes")
                    .font(style.titleFont)
                Text("Every model and AI runtime on this Mac: which tools intersect with it, what is necessary to keep, and what is extra or safe to clean.")
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

    // MARK: Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(ModelFilter.allCases, id: \.self) { filter in
                let count = countForFilter(filter)
                Button {
                    selectedFilter = filter
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filter.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(filter.rawValue)
                            .font(style.smallFont)
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(selectedFilter == filter ? Color.white.opacity(0.2) : style.groupingBackground)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundColor(selectedFilter == filter ? .white : style.text)
                    .background(selectedFilter == filter ? style.accent : style.groupingBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedFilter == filter ? style.accent : style.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func countForFilter(_ filter: ModelFilter) -> Int {
        let all = model.groups.flatMap { $0.models }
        switch filter {
        case .all: return all.count
        case .necessary: return all.filter { $0.necessity == .necessary }.count
        case .optional: return all.filter { $0.necessity == .optional }.count
        case .extra: return all.filter { $0.necessity == .extra }.count
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

    @ViewBuilder
    private func groupSection(_ group: ModelGroup) -> some View {
        let visibleModels = group.models.filter { item in
            switch selectedFilter {
            case .all: return true
            case .necessary: return item.necessity == .necessary
            case .optional: return item.necessity == .optional
            case .extra: return item.necessity == .extra
            }
        }

        if !visibleModels.isEmpty || (selectedFilter == .all && group.hint != nil) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.runtime.title)
                        .font(style.labelFont)
                    Text(visibleModels.count == 1 ? "1 model" : "\(visibleModels.count) models")
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

                if !visibleModels.isEmpty {
                    ThemePanel(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleModels.enumerated()), id: \.element.id) { index, entry in
                                row(entry)
                                if index < visibleModels.count - 1 {
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
    }

    // MARK: One model

    private func row(_ entry: LocalModel) -> some View {
        let refusal = model.refusal(for: entry)
        let working = model.busy == entry.id
        let blocked = model.busy != nil && !working

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(style.bodyFont)
                        .foregroundColor(style.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    if entry.loaded {
                        Text(entry.runtime == .mlx ? "ACTIVE DEFAULT" : "IN MEMORY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(style.positive)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(style.positive.opacity(0.5), lineWidth: 1)
                            )
                    }

                    necessityBadge(entry.necessity)
                }

                if !entry.facts.isEmpty {
                    Text(entry.facts.joined(separator: " · "))
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .lineLimit(1)
                }

                if !entry.intersections.isEmpty {
                    entryIntersectionsView(entry.intersections)
                }

                if let exp = entry.intersectionExplanation {
                    Text(exp)
                        .font(style.smallFont)
                        .foregroundColor(entry.necessity == .extra ? style.caution : style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let note = entry.note {
                    Text(note)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

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

    private func entryIntersectionsView(_ intersections: [String]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("Intersects:")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(style.secondaryText)
                .padding(.top, 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(intersections, id: \.self) { inter in
                        Text(inter)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(style.text)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(style.groupingBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(style.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func necessityBadge(_ status: NecessityStatus) -> some View {
        switch status {
        case .necessary:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("NECESSARY")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(style.positive)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(style.positive.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))

        case .optional:
            HStack(spacing: 3) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                Text("OPTIONAL")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(style.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(style.groupingBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(style.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))

        case .extra:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("EXTRA / ORPHANED")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(style.caution)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(style.caution.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    @ViewBuilder
    private func control(for entry: LocalModel, refusal: String?, working: Bool, blocked: Bool) -> some View {
        if working {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(entry.loaded ? "Unloading…" : "Working…")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            .frame(width: 140, alignment: .trailing)
        } else if entry.control == .trash || (entry.necessity == .extra && entry.path != nil) {
            HStack(spacing: 6) {
                if let path = entry.path {
                    ThemeButton(
                        title: "Reveal",
                        systemImage: "arrow.up.right.square",
                        isEnabled: true,
                        help: "Shows this item in Finder."
                    ) {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    }
                }
                ThemeButton(
                    title: "Trash",
                    systemImage: "trash",
                    isEnabled: !blocked,
                    help: "Safely moves this orphaned folder/model to macOS Trash."
                ) {
                    Task { await model.moveToTrash(entry) }
                }
            }
            .frame(width: 140, alignment: .trailing)
        } else if entry.loaded {
            ThemeButton(
                title: "Unload",
                systemImage: "eject",
                isEnabled: !blocked,
                help: "Takes \(entry.name) out of memory. The file on disk is untouched."
            ) {
                Task { await model.unload(entry) }
            }
            .frame(width: 140, alignment: .trailing)
        } else if entry.control == .loadAndUnload {
            ThemeButton(
                title: entry.runtime == .mlx ? "Set Default" : "Load",
                systemImage: entry.runtime == .mlx ? "checkmark.circle" : "arrow.down.circle",
                isEnabled: refusal == nil && !blocked,
                help: refusal ?? (entry.runtime == .mlx ? "Sets \(entry.name) as current default model in ~/.mlx-lm/models/current." : "Puts \(entry.name) into memory so it is ready to answer at once. It stays until it is unloaded or the runtime drops it.")
            ) {
                Task { await model.load(entry) }
            }
            .frame(width: 140, alignment: .trailing)
        } else if entry.control == .unloadOnly {
            ThemeButton(
                title: "Unload",
                systemImage: "eject",
                isEnabled: !blocked,
                help: "Takes \(entry.name) out of memory."
            ) {
                Task { await model.unload(entry) }
            }
            .frame(width: 140, alignment: .trailing)
        } else {
            Text("Not loadable")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .frame(width: 140, alignment: .trailing)
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text("Read from Draw Things, ComfyUI, Ollama, LM Studio, the housekeeper's weights, local MLX servers, and the Hugging Face cache. Shows which tools intersect with each model and what is necessary versus safe to clean.")
            .font(style.smallFont)
            .foregroundColor(style.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}
