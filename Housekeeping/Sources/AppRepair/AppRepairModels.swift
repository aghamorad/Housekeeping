import Foundation
import AppKit

// MARK: - App Repair Candidate

public struct AppRepairCandidate: Identifiable, Equatable {
    public let id: String
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public let hasQuarantine: Bool
    public let hasProvenance: Bool
    public let signatureValid: Bool
    public let statusText: String

    public var isDamagedCandidate: Bool {
        hasQuarantine || hasProvenance || !signatureValid
    }

    public init(
        url: URL,
        name: String,
        bundleID: String,
        version: String,
        hasQuarantine: Bool,
        hasProvenance: Bool,
        signatureValid: Bool,
        statusText: String
    ) {
        self.id = url.path
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.hasQuarantine = hasQuarantine
        self.hasProvenance = hasProvenance
        self.signatureValid = signatureValid
        self.statusText = statusText
    }
}

// MARK: - App Repair Outcome

public struct AppRepairOutcome: Identifiable, Equatable {
    public let id = UUID()
    public let appName: String
    public let url: URL
    public let succeeded: Bool
    public let stepsTaken: [String]
    public let message: String
}
