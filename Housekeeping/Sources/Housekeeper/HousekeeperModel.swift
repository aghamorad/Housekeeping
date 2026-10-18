import Foundation

/// An explicit user choice. No saved choice means chat is off, even if weights
/// left by an earlier app version are present. Selecting never downloads a file.
enum HousekeeperModel: String, CaseIterable, Identifiable {
    case none, apple, gemma1b, qwen15b, qwen17b, gemma2b, qwen4b
    var id: String { rawValue }
    static let preferenceKey = "housekeeping.housekeeper.model"
    static func savedChoice(_ raw: String?) -> Self { raw.flatMap(Self.init(rawValue:)) ?? .none }

    struct Download {
        let title: String
        let fileName: String
        let bytes: Int64
        let sha256: String
        let repository: String
        let detail: String
        var sourcePage: URL { URL(string: "https://huggingface.co/" + repository)! }
        var source: URL { URL(string: sourcePage.absoluteString + "/resolve/main/" + fileName)! }
        var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    }

    var download: Download? {
        switch self {
        case .none, .apple: return nil
        case .gemma1b: return Download(title: "Gemma 3 · 1B", fileName: "google_gemma-3-1b-it-Q4_K_M.gguf", bytes: 806058496, sha256: "12bf0fff8815d5f73a3c9b586bd8fee8e7b248c935de70dec367679873d0f29d", repository: "bartowski/google_gemma-3-1b-it-GGUF", detail: "Smallest download. General text chat; limited reasoning.")
        case .qwen15b: return Download(title: "Qwen 2.5 · 1.5B", fileName: "Qwen2.5-1.5B-Instruct-Q4_K_M.gguf", bytes: 986048768, sha256: "1adf0b11065d8ad2e8123ea110d1ec956dab4ab038eab665614adba04b6c3370", repository: "bartowski/Qwen2.5-1.5B-Instruct-GGUF", detail: "Compact instruction model for general questions and explanations.")
        case .qwen17b: return Download(title: "Qwen 3 · 1.7B", fileName: "Qwen3-1.7B-Q4_K_M.gguf", bytes: 1107409472, sha256: "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897", repository: "unsloth/Qwen3-1.7B-GGUF", detail: "A Qwen option near 2B parameters, with a larger download than the compact models.")
        case .gemma2b: return Download(title: "Gemma 2 · 2B", fileName: "gemma-2-2b-it-Q4_K_M.gguf", bytes: 1708582752, sha256: "e0aee85060f168f0f2d8473d7ea41ce2f3230c1bc1374847505ea599288a7787", repository: "bartowski/gemma-2-2b-it-GGUF", detail: "A 2B Gemma instruction model. Uses more storage than the compact options.")
        case .qwen4b: return Download(title: "Qwen 3 Instruct · 4B", fileName: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf", bytes: 2_497_281_120, sha256: "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597", repository: "unsloth/Qwen3-4B-Instruct-2507-GGUF", detail: "Larger optional model. About 2.5 GB of disk space; not required for Housekeeping.")
        }
    }

    var title: String {
        switch self {
        case .none: return "Off · no chatbot"
        case .apple: return "Apple Intelligence · system Foundation Model"
        default: return download!.title
        }
    }

    var choiceLabel: String {
        guard let download else { return title }
        return title + " · " + download.sizeLabel
    }
}
