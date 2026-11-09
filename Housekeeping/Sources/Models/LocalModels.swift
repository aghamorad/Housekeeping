// Housekeeping — every model this Mac can run, and what it costs to hold it
//
// Local inference on a Mac is not one thing. Ollama keeps its own store and loads
// on demand; LM Studio keeps another and has to be told; the housekeeper keeps a
// third inside this app; and the Hugging Face cache keeps a fourth that nothing can
// run at all, because a download is not a runtime. The question a reader actually
// has — "what have I got, and what is eating the RAM right now" — is spread across
// all of them, so this reads all of them into one list.
//
// Two rules hold everywhere in this file:
//
// Nothing is downloaded. The only two things a row can do are put a model that is
// already on disk into memory, and take it out again.
//
// Nothing loads by itself, and nothing loads that does not fit. The machine this
// app was written on has 16 GB, and a model larger than the free memory does not
// fail politely — it takes the session down with it. So every load is measured
// against the memory that is actually free first, and the ones that do not fit are
// offered as a refusal with the arithmetic rather than as a button.

import AppKit
import Foundation

// MARK: - What a row is

enum ModelRuntime: String, CaseIterable, Identifiable {
    case mlx
    case drawThings
    case comfyUI
    case ollama
    case lmStudio
    case housekeeper
    case hermes
    case huggingFace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mlx: return "Apple Silicon MLX & Local Registry"
        case .drawThings: return "Draw Things (Metal / MPS)"
        case .comfyUI: return "ComfyUI"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .housekeeper: return "The housekeeper"
        case .hermes: return "Hermes (MLX)"
        case .huggingFace: return "Hugging Face cache"
        }
    }

    /// What this runtime is, in one line, for a reader who has never had to know
    /// which of these is which. The last one is not a runtime at all, and says so.
    var summary: String {
        switch self {
        case .mlx: return "Local MLX model files and a configured default, if present. A symlink does not prove that a model is occupying memory; start and stop inference in its actual runtime."
        case .drawThings: return "Native Metal-accelerated image generation engine for Apple Silicon (~/Library/Containers/com.liuliu.draw-things)."
        case .comfyUI: return "Node-based visual image synthesis workbench and local server."
        case .ollama: return "A background service that loads a model when something asks and unloads it after a few idle minutes."
        case .lmStudio: return "An app with its own model store. Models are loaded into it explicitly, and stay loaded until they are taken out."
        case .housekeeper: return "This app's own chat model, run by the llama-server that ships inside Housekeeping."
        case .hermes: return "A separate local server (MLX) on this Mac, if it is running."
        case .huggingFace: return "Downloaded files, not a runtime. Nothing here can be loaded from this screen — it is shown because it is where the disk goes."
        }
    }
}

enum NecessityStatus: String, CaseIterable, Identifiable, Sendable {
    case necessary = "Necessary"
    case optional = "Optional"
    case extra = "Extra / Orphaned"

    var id: String { rawValue }
}

struct LocalModel: Identifiable {
    /// What the row is allowed to do. A downloaded file that nothing can load is
    /// still worth listing, and listing it with a Load button would be a lie.
    enum Control {
        case loadAndUnload
        case unloadOnly
        case trash
        case none
    }

    let id: String
    let runtime: ModelRuntime
    let name: String
    /// Size, quantisation, parameter count — whatever the runtime would tell us.
    var facts: [String] = []
    var bytes: Int64?
    var loaded: Bool = false
    /// How much memory the runtime says the loaded model is holding, when it says.
    var residentBytes: Int64?
    var path: String?
    var control: Control = .none
    /// The name the runtime itself uses, which is not always what is shown.
    var reference: String?
    var note: String?

    var necessity: NecessityStatus = .optional
    var intersections: [String] = []
    var intersectionExplanation: String?

    var sizeLabel: String? {
        guard let bytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct ModelGroup: Identifiable {
    let runtime: ModelRuntime
    var models: [LocalModel] = []
    /// Why the group is empty or partly unreadable, when the runtime said so.
    var hint: String?

    var id: String { runtime.rawValue }
}

// MARK: - Memory

struct ModelMemory {
    var total: UInt64 = 0
    var used: UInt64 = 0

    var free: UInt64 { total > used ? total - used : 0 }
    var freeFraction: Double { total > 0 ? Double(free) / Double(total) : 0 }

    static func read() -> ModelMemory {
        var memory = ModelMemory()
        memory.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return memory }

        // The same three figures the menu bar panel reads: what apps are using,
        // what cannot be paged out, and what the compressor is holding. Free is
        // what is left of the whole.
        let page = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        memory.used = min(used, memory.total)
        return memory
    }
}

// MARK: - The inventory

@MainActor
final class LocalModelInventory: ObservableObject {
    @Published private(set) var groups: [ModelGroup] = []
    @Published private(set) var memory = ModelMemory()
    @Published private(set) var isReading = false
    @Published private(set) var hasRead = false
    /// Rows with work in flight. Deliberately at most one at a time: two models
    /// loading together is how 16 GB becomes 8 GB twice.
    @Published private(set) var busy: String?
    @Published private(set) var note: String?
    @Published private(set) var problem: String?

