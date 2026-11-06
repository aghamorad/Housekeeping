// Housekeeping — Clean Up: the one class of thing it must never offer

import Foundation

/// Downloaded AI models are not junk, and Clean Up must never offer them.
///
/// A weight file looks like any other large file to a reader that only knows
/// names and sizes, so Clean Up grew a habit of sweeping model libraries — the
/// Hugging Face cache, the MLX registry, a Draw Things container — as "orphaned
/// leftovers" or "big & old files". Nothing on those shelves is discardable in
/// the sense the shelf promises: fetching it again costs hours, and on a
/// throttled connection may not happen at all.
///
/// The guard belongs here rather than in a list of protected paths because the
/// next runtime will put its weights somewhere nobody has thought of yet. It
/// answers one question — "is this a model library?" — and answers yes if the
/// place is a known model root, or if what is inside it is weights.
///
/// Models still have a home: the Local Models screen reads these same
/// directories and says what each model is for and whether it is necessary.
enum ModelStorageGuard {
    /// Places whose whole purpose is holding model weights, relative to home.
    /// Prefix-matched, so `~/.cache/huggingface/hub` is covered by the first
    /// entry and a sibling cache cannot slip past it.
    static let roots: [String] = [
        ".cache/huggingface",
        ".cache/mlx-vlm",
        ".cache/comfyui",
        ".cache/torch",
        ".mlx-lm",
        ".lmstudio",
        ".ollama",
        "Models",
        "Library/Application Support/ComfyUI",
        "Library/Containers/com.liuliu.draw-things"
    ]

    /// Draw Things writes `*.ckpt-tensordata`; Hugging Face writes safetensors,
    /// gguf and npz; Core ML writes mlpackage. `bin` is only counted when the
    /// file is large, which `minimumWeightFileSize` enforces.
    static let weightExtensions: Set<String> = [
        "safetensors", "ckpt", "ckpt-tensordata", "ckpt-index", "gguf", "npz",
        "onnx", "mlmodel", "mlpackage", "pt", "pth", "bin", "msgpack", "h5", "tflite"
    ]

    /// A weight file is never a few kilobytes. This keeps a stray `.bin` inside
    /// an ordinary cache from being promoted to a model library.
    static let minimumWeightFileSize: Int64 = 8_000_000

    /// True when `url` is model storage.
    ///
    /// `deep` exists for speed: the path check is free, walking a tree is not,
    /// and everything worth walking is large. Callers pass `deep: size >= …`.
    static func isModelLibrary(
        _ url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        deep: Bool = true
    ) -> Bool {
        if let relative = relativePath(url, home: home),
           roots.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) {
            return true
        }
        guard deep else { return false }
        return containsWeights(url)
    }

    /// The path as it would be written from home, or nil when it is somewhere else.
    static func relativePath(_ url: URL, home: URL) -> String? {
        let homePath = home.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return nil }
        return String(path.dropFirst(homePath.count + 1))
    }

    /// Whether any file under `url` is large enough and named enough like a model
    /// weight to be one. Bounded in both depth and entries: this runs during a
    /// scan and must not turn a sweep into a walk of the whole disk.
    static func containsWeights(_ url: URL, depthLimit: Int = 6, budget: Int = 4_000) -> Bool {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey
        ]
        guard let walk = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return false }

        let rootDepth = url.standardizedFileURL.pathComponents.count
        var remaining = budget

        while let entry = walk.nextObject() as? URL {
            remaining -= 1
            if remaining <= 0 { return false }
            if entry.standardizedFileURL.pathComponents.count - rootDepth > depthLimit {
                walk.skipDescendants()
                continue
            }
            guard weightExtensions.contains(entry.pathExtension.lowercased()) else { continue }
            guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            if bytes >= minimumWeightFileSize { return true }
        }
        return false
    }
}
