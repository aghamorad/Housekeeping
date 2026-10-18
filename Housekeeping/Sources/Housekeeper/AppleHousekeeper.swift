import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Uses only Apple's on-device SystemLanguageModel. No cloud fallback and no
/// model file is downloaded or copied into Housekeeping's storage.
enum AppleHousekeeper {
    struct Status {
        let isAvailable: Bool
        let message: String
    }
    static var status: Status {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return Status(isAvailable: true, message: "Ready. Uses the on-device Foundation Model already managed by macOS. No additional Housekeeping model download.")
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return Status(isAvailable: false, message: "This Mac is not eligible for Apple Intelligence. Choose a downloadable model or leave chat off.")
                case .appleIntelligenceNotEnabled: return Status(isAvailable: false, message: "Apple Intelligence is off. You can enable it in System Settings, or choose a downloadable model. Housekeeping will not enable it for you.")
                case .modelNotReady: return Status(isAvailable: false, message: "The system model is not ready. macOS manages its download and preparation; try again when Apple Intelligence is ready.")
                @unknown default: return Status(isAvailable: false, message: "Apple's on-device model is unavailable on this Mac right now.")
                }
            }
        }
        #endif
        return Status(isAvailable: false, message: "Requires macOS 26 or later and a Mac with Apple Intelligence enabled and its system model ready.")
    }

    static func complete(messages: [[String: String]]) async throws -> String {
        guard status.isAvailable else { throw Failure.unavailable(status.message) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            // Replay known turns as real transcript roles, with fresh system
            // instructions and context for this request. Never generate history again.
            let entries: [Transcript.Entry] = messages.dropLast().compactMap { message in
                let segments: [Transcript.Segment] = [.text(.init(content: message["content"] ?? ""))]
                switch message["role"] {
                case "system": return .instructions(.init(segments: segments, toolDefinitions: []))
                case "user": return .prompt(.init(segments: segments))
                case "assistant": return .response(.init(assetIDs: [], segments: segments))
                default: return nil
                }
            }
            let session = LanguageModelSession(model: SystemLanguageModel.default, transcript: Transcript(entries: entries))
            try Task.checkCancellation()
            let response = try await session.respond(to: messages.last?["content"] ?? "", options: GenerationOptions(temperature: 0.4, maximumResponseTokens: 512))
            try Task.checkCancellation()
            let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw Failure.unavailable("Apple's local model returned an empty response.") }
            return answer
        }
        #endif
        throw Failure.unavailable(status.message)
    }

    enum Failure: LocalizedError {
        case unavailable(String)
        var errorDescription: String? { switch self { case .unavailable(let message): return message } }
    }
}