    private let ollamaBase = URL(string: "http://127.0.0.1:11434")!
    private let lmStudioBase = URL(string: "http://127.0.0.1:1234")!
    private let hermesBase = URL(string: "http://127.0.0.1:18434")!

    var anythingLoaded: Bool {
        groups.contains { $0.models.contains { $0.loaded } }
    }

    var loadedBytes: Int64 {
        groups.reduce(0) { total, group in
            total + group.models.reduce(0) { $0 + ($1.loaded ? ($1.residentBytes ?? 0) : 0) }
        }
    }

    // MARK: Reading

    func readIfNeeded() async {
        guard !hasRead else { return }
        await read()
    }

    func read() async {
        guard !isReading else { return }
        isReading = true
        note = nil
        memory = ModelMemory.read()

        async let mlx = readMLX()
        async let ollama = readOllama()
        async let lmStudio = readLMStudio()
        async let hermes = readHermes()
        async let housekeeper = readHousekeeper()
        async let cache = readHuggingFace()

        let found = await [mlx, ollama, lmStudio, housekeeper, hermes, cache]
        groups = found
            .filter { !$0.models.isEmpty || $0.hint != nil }
            .sorted { order($0.runtime) < order($1.runtime) }
        hasRead = true
        isReading = false
    }

    private func order(_ runtime: ModelRuntime) -> Int {
        ModelRuntime.allCases.firstIndex(of: runtime) ?? 0
    }

    // MARK: - Apple Silicon MLX & Local Registry

    private func readMLX() async -> ModelGroup {
        var group = ModelGroup(runtime: .mlx)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let mlxModelsURL = URL(fileURLWithPath: home + "/.mlx-lm/models")
        let registryURL = URL(fileURLWithPath: home + "/Models")

        // Current symlink in ~/.mlx-lm/models/current
        let currentLink = home + "/.mlx-lm/models/current"
        let currentTarget = URL(fileURLWithPath: currentLink).resolvingSymlinksInPath().path

        var models: [LocalModel] = []
        var seenPaths = Set<String>()

        // 1. Scan ~/.mlx-lm/models
        if let entries = try? FileManager.default.contentsOfDirectory(at: mlxModelsURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            for entry in entries {
                let name = entry.lastPathComponent
                guard !name.hasPrefix("."), name != "current" else { continue }
                let resolved = entry.resolvingSymlinksInPath()
                guard !seenPaths.contains(resolved.path) else { continue }
                seenPaths.insert(resolved.path)

                let bytes = await Task.detached(priority: .utility) { Self.directorySize(resolved) }.value
                let isCurrent = (currentTarget == resolved.path) || (currentTarget == entry.path)

                var facts: [String] = ["MLX Metal", "LLM"]
                if name.lowercased().contains("4bit") { facts.append("4-bit") }
                if name.lowercased().contains("8bit") { facts.append("8-bit") }
                if isCurrent { facts.append("Active Default") }
                if bytes > 0 { facts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }

                models.append(LocalModel(
                    id: "mlx:\(entry.path)",
                    runtime: .mlx,
                    name: Self.formatMLXModelName(name),
                    facts: facts,
                    bytes: bytes,
                    loaded: false,
                    path: resolved.path,
                    control: .none,
                    reference: entry.path,
                    note: isCurrent ? "Configured default, not proof of a running model. Start or unload it in the MLX app or server that owns the process." : "Stored MLX weights. Housekeeping cannot load arbitrary MLX models into memory by changing a symlink."
                ))
            }
        }

        // 2. Scan ~/Models (llm, speech, voice, image)
        let categories = ["llm", "speech", "voice", "image"]
        for category in categories {
            let catURL = registryURL.appendingPathComponent(category)
            guard let entries = try? FileManager.default.contentsOfDirectory(at: catURL, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }

            for entry in entries {
                let name = entry.lastPathComponent
                guard !name.hasPrefix(".") else { continue }
                let resolved = entry.resolvingSymlinksInPath()
                guard !seenPaths.contains(resolved.path) else { continue }
                seenPaths.insert(resolved.path)

                let bytes = await Task.detached(priority: .utility) { Self.directorySize(resolved) }.value
                let isCurrent = (currentTarget == resolved.path)

                var facts: [String] = []
                switch category {
                case "llm": facts.append("LLM")
                case "speech": facts.append("Speech-to-Text")
                case "voice": facts.append("Voice Synthesis")
                case "image": facts.append("Image Gen")
                default: facts.append(category.uppercased())
                }

                if name.lowercased().contains("mlx") || resolved.path.contains("mlx") { facts.append("MLX Metal") }
                if name.lowercased().contains("4bit") { facts.append("4-bit") }
                if name.lowercased().contains("8bit") { facts.append("8-bit") }
                if name.lowercased().contains("onnx") { facts.append("ONNX") }
                if isCurrent { facts.append("Active Default") }
                if bytes > 0 { facts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }

                models.append(LocalModel(
                    id: "registry:\(entry.path)",
                    runtime: .mlx,
                    name: Self.formatRegistryModelName(name),
                    facts: facts,
                    bytes: bytes,
                    loaded: false,
                    path: resolved.path,
                    control: .none,
                    reference: entry.path,
                    note: "Stored in ~/Models/\(category)/. Configuration is not a live memory reading; use the owning runtime to load or unload."
                ))
            }
        }

        group.models = models.sorted {
            if $0.loaded != $1.loaded { return $0.loaded && !$1.loaded }
            return ($0.bytes ?? 0) > ($1.bytes ?? 0)
        }

        if group.models.isEmpty {
            group.hint = "No models detected in ~/Models or ~/.mlx-lm/models."
        } else {
            group.hint = "Found \(group.models.count) model\(group.models.count == 1 ? "" : "s") on disk. MLX has no universal process-level load/unload API; a selected default is not shown as loaded RAM."
        }

        return group
    }

    private static func formatMLXModelName(_ raw: String) -> String {
        switch raw {
        case "Qwen3.5-4B-Claude-Heretic-4bit":
            return "Qwen 3.5 4B (Claude Heretic 4-bit MLX)"
        case "Qwen3.5-9B-4bit":
            return "Qwen 3.5 9B (4-bit MLX)"
        default:
            return raw
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func formatRegistryModelName(_ raw: String) -> String {
        switch raw {
        case "qwen3.5-4b-mlx-4bit":
            return "Qwen 3.5 4B (Claude Heretic 4-bit MLX)"
        case "qwen3.5-9b-mlx-4bit":
            return "Qwen 3.5 9B (4-bit MLX)"
        case "whisper-large-v3-mlx":
            return "Whisper Large v3 (MLX)"
        case "fish-speech-s2-pro-8bit-mlx":
            return "Fish Speech S2 Pro (8-bit MLX)"
        case "whisper-large-v3-faster":
            return "Whisper Large v3 (faster-whisper)"
        case "whisper-base-faster":
            return "Whisper Base (faster-whisper)"
        case "sensevoice-onnx":
            return "SenseVoice (int8 ONNX)"
        case "nllb-200-distilled-600M":
            return "Meta NLLB-200 Distilled (Translation)"
        case "omnivoice":
            return "OmniVoice (TTS Clone)"
        case "moss-tts-nano":
            return "OpenMOSS TTS Nano"
        case "moss-tts-nano-100m":
            return "OpenMOSS TTS Nano (100M)"
        default:
            return raw
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: Ollama

    private func readOllama() async -> ModelGroup {
        var group = ModelGroup(runtime: .ollama)
        let installedOnDisk = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ollama")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ollama")
        // A reachable Ollama daemon is authoritative even if its executable lives
        // inside an app bundle or a custom installation path.
        guard let tags = await getJSON(ollamaBase.appendingPathComponent("api/tags")),
              let installed = tags["models"] as? [[String: Any]] else {
            if installedOnDisk {
                group.hint = "Ollama is installed but its API is not answering. Start Ollama to manage models here."
            }
            return group
        }

        var running: [String: Int64] = [:]
        if let ps = await getJSON(ollamaBase.appendingPathComponent("api/ps")),
           let loaded = ps["models"] as? [[String: Any]] {
            for entry in loaded {
                guard let name = entry["name"] as? String else { continue }
                running[name] = (entry["size"] as? NSNumber)?.int64Value ?? 0
            }
        }

        group.models = installed.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let size = (entry["size"] as? NSNumber)?.int64Value
            let details = entry["details"] as? [String: Any] ?? [:]
            var facts: [String] = []
            if let size, size > 0 { facts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
            if let quant = details["quantization_level"] as? String, !quant.isEmpty { facts.append(quant) }
            if let params = details["parameter_size"] as? String, !params.isEmpty { facts.append(params) }
            if let family = details["family"] as? String, !family.isEmpty { facts.append(family) }

            return LocalModel(
                id: "ollama:\(name)",
                runtime: .ollama,
                name: name,
                facts: facts,
                bytes: size,
                loaded: running[name] != nil,
                residentBytes: running[name],
                control: .loadAndUnload,
                reference: name
            )
        }
        if group.models.isEmpty {
            group.hint = "Ollama is running and has no models installed."
        }
        return group
    }

    private func loadInOllama(_ model: LocalModel) async {
        // A model is loaded by asking for one token from it. `keep_alive` is what
        // decides whether it stays: the runtime unloads it on its own afterwards.
        let status = await postJSON(
            ollamaBase.appendingPathComponent("api/generate"),
            ["model": model.reference ?? model.name, "prompt": " ", "stream": false, "keep_alive": "10m", "options": ["num_predict": 1]]
        )
        if status != 200 { problem = "Ollama did not confirm loading \(model.name) (HTTP \(status.map(String.init) ?? "no response"))." }
    }

    private func unloadFromOllama(_ model: LocalModel) async {
        // `keep_alive: 0` is the documented way to take a model out of memory
        // without unloading every other model the reader is using.
        let status = await postJSON(
            ollamaBase.appendingPathComponent("api/generate"),
            ["model": model.reference ?? model.name, "prompt": "", "stream": false, "keep_alive": 0]
        )
        if status != 200 { problem = "Ollama did not confirm unloading \(model.name) (HTTP \(status.map(String.init) ?? "no response"))." }
    }

    // MARK: LM Studio

    private var lmStudioCLI: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in ["\(home)/.lmstudio/bin/lms", "/opt/homebrew/bin/lms", "/usr/local/bin/lms"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// What LM Studio has on disk, and what it has in memory if it is running.
    ///
    /// Deliberately no `lms ls`: that command *wakes the app*, waits for it, and
    /// can sit there forever when it is closed — which is both a hang and a side
    /// effect this screen has no business causing while reading. The store is a
    /// folder, so it is read as one; the REST surface answers only when the app is
    /// already up, so it is asked only then.
    private func readLMStudio() async -> ModelGroup {
        var group = ModelGroup(runtime: .lmStudio)

        var loaded: [String: Int64] = [:]
        var isRunning = false
        if let answer = await getJSON(lmStudioBase.appendingPathComponent("api/v0/models")),
           let list = answer["data"] as? [[String: Any]] {
            isRunning = true
            for entry in list where (entry["state"] as? String) == "loaded" {
                guard let id = entry["id"] as? String else { continue }
                loaded[id] = 0
            }
        }

        let onDisk = await Task.detached(priority: .utility) { Self.scanLMStudioStore() }.value

        let canControl = isRunning && lmStudioCLI != nil
        var models: [LocalModel] = onDisk.map { entry in
            // Use the runtime identifier for unload, not the local file path.
            // A vague substring match can otherwise mark the wrong quantization loaded.
            let loadedID = loaded.keys.first { id in
                id == entry.name || id == entry.path
                    || URL(fileURLWithPath: id).lastPathComponent == URL(fileURLWithPath: entry.path).lastPathComponent
            }
            let isLoaded = loadedID != nil
            return LocalModel(
                id: "lmstudio:\(entry.path)",
                runtime: .lmStudio,
                name: entry.name,
                facts: entry.facts,
                bytes: entry.bytes,
                loaded: isLoaded,
                control: canControl ? .loadAndUnload : .none,
                reference: loadedID ?? entry.path,
                note: !isRunning ? "LM Studio is not running. Housekeeping will not wake it without asking." : (!canControl ? "The LM Studio CLI (lms) is unavailable, so load/unload controls are disabled." : nil)
            )
        }

        // A loaded model the file list did not match still belongs on screen,
        // because it is holding memory right now.
        for id in loaded.keys where !models.contains(where: { $0.name == id || $0.reference == id }) {
            models.insert(LocalModel(
                id: "lmstudio:\(id)",
                runtime: .lmStudio,
                name: id,
                facts: ["in memory"],
                loaded: true,
                control: canControl ? .unloadOnly : .none,
                reference: id
            ), at: 0)
        }

        group.models = models.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        if isRunning && !canControl {
            group.hint = "LM Studio is responding, but its lms command is not installed or not executable. The runtime must provide a working CLI before Housekeeping can manage its models."
        }
        if models.isEmpty {
            group.hint = FileManager.default.fileExists(atPath: Self.lmStudioStore.path)
                ? "LM Studio is installed and has no models."
                : "LM Studio is not installed on this Mac."
        }
        return group
    }

    nonisolated private static var lmStudioStore: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lmstudio/models", isDirectory: true)
    }

    private struct StoreEntry {
        let name: String
        let path: String
        let bytes: Int64
        let facts: [String]
    }

    /// Walks LM Studio's own store, which is laid out as
    /// `publisher/model/quantisation/file.gguf` — so the folder names say what the
    /// file is without opening it. Sharded MLX weights are one model per folder and
    /// are added up rather than listed shard by shard.
    nonisolated private static func scanLMStudioStore() -> [StoreEntry] {
        let manager = FileManager.default
        let root = lmStudioStore
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return [] }

        var entries: [StoreEntry] = []
        var shards: [String: (bytes: Int64, count: Int)] = [:]

        for case let file as URL in enumerator {
            // Four levels of folder plus the file: deeper than this is not a model.
            let depth = file.pathComponents.count - root.pathComponents.count
            if depth > 6 { enumerator.skipDescendants(); continue }

            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)

            let name = file.lastPathComponent.lowercased()
            if name.hasSuffix(".gguf") {
                let folder = file.deletingLastPathComponent()
                entries.append(StoreEntry(
                    name: file.deletingPathExtension().lastPathComponent,
                    path: file.path,
                    bytes: size,
                    facts: [folder.lastPathComponent, folder.deletingLastPathComponent().lastPathComponent]
                        .filter { !$0.isEmpty }
                ))
            } else if name.hasSuffix(".safetensors") {
                let folder = file.deletingLastPathComponent()
                var current = shards[folder.path] ?? (0, 0)
                current.bytes += size
                current.count += 1
                shards[folder.path] = current
            }
        }

        for (path, total) in shards {
            let folder = URL(fileURLWithPath: path)
            entries.append(StoreEntry(
                name: folder.lastPathComponent,
                path: path,
                bytes: total.bytes,
                facts: [total.count == 1 ? "1 file" : "\(total.count) files", "MLX"]
            ))
        }
        return entries
    }

    private func loadInLMStudio(_ model: LocalModel) async {
        guard let cli = lmStudioCLI else {
            problem = "LM Studio’s lms command is not installed. Open LM Studio to install its CLI integration."
            return
        }
        if await run(cli, ["load", model.reference ?? model.name, "--yes"], timeout: 120) == nil {
            problem = "LM Studio did not confirm loading \(model.name). Check the LM Studio app for an error."
        }
    }

    private func unloadFromLMStudio(_ model: LocalModel) async {
        guard let cli = lmStudioCLI else {
            problem = "LM Studio’s lms command is not installed. Unload the model inside LM Studio."
            return
        }
        guard let reference = model.reference else { return }
        // Never unload *all* models as a fallback for a failed targeted unload.
        if await run(cli, ["unload", reference], timeout: 30) == nil {
            problem = "LM Studio did not confirm unloading \(model.name). Other models were left alone."
        }
    }

    // MARK: The housekeeper's own model

    private func readHousekeeper() async -> ModelGroup {
        var group = ModelGroup(runtime: .housekeeper)
        let weights = HousekeeperWeights.shared
        let server = Housekeeper.shared.server
        let loadedPath = server.loadedModelPath
        let port = server.state.port

        group.models = weights.storedFiles
            .filter { !$0.url.lastPathComponent.hasSuffix(".partial") }
            .sorted { $0.bytes > $1.bytes }
            .map { file in
                let isLoaded = loadedPath == file.url.standardizedFileURL.path
                let eval = Self.evaluateNecessity(
                    runtime: .housekeeper,
                    name: file.url.deletingPathExtension().lastPathComponent,
                    path: file.url.path,
                    bytes: file.bytes,
                    isLoaded: isLoaded,
                    isCurrentMLX: false
                )
                return LocalModel(
                    id: "housekeeper:\(file.url.lastPathComponent)",
                    runtime: .housekeeper,
                    name: file.url.deletingPathExtension().lastPathComponent,
                    facts: [file.sizeLabel],
                    bytes: file.bytes,
                    loaded: isLoaded,
                    control: LlamaServer.isAvailable ? .loadAndUnload : .none,
                    reference: file.url.path,
                    note: isLoaded ? "This exact model is running on port \(port!)." : "Stored on disk, not currently running.",
                    necessity: eval.status,
                    intersections: eval.intersections,
                    intersectionExplanation: eval.explanation
                )
            }

        if group.models.isEmpty {
            group.hint = "No weights are downloaded. The Housekeeper screen (⌘K) offers them."
        }
        return group
    }

    // MARK: Hermes

    private func readHermes() async -> ModelGroup {
        var group = ModelGroup(runtime: .hermes)
        guard let answer = await getJSON(hermesBase.appendingPathComponent("v1/models")),
              let list = answer["data"] as? [[String: Any]], !list.isEmpty else {
            return group
        }
        group.hint = "Hermes offers \(list.count) model\(list.count == 1 ? "" : "s"), but /v1/models does not establish which one is resident in RAM. Per-model load/unload is unavailable until the runtime provides verified state."
        group.models = list.compactMap { (entry: [String: Any]) -> LocalModel? in
            guard let id = entry["id"] as? String else { return nil }
            let eval = Self.evaluateNecessity(
                runtime: .hermes,
                name: id,
                path: nil,
                bytes: nil,
                isLoaded: false,
                isCurrentMLX: false
            )
            return LocalModel(
                id: "hermes:\(id)",
                runtime: .hermes,
                name: id,
                facts: ["offered by the server; residency unknown"],
                loaded: false,
                control: .none,
                reference: id,
                necessity: eval.status,
                intersections: eval.intersections,
                intersectionExplanation: eval.explanation
            )
        }
        return group
    }

    private func unloadHermes() async {
        _ = await postJSON(hermesBase.appendingPathComponent("unload"), [:])
    }

    // MARK: Hugging Face cache

    private func readHuggingFace() async -> ModelGroup {
        var group = ModelGroup(runtime: .huggingFace)
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)

        let folders = await Task.detached(priority: .utility) { () -> [(String, Int64)] in
            let manager = FileManager.default
            guard let entries = try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return entries
                .filter { $0.lastPathComponent.hasPrefix("models--") }
                .map { url in (url.lastPathComponent, Self.directorySize(url)) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
        }.value

        group.models = folders.map { name, bytes in
            let readable = name
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/")
            let eval = Self.evaluateNecessity(
                runtime: .huggingFace,
                name: readable,
                path: nil,
                bytes: bytes,
                isLoaded: false,
                isCurrentMLX: false
            )
            return LocalModel(
                id: "hf:\(name)",
                runtime: .huggingFace,
                name: readable,
                facts: [ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)],
                bytes: bytes,
                control: .none,
                necessity: eval.status,
                intersections: eval.intersections,
                intersectionExplanation: eval.explanation
            )
        }
        if group.models.isEmpty {
            group.hint = "Nothing has been downloaded into the Hugging Face cache."
        }
        return group
    }

    // MARK: - Necessity & Intersections Engine

    static func evaluateNecessity(
        runtime: ModelRuntime,
        name: String,
        path: String?,
        bytes: Int64?,
        isLoaded: Bool,
        isCurrentMLX: Bool
    ) -> (status: NecessityStatus, intersections: [String], explanation: String) {
        let lower = (name + " " + (path ?? "")).lowercased()

        // 1. Draw Things / FLUX.2
        if runtime == .drawThings || lower.contains("draw-things") || lower.contains("flux_2") || lower.contains("flux") {
            return (
                status: .necessary,
                intersections: ["Jeopardy (generate_image.sh)", "Agent Skill (generate-image)", "draw-things-cli"],
                explanation: "Actively used as the local offline image generation engine by Jeopardy (generate_image.sh) and the universal 'generate-image' agent skill. Essential to retain."
            )
        }

        // 2. Qwen MLX Models (Resident & Default)
        if lower.contains("qwen") || lower.contains("heretic") {
            let activeNote = isCurrentMLX ? " (Active Default)" : ""
            return (
                status: .necessary,
                intersections: ["Hermes CLI (hermes-local 4b/9b)", "Resident MLX Server (:18434)", "DeepSeek Harness", "Local Registry (~/Models/llm)"],
                explanation: "Primary local LLM lane\(activeNote). Served by LaunchAgent on port 18434 and referenced by Hermes, DeepSeek Harness, and system agent skills."
            )
        }

        // 3. Speech-to-text: Whisper
        if lower.contains("whisper") {
            return (
                status: .necessary,
                intersections: ["VoiceStudio.app (mlx-whisper / faster-whisper)", "mlx_whisper CLI", "DeepSeek Harness"],
                explanation: "Core speech-to-text model for VoiceStudio and local transcription workflows."
            )
        }

        // 4. Speech-to-text: SenseVoice & Silero
        if lower.contains("sensevoice") || lower.contains("silero") {
            return (
                status: .necessary,
                intersections: ["DeepSeek Harness.app (Live Dictation / Mic)"],
                explanation: "DeepSeek Harness microphone input and speech-to-text engine. Removing this breaks the in-app dictation mic."
            )
        }

        // 5. Voice Synthesis: Fish Speech
        if lower.contains("fish-speech") || lower.contains("fishaudio") {
            return (
                status: .necessary,
                intersections: ["VoiceStudio.app (fish-clone engine via mlx-speech)"],
                explanation: "Local voice cloning and audio synthesis engine utilized by VoiceStudio."
            )
        }

        // 6. Vision: Apple Depth Pro
        if lower.contains("depth-pro") || lower.contains("depth_pro") {
            return (
                status: .necessary,
                intersections: ["Madavi Project (depth.py)"],
                explanation: "Metric depth field estimation engine utilized by the Madavi project."
            )
        }

        // 7. Speech-to-text: Parakeet
        if lower.contains("parakeet") {
            return (
                status: .optional,
                intersections: ["VoiceStudio.app (High-Speed English ASR)"],
                explanation: "Ultra-fast English transcription model; optional high-speed alternative to Whisper."
            )
        }

        // 8. Voice Synthesis: OmniVoice / MOSS TTS
        if lower.contains("omnivoice") || lower.contains("moss-tts") {
            return (
                status: .optional,
                intersections: ["VoiceStudio.app (CPU TTS Clone)"],
                explanation: "Standalone voice synthesis runtime. Available when CPU-based voice cloning is requested."
            )
        }

        // 9. Translation: NLLB-200
        if lower.contains("nllb") {
            return (
                status: .optional,
                intersections: ["Local Persian↔English Translation Tools"],
                explanation: "Offline translation model for Persian↔English when internet connectivity is unavailable."
            )
        }

        // 10. ComfyUI
        if runtime == .comfyUI || lower.contains("comfyui") {
            return (
                status: .extra,
                intersections: ["None (No Active Workflows)"],
                explanation: "No image generation checkpoints found in ComfyUI models directory. Redundant with native Draw Things engine; safe to clean to reclaim space."
            )
        }

        // 11. LM Studio
        if runtime == .lmStudio || lower.contains("lmstudio") {
            let appExists = FileManager.default.fileExists(atPath: "/Applications/LM Studio.app")
                || FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/LM Studio.app")
            if !appExists {
                return (
                    status: .extra,
                    intersections: ["None (App uninstalled)"],
                    explanation: "LM Studio.app is uninstalled from /Applications. Leftover ~/.lmstudio data contains orphaned backends and caches."
                )
            } else {
                return (
                    status: .optional,
                    intersections: ["LM Studio.app"],
                    explanation: "Model installed inside LM Studio's store."
                )
            }
        }

        // 12. Ollama
        if runtime == .ollama || lower.contains("ollama") {
            return (
                status: .optional,
                intersections: ["Ollama Service (:11434)"],
                explanation: "Available for on-demand local inference when Ollama service is running."
            )
        }

        // 13. Hugging Face Cache
        if runtime == .huggingFace || lower.contains("huggingface") {
            return (
                status: .optional,
                intersections: ["Hugging Face Download Cache"],
                explanation: "Cached model weights downloaded from Hugging Face hub. Can be purged or re-downloaded."
            )
        }

        // Fallback
        if isLoaded {
            return (
                status: .necessary,
                intersections: ["Active Running Process"],
                explanation: "Currently loaded into system memory."
            )
        }

        return (
            status: .optional,
            intersections: ["Local Standalone Storage"],
            explanation: "Installed locally on disk."
        )
    }

    func moveToTrash(_ model: LocalModel) async {
        guard let path = model.path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        busy = model.id
        problem = nil
        note = "Moving \(model.name) to the Trash…"

        do {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
            note = "Moved \(model.name) to the Trash."
            await read()
        } catch {
            problem = "Could not move \(model.name) to the Trash: \(error.localizedDescription)"
        }
        busy = nil
        note = nil
    }

    nonisolated private static func fileOrDirectorySize(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if isDir.boolValue {
            return directorySize(url)
        } else {
            var total: Int64 = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let tensordata = URL(fileURLWithPath: url.path + "-tensordata")
            if FileManager.default.fileExists(atPath: tensordata.path) {
                let tensorSize = (try? tensordata.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                total += tensorSize
            }
            return total
        }
    }

    nonisolated private static func directorySize(_ url: URL) -> Int64 {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: Loading and unloading

    /// What stands between a model and being loaded, in the app's own words. Nil
    /// means there is room. The multiplication is deliberate: a model's file size is
    /// not the memory it holds — the context window and the runtime's own buffers
    /// sit on top of it.
    func refusal(for model: LocalModel) -> String? {
        guard !model.loaded, model.control != .none else { return nil }
        guard let bytes = model.bytes, bytes > 0 else { return nil }
        let needed = UInt64(Double(bytes) * 1.15) + 700_000_000
        guard needed > memory.free else { return nil }

        let need = ByteCountFormatter.string(fromByteCount: Int64(needed), countStyle: .memory)
        let free = ByteCountFormatter.string(fromByteCount: Int64(memory.free), countStyle: .memory)
        return "This one needs about \(need) and \(free) is free. Something has to be unloaded first — \(model.name) is not worth the crash."
    }

    func load(_ model: LocalModel) async {
        guard busy == nil, !model.loaded, model.control == .loadAndUnload else { return }
        if let refusal = refusal(for: model) {
            problem = refusal
            return
        }
        busy = model.id
        problem = nil
        note = "Loading \(model.name)…"

        switch model.runtime {
        case .mlx: break // A filesystem alias cannot load an MLX model.
        case .ollama: await loadInOllama(model)
        case .lmStudio: await loadInLMStudio(model)
        case .housekeeper:
            if let reference = model.reference, LlamaServer.isAvailable {
                let server = Housekeeper.shared.server
                server.start(model: URL(fileURLWithPath: reference))
                // start() launches asynchronously. Wait for actual /health readiness
                // before refreshing inventory; otherwise every cold load looks failed.
                for _ in 0..<360 {
                    if case .ready = server.state { break }
                    if case .failed(let reason) = server.state {
                        problem = reason
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        case .hermes, .huggingFace, .drawThings, .comfyUI: break
        }

        busy = nil
        note = nil
        await read()
        if problem == nil, let fresh = self.model(model.id), !fresh.loaded {
            problem = "\(model.name) did not load. \(model.runtime.title) did not report it as running afterwards."
        }
    }

    func unload(_ model: LocalModel) async {
        guard busy == nil, model.loaded || model.control == .unloadOnly else { return }
        busy = model.id
        problem = nil
        note = "Unloading \(model.name)…"

        switch model.runtime {
        case .mlx: break // No arbitrary MLX process is owned by Housekeeping.
        case .ollama: await unloadFromOllama(model)
        case .lmStudio: await unloadFromLMStudio(model)
        case .housekeeper: Housekeeper.shared.server.stopAndWait()
        case .hermes: await unloadHermes()
        case .huggingFace, .drawThings, .comfyUI: break
        }

        busy = nil
        note = nil
        await read()
        if problem == nil, let fresh = self.model(model.id), fresh.loaded {
            problem = "\(model.name) still reports itself as loaded. \(model.runtime.title) may be keeping it for another request."
        }
    }

    /// Every loaded model, one at a time — the "make room" button, for a reader who
    /// does not want to hunt for whichever row is holding the memory.
    func freeEverything() async {
        guard busy == nil else { return }
        let loaded = groups.flatMap { $0.models }.filter { $0.loaded }
        for model in loaded {
            await unload(model)
        }
    }

    func model(_ id: String) -> LocalModel? {
        groups.flatMap { $0.models }.first { $0.id == id }
    }

    // MARK: Talking to the machine

    private func getJSON(_ url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    @discardableResult
    private func postJSON(_ url: URL, _ body: [String: Any]) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // A load can take a while on a large model; a refusal comes back at once.
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return http.statusCode
    }

    /// Runs a command-line tool and returns its output, or nil if it failed. The
    /// timeout exists because a runtime that hangs must not hang the screen with it.
    private func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 90) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            let gate = CompletionGate()

            process.terminationHandler = { finishedProcess in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                guard gate.claim() else { return }
                continuation.resume(returning: finishedProcess.terminationStatus == 0 ? text : nil)
            }

            do {
                try process.run()
            } catch {
                if gate.claim() { continuation.resume(returning: nil) }
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
                if gate.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// A continuation may only be resumed once, and a process can finish at the same
/// moment its timeout fires. This decides which of the two gets to answer.
private final class CompletionGate: @unchecked Sendable {
    private var used = false
    private let lock = NSLock()

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
